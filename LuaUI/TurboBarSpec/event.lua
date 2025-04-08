---@type {CommanderTracker: CommanderTracker}
local CommanderTracker = VFS.Include("LuaUI/TurboBarSpec/events/commander_tracker.lua")
---@type {SpybotTracker: SpybotTracker}
local SpybotTracker = VFS.Include("LuaUI/TurboBarSpec/events/spybot_tracker.lua")
---@type {NukeTracker: NukeTracker}
local NukeTracker = VFS.Include("LuaUI/TurboBarSpec/events/nuke_tracker.lua")

---@return EventModules
return {
    CommanderTracker = CommanderTracker.CommanderTracker,
    SpybotTracker = SpybotTracker.SpybotTracker,
    NukeTracker = NukeTracker.NukeTracker
}