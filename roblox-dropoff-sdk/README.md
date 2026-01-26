# DropOff Analytics SDK for Roblox

A lightweight, high-performance analytics SDK for tracking player session lifecycle events in Roblox games. Designed to measure session abandonment and provide actionable insights with **zero impact on gameplay**.

## Features

- **Automatic Event Capture**: Join/leave, first input, first interaction, phase changes
- **Fail-Open Design**: Network failures never block gameplay
- **Batching & Rate Limiting**: Efficient event transmission with configurable batch sizes
- **Session Tracking**: Per-player session IDs (no user tracking, privacy-first)
- **Studio Test Mode**: Built-in testing with synthetic events
- **Zero Dependencies**: Pure Lua, works in all Roblox environments

## 60-Second Install

### 1. Copy the SDK

Download `DropOffAnalytics.lua` and place it in `ServerScriptService` as a ModuleScript:

```
ServerScriptService
  └── DropOffAnalytics (ModuleScript)
```

### 2. Initialize

In any Script in ServerScriptService, add:

```lua
local DropOffAnalytics = require(game:GetService("ServerScriptService"):WaitForChild("DropOffAnalytics"))

DropOffAnalytics.init({
    projectKey = "pk_live_YOUR_PROJECT_KEY_HERE"
    -- endpoint defaults to https://api.dropoffanalytics.com
})
```

### 3. Done!

The SDK now automatically captures:
- ✅ Player joins and leaves
- ✅ First input (movement detected)
- ✅ First interaction (ProximityPrompt triggered)
- ✅ Phase changes (you define phases)

## Basic Usage

### Set Game Phases

Call this when your game state changes:

```lua
DropOffAnalytics.setPhase(player, "loading")      -- Loading screen
DropOffAnalytics.setPhase(player, "playable")     -- Ready to play
DropOffAnalytics.setPhase(player, "gameplay")     -- In-game action
```

### Mark Custom Interactions

Track specific user interactions:

```lua
DropOffAnalytics.markInteraction(player, "clicked_start_button")
DropOffAnalytics.markInteraction(player, "entered_tutorial")
```

### Check Performance

Monitor SDK performance in real-time:

```lua
local stats = DropOffAnalytics.getPerfStats()
print("Events sent:", stats.eventsSent)
print("Errors:", stats.errors)
print("Pending:", stats.pendingEvents)
```

## Studio Testing

Test your integration directly in Roblox Studio:

```lua
-- Add this to a Script in ServerScriptService
local DropOffAnalytics = require(game:GetService("ServerScriptService"):WaitForChild("DropOffAnalytics"))

DropOffAnalytics.init({
    projectKey = "pk_test_studio",
    studioTestMode = true,  -- Marks events as test data
    logLevel = "debug"       -- Show all log messages
})

-- Run test
task.wait(2)  -- Let players load
DropOffAnalytics.runStudioTest()
```

The test simulates a complete player journey and logs the results. Check your DropOff dashboard for the test session.

## Configuration

```lua
DropOffAnalytics.init({
    projectKey = "pk_live_...",              -- REQUIRED: Your project key
    endpointBaseUrl = "https://...",         -- (default: https://api.dropoffanalytics.com)
    studioTestMode = false,                  -- (default: false)
    flushIntervalSeconds = 10,               -- (default: 10)
    maxBatchSize = 25,                       -- (default: 25)
    logLevel = "info"                        -- "debug"|"info"|"warn"|"error" (default: "info")
})
```

### Option Details

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `projectKey` | string | **required** | Bearer token from DropOff dashboard |
| `endpointBaseUrl` | string | `https://api.dropoffanalytics.com` | API endpoint URL |
| `studioTestMode` | boolean | `false` | Mark events as test (visible in dashboard) |
| `flushIntervalSeconds` | number | `10` | Seconds between auto-flushes |
| `maxBatchSize` | number | `25` | Events before forced flush |
| `logLevel` | string | `"info"` | Console logging level |

### HttpService Setup

**Important**: You must enable HTTP requests in your game settings:
1. Open Game Settings in Roblox Studio
2. Go to Security tab
3. Enable "Allow HTTP Requests"

## Architecture & Performance

### No RemoteEvents

The SDK uses **pure server-side listening** for all events. No RemoteEvents means:
- No network overhead (events batched, sent once per 10 seconds)
- No latency spikes during gameplay
- Graceful degradation if HTTP service is unavailable

### Event Capture Strategy

```lua
-- First Input: Low-frequency polling (every 100ms) on Humanoid.MoveDirection
-- Disconnects after first movement (zero overhead after detection)

-- First Interaction: Built-in listener for ProximityPromptService.PromptTriggered
-- (Or use markInteraction() for custom interactions)
```

### Batching Strategy

Events are accumulated in memory and sent in batches:
- **Flush triggers**: Every 10 seconds OR when batch reaches 25 events
- **On network failure**: Events are discarded (fail-open, no blocking)
- **No retries**: Data loss possible but gameplay never blocked

This trades data completeness for gameplay performance—appropriate for analytics.

### Session IDs

Each player gets a unique `session_id` generated when they join:
- No personally identifiable information (PII) sent
- Session ID tied to server instance, not player account
- Useful for grouping events by play session

## Event Types

### Automatic Events

| Event | When | Props |
|-------|------|-------|
| `join` | Player enters game | — |
| `leave` | Player exits game | — |
| `first_input` | Movement detected | — |
| `first_interaction` | ProximityPrompt triggered | — |
| `phase_change` | `setPhase()` called | `phase: string` |

### Custom Events

| Event | Trigger | Props |
|-------|---------|-------|
| `first_interaction` | `markInteraction()` called | `label: string` |

## Troubleshooting

### Events not appearing in dashboard?

1. Check your `projectKey` (visible in DropOff dashboard settings)
2. Verify `endpointBaseUrl` is correct (default: `https://api.dropoffanalytics.com`)
3. Enable `logLevel: "debug"` to see all SDK messages
4. Use `DropOffAnalytics.runStudioTest()` to verify HTTP connectivity

### High error rate?

Check that:
- HttpService is enabled in game settings
- Network connectivity to endpoint
- No firewall blocking requests

Errors don't block gameplay—they're logged but events are discarded.

### Studio test mode hangs?

If testing locally, make sure your API server is running. For production, no setup needed—events go to `https://api.dropoffanalytics.com`.

```lua
-- For local development only:
DropOffAnalytics.init({
    projectKey = "pk_test_xxx",
    endpointBaseUrl = "http://localhost:3001",  -- Local dev server
    studioTestMode = true
})
```

## API Reference

```lua
-- Initialization
DropOffAnalytics.init(options: table) -> nil

-- Phase tracking
DropOffAnalytics.setPhase(player: Player, phaseName: string) -> nil

-- Custom interactions
DropOffAnalytics.markInteraction(player: Player, label: string) -> nil

-- Manual flush
DropOffAnalytics.flush() -> nil

-- Performance monitoring
DropOffAnalytics.getPerfStats() -> {
    eventsCaptured: number,
    eventsSent: number,
    flushes: number,
    errors: number,
    lastFlushTime: number,
    pendingEvents: number
}

-- Studio testing
DropOffAnalytics.runStudioTest() -> sessionId: string
```

## Documentation

For detailed patterns and best practices, see:
- [Onboarding Patterns](./docs/phases.md) – Common integration examples
- [Performance Considerations](./docs/performance.md) – Architecture and trade-offs
- [Support & Contributing](./docs/support.md) – Fork policy and community

## License

Proprietary – See LICENSE file. This software is confidential and owned by DropOff Analytics. Unauthorized copying, modification, or distribution is prohibited.

## Support

For support inquiries, contact DropOff Analytics. See [docs/support.md](./docs/support.md) for details.

---

**Version:** 1.0.0  
**Built for:** Roblox Luau  
**Status:** Production-ready
