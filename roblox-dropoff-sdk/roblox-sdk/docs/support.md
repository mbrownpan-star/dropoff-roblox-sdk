# Support & Contributing

This is a **fork-friendly project**. You are encouraged to customize it for your game's specific needs.

## Philosophy

The DropOff Roblox SDK is intentionally simple and open. Rather than building an infinitely configurable system that works for everyone, we've built something you can understand and modify.

**You own this code.** Feel free to:
- ✅ Modify event types for your game
- ✅ Add custom event capture logic
- ✅ Change batching strategy
- ✅ Fork and maintain your own version
- ✅ Use as reference for your own analytics SDK

We provide community support for the base implementation, but your modifications are yours to maintain.

## Getting Help

### Questions About Integration

**Question:** How do I track a custom game event (e.g., player dies)?

**Answer:**
```lua
humanoid.Died:Connect(function()
    DropOffAnalytics.markInteraction(player, "died_in_gameplay")
end)
```

Or add a custom event type by modifying `DropOffAnalytics.lua`.

### Debugging Issues

**Problem:** Events not showing in dashboard

**Checklist:**
1. Is your `projectKey` correct? (Check DropOff dashboard)
2. Is `endpointBaseUrl` pointing to the right server? (default: `https://api.dropoffanalytics.com`)
3. Enable debug logging: `logLevel = "debug"`
4. Run `DropOffAnalytics.runStudioTest()` to test connectivity

**Debug script:**
```lua
local DropOffAnalytics = require(script.Parent:WaitForChild("DropOffAnalytics"))

DropOffAnalytics.init({
    projectKey = "pk_live_YOUR_KEY",
    logLevel = "debug"  -- Show all messages
})

task.wait(2)
local sessionId = DropOffAnalytics.runStudioTest()
print("Test session ID:", sessionId)

-- Check your DropOff dashboard for this session
```

### Performance Issues

**Symptom:** Framerate drops after adding DropOff

**Unlikely**, but if it happens:
1. Check that input detection is disconnecting after first input
2. Reduce `logLevel` to "error" (debug logging has overhead)
3. Increase `flushIntervalSeconds` (less frequent HTTP)
4. Profile your game separately from DropOff (likely other issue)

---

## Contributing & Forks

### Reporting Issues

If you find a bug in the base SDK:

1. Create a minimal test case
2. Check the [Performance Considerations](./performance.md) docs
3. Review existing issues/discussions
4. Open an issue with:
   - What you expected
   - What actually happened
   - How to reproduce
   - Your game type / player count

### Suggesting Features

**Note:** This is intentionally minimal. We prioritize:
1. Zero gameplay impact
2. Simplicity over features
3. Privacy over tracking

Feature requests that increase complexity or add optional dependencies are unlikely to be accepted in the base SDK. **Consider forking instead.**

### Creating Your Own Version

You're encouraged to fork for:
- Custom event schemas
- Different analytics backend
- Additional validation
- Game-specific metrics

Example fork idea: **DropOff Plus**
```lua
-- Your fork: DropOffPlus.lua
-- Adds your own features while maintaining base functionality

local DropOff = require(script.Parent:WaitForChild("DropOffAnalytics"))

local DropOffPlus = {}

function DropOffPlus.init(options)
    DropOff.init(options)
    
    -- Your custom initialization
    setupCustomMetrics()
end

function DropOffPlus.trackCustomEvent(player, eventType, data)
    -- Your custom event format
    -- Could send to different backend, or enrich events, etc.
end

return DropOffPlus
```

### Maintaining Your Fork

Keep your fork maintainable:
1. Pin base DropOff version in your code comments
2. Document your changes (e.g., `CUSTOMIZATIONS.md`)
3. Consider contributing generic improvements back
4. Test thoroughly with your game's specific use cases

---

## Architecture Overview

If you're modifying the SDK, understanding the architecture helps:

### Event Flow

```
1. Game Events (join/leave/input)
   ↓
2. emitEvent() - Validates and queues event
   ↓
3. state.pendingEvents[] - In-memory accumulation
   ↓
4. Flush trigger (timer or batch size)
   ↓
5. buildBatchPayload() - Package events
   ↓
6. serializePayload() - JSON encoding
   ↓
7. httpService:PostAsync() - Async HTTP send
   ↓
8. API receives /v1/events/batch - Processing on server
```

### Key Entry Points for Customization

```lua
-- Add custom event types
emitEvent(sessionId, "your_custom_type", { prop1 = "value" })

-- Customize batch payload
function buildBatchPayload()
    -- Add your own fields here
end

-- Change serialization
function serializePayload(payload)
    -- Custom JSON format, protobuf, msgpack, etc.
end

-- Modify HTTP handling
task.spawn(function()
    -- Different backend, compression, retry logic, etc.
end)
```

### Adding Custom Listeners

```lua
-- Example: Track specific item collection
game:GetService("Workspace").Items.ChildAdded:Connect(function(item)
    if item:FindFirstChild("Player") then
        local player = item.Player.Value
        DropOffAnalytics.markInteraction(player, "collected_" .. item.Name)
    end
end)
```

---

## Common Customizations

### 1. Change Event Batching Strategy

```lua
-- Instead of time-based flushing, flush on demand
local function onGameCheckpoint()
    DropOffAnalytics.flush()  -- Send immediately
end
```

### 2. Add Event Validation

```lua
-- Before emitting events, validate
local function safeEmitEvent(sessionId, eventType, props)
    if not sessionId or not eventType then
        log("error", "Invalid event parameters")
        return
    end
    emitEvent(sessionId, eventType, props)
end
```

### 3. Custom Event Compression

```lua
-- Compress event payload before sending
local function buildBatchPayload()
    local payload = { events = state.pendingEvents, ... }
    return game:GetService("HttpService"):JSONEncode(payload)
    -- Could add zstd compression here
end
```

### 4. Offline Persistence

```lua
-- Save events to DataStore if network fails
local DataStore = game:GetService("DataStoreService"):GetDataStore("analytics_offline")

if not httpSuccess then
    -- Save for later transmission
    DataStore:SetAsync("pending_events", state.pendingEvents)
end
```

---

## Testing Your Modifications

### Unit Testing Pattern

```lua
-- YourTest.server.lua
local DropOffAnalytics = require(script.Parent:WaitForChild("DropOffAnalytics"))

local function testInit()
    DropOffAnalytics.init({ projectKey = "pk_test_xxx" })
    assert(DropOffAnalytics.getPerfStats().eventsCaptured == 0)
    print("✓ Init test passed")
end

local function testEventEmission()
    -- Simulate player join
    local testPlayer = { UserId = 12345, Name = "TestPlayer" }
    emitEvent("test_session", "join", {})
    
    local stats = DropOffAnalytics.getPerfStats()
    assert(stats.eventsCaptured == 1)
    print("✓ Event emission test passed")
end

testInit()
testEventEmission()
print("All tests passed!")
```

### Studio Testing

Use the built-in test mode:
```lua
DropOffAnalytics.runStudioTest()
```

Then verify:
1. Check API logs for incoming request
2. Verify event structure in database
3. Check dashboard for test session data

---

## License & Attribution

This SDK is provided as MIT. No attribution required, but appreciated!

If you use or fork this SDK, a mention in your game's credits is nice:

```
Analytics powered by DropOff Analytics
https://github.com/YOUR_FORK_HERE
```

---

## Related Resources

- **Main SDK Documentation:** [README.md](../README.md)
- **Onboarding Patterns:** [phases.md](./phases.md)
- **Performance Deep Dive:** [performance.md](./performance.md)
- **DropOff Backend:** https://github.com/dropoff-analytics/dropoff

---

## Questions?

Before asking:
1. Check the README's troubleshooting section
2. Review the onboarding patterns in `phases.md`
3. Enable debug logging and check output
4. Test with `runStudioTest()` to verify connectivity

For issues with the base SDK, open a GitHub issue with:
- What version you're using
- Steps to reproduce
- Expected vs actual behavior
- Your game context (player count, game type)

---

## Feedback

We're interested in hearing about:
- How you're using the SDK
- Custom modifications you've made
- Performance in your specific game
- Ideas for the base SDK

This helps us prioritize and understand real-world use cases.

---

**Remember:** You own this code. Modify it, improve it, adapt it to your game. That's the whole point.

Good luck with your analytics! 🚀
