-- Advanced Branch Miner - Main Turtle Program
-- Handles mining operations, command processing, and coordination

local config = require("config")
local protocol = require("protocol")
local state = require("state")
local utils = require("utils")
local coordinator = require("coordinator")
local projectClient = require("project-client")

-- ========== GLOBAL STATE ==========

local myState = nil
local running = true
local commandQueue = {}
local lastHeartbeat = 0
local lastSave = 0

-- ========== INITIALIZATION ==========

local function initializeMiner()
    print("=== Advanced Branch Miner ===")
    print("Turtle: " .. utils.getLabel())
    print("ID: " .. os.getComputerID())
    print("")
    
    -- Validate configuration
    config.validate()
    
    -- Initialize protocol
    protocol.init()
    
    -- Initialize project client and reconnect if assigned
    projectClient.init()
    local assignment = projectClient.loadAssignment()
    
    if assignment then
        print("Assigned to project: " .. assignment.projectName)
        print("Channel: " .. assignment.channel)
        print("")
        
        -- IMPORTANT: Load Y level from project (since we don't have GPS)
        if assignment.startY then
            config.START_Y = assignment.startY
            config.HOME_Y = assignment.startY  -- Turtle is placed at this Y level
            print("Y Level: " .. assignment.startY)
        else
            -- Old assignment file without startY - ask user to set it
            print("WARNING: Y level not set!")
            print("Enter the Y level where turtle is placed:")
            print("(Check F3 debug screen or Project Settings)")
            write("Y Level: ")
            local input = read()
            local yLevel = tonumber(input)
            
            if yLevel then
                config.START_Y = yLevel
                config.HOME_Y = yLevel
                -- Update assignment file with new startY
                assignment.startY = yLevel
                projectClient.saveAssignment(assignment.projectName, assignment.channel, yLevel)
                print("Y Level set to: " .. yLevel)
            else
                print("ERROR: Invalid Y level entered")
                print("Please restart and enter a valid number")
                return false
            end
        end
        
        -- Close old modem connection and switch to project channel
        protocol.close()
        config.MODEM_CHANNEL = assignment.channel
        protocol.init()
        print("Switched to channel: " .. config.MODEM_CHANNEL)
        print("")
        
        -- Reconnect to project
        local success, err = projectClient.reconnect()
        if not success then
            print("WARNING: Failed to reconnect")
            print(err)
        else
            print("Reconnected successfully!")
        end
        print("")
    else
        print("WARNING: No project assignment found!")
        print("Run installer to join a project.")
        print("")
        return false
    end
    
    -- Try to load saved state
    local savedState, err = state.load()
    
    if savedState then
        print("Found saved state!")
        state.printStatus(savedState)
        
        local resumeInfo = state.getResumeInfo(savedState)
        print("")
        print("Can resume: " .. tostring(resumeInfo.canResume))
        print("Reason: " .. resumeInfo.reason)
        print("")
        
        if resumeInfo.canResume then
            print("Press Y to resume, N for fresh start")
            print("Auto-resuming in 10 seconds...")
            
            local timer = os.startTimer(10)
            local choice = nil
            
            while true do
                local event, param = os.pullEvent()
                if event == "timer" and param == timer then
                    choice = "y"
                    break
                elseif event == "char" then
                    local key = param:lower()
                    if key == "y" or key == "n" then
                        os.cancelTimer(timer)
                        choice = key
                        break
                    end
                end
            end
            
            if choice == "y" then
                myState = savedState
                utils.setPosition(myState.position.x, myState.position.y, myState.position.z, myState.position.facing)
                print("Resuming from saved state...")
                
                -- If turtle is at home, verify orientation with chest detection
                local atHome = (myState.position.x == config.HOME_X and 
                               myState.position.y == config.HOME_Y and 
                               myState.position.z == config.HOME_Z)
                
                if atHome then
                    print("")
                    print("At home base - verifying orientation...")
                    if utils.detectOrientation() then
                        utils.position.x = config.HOME_X
                        utils.position.y = config.HOME_Y
                        utils.position.z = config.HOME_Z
                        myState.position = utils.position
                        print("✓ Orientation verified: " .. utils.facingNames[utils.position.facing + 1])
                        state.save(myState)
                    else
                        print("⚠ Could not verify orientation")
                    end
                    print("")
                end
                
                return true
            end
        end
    end
    
    -- Create new state
    print("Starting fresh...")
    myState = state.createNew()
    
    -- Set home position
    print("Home: X=" .. config.HOME_X .. " Y=" .. config.HOME_Y .. " Z=" .. config.HOME_Z)
    print("START_Y=" .. config.START_Y)
    myState.homePosition = {x = config.HOME_X, y = config.HOME_Y, z = config.HOME_Z}
    
    -- ORIENTATION DETECTION: Find which way is forward by detecting chests
    print("")
    if utils.detectOrientation() then
        utils.setPosition(config.HOME_X, config.HOME_Y, config.HOME_Z, utils.position.facing)
    else
        -- Fallback: assume facing north if detection fails
        print("⚠ Using default orientation (North)")
        utils.setPosition(config.HOME_X, config.HOME_Y, config.HOME_Z, 0)
    end
    myState.position = utils.position
    print("Facing: " .. utils.facingNames[utils.position.facing + 1])
    print("")
    
    state.save(myState)
    print("Initialized!")
    return true
end

-- ========== COMMAND HANDLING ==========

local function processCommand(msg)
    local cmd = msg.type
    local data = msg.data or {}
    
    print("Received command: " .. cmd)
    
    -- Send acknowledgment
    protocol.sendAck(msg, {status = "processing"})
    
    if cmd == protocol.MSG_TYPES.CMD_PAUSE then
        myState.status = "paused"
        myState.isPaused = true
        state.save(myState)
        print("PAUSED by controller")
        
    elseif cmd == protocol.MSG_TYPES.CMD_RESUME then
        myState.isPaused = false
        if myState.assignedTunnel then
            myState.status = "mining"
        else
            myState.status = "idle"
            -- Request work from coordinator
            print("Requesting work from coordinator...")
            protocol.claimTunnel()
        end
        state.save(myState)
        print("RESUMED by controller")
        
    elseif cmd == protocol.MSG_TYPES.CMD_RETURN_BASE then
        print("Returning to base...")
        myState.status = "returning"
        state.save(myState)
        returnToBase()
        myState.status = "idle"
        state.save(myState)
        
    elseif cmd == protocol.MSG_TYPES.CMD_SHUTDOWN then
        print("Shutdown requested...")
        myState.status = "idle"
        state.save(myState)
        running = false
        
    elseif cmd == protocol.MSG_TYPES.STATUS_QUERY then
        -- Send status response
        sendHeartbeat(true)
    end
end

local function checkForCommands()
    -- Non-blocking check for messages
    local event, side, channel, replyChannel, message = os.pullEvent("modem_message")
    
    if channel == config.MODEM_CHANNEL and type(message) == "table" then
        if message.version == config.PROTOCOL_VERSION then
            -- Check if it's a command for us
            local msgType = message.type
            
            if msgType == protocol.MSG_TYPES.CMD_PAUSE or
               msgType == protocol.MSG_TYPES.CMD_RESUME or
               msgType == protocol.MSG_TYPES.CMD_RETURN_BASE or
               msgType == protocol.MSG_TYPES.CMD_SHUTDOWN or
               msgType == protocol.MSG_TYPES.STATUS_QUERY then
                
                -- Process immediately
                processCommand(message)
                return true
            elseif msgType == protocol.MSG_TYPES.TUNNEL_ASSIGNED then
                -- Tunnel assignment response
                local assignment = message.data
                if assignment then
                    state.assignTunnel(myState, assignment.layer, assignment.tunnel, 
                                      assignment.startPos, assignment.endPos)
                    print("Assigned tunnel: Layer " .. assignment.layer .. ", Tunnel " .. assignment.tunnel)
                    state.save(myState)
                end
            end
        end
    end
    
    return false
end

-- ========== HEARTBEAT ==========

local function sendHeartbeat(force)
    local now = os.clock()
    
    if not force and (now - lastHeartbeat) < config.HEARTBEAT_INTERVAL then
        return
    end
    
    lastHeartbeat = now
    
    -- Update inventory info
    state.updateInventory(myState)
    
    local fuelData = {
        level = turtle.getFuelLevel(),
        max = turtle.getFuelLimit(),
        percent = utils.getFuelPercent()
    }
    
    local inventoryData = {
        freeSlots = myState.freeSlots,
        totalSlots = 16
    }
    
    local currentTask = nil
    if myState.assignedTunnel then
        currentTask = {
            layer = myState.currentLayer,
            tunnel = myState.currentTunnel,
            block = myState.blockProgress
        }
    end
    
    protocol.sendHeartbeat(myState.status, myState.position, fuelData, inventoryData, currentTask)
end

-- ========== RESUPPLY ==========

local function manageResupply()
    print("=== Resupply ===")
    
    -- Deposit items
    print("Depositing items...")
    local deposited = utils.depositInventory(true)
    print("Deposited " .. deposited .. " items")
    
    -- Restock fuel items in slot 16
    print("Restocking fuel items...")
    local fuelBefore = turtle.getFuelLevel()
    turtle.select(16)
    local fuelItemsBefore = turtle.getItemCount(16)
    utils.refuelFromChest()
    local fuelItemsAfter = turtle.getItemCount(16)
    print("Fuel Level: " .. fuelBefore .. " -> " .. turtle.getFuelLevel())
    print("Fuel Items (slot 16): " .. fuelItemsBefore .. " -> " .. fuelItemsAfter)
    
    -- Restock building blocks
    print("Restocking building blocks...")
    local restocked = utils.restockBuildingBlocks()
    print("Restocked " .. restocked .. " building blocks")
    
    -- Update state
    state.updateInventory(myState)
    myState.needsResupply = false
    
    print("=== Resupply Complete ===")
    return true
end

-- ========== PRE-FLIGHT CHECK ==========

local function checkInventoryReady()
    -- Check if turtle is ready to start mining
    -- Returns: ready (boolean), reason (string)
    
    print("Pre-flight check...")
    
    -- Check slot 1 for cobblestone (building blocks) - need 32-64 items
    turtle.select(1)
    local slot1 = turtle.getItemDetail()
    if not slot1 or slot1.count < 32 then
        return false, "Need 32+ cobblestone in slot 1 (currently: " .. (slot1 and slot1.count or 0) .. ")"
    end
    
    -- Check slot 16 for fuel
    turtle.select(16)
    local slot16 = turtle.getItemDetail()
    if not slot16 then
        return false, "Need fuel in slot 16"
    end
    
    -- Check fuel level
    local fuelLevel = turtle.getFuelLevel()
    if fuelLevel < config.MIN_FUEL then
        return false, "Fuel too low: " .. fuelLevel .. " (need " .. config.MIN_FUEL .. ")"
    end
    
    -- Check slots 2-15 are mostly empty (allow some items)
    local usedSlots = 0
    for slot = 2, 15 do
        turtle.select(slot)
        if turtle.getItemCount() > 0 then
            usedSlots = usedSlots + 1
        end
    end
    
    if usedSlots > 10 then
        return false, "Too many slots full (" .. usedSlots .. "/14). Need space for mining."
    end
    
    print("Pre-flight check PASSED")
    print("  Fuel: " .. fuelLevel)
    print("  Cobble (slot 1): " .. slot1.count .. " blocks")
    print("  Free slots: " .. (14 - usedSlots) .. "/14")
    
    return true, "Ready"
end

local function ensureInventoryReady()
    -- Check inventory and restock if needed
    local ready, reason = checkInventoryReady()
    
    if not ready then
        print("NOT READY: " .. reason)
        print("Restocking...")
        
        -- Make sure we're at base
        local atBase = (utils.position.x == myState.homePosition.x and 
                       utils.position.y == myState.homePosition.y and 
                       utils.position.z == myState.homePosition.z)
        
        if not atBase then
            print("ERROR: Not at base, cannot restock")
            print("Current: " .. utils.position.x .. "," .. utils.position.y .. "," .. utils.position.z)
            print("Home: " .. myState.homePosition.x .. "," .. myState.homePosition.y .. "," .. myState.homePosition.z)
            return false
        end
        
        -- Restock
        manageResupply()
        
        -- Check again
        ready, reason = checkInventoryReady()
        if not ready then
            print("ERROR: Still not ready after restock: " .. reason)
            return false
        end
    end
    
    return true
end

-- ========== NAVIGATION ==========

function returnToBase()
    myState.status = "returning"
    print("Returning to base...")
    
    -- Navigate to home
    local success = utils.goToPosition(myState.homePosition.x, 
                                      myState.homePosition.y, 
                                      myState.homePosition.z, true)
    
    if success then
        -- Face south for chest access
        utils.turnTo(2)
        print("Arrived at base")
        return true
    else
        print("ERROR: Could not return to base")
        return false
    end
end

function navigateToTunnelStart(assignment)
    print("Navigating to tunnel start...")
    print("Type: " .. (assignment.tunnelType or "unknown") .. ", Direction: " .. (assignment.direction or "unknown"))
    
    -- Debug: Show current position and target
    local currX, currY, currZ, currF = utils.getPosition()
    print("Current: X=" .. currX .. " Y=" .. currY .. " Z=" .. currZ)
    
    local startPos = assignment.startPos
    print("Target: X=" .. startPos.x .. " Y=" .. startPos.y .. " Z=" .. startPos.z)
    
    -- Check if we're already at the target
    if currX == startPos.x and currY == startPos.y and currZ == startPos.z then
        print("Already at tunnel start!")
        -- Face the correct direction for this tunnel
        local facing = 0  -- default north
        if assignment.direction == "west" then
            facing = 3
        elseif assignment.direction == "east" then
            facing = 1
        elseif assignment.direction == "south" then
            facing = 2
        end
        utils.turnTo(facing)
        return true
    end
    
    local success = utils.goToPosition(startPos.x, startPos.y, startPos.z, true)
    
    if success then
        -- Face tunnel direction based on assignment
        local facing = 0  -- default north
        if assignment.direction == "west" then
            facing = 3
        elseif assignment.direction == "east" then
            facing = 1
        elseif assignment.direction == "south" then
            facing = 2
        end
        utils.turnTo(facing)
        print("Arrived at tunnel start, facing " .. assignment.direction)
        return true
    else
        print("ERROR: Could not reach tunnel start")
        local finalX, finalY, finalZ = utils.getPosition()
        print("Stuck at: X=" .. finalX .. " Y=" .. finalY .. " Z=" .. finalZ)
        return false
    end
end

-- ========== MINING ==========

local function checkAndProtectWall(direction, wallName)
    -- Check wall for ore and holes, mine ore if found, place cobble if hole detected
    -- Returns: ores found
    local oresFound = 0
    
    -- Detect what's in this direction
    local hasBlock = false
    local success, blockData = false, nil
    
    if direction == "forward" then
        hasBlock, blockData = turtle.inspect()
    elseif direction == "up" then
        hasBlock, blockData = turtle.inspectUp()
    elseif direction == "down" then
        hasBlock, blockData = turtle.inspectDown()
    end
    
    -- If there's a block, check if it's ore
    if hasBlock and blockData then
        if utils.isOreBlock(blockData.name) then
            print("Ore at " .. wallName .. " - mining vein")
            oresFound = utils.mineVein(direction)
            -- After vein mining, recheck for holes
            if direction == "forward" then
                hasBlock = turtle.detect()
            elseif direction == "up" then
                hasBlock = turtle.detectUp()
            elseif direction == "down" then
                hasBlock = turtle.detectDown()
            end
        end
    end
    
    -- If there's no block (hole in wall), place cobblestone
    if not hasBlock then
        local placed = false
        turtle.select(1)  -- Cobble slot
        
        if direction == "forward" then
            placed = turtle.place()
        elseif direction == "up" then
            placed = turtle.placeUp()
        elseif direction == "down" then
            placed = turtle.placeDown()
        end
        
        if placed then
            print("Filled hole at " .. wallName)
        end
    end
    
    return oresFound
end

local function digAt3x3Position(level, row, tunnelDir)
    -- Dig vertically based on level (like reference file's digCurrentSpot)
    -- level 0=bottom (dig up), 1=middle (dig both), 2=top (dig down)
    local oresFound = 0
    local wallProtection = config.WALL_PROTECTION
    
    -- Check for ore and mine veins
    if utils.isOre("up") then oresFound = oresFound + utils.mineVein("up") end
    if utils.isOre("down") then oresFound = oresFound + utils.mineVein("down") end
    
    -- Dig based on level
    if level == 0 then
        -- Bottom: dig up only
        utils.safeDig("up")
    elseif level == 1 then
        -- Middle: dig both
        utils.safeDig("down")
        utils.safeDig("up")
    elseif level == 2 then
        -- Top: dig down only
        utils.safeDig("down")
    end
    
    -- Wall protection
    if wallProtection then
        if level == 0 then
            oresFound = oresFound + checkAndProtectWall("down", "floor")
        elseif level == 2 then
            oresFound = oresFound + checkAndProtectWall("up", "ceiling")
        end
        
        if row == 0 then
            -- Left column
            utils.turnLeft()
            oresFound = oresFound + checkAndProtectWall("forward", "left-wall")
            utils.turnRight()
        elseif row == 2 then
            -- Right column
            utils.turnRight()
            oresFound = oresFound + checkAndProtectWall("forward", "right-wall")
            utils.turnLeft()
        end
    end
    
    return oresFound
end

local function mine3x3Section()
    -- Mine 3x3 using exact pattern from reference file
    -- Pattern: MM→MR→BR→BM→BL→ML→TL→TM→TR
    local oresFound = 0
    local tunnelDir = utils.position.facing
    local leftDir = (tunnelDir + 3) % 4
    local rightDir = (tunnelDir + 1) % 4
    
    -- Step 1: MM (middle-middle, level=1 row=1)
    oresFound = oresFound + digAt3x3Position(1, 1, tunnelDir)
    
    -- Step 2: Move right to MR (level=1 row=2)
    utils.turnTo(rightDir)
    if not utils.safeForward(false) then return false, 0 end
    oresFound = oresFound + digAt3x3Position(1, 2, tunnelDir)
    
    -- Step 3: Move down to BR (level=0 row=2)
    if not utils.safeDown(false) then return false, 0 end
    oresFound = oresFound + digAt3x3Position(0, 2, tunnelDir)
    
    -- Step 4: Move left to BM (level=0 row=1)
    utils.turnTo(leftDir)
    if not utils.safeForward(false) then return false, 0 end
    oresFound = oresFound + digAt3x3Position(0, 1, tunnelDir)
    
    -- Step 5: Move left to BL (level=0 row=0)
    if not utils.safeForward(false) then return false, 0 end
    oresFound = oresFound + digAt3x3Position(0, 0, tunnelDir)
    
    -- Step 6: Move up to ML (level=1 row=0)
    if not utils.safeUp(false) then return false, 0 end
    oresFound = oresFound + digAt3x3Position(1, 0, tunnelDir)
    
    -- Step 7: Move up to TL (level=2 row=0)
    if not utils.safeUp(false) then return false, 0 end
    oresFound = oresFound + digAt3x3Position(2, 0, tunnelDir)
    
    -- Step 8: Move right to TM (level=2 row=1)
    utils.turnTo(rightDir)
    if not utils.safeForward(false) then return false, 0 end
    oresFound = oresFound + digAt3x3Position(2, 1, tunnelDir)
    
    -- Step 9: Move right to TR (level=2 row=2)
    if not utils.safeForward(false) then return false, 0 end
    oresFound = oresFound + digAt3x3Position(2, 2, tunnelDir)
    
    -- Return to MM (middle-middle)
    if not utils.safeDown(false) then return false, 0 end  -- TR to MR
    utils.turnTo(leftDir)
    if not utils.safeForward(false) then return false, 0 end  -- MR to MM
    
    -- Move forward to next cross-section
    utils.turnTo(tunnelDir)
    if utils.isOre("forward") then oresFound = oresFound + utils.mineVein("forward")
    else utils.safeDig("forward") end
    if not utils.safeForward(true) then return false, 0 end
    
    return true, oresFound
end

local function mineTunnelSection()
    -- Mine tunnel section based on configured size (2x1, 2x2, or 3x3)
    local oresFound = 0
    local tunnelSize = config.TUNNEL_SIZE or "2x2"
    local wallProtection = config.WALL_PROTECTION
    
    if tunnelSize == "3x3" then
        -- 3x3: Visit all 9 blocks in cross-section
        return mine3x3Section()
        
    elseif tunnelSize == "2x2" then
        -- 2x2: Visit all 4 blocks (BL, BR, TL, TR pattern)
        -- Start at bottom-left, go right, up-left, right, down to next
        
        -- Clear current position
        if utils.isOre("up") then oresFound = oresFound + utils.mineVein("up")
        else utils.safeDig("up") end
        if utils.isOre("down") then oresFound = oresFound + utils.mineVein("down")
        else utils.safeDig("down") end
        
        -- Move to BL (bottom-left)
        if not utils.safeDown(false) then return false, 0 end
        utils.turnLeft()
        if utils.isOre("forward") then oresFound = oresFound + utils.mineVein("forward")
        else utils.safeDig("forward") end
        if not utils.safeForward(false) then return false, 0 end
        
        if wallProtection then
            oresFound = oresFound + checkAndProtectWall("down", "floor-BL")
            oresFound = oresFound + checkAndProtectWall("forward", "left-wall")
        end
        
        -- Move to BR (bottom-right)
        utils.turnRight()
        if utils.isOre("forward") then oresFound = oresFound + utils.mineVein("forward")
        else utils.safeDig("forward") end
        if not utils.safeForward(false) then return false, 0 end
        if not utils.safeForward(false) then return false, 0 end
        
        if wallProtection then
            oresFound = oresFound + checkAndProtectWall("down", "floor-BR")
            utils.turnRight()
            oresFound = oresFound + checkAndProtectWall("forward", "right-wall")
            utils.turnLeft()
        end
        
        -- Move to TR (top-right)
        if not utils.safeUp(false) then return false, 0 end
        if wallProtection then
            oresFound = oresFound + checkAndProtectWall("up", "ceiling-TR")
            utils.turnRight()
            oresFound = oresFound + checkAndProtectWall("forward", "right-wall")
            utils.turnLeft()
        end
        
        -- Move to TL (top-left)
        utils.turnLeft()
        if not utils.safeForward(false) then return false, 0 end
        if not utils.safeForward(false) then return false, 0 end
        utils.turnRight()
        
        if wallProtection then
            oresFound = oresFound + checkAndProtectWall("up", "ceiling-TL")
            utils.turnLeft()
            oresFound = oresFound + checkAndProtectWall("forward", "left-wall")
            utils.turnRight()
        end
        
        -- Return to middle and advance
        if not utils.safeDown(false) then return false, 0 end
        utils.turnRight()
        if not utils.safeForward(false) then return false, 0 end
        utils.turnLeft()
        
        -- Move forward through tunnel
        if utils.isOre("forward") then oresFound = oresFound + utils.mineVein("forward")
        else utils.safeDig("forward") end
        if not utils.safeForward(true) then return false, 0 end
        
        return true, oresFound
        
    else
        -- 2x1 (default): Simple 2-block vertical (just top and current)
        -- Mine ceiling
        if utils.isOre("up") then oresFound = oresFound + utils.mineVein("up")
        else utils.safeDig("up") end
        
        -- Mine forward
        if utils.isOre("forward") then oresFound = oresFound + utils.mineVein("forward")
        else utils.safeDig("forward") end
        
        -- Move forward
        local success, err = utils.safeForward(true)
        if not success then
            print("Movement failed: " .. (err or "unknown"))
            return false, 0
        end
        
        -- Check walls if protection enabled
        if wallProtection then
            oresFound = oresFound + checkAndProtectWall("up", "ceiling")
            utils.turnLeft()
            oresFound = oresFound + checkAndProtectWall("forward", "left wall")
            utils.turnRight()
            utils.turnRight()
            oresFound = oresFound + checkAndProtectWall("forward", "right wall")
            utils.turnLeft()
        end
        
        return true, oresFound
    end
end

local function mineTunnel(assignment)
    print("=== Mining Tunnel ===")
    print("Layer " .. assignment.layer .. ", Tunnel " .. assignment.tunnel)
    print("Type: " .. (assignment.tunnelType or "unknown") .. ", Length: " .. (assignment.length or config.TUNNEL_LENGTH))
    
    myState.status = "mining"
    local blocksMined = myState.blockProgress
    local oresFound = 0
    local torchCounter = 0
    
    -- Get tunnel length from assignment (supports different lengths for main vs branches)
    local tunnelLength = assignment.length or config.TUNNEL_LENGTH
    
    -- Navigate to start position (if not already there)
    if myState.blockProgress == 0 then
        -- PRE-FLIGHT CHECK: Ensure inventory is ready before leaving base
        if not ensureInventoryReady() then
            print("ERROR: Cannot start - inventory not ready")
            myState.status = "idle"
            return false
        end
        
        -- Check if tunnel starts at home base (special case for main tunnel on layer 1)
        local atTunnelStart = (utils.position.x == assignment.startPos.x and
                              utils.position.y == assignment.startPos.y and
                              utils.position.z == assignment.startPos.z)
        
        if atTunnelStart then
            print("Already at tunnel start")
            -- Face the correct direction for this tunnel
            local facing = 0
            if assignment.direction == "west" then
                facing = 3
            elseif assignment.direction == "east" then
                facing = 1
            elseif assignment.direction == "south" then
                facing = 2
            end
            utils.turnTo(facing)
        else
            if not navigateToTunnelStart(assignment) then
                return false
            end
        end
    end
    
    -- For first block only: Move forward to clear home base before starting pattern
    if blocksMined == 0 then
        print("First block: Moving away from home base...")
        -- Just mine forward and move without complex pattern
        if utils.isOre("up") then oresFound = oresFound + utils.mineVein("up")
        else utils.safeDig("up") end
        
        if utils.isOre("forward") then oresFound = oresFound + utils.mineVein("forward")
        else utils.safeDig("forward") end
        
        if not utils.safeForward(true) then
            print("ERROR: Could not move forward from home base")
            return false
        end
        
        blocksMined = 1
        myState.blockProgress = 1
        state.updateProgress(myState, 1, 0)
        print("Moved to block 1 - starting pattern mining...")
    end
    
    -- Mine tunnel
    while blocksMined < tunnelLength and running do
        -- Check for pause command
        parallel.waitForAny(
            function()
                checkForCommands()
            end,
            function()
                sleep(0.05)
            end
        )
        
        if myState.isPaused then
            print("Paused - waiting...")
            while myState.isPaused and running do
                checkForCommands()
                sleep(1)
            end
            print("Resumed!")
        end
        
        if not running then break end
        
        -- Check if resupply needed
        local needsResupply, reason = utils.needsResupply()
        if needsResupply then
            print("Need resupply: " .. reason)
            
            -- Save progress
            myState.blockProgress = blocksMined
            state.save(myState)
            
            -- Return to base
            if not returnToBase() then
                print("ERROR: Could not return for resupply")
                return false
            end
            
            -- Resupply
            manageResupply()
            
            -- Verify inventory is ready after resupply
            if not ensureInventoryReady() then
                print("ERROR: Resupply failed - inventory still not ready")
                return false
            end
            
            -- Return to tunnel
            if not navigateToTunnelStart(assignment) then
                print("ERROR: Could not return to tunnel")
                return false
            end
            
            -- Move to current position in tunnel
            for i = 1, blocksMined do
                utils.safeForward(false)
            end
        end
        
        -- Mine section
        local success, sectionOres = mineTunnelSection()
        if not success then
            print("Mining failed at block " .. blocksMined)
            state.recordError(myState, "Mining failed")
            state.save(myState)
            return false
        end
        
        blocksMined = blocksMined + 1
        oresFound = oresFound + sectionOres
        torchCounter = torchCounter + 1
        
        -- Place torch
        if torchCounter >= config.TORCH_INTERVAL then
            utils.turnAround()
            utils.placeTorch()
            utils.turnAround()
            torchCounter = 0
        end
        
        -- Update progress
        myState.blockProgress = blocksMined
        state.updateProgress(myState, 1, sectionOres)
        
        -- Auto-save
        if (blocksMined % 10) == 0 then
            state.save(myState)
            sendHeartbeat(false)
        end
        
        print("Progress: " .. blocksMined .. "/" .. tunnelLength)
    end
    
    -- Tunnel complete!
    print("=== Tunnel Complete ===")
    print("Mined " .. blocksMined .. " blocks, found " .. oresFound .. " ores")
    
    -- Report completion
    protocol.reportTunnelComplete(assignment.layer, assignment.tunnel, blocksMined, oresFound)
    state.completeTunnel(myState)
    state.save(myState)
    
    return true
end

-- ========== MAIN LOOP ==========

local function mainLoop()
    print("Registering with network...")
    protocol.registerTurtle()
    sleep(1)
    
    while running do
        -- Send heartbeat
        sendHeartbeat(false)
        
        -- Check for commands
        parallel.waitForAny(
            function()
                checkForCommands()
            end,
            function()
                sleep(0.1)
            end
        )
        
        -- Handle paused state
        if myState.isPaused then
            print("Paused - waiting for resume...")
            while myState.isPaused and running do
                sendHeartbeat(false)
                sleep(1)
                parallel.waitForAny(
                    function()
                        checkForCommands()
                    end,
                    function()
                        sleep(0.1)
                    end
                )
            end
            print("Resumed!")
        end
        
        -- Main state machine
        if myState.status == "idle" then
            -- Claim work if we don't have any
            if not myState.assignedTunnel then
                print("Claiming tunnel assignment...")
                protocol.claimTunnel()
                
                -- Wait for assignment
                local msg = protocol.filterMessages(protocol.MSG_TYPES.TUNNEL_ASSIGNED, 5)
                if msg and msg.data then
                    local assignment = msg.data
                    state.assignTunnel(myState, assignment.layer, assignment.tunnel,
                                      assignment.startPos, assignment.endPos)
                    state.save(myState)
                    print("✓ Assigned: Layer " .. assignment.layer .. ", Tunnel " .. assignment.tunnel)
                else
                    print("No work available - waiting...")
                    sleep(10)
                end
            else
                -- Already have an assignment - probably resuming after restart
                print("✓ Resuming: Layer " .. myState.assignedTunnel.layer .. ", Tunnel " .. myState.assignedTunnel.tunnel)
                print("  Progress: " .. myState.blockProgress .. "/" .. config.TUNNEL_LENGTH .. " blocks")
                
                -- Transition to mining status to actually mine the tunnel
                myState.status = "mining"
                state.save(myState)
            end
            
        elseif myState.status == "mining" then
            -- Mine assigned tunnel
            if myState.assignedTunnel then
                local success = mineTunnel(myState.assignedTunnel)
                
                if success then
                    -- Return to base
                    returnToBase()
                    manageResupply()
                    
                    -- Ready for next tunnel
                    myState.status = "idle"
                    state.save(myState)
                else
                    print("Mining failed - returning to base")
                    returnToBase()
                    myState.status = "idle"
                    state.save(myState)
                end
            else
                -- No assignment
                myState.status = "idle"
            end
            
        else
            -- Unknown status - go idle
            myState.status = "idle"
            sleep(1)
        end
    end
    
    print("Shutdown complete")
end

-- ========== STARTUP ==========

local function main()
    -- Initialize
    if not initializeMiner() then
        print("ERROR: Initialization failed")
        return
    end
    
    -- Run main loop
    local success, err = pcall(mainLoop)
    
    if not success then
        print("ERROR: " .. tostring(err))
        state.recordError(myState, tostring(err))
        state.save(myState)
    end
    
    -- Cleanup
    protocol.close()
    print("Miner stopped")
end

-- Run
main()

