# Support

This SDK is proprietary software provided by DropOff Analytics.

## Getting Support

For technical support, integration help, or questions about the SDK, please contact DropOff Analytics through the official dashboard or support channels.

## Getting Help

### Questions About Integration

**Question:** How do I track a custom game event (e.g., player dies)?

**Answer:**
```lua
humanoid.Died:Connect(function()
    DropOffAnalytics.markInteraction(player, "died_in_gameplay")
end)
```

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

## Reporting Issues

If you encounter a bug or issue with the SDK:

1. Check the [Performance Considerations](./performance.md) docs
2. Enable debug logging: `logLevel = "debug"`
3. Contact DropOff Analytics support with:
   - What you expected
   - What actually happened
   - Steps to reproduce
   - Your game type / player count

---

## Related Resources

- **Main SDK Documentation:** [README.md](../README.md)
- **Onboarding Patterns:** [phases.md](./phases.md)
- **Performance Deep Dive:** [performance.md](./performance.md)
- **DropOff Dashboard:** https://dropoffanalytics.com

---

## License

This SDK is proprietary and confidential. See the LICENSE file for full terms.

Unauthorized copying, modification, or distribution of this software is strictly prohibited.

---

**DropOff Analytics** – Session analytics for Roblox games.
