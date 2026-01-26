--[[
DropOffAnalytics ModuleScript for Roblox

A high-performance, fail-open analytics SDK for tracking player session lifecycle events
in Roblox games. Designed for production use with zero impact on gameplay.

Install:
1. Copy DropOffAnalytics.lua to ServerScriptService as a ModuleScript
2. In a Script in ServerScriptService:
   local DropOffAnalytics = require(game:GetService("ServerScriptService"):WaitForChild("DropOffAnalytics"))
   DropOffAnalytics.init({projectKey = "pk_live_xxx"})  -- endpoint defaults to https://api.dropoffanalytics.com

No user identifiers are sent. Session IDs are generated per player.
All events are batched and sent asynchronously to avoid blocking gameplay.
]]

local DropOffAnalytics = {}

-- ============================================================================
-- CONFIG & STATE
-- ============================================================================

-- HTTP timeout in seconds
local HTTP_TIMEOUT_SECONDS = 30

local config = {
	projectKey = nil,
	endpointBaseUrl = "https://api.dropoffanalytics.com",
	studioTestMode = false,
	flushIntervalSeconds = 10,
	maxBatchSize = 25,
	logLevel = "info", -- "debug", "info", "warn", "error"
}

local state = {
	initialized = false,
	sessionMap = {}, -- { [player] = { sessionId, joinedAt, ... } }
	pendingEvents = {},
	flushTimer = nil,
	interactionConnection = nil, -- Store interaction detection connection for cleanup
	perfStats = {
		eventsCaptured = 0,
		eventsSent = 0,
		flushes = 0,
		errors = 0,
		lastFlushTime = 0,
	},
}

-- ============================================================================
-- LOGGING
-- ============================================================================

local function log(level, message, ...)
	local levels = { debug = 0, info = 1, warn = 2, error = 3 }
	if levels[level] and levels[level] >= levels[config.logLevel] then
		local prefix = string.format("[DropOff:%s]", level:upper())
		if select("#", ...) > 0 then
			message = string.format(message, ...)
		end
		print(prefix .. " " .. message)
	end
end

-- ============================================================================
-- SESSION MANAGEMENT
-- ============================================================================

local function generateSessionId()
	-- UUID v4-like generation (not cryptographically secure, but good enough)
	local bytes = {}
	for i = 1, 16 do
		bytes[i] = math.random(0, 255)
	end
	
	-- Set version to 4 and variant to RFC 4122
	bytes[7] = bit32.bor(bit32.band(bytes[7], 0x0f), 0x40)
	bytes[9] = bit32.bor(bit32.band(bytes[9], 0x3f), 0x80)
	
	return string.format(
		"%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
		bytes[1], bytes[2], bytes[3], bytes[4],
		bytes[5], bytes[6],
		bytes[7], bytes[8],
		bytes[9], bytes[10],
		bytes[11], bytes[12], bytes[13], bytes[14], bytes[15], bytes[16]
	)
end

local function createSessionData(player)
	return {
		sessionId = generateSessionId(),
		joinedAt = os.time(),
		player = player,
		userId = player.UserId,
		firstInputSeen = false,
		firstInteractionSeen = false,
		currentPhase = nil,
		inputDetectionConnection = nil,
		characterAddedConnection = nil,
	}
end

local function getOrCreateSession(player)
	if not state.sessionMap[player] then
		state.sessionMap[player] = createSessionData(player)
	end
	return state.sessionMap[player]
end

local function destroySession(player)
	local session = state.sessionMap[player]
	if session then
		if session.inputDetectionConnection then
			session.inputDetectionConnection:Disconnect()
		end
		if session.characterAddedConnection then
			session.characterAddedConnection:Disconnect()
		end
	end
	state.sessionMap[player] = nil
end

-- ============================================================================
-- EVENT CAPTURE
-- ============================================================================

local function emitEvent(sessionId, eventType, props)
	if not state.initialized then
		return
	end
	
	table.insert(state.pendingEvents, {
		session_id = sessionId,
		type = eventType,
		ts = os.time(),
		props = props or {},
	})
	
	state.perfStats.eventsCaptured = state.perfStats.eventsCaptured + 1
	log("debug", "Event captured: %s (%s)", eventType, sessionId)
	
	-- Auto-flush if max batch size reached
	if #state.pendingEvents >= config.maxBatchSize then
		DropOffAnalytics.flush()
	end
end

local function setupFirstInputDetection(player, session)
	if session.firstInputSeen then
		return
	end
	
	local humanoid = player.Character and player.Character:FindFirstChild("Humanoid")
	if not humanoid then
		return
	end
	
	-- Listen for first movement (low-frequency check to avoid per-frame overhead)
	local lastCheck = tick()
	local pollConnection
	pollConnection = game:GetService("RunService").Heartbeat:Connect(function()
		if not state.sessionMap[player] then
			if pollConnection then
				pollConnection:Disconnect()
			end
			return
		end
		
		local now = tick()
		if now - lastCheck < 0.1 then
			return -- Check at most every 100ms
		end
		lastCheck = now
		
		if humanoid and humanoid.MoveDirection.Magnitude > 0 then
			if not session.firstInputSeen then
				session.firstInputSeen = true
				emitEvent(session.sessionId, "first_input", {})
				log("info", "First input detected for %s", player.Name)
			end
			
			if pollConnection then
				pollConnection:Disconnect()
			end
		end
	end)
	
	session.inputDetectionConnection = pollConnection
end

local function setupDefaultInteractionDetection()
	local proximityService = game:GetService("ProximityPromptService")
	
	local connection = proximityService.PromptTriggered:Connect(function(prompt, player)
		local session = state.sessionMap[player]
		if session and not session.firstInteractionSeen then
			session.firstInteractionSeen = true
			emitEvent(session.sessionId, "first_interaction", {})
			log("info", "First interaction detected for %s", player.Name)
		end
	end)
	
	-- Store connection for cleanup
	state.interactionConnection = connection
	return connection
end

-- ============================================================================
-- BATCHING & SENDING
-- ============================================================================

local function buildBatchPayload()
	if #state.pendingEvents == 0 then
		return nil
	end
	
	local now = os.time()
	return {
		sdk_version = "1.0.0",
		experience_id = game.GameId,
		place_id = game.PlaceId,
		server_instance_id = tostring(game.JobId),
		sent_at = os.date("!%Y-%m-%dT%H:%M:%SZ", now),
		test = config.studioTestMode,
		events = state.pendingEvents,
	}
end

local function serializePayload(payload)
	-- Simple JSON serialization (Roblox doesn't have built-in JSON)
	local function encodeString(s)
		s = s:gsub("\\", "\\\\")
		s = s:gsub('"', '\\"')
		s = s:gsub("\n", "\\n")
		s = s:gsub("\r", "\\r")
		s = s:gsub("\t", "\\t")
		return '"' .. s .. '"'
	end
	
	local function encodeValue(v)
		if type(v) == "string" then
			return encodeString(v)
		elseif type(v) == "number" then
			return tostring(v)
		elseif type(v) == "boolean" then
			return v and "true" or "false"
		elseif type(v) == "table" then
			local isArray = #v > 0 and v[1] ~= nil
			if isArray then
				local parts = {}
				for i, item in ipairs(v) do
					table.insert(parts, encodeValue(item))
				end
				return "[" .. table.concat(parts, ",") .. "]"
			else
				local parts = {}
				for key, item in pairs(v) do
					table.insert(parts, encodeString(key) .. ":" .. encodeValue(item))
				end
				return "{" .. table.concat(parts, ",") .. "}"
			end
		else
			return "null"
		end
	end
	
	return encodeValue(payload)
end

function DropOffAnalytics.flush()
	if not state.initialized or #state.pendingEvents == 0 then
		return
	end
	
	local payload = buildBatchPayload()
	local eventCount = #state.pendingEvents
	state.pendingEvents = {} -- Clear immediately (fire-and-forget)
	
	-- Send asynchronously in background with timeout
	task.spawn(function()
		local success, response = pcall(function()
			local endpoint = config.endpointBaseUrl .. "/v1/events/batch"
			local headers = {
				["Authorization"] = "Bearer " .. config.projectKey,
				["Content-Type"] = "application/json",
			}
			
			local jsonBody = serializePayload(payload)
			
			-- Use HttpService with timeout
			local httpService = game:GetService("HttpService")
			if httpService then
				-- Wrap in timeout to prevent hanging indefinitely
				local result = nil
				local requestError = nil
				local completed = false
				local timedOut = false
				
				local requestThread = task.spawn(function()
					local ok, res = pcall(function()
						return httpService:PostAsync(endpoint, jsonBody, Enum.HttpContentType.ApplicationJson, false, headers)
					end)
					if ok then
						result = res
					else
						requestError = res
					end
					completed = true
				end)
				
				-- Wait for completion with timeout
				local startTime = tick()
				while not completed and not timedOut do
					if tick() - startTime > HTTP_TIMEOUT_SECONDS then
						timedOut = true
						task.cancel(requestThread)
					end
					task.wait(0.1)
				end
				
				if timedOut then
					error("HTTP request timed out after " .. HTTP_TIMEOUT_SECONDS .. " seconds")
				end
				
				if requestError then
					error(requestError)
				end
				
				return result
			end
		end)
		
		if success then
			state.perfStats.eventsSent = state.perfStats.eventsSent + eventCount
			state.perfStats.flushes = state.perfStats.flushes + 1
			state.perfStats.lastFlushTime = os.time()
			log("info", "Flushed %d events", eventCount)
		else
			state.perfStats.errors = state.perfStats.errors + 1
			log("warn", "Failed to send events: %s", tostring(response))
			-- Fail-open: do not retry, let data be discarded
		end
	end)
end

local function startAutoFlush()
	if state.flushTimer then
		task.cancel(state.flushTimer)
	end
	
	state.flushTimer = task.delay(config.flushIntervalSeconds, function()
		if state.initialized then
			DropOffAnalytics.flush()
			startAutoFlush() -- Reschedule
		end
	end)
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function DropOffAnalytics.init(options)
	if state.initialized then
		log("warn", "DropOffAnalytics already initialized")
		return
	end
	
	-- Validate and merge options
	if not options.projectKey then
		error("DropOffAnalytics.init: projectKey is required")
	end
	
	for key, value in pairs(options) do
		if config[key] ~= nil then
			config[key] = value
		else
			log("warn", "Unknown config option ignored: %s", key)
		end
	end
	
	state.initialized = true
	log("info", "DropOffAnalytics initialized with projectKey: %s", config.projectKey:sub(1, 15) .. "...")
	
	-- Setup event listeners
	local players = game:GetService("Players")
	
	players.PlayerAdded:Connect(function(player)
		local session = getOrCreateSession(player)
		emitEvent(session.sessionId, "join", {})
		log("info", "Player joined: %s (%s)", player.Name, session.sessionId:sub(1, 8))
		
		-- Setup first input detection when character loads
		-- Store the connection to prevent memory leak on respawns
		session.characterAddedConnection = player.CharacterAdded:Connect(function(character)
			task.wait(0.1) -- Let character fully load
			setupFirstInputDetection(player, session)
		end)
		
		-- Setup character immediately if it exists
		if player.Character then
			setupFirstInputDetection(player, session)
		end
	end)
	
	players.PlayerRemoving:Connect(function(player)
		local session = state.sessionMap[player]
		if session then
			emitEvent(session.sessionId, "leave", {})
			log("info", "Player left: %s", player.Name)
			destroySession(player)
		end
	end)
	
	-- Setup default interaction detection
	setupDefaultInteractionDetection()
	
	-- Start auto-flush timer
	startAutoFlush()
	
	log("info", "Event listeners attached")
end

function DropOffAnalytics.setPhase(player, phaseName)
	if not state.initialized then
		log("warn", "setPhase called before init")
		return
	end
	
	-- Input validation
	if player == nil then
		log("warn", "setPhase called with nil player")
		return
	end
	
	if phaseName == nil or type(phaseName) ~= "string" then
		log("warn", "setPhase called with invalid phaseName: %s", tostring(phaseName))
		return
	end
	
	-- Validate phase name:
	-- - Maximum 64 characters
	-- - Allowed: letters (a-z, A-Z), numbers (0-9), underscores (_), hyphens (-)
	-- - Pattern: ^[%w_%-]+$ means "start to end, one or more word chars/underscore/hyphen"
	if #phaseName > 64 or not phaseName:match("^[%w_%-]+$") then
		log("warn", "setPhase called with invalid phaseName format: %s", phaseName)
		return
	end
	
	local session = getOrCreateSession(player)
	session.currentPhase = phaseName
	
	emitEvent(session.sessionId, "phase_change", { phase = phaseName })
	log("debug", "Phase changed for %s: %s", player.Name, phaseName)
end

function DropOffAnalytics.markInteraction(player, label)
	if not state.initialized then
		log("warn", "markInteraction called before init")
		return
	end
	
	-- Input validation
	if player == nil then
		log("warn", "markInteraction called with nil player")
		return
	end
	
	-- Validate label (optional but if provided, must be valid)
	if label ~= nil then
		if type(label) ~= "string" then
			log("warn", "markInteraction called with non-string label: %s", type(label))
			label = tostring(label)
		end
		-- Sanitize label: alphanumeric, underscores, hyphens, max 64 chars
		if #label > 64 then
			label = label:sub(1, 64)
			log("warn", "markInteraction label truncated to 64 chars")
		end
		if not label:match("^[%w_%-]*$") then
			log("warn", "markInteraction label contains invalid characters, sanitizing")
			label = label:gsub("[^%w_%-]", "_")
		end
	end
	
	local session = getOrCreateSession(player)
	if not session.firstInteractionSeen then
		session.firstInteractionSeen = true
		emitEvent(session.sessionId, "first_interaction", { label = label })
		log("debug", "Interaction marked for %s: %s", player.Name, tostring(label))
	end
end

function DropOffAnalytics.getPerfStats()
	return {
		eventsCaptured = state.perfStats.eventsCaptured,
		eventsSent = state.perfStats.eventsSent,
		flushes = state.perfStats.flushes,
		errors = state.perfStats.errors,
		lastFlushTime = state.perfStats.lastFlushTime,
		pendingEvents = #state.pendingEvents,
	}
end

-- Check if a player has an active session
-- Use this instead of accessing state.sessionMap directly
function DropOffAnalytics.hasSession(player)
	return state.sessionMap[player] ~= nil
end

-- Cleanup method to properly shutdown the SDK
function DropOffAnalytics.shutdown()
	if not state.initialized then
		return
	end
	
	log("info", "Shutting down DropOffAnalytics...")
	
	-- Flush any remaining events
	DropOffAnalytics.flush()
	
	-- Cancel flush timer
	if state.flushTimer then
		task.cancel(state.flushTimer)
		state.flushTimer = nil
	end
	
	-- Disconnect interaction listener to prevent memory leak
	if state.interactionConnection then
		pcall(function()
			state.interactionConnection:Disconnect()
		end)
		state.interactionConnection = nil
	end
	
	-- Cleanup all session connections
	for player, session in pairs(state.sessionMap) do
		if session and session.inputDetectionConnection then
			pcall(function()
				session.inputDetectionConnection:Disconnect()
			end)
		end
		if session and session.characterAddedConnection then
			pcall(function()
				session.characterAddedConnection:Disconnect()
			end)
		end
	end
	
	state.sessionMap = {}
	state.initialized = false
	
	log("info", "DropOffAnalytics shutdown complete")
end

-- ============================================================================
-- STUDIO TEST MODE
-- ============================================================================

function DropOffAnalytics.runStudioTest()
	if not state.initialized then
		log("error", "Cannot run test: SDK not initialized")
		return
	end
	
	log("info", "=== Starting DropOff Studio Test ===")
	
	-- Simulate a player joining
	local testPlayerId = 99999
	local testPlayer = {
		UserId = testPlayerId,
		Name = "TestPlayer_" .. testPlayerId,
		Character = nil,
	}
	
	-- Create fake session
	state.sessionMap[testPlayer] = createSessionData(testPlayer)
	local session = state.sessionMap[testPlayer]
	
	-- Simulate events
	emitEvent(session.sessionId, "join", {})
	task.wait(0.5)
	
	emitEvent(session.sessionId, "phase_change", { phase = "loading" })
	task.wait(0.5)
	
	emitEvent(session.sessionId, "phase_change", { phase = "playable" })
	task.wait(0.5)
	
	emitEvent(session.sessionId, "first_input", {})
	task.wait(0.5)
	
	emitEvent(session.sessionId, "first_interaction", { label = "test_button" })
	task.wait(0.5)
	
	emitEvent(session.sessionId, "leave", {})
	
	-- Flush and wait for response
	log("info", "Sending %d test events...", #state.pendingEvents)
	DropOffAnalytics.flush()
	
	task.wait(1) -- Wait for flush to complete
	
	local stats = DropOffAnalytics.getPerfStats()
	log("info", "=== Studio Test Complete ===")
	log("info", "Events captured: %d", stats.eventsCaptured)
	log("info", "Events sent: %d", stats.eventsSent)
	log("info", "Flushes: %d", stats.flushes)
	log("info", "Errors: %d", stats.errors)
	log("info", "Session ID: %s", session.sessionId)
	
	return session.sessionId
end

return DropOffAnalytics
