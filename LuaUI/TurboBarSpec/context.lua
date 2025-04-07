WG.TurboBarSpec = WG.TurboBarSpec or {}

VFS.Include("LuaUI/TurboBarSpec/context/state.lua")
VFS.Include("LuaUI/TurboBarSpec/context/config.lua")

---@return WidgetContext
return {
    CONFIG = WG.TurboBarSpec.CONFIG,
    STATE = WG.TurboBarSpec.STATE
}