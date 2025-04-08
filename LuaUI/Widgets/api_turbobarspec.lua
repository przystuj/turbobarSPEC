function widget:GetInfo()
    return {
        name = "Tactical Ultra-Responsive Broadcast Optimization for BAR Spectators",
        desc = "Tracks the action so you don't have to.",
        author = "SuperKitowiec",
        date = "April 2025",
        license = "GNU GPL, v2 or later",
        layer = 0,
        enabled = true,
        handler = true,
    }
end

---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarSpec/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarSpec/common.lua")
---@type EventModules
local EventModules = VFS.Include("LuaUI/TurboBarSpec/event.lua")
---@type CoreModules
local CoreModules = VFS.Include("LuaUI/TurboBarSpec/core.lua")

local Log = CommonModules.Log
local STATE = WidgetContext.STATE
local CONFIG = WidgetContext.CONFIG
local Renderer = CoreModules.Renderer
local EventManager = CoreModules.EventManager

-- Initialize widget
function widget:Shutdown()
    WG.TurboBarSpec = nil
end

-- Initialize widget
function widget:Initialize()
    Log.info("Spectator Events Tracker initialized")

    -- Normally we would restrict to spectator mode, but skipping for easier testing
    -- if (not Spring.IsReplay() and not Spring.IsCheatingEnabled()) then
    --     widgetHandler:RemoveWidget(self)
    --     return
    -- end

    EventModules.CommanderTracker.findAllCommanders()
end

-- Update on game start (for finding commanders in existing games)
function widget:GameStart()
    EventModules.CommanderTracker.findAllCommanders()
end

---@param unitID number Unit ID that was created
---@param unitDefID number Unit definition ID
---@param unitTeam number Team ID
function widget:UnitCreated(unitID, unitDefID, unitTeam)
    EventModules.CommanderTracker.checkIfCommander(unitID)
end

---@param unitID number Unit ID that was destroyed
---@param unitDefID number Unit definition ID
---@param unitTeam number Team ID
function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
    EventModules.CommanderTracker.handleUnitDestroyed(unitID, unitDefID, unitTeam)
    EventModules.SpybotTracker.handleUnitDestroyed(unitID, unitDefID, unitTeam)
end

---@param unitID number Unit ID receiving command
---@param unitDefID number Unit definition ID
---@param unitTeam number Team ID
---@param cmdID number Command ID
---@param cmdParams table Command parameters
---@param cmdOpts table Command options
---@param cmdTag number Command tag
function widget:UnitCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOpts, cmdTag)
    -- Handle self-destruct commands
    if cmdID == EventModules.CommanderTracker.CMD_SELFD then
        if EventModules.CommanderTracker.checkForSelfDestruct(unitID, cmdID) then
            return
        end

        if EventModules.SpybotTracker.checkForSelfDestruct(unitID, unitDefID, unitTeam, cmdID) then
            return
        end
    end

    -- Handle nuke launch commands
    EventModules.NukeTracker.checkForNukeLaunch(unitID, unitDefID, unitTeam, cmdID, cmdParams)
end

---@param unitID number Unit ID that was given
---@param unitDefID number Unit definition ID
---@param newTeam number New team ID
---@param oldTeam number Old team ID
function widget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
    EventModules.CommanderTracker.handleUnitGiven(unitID, newTeam, oldTeam)
end

---@param frame number Current game frame
function widget:GameFrame(frame)
    -- Only update on specific frames to reduce CPU usage
    if frame % CONFIG.PERFORMANCE.UPDATE_FREQUENCY == 0 then
        EventModules.CommanderTracker.checkCommanderHealth()
        EventModules.SpybotTracker.checkForSpybotsNearAntinukes()
        EventModules.NukeTracker.updateNukes(frame)
        EventManager.updateEventQueue(frame)
    end
end

-- Draw event markers in the game world
function widget:DrawWorld()
    Renderer.drawEventMarkers()
end

---@return EventData[] events List of current events
function widget:GetEvents()
    return STATE.eventQueue
end

---@param id string Listener identifier
---@param callback function Callback function that receives events
---@return boolean success Whether registration was successful
function widget:RegisterEventListener(id, callback)
    return EventManager.registerEventListener(id, callback)
end

---@param id string Listener identifier
---@return boolean success Whether unregistration was successful
function widget:UnregisterEventListener(id)
    return EventManager.unregisterEventListener(id)
end