---@type {Log: Log}
local LogModule = VFS.Include("LuaUI/TurboBarSpec/common/log.lua")
---@type {Util: Util}
local UtilsModule = VFS.Include("LuaUI/TurboBarSpec/common/utils.lua")

---@return CommonModules
return {
    Util = UtilsModule.Util,
    Log = LogModule.Log,
}