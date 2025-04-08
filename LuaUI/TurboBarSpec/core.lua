---@type {EventManager: EventManager}
local EventManagerModule = VFS.Include("LuaUI/TurboBarSpec/core/event_manager.lua")
---@type {Renderer: Renderer}
local RendererModule = VFS.Include("LuaUI/TurboBarSpec/core/renderer.lua")

---@return CoreModules
return {
    EventManager = EventManagerModule.EventManager,
    Renderer = RendererModule.Renderer
}