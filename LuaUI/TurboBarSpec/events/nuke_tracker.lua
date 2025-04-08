---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarSpec/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarSpec/common.lua")
---@type {EventManager: EventManager}
local EventManagerModule = VFS.Include("LuaUI/TurboBarSpec/core/event_manager.lua")

local Log = CommonModules.Log
local STATE = WidgetContext.STATE
local EventManager = EventManagerModule.EventManager

-- State references
local activeNukes = STATE.activeNukes
local nextNukeID = STATE.nextNukeID

-- Constants
local ANTINUKE_COVERAGE_RANGE = 2000 -- Approximate range of antinuke defense coverage

---@class NukeTracker
local NukeTracker = {}

---@param unitDefID number Unit definition ID
---@return boolean isNukeSilo
local function isNukeSilo(unitDefID)
    local unitDef = UnitDefs[unitDefID]
    if not unitDef then
        return false
    end
    local name = unitDef.name and unitDef.name:lower()

    -- Check for known nuke silo names
    return name == "corsilo" or name == "armsilo"
end

---@param unitDefID number Unit definition ID
---@return boolean isAntinuke
local function isAntinuke(unitDefID)
    local unitDef = UnitDefs[unitDefID]
    if not unitDef then
        return false
    end
    local name = unitDef.name and unitDef.name:lower()
    return name == "armamd" or name == "corfmd" -- Common antinuke unit names
end

---@param position Position Position to check
---@return boolean isCovered Whether position is covered by an antinuke
local function isPositionCoveredByAntinuke(position)
    -- Get all units
    local allUnits = Spring.GetAllUnits()

    for _, unitID in ipairs(allUnits) do
        local unitDefID = Spring.GetUnitDefID(unitID)

        -- Check if it's an antinuke
        if isAntinuke(unitDefID) then
            -- Get position
            local x, y, z = Spring.GetUnitPosition(unitID)

            -- Check if unit is active/operational (not being built or disabled)
            local _, _, _, _, buildProgress = Spring.GetUnitHealth(unitID)
            local isComplete = buildProgress >= 1.0

            if isComplete then
                -- Calculate distance to the target position
                local dx = position.x - x
                local dz = position.z - z
                local distSq = dx * dx + dz * dz

                -- If within coverage range, it's protected
                if distSq <= (ANTINUKE_COVERAGE_RANGE * ANTINUKE_COVERAGE_RANGE) then
                    return true
                end
            end
        end
    end

    -- No antinuke coverage found
    return false
end

---@param currentFrame number Current game frame
function NukeTracker.updateNukes(currentFrame)
    -- Check each active nuke
    for nukeID, nukeData in pairs(activeNukes) do
        -- Check if nuke has launched (preparation time complete)
        if currentFrame >= nukeData.launchFrame then
            -- Adjust priority if not intercepted after preparation
            if not nukeData.isCovered and not nukeData.priorityUpdated then
                -- Increase priority to 8 for undefended nukes
                for i, event in ipairs(STATE.eventQueue) do
                    if event.unitID == nukeData.siloUnitID and event.type == "NUKE_LAUNCH_LOADING" then
                        event.priority = 8
                        event.type = "NUKE_LAUNCH_UNDEFENDED"
                        event.message = "CRITICAL: Undefended nuke launch! (Team " .. nukeData.teamID .. ")"
                        break
                    end
                end
                nukeData.priorityUpdated = true
            end

            -- Check if nuke has reached its destination (based on flight time)
            if currentFrame >= nukeData.expiryFrame then
                local targetPos = nukeData.targetPosition
                local teamID = nukeData.teamID

                -- Add event for nuke detonation or interception
                local eventType, message, priority

                if nukeData.isCovered then
                    eventType = "NUKE_INTERCEPTED"
                    message = "Nuke intercepted (Team " .. teamID .. ")"
                    priority = 1
                else
                    eventType = "NUKE_DETONATION"
                    message = "CRITICAL: Nuclear detonation! (Team " .. teamID .. ")"
                    priority = 10
                end

                EventManager.addEvent({
                    type = eventType,
                    priority = priority,
                    teamID = teamID,
                    location = targetPos,
                    message = message,
                    expiryFrame = currentFrame + 600, -- Show for 10 seconds
                })

                Log.info(message)

                -- Remove from tracking
                activeNukes[nukeID] = nil
            else
                -- Update nuke position based on interpolation between launch and target
                local launchPos = nukeData.position
                local targetPos = nukeData.targetPosition
                local totalFrames = nukeData.expiryFrame - nukeData.launchFrame
                local elapsedFrames = currentFrame - nukeData.launchFrame
                local progress = math.min(1.0, elapsedFrames / totalFrames)

                -- Calculate current position (with arc trajectory)
                local dx = targetPos.x - launchPos.x
                local dz = targetPos.z - launchPos.z

                -- Simple ballistic arc
                local arcHeight = 1000 -- Maximum height of the arc
                local arcProgress = math.sin(progress * math.pi) -- 0 to 1 to 0

                local currentPos = {
                    x = launchPos.x + dx * progress,
                    z = launchPos.z + dz * progress,
                    y = launchPos.y + arcHeight * arcProgress
                }

                -- Update the position
                nukeData.currentPosition = currentPos
            end
        end
    end
end

---@param gameFrame number Current game frame
---@param drawCylinder fun(x: number, y: number, z: number, radius: number, height: number, sides: number) Function to draw cylinder
---@param drawFilledCylinder fun(x: number, y: number, z: number, radius: number, height: number, sides: number) Function to draw filled cylinder
function NukeTracker.drawEventMarkers(gameFrame, drawCylinder, drawFilledCylinder)
    -- Draw nuclear missiles in flight
    for nukeID, data in pairs(activeNukes) do
        -- Get the current interpolated position
        local currentPos = data.currentPosition
        if currentPos then
            local x, y, z = currentPos.x, currentPos.y, currentPos.z
            local targetX, targetZ = data.targetPosition.x, data.targetPosition.z
            local targetY = Spring.GetGroundHeight(targetX, targetZ)

            -- Different visualization based on whether nuke will be intercepted
            local pulseSpeed, color, baseRadius, pulseSize

            if data.isCovered then
                -- Nuke that will be intercepted (less interesting)
                pulseSpeed = 30 -- Slower pulse
                pulseSize = 6 -- Smaller pulse
                baseRadius = 5 -- Smaller radius
                color = { 0.2, 0.7, 1, 0.6 } -- Blue for intercepted nuke
            else
                -- Nuke that won't be intercepted (high interest)
                pulseSpeed = 10 -- Very fast pulse (most urgent)
                pulseSize = 15 -- Large pulse
                baseRadius = 25 -- Large radius
                color = { 1, 0, 0, 0.8 } -- Bright red for dangerous nuke
            end

            -- Calculate pulsing effect
            local pulseFactor = math.sin(gameFrame / pulseSpeed) * 0.5 + 0.5
            local radius = baseRadius + (pulseSize * pulseFactor)

            -- Draw pulsing cylinder at nuke position
            gl.PushMatrix()
            gl.Color(color[1], color[2], color[3], color[4])
            drawCylinder(x, y, z, radius, 1000, 16)
            gl.PopMatrix()

            -- Draw target indicator for undefended nukes
            if not data.isCovered then
                local targetRadius = 30 + (pulseFactor * 15) -- Larger radius for target indicator
                gl.PushMatrix()
                gl.Color(1, 0, 0, 0.5) -- Red for impact point
                drawFilledCylinder(targetX, targetY, targetZ, 500, 100, 24)
                gl.PopMatrix()

                -- Draw a line connecting missile to target
                gl.PushMatrix()
                gl.Color(1, 0, 0, 0.3) -- Red with transparency
                gl.LineWidth(3.0)
                gl.BeginEnd(GL.LINES, function()
                    gl.Vertex(x, y, z)
                    gl.Vertex(targetX, targetY + 50, targetZ)
                end)
                gl.PopMatrix()
            end
        end
    end
end

return {
    NukeTracker = NukeTracker
}