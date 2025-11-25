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
    
    -- Refuel
    print("Refueling...")
    local fuelBefore = turtle.getFuelLevel()
    utils.refuelFromChest()
    print("Fuel: " .. fuelBefore .. " -> " .. turtle.getFuelLevel())
    
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
    
    -- Check slot 1 for cobblestone (building blocks)
    turtle.select(1)
    local slot1 = turtle.getItemDetail()
    if not slot1 or slot1.count < 8 then
        return false, "Need cobblestone in slot 1"
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
    print("  Cobble: " .. slot1.count .. " blocks")
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
    
    -- Debug: Show current position and target
    local currX, currY, currZ, currF = utils.getPosition()
    print("Current: X=" .. currX .. " Y=" .. currY .. " Z=" .. currZ)
    
    local startPos = assignment.startPos
    print("Target: X=" .. startPos.x .. " Y=" .. startPos.y .. " Z=" .. startPos.z)
    
    local success = utils.goToPosition(startPos.x, startPos.y, startPos.z, true)
    
    if success then
        -- Face tunnel direction (north)
        utils.turnTo(0)
        print("Arrived at tunnel start")
        return true
    else
        print("ERROR: Could not reach tunnel start")
        local finalX, finalY, finalZ = utils.getPosition()
        print("Stuck at: X=" .. finalX .. " Y=" .. finalY .. " Z=" .. finalZ)
        return false
    end
end

-- ========== MINING ==========

local function mineTunnelSection()
    -- Mine a 2-block high section
    local oresFound = 0
    
    -- Mine top block
    if utils.isOre("up") then
        oresFound = oresFound + utils.mineVein("up")
    else
        turtle.digUp()
    end
    
    -- Mine forward block
    if utils.isOre("forward") then
        oresFound = oresFound + utils.mineVein("forward")
    else
        turtle.dig()
    end
    
    -- Move forward
    local success, err = utils.safeForward(true)
    if not success then
        print("Movement failed: " .. (err or "unknown"))
        return false, 0
    end
    
    -- Mine bottom block (stand on it)
    if utils.isOre("down") then
        oresFound = oresFound + utils.mineVein("down")
    else
        turtle.digDown()
    end
    
    return true, oresFound
end

local function mineTunnel(assignment)
    print("=== Mining Tunnel ===")
    print("Layer " .. assignment.layer .. ", Tunnel " .. assignment.tunnel)
    
    myState.status = "mining"
    local blocksMined = myState.blockProgress
    local oresFound = 0
    local torchCounter = 0
    
    -- Navigate to start position (if not already there)
    if myState.blockProgress == 0 then
        -- PRE-FLIGHT CHECK: Ensure inventory is ready before leaving base
        if not ensureInventoryReady() then
            print("ERROR: Cannot start - inventory not ready")
            myState.status = "idle"
            return false
        end
        
        if not navigateToTunnelStart(assignment) then
            return false
        end
    end
    
    -- Mine tunnel
    while blocksMined < config.TUNNEL_LENGTH and running do
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
        
        print("Progress: " .. blocksMined .. "/" .. config.TUNNEL_LENGTH)
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

