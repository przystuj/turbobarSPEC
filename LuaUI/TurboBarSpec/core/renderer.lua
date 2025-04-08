---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarSpec/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarSpec/common.lua")
---@type EventModules
local EventModules = VFS.Include("LuaUI/TurboBarSpec/event.lua")

local Log = CommonModules.Log
local STATE = WidgetContext.STATE

---@class Renderer
local Renderer = {}

---@param x number X coordinate
---@param y number Y coordinate
---@param z number Z coordinate
---@param radius number Cylinder radius
---@param height number Cylinder height
---@param sides number Number of sides (detail level)
local function drawCylinder(x, y, z, radius, height, sides)
    if not gl.BeginEnd then
        return
    end

    local topY = y + height
    local bottomY = y

    gl.BeginEnd(GL.TRIANGLE_STRIP, function()
        for i = 0, sides do
            local angle = (i / sides) * (2 * math.pi)
            local px = x + radius * math.cos(angle)
            local pz = z + radius * math.sin(angle)

            -- Bottom vertex
            gl.Vertex(px, bottomY, pz)
            -- Top vertex
            gl.Vertex(px, topY, pz)
        end
    end)
end

---@param x number X coordinate
---@param y number Y coordinate
---@param z number Z coordinate
---@param radius number Cylinder radius
---@param height number Cylinder height
---@param sides number Number of sides (detail level)
local function drawFilledCylinder(x, y, z, radius, height, sides)
    if not gl.BeginEnd then
        return
    end

    local topY = y + height
    local bottomY = y

    -- Draw the sides (like before)
    gl.BeginEnd(GL.TRIANGLE_STRIP, function()
        for i = 0, sides do
            local angle = (i / sides) * (2 * math.pi)
            local px = x + radius * math.cos(angle)
            local pz = z + radius * math.sin(angle)

            -- Bottom vertex
            gl.Vertex(px, bottomY, pz)
            -- Top vertex
            gl.Vertex(px, topY, pz)
        end
    end)

    -- Draw bottom circular face
    gl.BeginEnd(GL.TRIANGLE_FAN, function()
        gl.Vertex(x, bottomY, z)  -- Center point
        for i = 0, sides do
            local angle = (i / sides) * (2 * math.pi)
            local px = x + radius * math.cos(angle)
            local pz = z + radius * math.sin(angle)
            gl.Vertex(px, bottomY, pz)
        end
    end)

    -- Draw top circular face
    gl.BeginEnd(GL.TRIANGLE_FAN, function()
        gl.Vertex(x, topY, z)  -- Center point
        for i = sides, 0, -1 do  -- Reverse order to maintain correct winding
            local angle = (i / sides) * (2 * math.pi)
            local px = x + radius * math.cos(angle)
            local pz = z + radius * math.sin(angle)
            gl.Vertex(px, topY, pz)
        end
    end)
end

---@param priority number Event priority
---@return table color RGBA color array {r, g, b, a} with values from 0-1
local function getPriorityColor(priority)
    -- Higher priority = more red, less other colors
    if priority >= 10 then
        return { 1, 0, 0, 0.4 } -- Highest priority: pure red
    elseif priority >= 8 then
        return { 1, 0.2, 0, 0.4 } -- Very high: red-orange
    elseif priority >= 6 then
        return { 1, 0.4, 0, 0.4 } -- High: orange
    elseif priority >= 4 then
        return { 1, 0.7, 0, 0.4 } -- Medium: yellow-orange
    else
        return { 0.7, 0.7, 0.7, 0.4 } -- Low priority: gray
    end
end

---@param priority number Event priority
---@return number radius Cylinder radius scaled by priority
local function getPriorityRadius(priority)
    -- Base radius is 3, adds 2 for each priority level
    return 3 + (priority * 2)
end

-- Draw all event markers in the game world
function Renderer.drawEventMarkers()
    -- Check if the gl functions we need are available
    if not gl then
        return
    end

    -- Verify all required functions exist before using them
    if not (gl.PushMatrix and gl.PopMatrix and gl.Translate and gl.Color and
            gl.LineWidth and gl.BeginEnd) then
        return
    end

    -- Get current game frame for pulsing effects
    local gameFrame = Spring.GetGameFrame()

    -- Draw commander markers
    EventModules.CommanderTracker.drawEventMarkers(gameFrame, drawCylinder)

    -- Draw spybot markers
    EventModules.SpybotTracker.drawEventMarkers(gameFrame, drawCylinder)

    -- Draw nuke markers
    EventModules.NukeTracker.drawEventMarkers(gameFrame, drawCylinder, drawFilledCylinder)

    -- Draw static event-based visualizations
    Renderer.drawStaticEventMarkers(gameFrame)
end