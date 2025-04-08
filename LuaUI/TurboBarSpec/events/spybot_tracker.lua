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
local selfDestructingSpybots = STATE.selfDestructingSpybots
local spybotsNearAntinuke = STATE.spybotsNearAntinuke

-- Constants
local CMD_SELFD = 65 -- Self destruct command ID
local SPYBOT_DETECTION_RANGE = 220 -- Range to check for enemies near spybots
local SPYBOT_ANTINUKE_ALERT_RANGE = 600 -- Range to check for antinukes near spybots

---@class SpybotTracker
local SpybotTracker = {}

---@param unitDefID number Unit definition ID
---@return boolean isSpybot
local function isSpybot(unitDefID)
    local unitDef = UnitDefs[unitDefID]
    return unitDef and unitDef.name and unitDef.name:lower() == "armspy"
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

---@param unitID number Unit ID to check
---@param range? number Optional detection range
---@return boolean hasEnemies
local function checkForNearbyEnemies(unitID, range)
    if not Spring.ValidUnitID(unitID) then
        return false
    end

    local teamID = Spring.GetUnitTeam(unitID)
    local x, y, z = Spring.GetUnitPosition(unitID)
    local detectionRange = range or SPYBOT_DETECTION_RANGE

    -- Get all units in the detection range
    local nearbyUnits = Spring.GetUnitsInCylinder(x, z, detectionRange)

    -- Check if any of them are enemies
    for _, nearUnitID in ipairs(nearbyUnits) do
        local nearTeamID = Spring.GetUnitTeam(nearUnitID)

        -- If not the same team and not allied
        if nearTeamID ~= teamID and not Spring.AreTeamsAllied(teamID, nearTeamID) then
            return true
        end
    end

    return false
end

---@param unitID number Unit ID to check
---@param range? number Optional detection range
---@return boolean hasAntinuke
local function checkForNearbyAntinuke(unitID, range)
    if not Spring.ValidUnitID(unitID) then
        return false
    end

    local teamID = Spring.GetUnitTeam(unitID)
    local x, y, z = Spring.GetUnitPosition(unitID)
    local detectionRange = range or SPYBOT_DETECTION_RANGE

    -- Get all units in the detection range
    local nearbyUnits = Spring.GetUnitsInCylinder(x, z, detectionRange)

    -- Check if any of them are enemy antinukes
    for _, nearUnitID in ipairs(nearbyUnits) do
        local nearTeamID = Spring.GetUnitTeam(nearUnitID)
        local nearUnitDefID = Spring.GetUnitDefID(nearUnitID)

        -- If not the same team, not allied, and is an antinuke
        if nearTeamID ~= teamID and
                not Spring.AreTeamsAllied(teamID, nearTeamID) and
                isAntinuke(nearUnitDefID) then
            return true
        end
    end

    return false
end

-- Check for spybots near antinukes
function SpybotTracker.checkForSpybotsNearAntinukes()
    local allUnits = Spring.GetAllUnits()
    for _, unitID in ipairs(allUnits) do
        local unitDefID = Spring.GetUnitDefID(unitID)

        -- Check if it's a spybot
        if isSpybot(unitDefID) and Spring.ValidUnitID(unitID) then
            local hasAntinukeNearby = checkForNearbyAntinuke(unitID, SPYBOT_ANTINUKE_ALERT_RANGE)

            -- If spybot is near antinuke and we're not already tracking it
            if hasAntinukeNearby and not spybotsNearAntinuke[unitID] and not selfDestructingSpybots[unitID] then
                local teamID = Spring.GetUnitTeam(unitID)
                local x, y, z = Spring.GetUnitPosition(unitID)
                local position = { x = x, y = y, z = z }

                -- Start tracking this spybot
                spybotsNearAntinuke[unitID] = {
                    teamID = teamID,
                    position = position,
                    firstDetected = Spring.GetGameFrame()
                }

                -- Log this once
                Log.info("ALERT: Spybot near enemy Antinuke! (Team " .. teamID .. ")")

                -- Add a one-time event for notification
                EventManager.addEvent({
                    type = "SPYBOT_NEAR_ANTINUKE_NOTIFICATION",
                    priority = 9,
                    unitID = unitID,
                    teamID = teamID,
                    location = position,
                    message = "ALERT: Spybot near enemy Antinuke! (Team " .. teamID .. ")",
                    expiryFrame = Spring.GetGameFrame() + 90, -- Show notification for 3 seconds
                })
                -- If spybot is no longer near antinuke but we were tracking it
            elseif not hasAntinukeNearby and spybotsNearAntinuke[unitID] then
                -- Stop tracking this spybot
                spybotsNearAntinuke[unitID] = nil
                -- If still near antinuke and we're tracking it, update position
            elseif hasAntinukeNearby and spybotsNearAntinuke[unitID] then
                local x, y, z = Spring.GetUnitPosition(unitID)
                spybotsNearAntinuke[unitID].position = { x = x, y = y, z = z }
            end
        end
    end

    -- Remove any invalid units from tracking
    for unitID in pairs(spybotsNearAntinuke) do
        if not Spring.ValidUnitID(unitID) then
            spybotsNearAntinuke[unitID] = nil
        end
    end
end

---@param unitID number Unit ID that was destroyed
---@param unitDefID number Unit definition ID
---@param unitTeam number Team ID
---@return boolean handled Whether the unit was handled
function SpybotTracker.handleUnitDestroyed(unitID, unitDefID, unitTeam)
    if selfDestructingSpybots[unitID] then
        local spybotData = selfDestructingSpybots[unitID]
        local position = spybotData.position
        local hasAntinuke = spybotData.hasAntinukeNearby
        local hasEnemies = spybotData.hasEnemiesNearby

        -- Add spybot destroyed event with appropriate type and priority
        local priority = 5 -- Default priority
        local eventType = "SPYBOT_DESTROYED"
        local message = "Spybot destroyed (Team " .. unitTeam .. ")"

        if hasAntinuke then
            priority = 10 -- Highest priority if targeted antinuke
            eventType = "SPYBOT_ANTINUKE_DESTROYED"
            message = "CRITICAL: Spybot destroyed Antinuke! (Team " .. unitTeam .. ")"
            Log.info(message)
        elseif hasEnemies then
            priority = 8 -- High priority if targeted enemies
            eventType = "SPYBOT_ENEMIES_DESTROYED"
            message = "ALERT: Spybot destroyed enemies! (Team " .. unitTeam .. ")"
            Log.info(message)
        else
            Log.info("Spybot destroyed: Team " .. unitTeam)
        end

        -- Add event
        EventManager.addEvent({
            type = eventType,
            priority = priority,
            unitID = unitID,
            teamID = unitTeam,
            location = position,
            message = message,
            expiryFrame = Spring.GetGameFrame() + 300, -- Show for 10 seconds
        })

        -- Clean up tracking
        selfDestructingSpybots[unitID] = nil
        return true
    end

    return false
end

---@param gameFrame number Current game frame
---@param drawCylinder fun(x: number, y: number, z: number, radius: number, height: number, sides: number) Function to draw cylinder
function SpybotTracker.drawEventMarkers(gameFrame, drawCylinder)
    -- Draw self-destructing spybots
    for unitID, data in pairs(selfDestructingSpybots) do
        if Spring.ValidUnitID(unitID) then
            local x, y, z = Spring.GetUnitPosition(unitID)

            if x and y and z then
                -- Update the stored position
                data.position = { x = x, y = y, z = z }

                -- Get ground height
                y = Spring.GetGroundHeight(x, z)

                -- Different visualization based on what's nearby
                local pulseSpeed, color, baseRadius, pulseSize

                if data.hasAntinukeNearby then
                    -- Spybot targeting antinuke (highest interest)
                    pulseSpeed = 10 -- Very fast pulse (most urgent)
                    pulseSize = 12 -- Large pulse
                    baseRadius = 20 -- Large base radius
                    color = { 1, 0, 0, 0.8 } -- Pure red for antinuke attack
                elseif data.hasEnemiesNearby then
                    -- Spybot targeting enemies (high interest)
                    pulseSpeed = 15 -- Fast pulse
                    pulseSize = 8 -- Medium pulse
                    baseRadius = 15 -- Medium base radius
                    color = { 1, 0.3, 0, 0.7 } -- Orange-red for enemy attack
                else
                    -- Regular spybot self-destruct
                    pulseSpeed = 25 -- Slower pulse
                    pulseSize = 5 -- Smaller pulse
                    baseRadius = 10 -- Smaller base radius
                    color = { 0.3, 0.3, 1, 0.5 } -- Blue for non-tactical
                end

                -- Calculate pulsing effect
                local pulseFactor = math.sin(gameFrame / pulseSpeed) * 0.5 + 0.5
                local radius = baseRadius + (pulseSize * pulseFactor)

                -- Draw pulsing cylinder
                gl.PushMatrix()
                gl.Color(color[1], color[2], color[3], color[4])
                drawCylinder(x, y, z, radius, 1000, 16)
                gl.PopMatrix()
            end
        else
            -- Unit no longer valid - remove from tracking
            selfDestructingSpybots[unitID] = nil
        end
    end

    -- Draw spybots near antinukes (continuous tracking)
    for unitID, data in pairs(spybotsNearAntinuke) do
        if Spring.ValidUnitID(unitID) then
            local x, y, z = Spring.GetUnitPosition(unitID)

            if x and y and z then
                -- Update the stored position
                data.position = { x = x, y = y, z = z }

                -- Get ground height
                y = Spring.GetGroundHeight(x, z)

                -- Visualization for spybot near antinuke
                local pulseSpeed = 40 -- Slower pulse (less urgent than self-destruct)
                local pulseSize = 6 -- Medium pulse
                local baseRadius = 15 -- Medium radius
                local color = { 1, 0.7, 0, 0.6 } -- Yellow-orange for spybot near antinuke

                -- Calculate pulsing effect
                local pulseFactor = math.sin(gameFrame / pulseSpeed) * 0.5 + 0.5
                local radius = baseRadius + (pulseSize * pulseFactor)

                -- Draw pulsing cylinder
                gl.PushMatrix()
                gl.Color(color[1], color[2], color[3], color[4])
                drawCylinder(x, y, z, radius, 1000, 16)
                gl.PopMatrix()
            end
        else
            -- Unit no longer valid - remove from tracking
            spybotsNearAntinuke[unitID] = nil
        end
    end
end

return {
    SpybotTracker = SpybotTracker
}