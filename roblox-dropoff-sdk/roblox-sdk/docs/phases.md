# Onboarding Patterns

This guide shows 4 common ways to integrate DropOff Analytics into your Roblox game, from simplest to most advanced.

## Pattern 1: Basic (Copy-Paste)

**Use case**: Minimal setup, just track join/leave/first_input

```lua
-- ServerScriptService/InitScript.server.lua
local DropOffAnalytics = require(game:GetService("ServerScriptService"):WaitForChild("DropOffAnalytics"))

DropOffAnalytics.init({
    projectKey = "pk_live_YOUR_KEY"
})

-- That's it! Automatic tracking is now active.
```

**What you get:**
- ✅ Join events (when player enters game)
- ✅ Leave events (when player exits)
- ✅ First input events (when player moves for first time)
- ✅ First interaction events (from ProximityPrompts)

**No additional code needed.**

---

## Pattern 2: Phase Tracking (Loading → Playable → Gameplay)

**Use case**: Understand where players drop off (loading, menu, in-game)

```lua
-- ServerScriptService/InitScript.server.lua
local DropOffAnalytics = require(game:GetService("ServerScriptService"):WaitForChild("DropOffAnalytics"))

DropOffAnalytics.init({
    projectKey = "pk_live_YOUR_KEY"
})

-- ============================================================================
-- Track game lifecycle phases
-- ============================================================================

local function handlePlayerJoined(player)
    -- Emit phase change when player joins
    DropOffAnalytics.setPhase(player, "loading")
    
    -- Simulate load time (e.g., loading assets, initializing character)
    task.wait(5)
    
    -- Move to playable state (user can interact)
    DropOffAnalytics.setPhase(player, "playable")
end

game:GetService("Players").PlayerAdded:Connect(handlePlayerJoined)

-- Later, when gameplay starts (e.g., after menu)
local function handleGameplayStart(player)
    DropOffAnalytics.setPhase(player, "gameplay")
end

-- You'd call this from your game menu/level select logic
```

**What you measure:**
- Players who join but don't reach "playable" = **loading abandonment**
- Players who reach "playable" but not "gameplay" = **menu abandonment**
- Players in "gameplay" = **engaged players**

**Dashboard shows:**
- Exit buckets per phase (see % who leave during loading vs menu)
- FSAR (First Session Abandonment Rate) overall

---

## Pattern 3: Custom Interactions (Buttons, Collectibles, Actions)

**Use case**: Track specific user actions beyond automatic detection

```lua
-- ServerScriptService/InitScript.server.lua
local DropOffAnalytics = require(game:GetService("ServerScriptService"):WaitForChild("DropOffAnalytics"))

DropOffAnalytics.init({
    projectKey = "pk_live_YOUR_KEY"
})

-- ============================================================================
-- Track custom user interactions
-- ============================================================================

local function handleButtonClick(player, buttonName)
    -- Mark any custom interaction
    DropOffAnalytics.markInteraction(player, "clicked_" .. buttonName)
end

-- Example: Hook into your GUI system
local function setupPlayerUI(player)
    -- Assume you have a GUI with buttons
    local gui = player:WaitForChild("PlayerGui"):WaitForChild("MainGui")
    
    local startButton = gui:WaitForChild("StartButton")
    startButton.MouseButton1Click:Connect(function()
        handleButtonClick(player, "start_button")
        -- ... rest of your click logic
    end)
    
    local settingsButton = gui:WaitForChild("SettingsButton")
    settingsButton.MouseButton1Click:Connect(function()
        handleButtonClick(player, "settings_button")
        -- ... rest of your click logic
    end)
end

game:GetService("Players").PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function()
        setupPlayerUI(player)
    end)
end)
```

**What you measure:**
- Who clicks start button → who doesn't = UX issue
- Who enters settings → suggests engaged players
- Correlation between interactions and retention

**Pro tip**: Use descriptive labels like `"clicked_play_button"`, `"collected_coin"`, `"opened_shop"` so your dashboard is self-explanatory.

---

## Pattern 4: Full Instrumentation (Comprehensive Metrics)

**Use case**: Deep analytics across game lifecycle, custom events, performance monitoring

```lua
-- ServerScriptService/InitScript.server.lua
local DropOffAnalytics = require(game:GetService("ServerScriptService"):WaitForChild("DropOffAnalytics"))

DropOffAnalytics.init({
    projectKey = "pk_live_YOUR_KEY",
    flushIntervalSeconds = 5,  -- More frequent flushing for real-time dashboard
    maxBatchSize = 15,         -- Smaller batches
    logLevel = "info"
})

-- ============================================================================
-- PHASE 1: LOADING
-- ============================================================================

local function startLoadingPhase(player)
    DropOffAnalytics.setPhase(player, "loading")
    
    -- Simulate asset loading
    local startTime = os.time()
    task.wait(3)  -- Pretend we're loading assets
    
    if not DropOffAnalytics.hasSession(player) then
        return  -- Player left during loading
    end
    
    DropOffAnalytics.markInteraction(player, "completed_asset_load")
    DropOffAnalytics.setPhase(player, "main_menu")
end

-- ============================================================================
-- PHASE 2: MAIN MENU
-- ============================================================================

local function setupMainMenuUI(player)
    -- Show menu, track interactions
    DropOffAnalytics.markInteraction(player, "reached_main_menu")
    
    local gui = player:WaitForChild("PlayerGui"):WaitForChild("MainMenu")
    
    gui:WaitForChild("PlayButton").MouseButton1Click:Connect(function()
        DropOffAnalytics.markInteraction(player, "clicked_play_from_menu")
        startGameplay(player)
    end)
    
    gui:WaitForChild("SettingsButton").MouseButton1Click:Connect(function()
        DropOffAnalytics.markInteraction(player, "clicked_settings_from_menu")
    end)
    
    gui:WaitForChild("QuitButton").MouseButton1Click:Connect(function()
        DropOffAnalytics.markInteraction(player, "clicked_quit_from_menu")
        player:Kick()
    end)
end

-- ============================================================================
-- PHASE 3: GAMEPLAY
-- ============================================================================

local function startGameplay(player)
    DropOffAnalytics.setPhase(player, "gameplay")
    
    -- Hide menu, show game
    local character = player.Character or player.CharacterAdded:Wait()
    
    -- Track milestones
    local levelStartTime = os.time()
    DropOffAnalytics.markInteraction(player, "gameplay_started")
    
    -- Wait for gameplay events
    local humanoid = character:WaitForChild("Humanoid")
    humanoid.Died:Connect(function()
        DropOffAnalytics.markInteraction(player, "died_in_gameplay")
        DropOffAnalytics.setPhase(player, "death_screen")
    end)
    
    -- Track level completion
    task.spawn(function()
        local checkpoint = character:WaitForChild("Checkpoint")
        checkpoint.Touched:Connect(function(hit)
            if hit.Parent:FindFirstChild("Humanoid") == humanoid then
                DropOffAnalytics.markInteraction(player, "reached_level_checkpoint")
            end
        end)
    end)
end

-- ============================================================================
-- MAIN FLOW
-- ============================================================================

game:GetService("Players").PlayerAdded:Connect(function(player)
    -- Phase 1: Loading
    task.spawn(function()
        startLoadingPhase(player)
    end)
    
    -- Phase 2: Menu (when loading done)
    task.spawn(function()
        task.wait(3)  -- Wait for phase 1
        if DropOffAnalytics.hasSession(player) then
            DropOffAnalytics.setPhase(player, "main_menu")
            setupMainMenuUI(player)
        end
    end)
    
    -- Optional: Monitor SDK performance periodically
    task.spawn(function()
        while DropOffAnalytics.hasSession(player) do
            task.wait(60)
            local stats = DropOffAnalytics.getPerfStats()
            if stats.errors > 0 then
                -- Alert developer to analytics issues
                warn("DropOff SDK errors:", stats.errors)
            end
        end
    end)
end)

-- ============================================================================
-- OFFLINE STATE TRACKING (Optional)
-- ============================================================================

-- If your game has reconnect/save state logic:
local function handlePlayerDisconnect(player)
    DropOffAnalytics.setPhase(player, "disconnected")
end

game:GetService("Players").PlayerRemoving:Connect(function(player)
    -- SDK automatically emits 'leave' event, but you can add context
    handlePlayerDisconnect(player)
end)
```

**What you measure:**
- Complete player journey (loading → menu → gameplay)
- Granular drop-off points (where players leave)
- Interaction depth (which menu buttons matter)
- Gameplay engagement (checkpoints, deaths, progression)

**Dashboard insights:**
- Loading abandonment vs menu abandonment vs mid-game
- Correlation between "clicked_play_from_menu" and "gameplay_started"
- Evidence cards highlighting friction points

---

## Which Pattern Should I Use?

| Game Type | Pattern | Why |
|-----------|---------|-----|
| Simple / Jam | **Pattern 1** | Just need to know if people leave |
| Tycoon / Sandbox | **Pattern 2** | Track loading/menu phases |
| Action Game | **Pattern 3** | Custom interactions in-game |
| Complex / Live Service | **Pattern 4** | Full funnel analysis |

---

## Tips

### 1. Label Interactions Consistently

Good labels:
```lua
"clicked_start_button"
"reached_playable_state"
"collected_first_coin"
```

Bad labels:
```lua
"action"     -- Too vague
"do_stuff"   -- Can't measure anything
"xyz123"     -- No context
```

### 2. Don't Mark First Interaction Twice

The SDK auto-detects first_input and ProximityPrompt interaction. Only use `markInteraction()` for **additional** interactions:

```lua
-- Good: Auto-detection + custom
DropOffAnalytics.markInteraction(player, "opened_shop")  -- Beyond first interaction

-- Bad: Redundant
DropOffAnalytics.markInteraction(player, "first_interaction")  -- SDK handles this
```

### 3. Use setPhase() Sparingly

Only call `setPhase()` for major game state changes (loading, menu, gameplay, results). Not for every small event.

```lua
-- Good
DropOffAnalytics.setPhase(player, "gameplay")

-- Bad (too granular)
DropOffAnalytics.setPhase(player, "walking")  -- Don't do this
DropOffAnalytics.setPhase(player, "jumping")  -- Don't do this
```

### 4. Monitor SDK Health

In production, periodically check error counts:

```lua
task.spawn(function()
    while true do
        task.wait(300)  -- Check every 5 minutes
        local stats = DropOffAnalytics.getPerfStats()
        if stats.errors > 100 then
            warn("SDK unhealthy! Errors:", stats.errors)
        end
    end
end)
```

---

## Next Steps

1. **Choose your pattern** above
2. **Copy the code template** into your game
3. **Replace `projectKey`** with yours (from DropOff dashboard)
4. **Test with `DropOffAnalytics.runStudioTest()`**
5. **Check your dashboard** for data appearing

For more on architecture and performance, see [performance.md](./performance.md).
