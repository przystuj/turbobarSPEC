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

local Log = CommonModules.Log
local Util = CommonModules.Util
local CONFIG = WidgetContext.CONFIG

-- Reference to shared state
local STATE = WidgetContext.STATE
local commanderUnits = STATE.commanderUnits
local lastCommanderHealth = STATE.lastCommanderHealth
local eventQueue = STATE.eventQueue
local eventListeners = STATE.eventListeners
local selfDestructingCommanders = {} -- Track commanders that are self-destructing
local selfDestructingSpybots = {} -- Track spybots that are self-destructing

-- Constants
local CMD_SELFD = 65 -- Self destruct command ID
local ENEMY_DETECTION_RANGE = 360 -- Range to check for nearby enemies (in game units)
local SPYBOT_DETECTION_RANGE = 220 -- Range to check for enemies near spybots
local SPYBOT_ANTINUKE_ALERT_RANGE = 600 -- Range to check for antinukes near spybots

local lowHealthCommanders = {} -- Track commanders with low health
local criticalHealthCommanders = {} -- Track commanders with critical health


-- Check if a unit is a commander (local helper function)
local function checkIfCommander(unitID)
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

            Log.debug("Tracking commander: " .. unitID .. " (Team " .. teamID .. ")")
        end
    end
end



-- Add an event to the queue (local helper function)
local function addEvent(event)
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

-- Check if a unit is a spybot
local function isSpybot(unitDefID)
    local unitDef = UnitDefs[unitDefID]
    return unitDef and unitDef.name and unitDef.name:lower() == "armspy"
end

-- Check if a unit is an antinuke
local function isAntinuke(unitDefID)
    local unitDef = UnitDefs[unitDefID]
    if not unitDef then return false end
    local name = unitDef.name and unitDef.name:lower()
    return name == "armamd" or name == "corfmd" -- Common antinuke unit names
end

-- Check if a unit has nearby enemies (local helper function)
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

-- Check if a unit has nearby antinuke units
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

-- Regularly check for spybots near antinukes (will be called in GameFrame)
local spybotsNearAntinuke = {} -- Track spybots that are near antinukes

local function checkForSpybotsNearAntinukes()
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
                addEvent({
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

-- Find all existing commanders (local helper function)
local function findAllCommanders()
    Log.debug("Finding all commanders...")
    local allUnits = Spring.GetAllUnits()
    for _, unitID in ipairs(allUnits) do
        checkIfCommander(unitID)
    end
    Log.debug("Found " .. Util.tableLength(commanderUnits) .. " commanders")
end

-- Update event queue (remove expired events) (local helper function)
local function updateEventQueue(currentFrame)
    for i = #eventQueue, 1, -1 do
        if eventQueue[i].expiryFrame <= currentFrame then
            table.remove(eventQueue, i)
        end
    end
end

-- Check for self-destruct command (local helper function)
local function checkForSelfDestruct(unitID, cmdID)
    -- Command ID 65 is self-destruct
    if cmdID == CMD_SELFD then
        local unitDefID = Spring.GetUnitDefID(unitID)
        local teamID = Spring.GetUnitTeam(unitID)

        -- Check if it's a commander
        if commanderUnits[unitID] then
            local data = commanderUnits[unitID]

            -- Toggle self-destruct status (in Spring, calling self-destruct again cancels it)
            local isCurrentlySelfDestructing = selfDestructingCommanders[unitID]

            if isCurrentlySelfDestructing then
                -- This is a cancellation
                selfDestructingCommanders[unitID] = nil
                Log.info("Commander canceled self-destruct: Team " .. data.teamID)

                -- Remove self-destruct events for this unit from the queue
                for i = #eventQueue, 1, -1 do
                    if eventQueue[i].unitID == unitID and
                            (eventQueue[i].type == "COMMANDER_SELF_DESTRUCT" or
                                    eventQueue[i].type == "COMMANDER_COMBOMB" or
                                    eventQueue[i].type == "COMMANDER_SACRIFICE") then
                        table.remove(eventQueue, i)
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
            -- Check if it's a spybot
        elseif isSpybot(unitDefID) then
            local x, y, z = Spring.GetUnitPosition(unitID)
            local position = { x = x, y = y, z = z }

            -- Toggle self-destruct status
            local isCurrentlySelfDestructing = selfDestructingSpybots[unitID]

            if isCurrentlySelfDestructing then
                -- This is a cancellation
                selfDestructingSpybots[unitID] = nil
                Log.info("Spybot canceled self-destruct: Team " .. teamID)

                -- Remove spybot self-destruct events for this unit from the queue
                for i = #eventQueue, 1, -1 do
                    if eventQueue[i].unitID == unitID and eventQueue[i].type == "SPYBOT_SELF_DESTRUCT" then
                        table.remove(eventQueue, i)
                    end
                end
            else
                -- This is an initiation
                local hasEnemiesNearby = checkForNearbyEnemies(unitID, SPYBOT_DETECTION_RANGE)
                local hasAntinukeNearby = checkForNearbyAntinuke(unitID, SPYBOT_DETECTION_RANGE)

                selfDestructingSpybots[unitID] = {
                    teamID = teamID,
                    unitID = unitID,
                    position = position,
                    hasEnemiesNearby = hasEnemiesNearby,
                    hasAntinukeNearby = hasAntinukeNearby
                }

                -- Determine priority based on what's nearby
                local priority = 5 -- Default priority
                local eventType = "SPYBOT_SELF_DESTRUCT"
                local message = "Spybot self-destructing (Team " .. teamID .. ")"

                if hasAntinukeNearby then
                    priority = 10 -- Highest priority if antinuke nearby
                    eventType = "SPYBOT_ANTINUKE_ATTACK"
                    message = "CRITICAL: Spybot targeting Antinuke! (Team " .. teamID .. ")"
                    Log.info(message)

                    -- Add spybot self-destruct event
                    addEvent({
                        type = eventType,
                        priority = priority,
                        unitID = unitID,
                        teamID = teamID,
                        location = position,
                        message = message,
                        expiryFrame = Spring.GetGameFrame() + 300, -- Show for 10 seconds
                    })
                elseif hasEnemiesNearby then
                    priority = 8 -- High priority if enemies nearby
                    eventType = "SPYBOT_ENEMY_ATTACK"
                    message = "ALERT: Spybot targeting enemies! (Team " .. teamID .. ")"
                    Log.info(message)

                    -- Add spybot self-destruct event
                    addEvent({
                        type = eventType,
                        priority = priority,
                        unitID = unitID,
                        teamID = teamID,
                        location = position,
                        message = message,
                        expiryFrame = Spring.GetGameFrame() + 300, -- Show for 10 seconds
                    })
                else
                    -- No event for spybots with no enemies in range
                    Log.info("Spybot self-destructing (no enemies nearby): Team " .. teamID)
                end
            end

            return true
        end
    end

    return false
end

-- Check health status of all tracked commanders (local helper function)
local function checkCommanderHealth()
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

    findAllCommanders()
end

-- Update on game start (for finding commanders in existing games)
function widget:GameStart()
    findAllCommanders()
end

-- Called when new units are created
function widget:UnitCreated(unitID, unitDefID, unitTeam)
    checkIfCommander(unitID)
end

-- Called when units are destroyed
function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
    if commanderUnits[unitID] then
        local lastPosition = commanderUnits[unitID].lastPosition
        local wasSelfDestructed = selfDestructingCommanders[unitID]

        if wasSelfDestructed then
            Log.info("Commander self-destructed: Team " .. unitTeam)

            -- Add commander self-destruct event
            addEvent({
                type = "COMMANDER_SELF_DESTRUCTED",
                priority = 10, -- Highest priority
                unitID = unitID,
                teamID = unitTeam,
                location = lastPosition,
                message = "Commander self-destructed! (Team " .. unitTeam .. ")",
                expiryFrame = Spring.GetGameFrame() + 300, -- Show for 10 seconds
            })
        else
            Log.info("Commander destroyed: Team " .. unitTeam)

            -- Add commander death event (normal death)
            addEvent({
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
    elseif selfDestructingSpybots[unitID] then
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
        addEvent({
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
    end
end

-- Intercept unit commands to detect self-destruct
function widget:UnitCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOpts, cmdTag)
    checkForSelfDestruct(unitID, cmdID)
end

-- When unit is given (used for detecting commander transfers)
function widget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
    if commanderUnits[unitID] then
        commanderUnits[unitID].teamID = newTeam
        Log.debug("Commander transferred from team " .. oldTeam .. " to team " .. newTeam)
    end
end

-- Main update function
function widget:GameFrame(frame)
    -- Only update on specific frames to reduce CPU usage
    if frame % CONFIG.PERFORMANCE.UPDATE_FREQUENCY == 0 then
        checkCommanderHealth()
        updateEventQueue(frame)
        -- Check for spybots near antinukes every update cycle
        checkForSpybotsNearAntinukes()
    end
end

-- API: Get all current events
function widget:GetEvents()
    return eventQueue
end

-- API: Register an event listener
function widget:RegisterEventListener(id, callback)
    if type(callback) == "function" then
        eventListeners[id] = callback
        Log.debug("Registered event listener: " .. id)
        return true
    else
        Log.info("Failed to register event listener: " .. id .. " (not a function)")
        return false
    end
end

-- API: Unregister an event listener
function widget:UnregisterEventListener(id)
    if eventListeners[id] then
        eventListeners[id] = nil
        Log.debug("Unregistered event listener: " .. id)
        return true
    else
        return false
    end
end

-- Add drawing function to visualize events
-- Draw a cylinder (local helper function)
local function drawCylinder(x, y, z, radius, height, sides)
    if not gl.BeginEnd then return end

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

local function getPriorityColor(priority)
    -- Higher priority = more red, less other colors
    if priority >= 10 then
        return {1, 0, 0, 0.4} -- Highest priority: pure red
    elseif priority >= 8 then
        return {1, 0.2, 0, 0.4} -- Very high: red-orange
    elseif priority >= 6 then
        return {1, 0.4, 0, 0.4} -- High: orange
    elseif priority >= 4 then
        return {1, 0.7, 0, 0.4} -- Medium: yellow-orange
    else
        return {0.7, 0.7, 0.7, 0.4} -- Low priority: gray
    end
end

-- Get cylinder radius based on priority (local helper function)
local function getPriorityRadius(priority)
    -- Base radius is 3, adds 2 for each priority level
    return 3 + (priority * 2)
end

-- Modified DrawWorld function to show cylinders for all tracked commanders and spybots
function widget:DrawWorld()
    -- Check if the gl functions we need are available
    if not gl then return end

    -- Verify all required functions exist before using them
    if not (gl.PushMatrix and gl.PopMatrix and gl.Translate and gl.Color and
            gl.LineWidth and gl.BeginEnd) then
        return
    end

    -- Get current game frame for pulsing effects
    local gameFrame = Spring.GetGameFrame()

    -- Draw self-destructing commanders
    for unitID, _ in pairs(selfDestructingCommanders) do
        if commanderUnits[unitID] then
            local data = commanderUnits[unitID]
            local x, y, z = Spring.GetUnitPosition(unitID)

            if x and y and z then
                -- Update the stored position with the latest
                data.lastPosition = {x = x, y = y, z = z}

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
                    color = {1, 0.2, 0, 0.7} -- Bright orange-red for combomb
                else
                    -- Com sacrifice (less interesting)
                    pulseSpeed = 30 -- Slower pulse
                    pulseSize = 5 -- Smaller pulse
                    baseRadius = 15 -- Smaller base radius
                    color = {0.5, 0.5, 1, 0.6} -- Blue for sacrifice
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

    -- Draw self-destructing spybots
    for unitID, data in pairs(selfDestructingSpybots) do
        if Spring.ValidUnitID(unitID) then
            local x, y, z = Spring.GetUnitPosition(unitID)

            if x and y and z then
                -- Update the stored position
                data.position = {x = x, y = y, z = z}

                -- Get ground height
                y = Spring.GetGroundHeight(x, z)

                -- Different visualization based on what's nearby
                local pulseSpeed, color, baseRadius, pulseSize

                if data.hasAntinukeNearby then
                    -- Spybot targeting antinuke (highest interest)
                    pulseSpeed = 10 -- Very fast pulse (most urgent)
                    pulseSize = 12 -- Large pulse
                    baseRadius = 20 -- Large base radius
                    color = {1, 0, 0, 0.8} -- Pure red for antinuke attack
                elseif data.hasEnemiesNearby then
                    -- Spybot targeting enemies (high interest)
                    pulseSpeed = 15 -- Fast pulse
                    pulseSize = 8 -- Medium pulse
                    baseRadius = 15 -- Medium base radius
                    color = {1, 0.3, 0, 0.7} -- Orange-red for enemy attack
                else
                    -- Regular spybot self-destruct
                    pulseSpeed = 25 -- Slower pulse
                    pulseSize = 5 -- Smaller pulse
                    baseRadius = 10 -- Smaller base radius
                    color = {0.3, 0.3, 1, 0.5} -- Blue for non-tactical
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
                data.position = {x = x, y = y, z = z}

                -- Get ground height
                y = Spring.GetGroundHeight(x, z)

                -- Visualization for spybot near antinuke
                local pulseSpeed = 40 -- Slower pulse (less urgent than self-destruct)
                local pulseSize = 6 -- Medium pulse
                local baseRadius = 15 -- Medium radius
                local color = {1, 0.7, 0, 0.6} -- Yellow-orange for spybot near antinuke

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

    -- Draw critical health commanders
    for unitID, _ in pairs(criticalHealthCommanders) do
        if commanderUnits[unitID] and not selfDestructingCommanders[unitID] then
            local data = commanderUnits[unitID]
            local x, y, z = Spring.GetUnitPosition(unitID)

            if x and y and z then
                -- Update the stored position with the latest
                data.lastPosition = {x = x, y = y, z = z}

                -- Get ground height
                y = Spring.GetGroundHeight(x, z)

                -- Critical health visualization
                local pulseSpeed = 20
                local baseRadius = 20
                local pulseSize = 8
                local color = {1, 0, 0, 0.7} -- Bright red for critical

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
                data.lastPosition = {x = x, y = y, z = z}

                -- Get ground height
                y = Spring.GetGroundHeight(x, z)

                -- Low health visualization
                local pulseSpeed = 35
                local baseRadius = 15
                local pulseSize = 5
                local color = {1, 0.5, 0, 0.6} -- Orange for low health

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

    -- Then draw all the static event-based visualizations as cylinders
    -- (Only draw ones that aren't actively being followed)
    for _, event in ipairs(eventQueue) do
        -- Only process event if it has location data and isn't for a unit we're actively following
        local isTrackedUnit = event.unitID and (
                selfDestructingCommanders[event.unitID] or
                        selfDestructingSpybots[event.unitID] or
                        spybotsNearAntinuke[event.unitID] or
                        lowHealthCommanders[event.unitID] or
                        criticalHealthCommanders[event.unitID]
        )

        if event.location and not isTrackedUnit then
            local x, y, z = event.location.x, event.location.y, event.location.z
            local priority = event.priority or 5
            local color = getPriorityColor(priority)
            local radius = getPriorityRadius(priority)

            -- Get terrain height at this position to avoid clipping
            y = Spring.GetGroundHeight(x, z)

            -- Check if this is a critical event that should pulse
            local shouldPulse = event.type == "COMMANDER_SELF_DESTRUCTED" or
                    event.type == "COMMANDER_DESTROYED" or
                    event.type == "SPYBOT_ANTINUKE_DESTROYED" or
                    event.type == "SPYBOT_ENEMIES_DESTROYED" or
                    event.type == "SPYBOT_ANTINUKE_ATTACK" or
                    event.type == "SPYBOT_NEAR_ANTINUKE_NOTIFICATION"

            -- Determine cylinder attributes based on event type
            if event.type == "COMMANDER_DESTROYED" then
                color = {0.7, 0, 0, 0.8} -- Dark red for destroyed
                radius = radius * 1.1 -- Slightly larger
            elseif event.type == "COMMANDER_SELF_DESTRUCTED" then
                color = {0.9, 0.1, 0.1, 0.8} -- Bright red for self-destruct
                radius = radius * 1.3 -- Even larger
            elseif event.type == "SPYBOT_ANTINUKE_DESTROYED" then
                color = {1, 0, 0, 0.9} -- Bright red for antinuke destruction
                radius = radius * 1.2 -- Larger for importance
            elseif event.type == "SPYBOT_ENEMIES_DESTROYED" then
                color = {1, 0.3, 0, 0.8} -- Orange-red for enemy destruction
                radius = radius * 1.1 -- Slightly larger
            elseif event.type == "SPYBOT_ANTINUKE_ATTACK" then
                color = {1, 0, 0, 0.7} -- Bright red for antinuke targeting
                radius = radius * 1.2 -- Larger for importance
            elseif event.type == "SPYBOT_ENEMY_ATTACK" then
                color = {1, 0.4, 0, 0.7} -- Orange-red for enemy targeting
                radius = radius * 1.1 -- Slightly larger
            elseif event.type == "SPYBOT_NEAR_ANTINUKE_NOTIFICATION" then
                color = {1, 0.7, 0, 0.6} -- Yellow-orange for spybot near antinuke notification
                radius = radius * 1.0 -- Standard size
            end

            -- Add pulsing effect if needed
            if shouldPulse then
                local pulseSpeed = 25
                local pulseSize = radius * 0.3 -- Pulse size relative to radius
                local pulseFactor = math.sin(gameFrame / pulseSpeed) * 0.5 + 0.5
                radius = radius + (pulseSize * pulseFactor)
            end

            -- Draw the cylinder
            gl.PushMatrix()
            gl.Color(color[1], color[2], color[3], color[4])
            drawCylinder(x, y, z, radius, 1000, 16)
            gl.PopMatrix()
        end
    end
end