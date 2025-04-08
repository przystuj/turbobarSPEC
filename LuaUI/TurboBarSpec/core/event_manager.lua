---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarSpec/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarSpec/common.lua")

local Log = CommonModules.Log
local STATE = WidgetContext.STATE

local eventQueue = STATE.eventQueue
local eventListeners = STATE.eventListeners

---@class EventManager
local EventManager = {}

---@param event EventData
function EventManager.addEvent(event)
    table.insert(eventQueue, event)

    -- Sort queue by priority (higher priority first)
    table.sort(eventQueue, function(a, b)
        return a.priority > b.priority
    end)

    -- Call any registered event listeners
    for id, listener in pairs(eventListeners) do
        if type(listener) == "function" then
            listener(event)
        end
    end
end

---@param currentFrame number Current game frame
function EventManager.updateEventQueue(currentFrame)
    for i = #eventQueue, 1, -1 do
        if eventQueue[i].expiryFrame <= currentFrame then
            table.remove(eventQueue, i)
        end
    end
end

---@param id string Listener identifier
---@param callback function Callback function that receives EventData
---@return boolean success Whether registration was successful
function EventManager.registerEventListener(id, callback)
    if type(callback) == "function" then
        eventListeners[id] = callback
        Log.debug("Registered event listener: " .. id)
        return true
    else
        Log.info("Failed to register event listener: " .. id .. " (not a function)")
        return false
    end
end

---@param id string Listener identifier
---@return boolean success Whether unregistration was successful
function EventManager.unregisterEventListener(id)
    if eventListeners[id] then
        eventListeners[id] = nil
        Log.debug("Unregistered event listener: " .. id)
        return true
    else
        return false
    end
end

return {
    EventManager = EventManager
}