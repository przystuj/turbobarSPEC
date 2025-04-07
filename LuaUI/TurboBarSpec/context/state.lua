WG.TurboBarSpec = WG.TurboBarSpec or {}

if not WG.TurboBarSpec.STATE then
    ---@class WidgetState
    WG.TurboBarSpec.STATE = {
        commanderUnits = {},  -- Tracks all commanders by unitID
        lastCommanderHealth = {},  -- Tracks last health percentage of commanders
        eventQueue = {},  -- Queue of active events
        eventListeners = {}
    }
end