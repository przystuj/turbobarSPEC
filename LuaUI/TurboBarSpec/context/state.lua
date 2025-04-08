WG.TurboBarSpec = WG.TurboBarSpec or {}

if not WG.TurboBarSpec.STATE then
    ---@class WidgetState
    WG.TurboBarSpec.STATE = {
        commanderUnits = {},          -- Tracks all commanders by unitID
        lastCommanderHealth = {},     -- Tracks last health percentage of commanders
        selfDestructingCommanders = {},  -- Track commanders that are self-destructing
        lowHealthCommanders = {},     -- Track commanders with low health
        criticalHealthCommanders = {}, -- Track commanders with critical health

        selfDestructingSpybots = {},  -- Track spybots that are self-destructing
        spybotsNearAntinuke = {},     -- Track spybots that are near antinukes

        activeNukes = {},             -- Track active nuclear missiles
        nextNukeID = 1,               -- Counter for generating unique IDs for nuke tracks

        eventQueue = {},              -- Queue of active events
        eventListeners = {}           -- Event listeners
    }
end