---@type WidgetContext
local WidgetContext = VFS.Include("LuaUI/TurboBarSpec/context.lua")
---@type CommonModules
local CommonModules = VFS.Include("LuaUI/TurboBarSpec/common.lua")
---@type {EventManager: EventManager}
local EventManagerModule = VFS.Include("LuaUI/TurboBarSpec/core/event_manager.lua")

local Log = CommonModules.Log
local Util = CommonModules.Util
local CONFIG = WidgetContext.CONFIG
local STATE = WidgetContext.STATE
local EventManager = EventManagerModule.EventManager

-- State references
local commanderUnits = STATE.commanderUnits
local lastCommanderHealth = STATE.lastCommanderHealth
local selfDestructingCommanders = STATE.selfDestructingCommanders
local lowHealthCommanders = STATE.lowHealthCommanders
local criticalHealthCommanders = STATE.criticalHealthCommanders

-- Constants
local CMD_SELFD = 65 -- Self destruct command ID
local ENEMY_DETECTION_RANGE = 360 -- Range to check for nearby enemies (in game units)

---@class CommanderTracker
local CommanderTracker = {
    CMD_SELFD = CMD_SELFD
}

---@param unitID number Unit ID to check
---@param range? number Optional detection range
---@return boolean hasEnemies Whether unit has nearby enemies
local function checkForNearbyEnemies(unitID, range)
    if not Spring.ValidUnitID(unitID) then
        return false
    end

    local teamID = Spring.GetUnitTeam(unitID)
    local x, y, z = Spring.GetUnitPosition(unitID)
    local detectionRange = range or ENEMY_DETECTION_RANGE

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
---@return boolean isCommander Whether the unit is a commander and was tracked
function CommanderTracker.checkIfCommander(unitID)
    if unitID and Spring.ValidUnitID(unitID) then
        local unitDefID = Spring.GetUnitDefID(unitID)
        local unitDef = UnitDefs[unitDefID]

        -- Check if the unit is a commander
        if unitDef and unitDef.customParams and unitDef.customParams.iscommander then
            local teamID = Spring.GetUnitTeam(unitID)
            local x, y, z = Spring.GetUnitPosition(unitID)

            -- Store commander information
            commanderUnits[unitID] = {
                unitDefID = unitDefID,
                teamID = teamID,
                lastPosition = { x = x, y = y, z = z },
                hasNearbyEnemies = false
            }

            -- Initialize health tracking
            local health, maxHealth = Spring.GetUnitHealth(unitID)
            if health and maxHealth then
                lastCommanderHealth[unitID] = health / maxHealth
            end

            return true
        end
    end

    return false
end

---@return number count Number of commanders found
function CommanderTracker.findAllCommanders()
    Log.debug("Finding all commanders...")
    local allUnits = Spring.GetAllUnits()
    for _, unitID in ipairs(allUnits) do
        CommanderTracker.checkIfCommander(unitID)
    end

    local count = Util.tableLength(commanderUnits)
    Log.debug("Found " .. count .. " commanders")
    return count
end

---@param unitID number Unit ID to check
---@param cmdID number Command ID
---@return boolean handled Whether the command was handled
function CommanderTracker.checkForSelfDestruct(unitID, cmdID)
    -- Command ID 65 is self-destruct
    if cmdID == CMD_SELFD and commanderUnits[unitID] then
        local data = commanderUnits[unitID]

        -- Toggle self-destruct status (in Spring, calling self-destruct again cancels it)
        local isCurrentlySelfDestructing = selfDestructingCommanders[unitID]

        if isCurrentlySelfDestructing then
            -- This is a cancellation
            selfDestructingCommanders[unitID] = nil
            Log.info("Commander canceled self-destruct: Team " .. data.teamID)

            -- Remove self-destruct events for this unit from the queue
            for i = #STATE.eventQueue, 1, -1 do
                if STATE.eventQueue[i].unitID == unitID and
                        (STATE.eventQueue[i].type == "COMMANDER_SELF_DESTRUCT" or
                                STATE.eventQueue[i].type == "COMMANDER_COMBOMB" or
                                STATE.eventQueue[i].type == "COMMANDER_SACRIFICE") then
                    table.remove(STATE.eventQueue, i)
                end
            end
        else
            -- This is an initiation
            selfDestructingCommanders[unitID] = true

            -- Check for nearby enemies to determine type of self-destruct
            local hasEnemiesNearby = checkForNearbyEnemies(unitID)
            data.hasNearbyEnemies = hasEnemiesNearby

            -- Log the event but DON'T add it to the event queue
            -- We'll just track it in selfDestructingCommanders and follow it
            if hasEnemiesNearby then
                Log.info("ALERT: Commander combomb! Team " .. data.teamID)
            else
                Log.info("Commander sacrifice: Team " .. data.teamID)
            end
        end

        return true
    end

    return false
end

---@param unitID number Unit ID that was destroyed
---@param unitDefID number Unit definition ID
---@param unitTeam number Team ID
---@return boolean handled Whether the unit was handled
function CommanderTracker.handleUnitDestroyed(unitID, unitDefID, unitTeam)
    if commanderUnits[unitID] then
        local lastPosition = commanderUnits[unitID].lastPosition
        local wasSelfDestructed = selfDestructingCommanders[unitID]

        if wasSelfDestructed then
            Log.info("Commander self-destructed: Team " .. unitTeam)

            -- Add commander self-destruct event
            EventManager.addEvent({
                type = "COMMANDER_SELF_DESTRUCTED",
                priority = 1,
                unitID = unitID,
                teamID = unitTeam,
                location = lastPosition,
                message = "Commander self-destructed! (Team " .. unitTeam .. ")",
                expiryFrame = Spring.GetGameFrame() + 300, -- Show for 10 seconds
            })
        else
            Log.info("Commander destroyed: Team " .. unitTeam)

            -- Add commander death event (normal death)
            EventManager.addEvent({
                type = "COMMANDER_DESTROYED",
                priority = 10, -- Highest priority
                unitID = unitID,
                teamID = unitTeam,
                location = lastPosition,
                message = "Commander destroyed (Team " .. unitTeam .. ")",
                expiryFrame = Spring.GetGameFrame() + 300, -- Show for 10 seconds
            })
        end

        -- Clean up our tracking tables
        commanderUnits[unitID] = nil
        lastCommanderHealth[unitID] = nil
        selfDestructingCommanders[unitID] = nil
        lowHealthCommanders[unitID] = nil
        criticalHealthCommanders[unitID] = nil

        return true
    end

    return false
end

---@param unitID number Unit ID that was given
---@param newTeam number New team ID
---@param oldTeam number Old team ID
function CommanderTracker.handleUnitGiven(unitID, newTeam, oldTeam)
    if commanderUnits[unitID] then
        commanderUnits[unitID].teamID = newTeam
        Log.debug("Commander transferred from team " .. oldTeam .. " to team " .. newTeam)
    end
end

-- Check health status of all tracked commanders
function CommanderTracker.checkCommanderHealth()
    for unitID, data in pairs(commanderUnits) do
        if Spring.ValidUnitID(unitID) then
            local health, maxHealth = Spring.GetUnitHealth(unitID)
            local x, y, z = Spring.GetUnitPosition(unitID)

            -- Update position
            data.lastPosition = { x = x, y = y, z = z }

            -- Check for nearby enemies
            data.hasNearbyEnemies = checkForNearbyEnemies(unitID)

            if health and maxHealth then
                local healthPercent = health / maxHealth
                local lastHealth = lastCommanderHealth[unitID] or 1.0

                -- Update last health regardless
                lastCommanderHealth[unitID] = healthPercent

                -- Skip health alerts for commanders that are self-destructing
                if not selfDestructingCommanders[unitID] then
                    -- Critical health check
                    if healthPercent <= CONFIG.EVENTS.COMMANDER.CRITICAL_HEALTH_THRESHOLD then
                        -- Add to tracking if not already there
                        if not criticalHealthCommanders[unitID] then
                            Log.info("ALERT: Commander critical health! Team " .. data.teamID .. " (" .. math.floor(healthPercent * 100) .. "%)")
                            criticalHealthCommanders[unitID] = true
                            -- Remove from low health tracking if it was there
                            lowHealthCommanders[unitID] = nil
                        end
                        -- Low health check
                    elseif healthPercent <= CONFIG.EVENTS.COMMANDER.LOW_HEALTH_THRESHOLD then
                        -- Add to tracking if not already there and wasn't critical before
                        if not lowHealthCommanders[unitID] and not criticalHealthCommanders[unitID] then
                            Log.info("Warning: Commander low health! Team " .. data.teamID .. " (" .. math.floor(healthPercent * 100) .. "%)")
                            lowHealthCommanders[unitID] = true
                        end
                        -- If it was critical before but now just low, update tracking
                        if criticalHealthCommanders[unitID] then
                            criticalHealthCommanders[unitID] = nil
                            lowHealthCommanders[unitID] = true
                        end
                    else
                        -- Health back to normal, remove from tracking
                        if lowHealthCommanders[unitID] or criticalHealthCommanders[unitID] then
                            lowHealthCommanders[unitID] = nil
                            criticalHealthCommanders[unitID] = nil
                        end
                    end
                end
            end
        else
            -- Unit no longer valid - remove from tracking
            commanderUnits[unitID] = nil
            lastCommanderHealth[unitID] = nil
            selfDestructingCommanders[unitID] = nil
            lowHealthCommanders[unitID] = nil
            criticalHealthCommanders[unitID] = nil
        end
    end
end

---@param gameFrame number Current game frame
---@param drawCylinder fun(x: number, y: number, z: number, radius: number, height: number, sides: number) Function to draw cylinder
function CommanderTracker.drawEventMarkers(gameFrame, drawCylinder)
    -- Draw self-destructing commanders
    for unitID, _ in pairs(selfDestructingCommanders) do
        if commanderUnits[unitID] then
            local data = commanderUnits[unitID]
            local x, y, z = Spring.GetUnitPosition(unitID)

            if x and y and z then
                -- Update the stored position with the latest
                data.lastPosition = { x = x, y = y, z = z }

                -- Get ground height
                y = Spring.GetGroundHeight(x, z)

                -- Different visualization based on enemy presence
                local hasNearbyEnemies = data.hasNearbyEnemies
                local pulseSpeed, color, baseRadius, pulseSize

                if hasNearbyEnemies then
                    -- Tactical combomb (high interest)
                    pulseSpeed = 15 -- Faster pulse for combomb (more urgent)
                    pulseSize = 10 -- Pulse size
                    baseRadius = 25 -- Base cylinder radius
                    color = { 1, 0.2, 0, 0.7 } -- Bright orange-red for combomb
                else
                    -- Com sacrifice (less interesting)
                    pulseSpeed = 30 -- Slower pulse
                    pulseSize = 5 -- Smaller pulse
                    baseRadius = 15 -- Smaller base radius
                    color = { 0.5, 0.5, 1, 0.6 } -- Blue for sacrifice
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
        end
    end

    -- Draw critical health commanders
    for unitID, _ in pairs(criticalHealthCommanders) do
        if commanderUnits[unitID] and not selfDestructingCommanders[unitID] then
            local data = commanderUnits[unitID]
            local x, y, z = Spring.GetUnitPosition(unitID)

            if x and y and z then
                -- Update the stored position with the latest
                data.lastPosition = { x = x, y = y, z = z }

                -- Get ground height
                y = Spring.GetGroundHeight(x, z)

                -- Critical health visualization
                local pulseSpeed = 20
                local baseRadius = 20
                local pulseSize = 8
                local color = { 1, 0, 0, 0.7 } -- Bright red for critical

                -- Calculate pulsing effect
                local pulseFactor = math.sin(gameFrame / pulseSpeed) * 0.5 + 0.5
                local radius = baseRadius + (pulseSize * pulseFactor)

                -- Draw pulsing cylinder
                gl.PushMatrix()
                gl.Color(color[1], color[2], color[3], color[4])
                drawCylinder(x, y, z, radius, 1000, 16)
                gl.PopMatrix()
            end
        end
    end

    -- Draw low health commanders
    for unitID, _ in pairs(lowHealthCommanders) do
        if commanderUnits[unitID] and not selfDestructingCommanders[unitID] then
            local data = commanderUnits[unitID]
            local x, y, z = Spring.GetUnitPosition(unitID)

            if x and y and z then
                -- Update the stored position with the latest
                data.lastPosition = { x = x, y = y, z = z }

                -- Get ground height
                y = Spring.GetGroundHeight(x, z)

                -- Low health visualization
                local pulseSpeed = 35
                local baseRadius = 15
                local pulseSize = 5
                local color = { 1, 0.5, 0, 0.6 } -- Orange for low health

                -- Calculate pulsing effect
                local pulseFactor = math.sin(gameFrame / pulseSpeed) * 0.5 + 0.5
                local radius = baseRadius + (pulseSize * pulseFactor)

                -- Draw pulsing cylinder
                gl.PushMatrix()
                gl.Color(color[1], color[2], color[3], color[4])
                drawCylinder(x, y, z, radius, 1000, 16)
                gl.PopMatrix()
            end
        end
    end
end

return {
    CommanderTracker = CommanderTracker
}