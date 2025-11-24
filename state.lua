-- Advanced Branch Miner State Management
-- Handles persistent state saving and loading for resumable operation

local state = {}

-- ========== STATE STRUCTURE ==========

function state.createNew()
    return {
        -- Identity
        computerID = os.getComputerID(),
        label = os.getComputerLabel() or ("Turtle-" .. os.getComputerID()),
        
        -- Position tracking
        position = {x = 0, y = 0, z = 0, facing = 0},
        homePosition = {x = 0, y = 0, z = 0},
        
        -- Work assignment
        assignedTunnel = nil,  -- {layer, tunnel, startPos, endPos}
        currentLayer = 1,
        currentTunnel = 1,
        blockProgress = 0,  -- Blocks mined in current tunnel
        
        -- Mining statistics
        totalBlocksMined = 0,
        oresFound = 0,
        tunnelsCompleted = 0,
        
        -- Status flags
        status = "idle",  -- "idle", "mining", "returning", "paused"
        isPaused = false,
        needsResupply = false,
        
        -- Inventory snapshot
        fuelLevel = 0,
        freeSlots = 16,
        
        -- Timestamps
        startedAt = os.epoch("utc"),
        lastSaveAt = os.epoch("utc"),
        lastPositionAt = os.epoch("utc"),
        
        -- Error recovery
        stuckCount = 0,
        lastError = nil,
        retryCount = 0,
        
        -- Version
        version = 1
    }
end

-- ========== FILE OPERATIONS ==========

function state.getFilename()
    local id = os.getComputerID()
    return "miner_state_" .. id .. ".dat"
end

function state.save(stateData)
    local filename = state.getFilename()
    
    -- Update timestamp
    stateData.lastSaveAt = os.epoch("utc")
    
    -- Serialize and save
    local file = fs.open(filename, "w")
    if not file then
        return false, "Could not open file for writing"
    end
    
    file.write(textutils.serialize(stateData))
    file.close()
    
    return true
end

function state.load()
    local filename = state.getFilename()
    
    if not fs.exists(filename) then
        return nil, "No saved state found"
    end
    
    local file = fs.open(filename, "r")
    if not file then
        return nil, "Could not open state file"
    end
    
    local content = file.readAll()
    file.close()
    
    if not content or content == "" then
        return nil, "State file is empty"
    end
    
    local stateData = textutils.unserialize(content)
    
    if not stateData then
        return nil, "Could not parse state file"
    end
    
    -- Validate state structure
    local valid, err = state.validate(stateData)
    if not valid then
        return nil, "Invalid state: " .. err
    end
    
    return stateData
end

function state.delete()
    local filename = state.getFilename()
    
    if fs.exists(filename) then
        fs.delete(filename)
        return true
    end
    
    return false, "No state file to delete"
end

-- ========== VALIDATION ==========

function state.validate(stateData)
    if type(stateData) ~= "table" then
        return false, "State is not a table"
    end
    
    -- Check required fields
    local required = {"computerID", "position", "status", "version"}
    for _, field in ipairs(required) do
        if stateData[field] == nil then
            return false, "Missing required field: " .. field
        end
    end
    
    -- Validate position
    if type(stateData.position) ~= "table" then
        return false, "Position is not a table"
    end
    
    if not stateData.position.x or not stateData.position.y or not stateData.position.z then
        return false, "Position missing coordinates"
    end
    
    -- Validate status
    local validStatuses = {idle = true, mining = true, returning = true, paused = true}
    if not validStatuses[stateData.status] then
        return false, "Invalid status: " .. tostring(stateData.status)
    end
    
    return true
end

-- ========== STATE UPDATES ==========

function state.updatePosition(stateData, x, y, z, facing)
    stateData.position.x = x
    stateData.position.y = y
    stateData.position.z = z
    if facing then
        stateData.position.facing = facing
    end
    stateData.lastPositionAt = os.epoch("utc")
end

function state.updateStatus(stateData, newStatus)
    stateData.status = newStatus
end

function state.setPaused(stateData, paused)
    stateData.isPaused = paused
    if paused then
        stateData.status = "paused"
    end
end

function state.updateProgress(stateData, blocksMined, oresFound)
    if blocksMined then
        stateData.blockProgress = stateData.blockProgress + blocksMined
        stateData.totalBlocksMined = stateData.totalBlocksMined + blocksMined
    end
    
    if oresFound then
        stateData.oresFound = stateData.oresFound + oresFound
    end
end

function state.updateInventory(stateData)
    -- Update from current turtle state
    stateData.fuelLevel = turtle.getFuelLevel()
    
    local freeSlots = 0
    for slot = 1, 16 do
        if turtle.getItemCount(slot) == 0 then
            freeSlots = freeSlots + 1
        end
    end
    stateData.freeSlots = freeSlots
end

function state.assignTunnel(stateData, layer, tunnel, startPos, endPos)
    stateData.assignedTunnel = {
        layer = layer,
        tunnel = tunnel,
        startPos = startPos,
        endPos = endPos
    }
    stateData.currentLayer = layer
    stateData.currentTunnel = tunnel
    stateData.blockProgress = 0
end

function state.completeTunnel(stateData)
    stateData.tunnelsCompleted = stateData.tunnelsCompleted + 1
    stateData.assignedTunnel = nil
    stateData.blockProgress = 0
end

-- ========== ERROR TRACKING ==========

function state.recordError(stateData, errorMsg)
    stateData.lastError = {
        message = errorMsg,
        timestamp = os.epoch("utc"),
        position = {
            x = stateData.position.x,
            y = stateData.position.y,
            z = stateData.position.z
        }
    }
    stateData.retryCount = stateData.retryCount + 1
end

function state.recordStuck(stateData)
    stateData.stuckCount = stateData.stuckCount + 1
end

function state.clearErrors(stateData)
    stateData.stuckCount = 0
    stateData.lastError = nil
    stateData.retryCount = 0
end

-- ========== RESUME LOGIC ==========

function state.shouldResume(stateData)
    -- Check if turtle should resume from saved state
    
    if stateData.isPaused then
        return false, "Turtle was paused"
    end
    
    if stateData.status == "idle" then
        return false, "Turtle was idle"
    end
    
    if not stateData.assignedTunnel then
        return false, "No tunnel assigned"
    end
    
    -- Check if state is too old (possible corruption)
    local ageSeconds = (os.epoch("utc") - stateData.lastSaveAt) / 1000
    if ageSeconds > 3600 then  -- 1 hour
        return false, "State is too old (over 1 hour)"
    end
    
    return true, "Can resume"
end

function state.getResumeInfo(stateData)
    local info = {
        canResume = false,
        reason = "",
        position = stateData.position,
        status = stateData.status,
        isPaused = stateData.isPaused,
        tunnel = stateData.assignedTunnel,
        progress = stateData.blockProgress,
        age = (os.epoch("utc") - stateData.lastSaveAt) / 1000
    }
    
    info.canResume, info.reason = state.shouldResume(stateData)
    
    return info
end

-- ========== AUTO-SAVE SYSTEM ==========

state.autoSaveInterval = 10  -- Saves per minute
state.movesSinceLastSave = 0

function state.autoSave(stateData, force)
    state.movesSinceLastSave = state.movesSinceLastSave + 1
    
    if force or state.movesSinceLastSave >= state.autoSaveInterval then
        state.updateInventory(stateData)
        local success, err = state.save(stateData)
        
        if success then
            state.movesSinceLastSave = 0
        end
        
        return success, err
    end
    
    return true  -- No save needed
end

-- ========== STATISTICS ==========

function state.getStatistics(stateData)
    local runtime = (os.epoch("utc") - stateData.startedAt) / 1000  -- seconds
    
    return {
        totalBlocksMined = stateData.totalBlocksMined,
        oresFound = stateData.oresFound,
        tunnelsCompleted = stateData.tunnelsCompleted,
        runtime = runtime,
        blocksPerMinute = runtime > 0 and (stateData.totalBlocksMined / runtime * 60) or 0,
        currentProgress = stateData.blockProgress,
        fuelLevel = stateData.fuelLevel,
        freeSlots = stateData.freeSlots
    }
end

-- ========== DISPLAY HELPERS ==========

function state.printStatus(stateData)
    print("=== Turtle Status ===")
    print("ID: " .. stateData.computerID .. " (" .. stateData.label .. ")")
    print("Status: " .. stateData.status .. (stateData.isPaused and " (PAUSED)" or ""))
    print("Position: " .. stateData.position.x .. "," .. stateData.position.y .. "," .. stateData.position.z)
    print("Fuel: " .. stateData.fuelLevel .. " / Free Slots: " .. stateData.freeSlots)
    
    if stateData.assignedTunnel then
        local t = stateData.assignedTunnel
        print("Tunnel: Layer " .. t.layer .. ", Tunnel " .. t.tunnel)
        print("Progress: " .. stateData.blockProgress .. " blocks")
    else
        print("No tunnel assigned")
    end
    
    local stats = state.getStatistics(stateData)
    print("Stats: " .. stats.totalBlocksMined .. " blocks, " .. stats.oresFound .. " ores")
    print("=====================")
end

return state

