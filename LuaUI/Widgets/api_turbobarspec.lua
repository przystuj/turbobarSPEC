function widget:GetInfo()
    return {
        name = "Tactical Ultra-Responsive Broadcast Optimization for BAR Spectators",
        desc = "Tracks the action so you don’t have to.",
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
local STATE = WidgetContext.STATE

-- Reference to shared state
local commanderUnits = STATE.commanderUnits
local lastCommanderHealth = STATE.lastCommanderHealth
local eventQueue = STATE.eventQueue
local eventListeners = STATE.eventListeners

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
                lastPosition = {x = x, y = y, z = z}
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

-- Find all existing commanders (local helper function)
local function findAllCommanders()
    Log.debug("Finding all commanders...")
    local allUnits = Spring.GetAllUnits()
    for _, unitID in ipairs(allUnits) do
        checkIfCommander(unitID)
    end
    Log.debug("Found " .. Util.tableLength(commanderUnits) .. " commanders")
end

-- Add an event to the queue (local helper function)
local function addEvent(event)
    table.insert(eventQueue, event)

    -- Sort queue by priority (higher priority first)
    table.sort(eventQueue, function(a, b) return a.priority > b.priority end)

    -- Call any registered event listeners
    for id, listener in pairs(eventListeners) do
        if type(listener) == "function" then
            listener(event)
        end
    end
end

-- Update event queue (remove expired events) (local helper function)
local function updateEventQueue(currentFrame)
    for i = #eventQueue, 1, -1 do
        if eventQueue[i].expiryFrame <= currentFrame then
            table.remove(eventQueue, i)
        end
    end
end

-- Check health status of all tracked commanders (local helper function)
local function checkCommanderHealth()
    for unitID, data in pairs(commanderUnits) do
        if Spring.ValidUnitID(unitID) then
            local health, maxHealth = Spring.GetUnitHealth(unitID)
            local x, y, z = Spring.GetUnitPosition(unitID)

            -- Update position
            data.lastPosition = {x = x, y = y, z = z}

            if health and maxHealth then
                local healthPercent = health / maxHealth
                local lastHealth = lastCommanderHealth[unitID] or 1.0

                -- Critical health check
                if healthPercent <= CONFIG.EVENTS.COMMANDER.CRITICAL_HEALTH_THRESHOLD then
                    if lastHealth > CONFIG.EVENTS.COMMANDER.CRITICAL_HEALTH_THRESHOLD then
                        -- Commander just dropped to critical health
                        Log.info("ALERT: Commander critical health! Team " .. data.teamID .. " (" .. math.floor(healthPercent * 100) .. "%)")

                        -- Add to event queue
                        addEvent({
                            type = "COMMANDER_CRITICAL",
                            priority = 9,  -- Very high priority
                            unitID = unitID,
                            teamID = data.teamID,
                            location = data.lastPosition,
                            healthPercent = healthPercent,
                            message = "Commander in critical danger! (" .. math.floor(healthPercent * 100) .. "% health)",
                            expiryFrame = Spring.GetGameFrame() + 150,  -- Show for 5 seconds
                        })
                    end
                    -- Low health check
                elseif healthPercent <= CONFIG.EVENTS.COMMANDER.LOW_HEALTH_THRESHOLD then
                    if lastHealth > CONFIG.EVENTS.COMMANDER.LOW_HEALTH_THRESHOLD then
                        -- Commander just dropped to low health
                        Log.info("Warning: Commander low health! Team " .. data.teamID .. " (" .. math.floor(healthPercent * 100) .. "%)")

                        -- Add to event queue
                        addEvent({
                            type = "COMMANDER_LOW_HEALTH",
                            priority = 7,  -- High priority
                            unitID = unitID,
                            teamID = data.teamID,
                            location = data.lastPosition,
                            healthPercent = healthPercent,
                            message = "Commander in danger (" .. math.floor(healthPercent * 100) .. "% health)",
                            expiryFrame = Spring.GetGameFrame() + 120,  -- Show for 4 seconds
                        })
                    end
                end

                -- Update last health
                lastCommanderHealth[unitID] = healthPercent
            end
        else
            -- Unit no longer valid - remove from tracking
            commanderUnits[unitID] = nil
            lastCommanderHealth[unitID] = nil
        end
    end
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

        Log.info("Commander destroyed: Team " .. unitTeam)
        commanderUnits[unitID] = nil
        lastCommanderHealth[unitID] = nil

        -- Add commander death event
        addEvent({
            type = "COMMANDER_DESTROYED",
            priority = 10,  -- Highest priority
            unitID = unitID,
            teamID = unitTeam,
            location = lastPosition,
            message = "Commander destroyed (Team " .. unitTeam .. ")",
            expiryFrame = Spring.GetGameFrame() + 300,  -- Show for 10 seconds
        })
    end
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

-- Add drawing function to visualize events (optional, for debugging)
function widget:DrawWorld()
    -- Check if the gl functions we need are available
    if not gl then return end

    -- Verify all required functions exist before using them
    if not (gl.PushMatrix and gl.PopMatrix and gl.Translate and gl.Color and
            gl.LineWidth and gl.DrawGroundCircle) then
        return
    end

    for _, event in ipairs(eventQueue) do
        if event.location then
            -- Draw colored circles on the ground instead of spheres
            local color = {1, 0, 0, 0.5} -- Default red

            -- Different colors for different event types
            if event.type == "COMMANDER_CRITICAL" then
                color = {1, 0, 0, 0.7} -- Bright red for critical
            elseif event.type == "COMMANDER_LOW_HEALTH" then
                color = {1, 0.5, 0, 0.7} -- Orange for low health
            elseif event.type == "COMMANDER_DESTROYED" then
                color = {0.7, 0, 0, 0.8} -- Dark red for destroyed
            end

            gl.LineWidth(2.0)
            gl.Color(color[1], color[2], color[3], color[4])

            -- Draw a circle on the ground - safer than trying to use Sphere
            local radius = 100 -- Same size as your original sphere
            gl.DrawGroundCircle(event.location.x, event.location.y, event.location.z, radius, 30)
        end
    end
end