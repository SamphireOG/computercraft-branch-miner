-- Advanced Branch Miner Work Coordinator
-- Manages work distribution, tunnel assignments, and turtle tracking

local config = require("config")
local protocol = require("protocol")
local state = require("state")

local coordinator = {}

-- ========== WORK QUEUE ==========

coordinator.workQueue = {}  -- Available tunnel assignments
coordinator.activeTurtles = {}  -- Registered turtles
coordinator.assignedWork = {}  -- Claimed tunnel assignments
coordinator.completedWork = {}  -- Finished tunnels
coordinator.lastHeartbeats = {}  -- Timestamp of last heartbeat per turtle

-- ========== INITIALIZATION ==========

function coordinator.init()
    coordinator.generateWorkQueue()
    -- Silent init for GUI mode
    -- print("Coordinator initialized with " .. #coordinator.workQueue .. " tunnel assignments")
end

function coordinator.generateWorkQueue()
    coordinator.workQueue = {}
    
    -- Generate tunnel assignments for all layers
    for layer = 1, config.NUM_LAYERS do
        local layerY = config.START_Y - (layer - 1) * config.LAYER_SPACING
        
        -- Generate tunnels for this layer
        local numTunnels = math.min(config.MAX_TUNNELS, 
                                    math.floor(config.TUNNEL_LENGTH / config.TUNNEL_SPACING))
        
        for tunnelNum = 1, numTunnels do
            local startX = config.HOME_X
            local startY = layerY
            local startZ = config.HOME_Z - (tunnelNum - 1) * config.TUNNEL_SPACING
            
            local endX = startX
            local endY = layerY
            local endZ = startZ - config.TUNNEL_LENGTH
            
            local assignment = {
                id = "L" .. layer .. "T" .. tunnelNum,
                layer = layer,
                tunnel = tunnelNum,
                startPos = {x = startX, y = startY, z = startZ},
                endPos = {x = endX, y = endY, z = endZ},
                status = "available",  -- "available", "assigned", "completed"
                assignedTo = nil,
                startedAt = nil,
                completedAt = nil
            }
            
            table.insert(coordinator.workQueue, assignment)
        end
    end
end

-- ========== TURTLE REGISTRATION ==========

function coordinator.registerTurtle(turtleID, label, fuelLevel)
    coordinator.activeTurtles[turtleID] = {
        id = turtleID,
        label = label or ("Turtle-" .. turtleID),
        status = "idle",
        fuelLevel = fuelLevel or 0,
        position = {x = config.HOME_X, y = config.HOME_Y, z = config.HOME_Z},
        assignedWork = nil,
        registeredAt = os.epoch("utc"),
        lastSeen = os.epoch("utc")
    }
    
    coordinator.lastHeartbeats[turtleID] = os.epoch("utc")
    
    -- Silent for GUI mode
    -- print("Registered turtle: " .. label .. " (ID: " .. turtleID .. ")")
    return true
end

function coordinator.unregisterTurtle(turtleID)
    local turtle = coordinator.activeTurtles[turtleID]
    if turtle and turtle.assignedWork then
        -- Release assigned work back to queue
        coordinator.releaseWork(turtle.assignedWork)
    end
    
    coordinator.activeTurtles[turtleID] = nil
    coordinator.lastHeartbeats[turtleID] = nil
    
    -- Silent for GUI mode
    -- print("Unregistered turtle ID: " .. turtleID)
end

-- ========== WORK ASSIGNMENT ==========

function coordinator.claimTunnel(turtleID)
    -- FIRST: Check if this turtle already has an unfinished assignment
    -- This allows turtles to resume their work after restart
    for _, assignment in ipairs(coordinator.workQueue) do
        if assignment.assignedTo == turtleID and assignment.status == "assigned" then
            -- Turtle is resuming its previous assignment
            -- Silent for GUI mode
            -- print("Turtle " .. turtleID .. " resuming " .. assignment.id)
            
            -- Update turtle record
            if coordinator.activeTurtles[turtleID] then
                coordinator.activeTurtles[turtleID].assignedWork = assignment.id
                coordinator.activeTurtles[turtleID].status = "mining"
            end
            
            return assignment
        end
    end
    
    -- SECOND: If no existing assignment, find next available tunnel
    for _, assignment in ipairs(coordinator.workQueue) do
        if assignment.status == "available" then
            -- Assign to turtle
            assignment.status = "assigned"
            assignment.assignedTo = turtleID
            assignment.startedAt = os.epoch("utc")
            
            coordinator.assignedWork[assignment.id] = assignment
            
            -- Update turtle record
            if coordinator.activeTurtles[turtleID] then
                coordinator.activeTurtles[turtleID].assignedWork = assignment.id
                coordinator.activeTurtles[turtleID].status = "mining"
            end
            
            -- Silent for GUI mode
            -- print("Assigned " .. assignment.id .. " to turtle " .. turtleID)
            return assignment
        end
    end
    
    -- No work available
    return nil
end

function coordinator.releaseWork(assignmentID)
    local assignment = coordinator.assignedWork[assignmentID]
    if assignment then
        assignment.status = "available"
        assignment.assignedTo = nil
        assignment.startedAt = nil
        
        coordinator.assignedWork[assignmentID] = nil
        -- Silent for GUI mode
        -- print("Released work: " .. assignmentID)
    end
end

function coordinator.completeTunnel(assignmentID, blocksMined, oresFound)
    local assignment = coordinator.assignedWork[assignmentID]
    if not assignment then
        -- Try to find in work queue by ID
        for _, work in ipairs(coordinator.workQueue) do
            if work.id == assignmentID then
                assignment = work
                break
            end
        end
    end
    
    if assignment then
        assignment.status = "completed"
        assignment.completedAt = os.epoch("utc")
        assignment.blocksMined = blocksMined or 0
        assignment.oresFound = oresFound or 0
        
        coordinator.completedWork[assignmentID] = assignment
        coordinator.assignedWork[assignmentID] = nil
        
        -- Update turtle status to idle so it can claim next tunnel
        if assignment.assignedTo and coordinator.activeTurtles[assignment.assignedTo] then
            coordinator.activeTurtles[assignment.assignedTo].assignedWork = nil
            coordinator.activeTurtles[assignment.assignedTo].status = "idle"
        end
        
        -- Silent for GUI mode
        -- print("Completed: " .. assignmentID .. " (" .. blocksMined .. " blocks, " .. oresFound .. " ores)")
        return true
    end
    
    -- Silent failure for GUI mode
    -- print("Warning: Could not find assignment " .. tostring(assignmentID))
    return false
end

-- ========== HEARTBEAT TRACKING ==========

function coordinator.updateHeartbeat(turtleID, status, position, fuel, inventory, currentTask)
    coordinator.lastHeartbeats[turtleID] = os.epoch("utc")
    
    if coordinator.activeTurtles[turtleID] then
        local turtle = coordinator.activeTurtles[turtleID]
        turtle.status = status or turtle.status
        turtle.position = position or turtle.position
        turtle.fuelLevel = fuel and fuel.level or turtle.fuelLevel
        turtle.lastSeen = os.epoch("utc")
    else
        -- Auto-register if not known
        coordinator.registerTurtle(turtleID, "Turtle-" .. turtleID, fuel and fuel.level)
    end
end

function coordinator.checkStaleHeartbeats()
    local now = os.epoch("utc")
    local stalled = {}
    
    for turtleID, lastBeat in pairs(coordinator.lastHeartbeats) do
        local ageSeconds = (now - lastBeat) / 1000
        
        if ageSeconds > config.OFFLINE_THRESHOLD then
            -- Turtle is offline
            -- Silent for GUI mode
            -- print("Turtle " .. turtleID .. " is offline (no heartbeat for " .. ageSeconds .. "s)")
            table.insert(stalled, turtleID)
        end
    end
    
    -- Handle stalled turtles
    for _, turtleID in ipairs(stalled) do
        coordinator.handleStalledTurtle(turtleID)
    end
end

function coordinator.handleStalledTurtle(turtleID)
    local turtle = coordinator.activeTurtles[turtleID]
    if turtle and turtle.assignedWork then
        -- Silent for GUI mode
        -- print("Releasing work from stalled turtle " .. turtleID)
        coordinator.releaseWork(turtle.assignedWork)
    end
    
    -- Don't unregister - turtle might come back online
    if coordinator.activeTurtles[turtleID] then
        coordinator.activeTurtles[turtleID].status = "offline"
    end
end

-- ========== STATISTICS ==========

function coordinator.getStatistics()
    local stats = {
        totalTunnels = #coordinator.workQueue,
        available = 0,
        assigned = 0,
        completed = 0,
        activeTurtles = 0,
        idleTurtles = 0,
        miningTurtles = 0,
        offlineTurtles = 0,
        totalBlocksMined = 0,
        totalOresFound = 0
    }
    
    -- Count work status
    for _, work in ipairs(coordinator.workQueue) do
        if work.status == "available" then
            stats.available = stats.available + 1
        elseif work.status == "assigned" then
            stats.assigned = stats.assigned + 1
        elseif work.status == "completed" then
            stats.completed = stats.completed + 1
        end
    end
    
    -- Count turtle status
    for _, turtle in pairs(coordinator.activeTurtles) do
        if turtle.status == "offline" then
            stats.offlineTurtles = stats.offlineTurtles + 1
        elseif turtle.status == "idle" or turtle.status == "returning" then
            stats.idleTurtles = stats.idleTurtles + 1
            stats.activeTurtles = stats.activeTurtles + 1
        elseif turtle.status == "mining" then
            stats.miningTurtles = stats.miningTurtles + 1
            stats.activeTurtles = stats.activeTurtles + 1
        end
    end
    
    -- Sum completed work stats
    for _, work in pairs(coordinator.completedWork) do
        stats.totalBlocksMined = stats.totalBlocksMined + (work.blocksMined or 0)
        stats.totalOresFound = stats.totalOresFound + (work.oresFound or 0)
    end
    
    -- Calculate progress
    if stats.totalTunnels > 0 then
        stats.percentComplete = math.floor((stats.completed / stats.totalTunnels) * 100)
    else
        stats.percentComplete = 0
    end
    
    return stats
end

function coordinator.printStatistics()
    local stats = coordinator.getStatistics()
    
    print("=== Coordinator Statistics ===")
    print("Tunnels: " .. stats.completed .. "/" .. stats.totalTunnels .. " (" .. stats.percentComplete .. "%)")
    print("  Available: " .. stats.available)
    print("  Assigned: " .. stats.assigned)
    print("  Completed: " .. stats.completed)
    print("")
    print("Turtles: " .. stats.activeTurtles .. " active")
    print("  Mining: " .. stats.miningTurtles)
    print("  Idle: " .. stats.idleTurtles)
    print("  Offline: " .. stats.offlineTurtles)
    print("")
    print("Total mined: " .. stats.totalBlocksMined .. " blocks, " .. stats.totalOresFound .. " ores")
    print("==============================")
end

-- ========== PERSISTENCE ==========

function coordinator.save()
    local data = {
        workQueue = coordinator.workQueue,
        activeTurtles = coordinator.activeTurtles,
        assignedWork = coordinator.assignedWork,
        completedWork = coordinator.completedWork,
        lastHeartbeats = coordinator.lastHeartbeats,
        savedAt = os.epoch("utc")
    }
    
    local file = fs.open("coordinator_state.dat", "w")
    if file then
        file.write(textutils.serialize(data))
        file.close()
        return true
    end
    
    return false
end

function coordinator.load()
    if not fs.exists("coordinator_state.dat") then
        return false, "No saved state"
    end
    
    local file = fs.open("coordinator_state.dat", "r")
    if not file then
        return false, "Could not open file"
    end
    
    local content = file.readAll()
    file.close()
    
    local data = textutils.unserialize(content)
    if not data then
        return false, "Could not parse file"
    end
    
    coordinator.workQueue = data.workQueue or {}
    coordinator.activeTurtles = data.activeTurtles or {}
    coordinator.assignedWork = data.assignedWork or {}
    coordinator.completedWork = data.completedWork or {}
    coordinator.lastHeartbeats = data.lastHeartbeats or {}
    
    print("Loaded coordinator state from " .. math.floor((os.epoch("utc") - data.savedAt) / 1000) .. "s ago")
    return true
end

return coordinator

