-- Advanced Branch Miner Utility Functions
-- Movement, inventory, fuel, and common helper functions

local config = require("config")
local protocol = require("protocol")

local utils = {}

-- ========== POSITION TRACKING ==========

utils.position = {x = 0, y = 0, z = 0, facing = 0}

-- Facing: 0=North(-Z), 1=East(+X), 2=South(+Z), 3=West(-X)
utils.facingNames = {"North", "East", "South", "West"}

function utils.setPosition(x, y, z, facing)
    utils.position.x = x
    utils.position.y = y
    utils.position.z = z
    if facing then
        utils.position.facing = facing
    end
end

function utils.getPosition()
    return utils.position.x, utils.position.y, utils.position.z, utils.position.facing
end

-- ========== TURNING ==========

function utils.turnRight()
    turtle.turnRight()
    utils.position.facing = (utils.position.facing + 1) % 4
end

function utils.turnLeft()
    turtle.turnLeft()
    utils.position.facing = (utils.position.facing - 1) % 4
end

function utils.turnTo(targetFacing)
    while utils.position.facing ~= targetFacing do
        local diff = (targetFacing - utils.position.facing) % 4
        if diff <= 2 then
            utils.turnRight()
        else
            utils.turnLeft()
        end
    end
end

function utils.turnAround()
    utils.turnRight()
    utils.turnRight()
end

-- ========== MOVEMENT ==========

function utils.updatePositionAfterMove(direction)
    if direction == "forward" then
        if utils.position.facing == 0 then
            utils.position.z = utils.position.z - 1
        elseif utils.position.facing == 1 then
            utils.position.x = utils.position.x + 1
        elseif utils.position.facing == 2 then
            utils.position.z = utils.position.z + 1
        else
            utils.position.x = utils.position.x - 1
        end
    elseif direction == "up" then
        utils.position.y = utils.position.y + 1
    elseif direction == "down" then
        utils.position.y = utils.position.y - 1
    end
end

function utils.safeMove(direction, useBroadcast)
    useBroadcast = useBroadcast ~= false  -- Default true
    
    -- Check fuel
    if not utils.ensureFuel(config.MIN_FUEL) then
        return false, "Low fuel"
    end
    
    -- Select movement functions
    local moveFunc, digFunc, detectFunc, attackFunc
    if direction == "forward" then
        moveFunc = turtle.forward
        digFunc = turtle.dig
        detectFunc = turtle.detect
        attackFunc = turtle.attack
    elseif direction == "up" then
        moveFunc = turtle.up
        digFunc = turtle.digUp
        detectFunc = turtle.detectUp
        attackFunc = turtle.attackUp
    elseif direction == "down" then
        moveFunc = turtle.down
        digFunc = turtle.digDown
        detectFunc = turtle.detectDown
        attackFunc = turtle.attackDown
    else
        return false, "Invalid direction"
    end
    
    -- Broadcast position if using collision avoidance
    if useBroadcast then
        protocol.broadcastPosition(utils.position.x, utils.position.y, utils.position.z, 
                                   utils.position.facing, "moving_" .. direction)
    end
    
    -- Attempt movement with retries
    local attempts = 0
    while attempts < config.MAX_RETRIES do
        attempts = attempts + 1
        
        -- Try to move
        if moveFunc() then
            utils.updatePositionAfterMove(direction)
            return true
        end
        
        -- Movement failed - check what's blocking
        if detectFunc() then
            -- Block detected - try to dig it
            digFunc()
            sleep(0.4)  -- Wait for falling blocks
        else
            -- No block - probably entity or turtle
            attackFunc()  -- Clear mobs
            sleep(0.5)
        end
    end
    
    return false, "Movement blocked after " .. attempts .. " attempts"
end

function utils.safeForward(useBroadcast)
    return utils.safeMove("forward", useBroadcast)
end

function utils.safeUp(useBroadcast)
    return utils.safeMove("up", useBroadcast)
end

function utils.safeDown(useBroadcast)
    return utils.safeMove("down", useBroadcast)
end

-- ========== PATHFINDING ==========

function utils.goToPosition(targetX, targetY, targetZ, useBroadcast)
    useBroadcast = useBroadcast ~= false
    
    -- Move vertically first (safer for collision avoidance)
    while utils.position.y < targetY do
        local success, err = utils.safeUp(useBroadcast)
        if not success then return false, err end
    end
    
    while utils.position.y > targetY do
        local success, err = utils.safeDown(useBroadcast)
        if not success then return false, err end
    end
    
    -- Move horizontally
    while utils.position.x < targetX do
        utils.turnTo(1)  -- East
        local success, err = utils.safeForward(useBroadcast)
        if not success then return false, err end
    end
    
    while utils.position.x > targetX do
        utils.turnTo(3)  -- West
        local success, err = utils.safeForward(useBroadcast)
        if not success then return false, err end
    end
    
    while utils.position.z < targetZ do
        utils.turnTo(2)  -- South
        local success, err = utils.safeForward(useBroadcast)
        if not success then return false, err end
    end
    
    while utils.position.z > targetZ do
        utils.turnTo(0)  -- North
        local success, err = utils.safeForward(useBroadcast)
        if not success then return false, err end
    end
    
    return true
end

-- ========== ORE VEIN MINING ==========

function utils.isOre(direction)
    local inspectFunc = direction == "forward" and turtle.inspect or
                       direction == "up" and turtle.inspectUp or
                       turtle.inspectDown
    
    local success, blockData = inspectFunc()
    if success and blockData and blockData.name then
        return config.isOre(blockData.name)
    end
    return false
end

function utils.mineVein(direction, maxDepth, visited)
    maxDepth = maxDepth or config.MAX_VEIN_DEPTH
    visited = visited or {}
    
    if maxDepth <= 0 then return 0 end
    
    local oresFound = 0
    
    -- Check if there's ore in this direction
    if utils.isOre(direction) then
        local digFunc = direction == "forward" and turtle.dig or
                       direction == "up" and turtle.digUp or
                       turtle.digDown
        
        digFunc()
        oresFound = 1
        sleep(0.4)  -- Wait for falling blocks
        
        -- Try to move into the space
        local moveFunc = direction == "forward" and turtle.forward or
                        direction == "up" and turtle.up or
                        turtle.down
        
        if moveFunc() then
            -- Update position temporarily
            local oldX, oldY, oldZ = utils.position.x, utils.position.y, utils.position.z
            utils.updatePositionAfterMove(direction)
            
            local posKey = utils.position.x .. "," .. utils.position.y .. "," .. utils.position.z
            if not visited[posKey] then
                visited[posKey] = true
                
                -- Check all directions for more ore
                oresFound = oresFound + utils.mineVein("up", maxDepth - 1, visited)
                oresFound = oresFound + utils.mineVein("down", maxDepth - 1, visited)
                oresFound = oresFound + utils.mineVein("forward", maxDepth - 1, visited)
                
                -- Check sides
                local oldFacing = utils.position.facing
                for i = 1, 4 do
                    oresFound = oresFound + utils.mineVein("forward", maxDepth - 1, visited)
                    utils.turnRight()
                end
                utils.turnTo(oldFacing)
            end
            
            -- Move back
            local backFunc = direction == "forward" and turtle.back or
                           direction == "up" and turtle.down or
                           turtle.up
            backFunc()
            utils.position.x, utils.position.y, utils.position.z = oldX, oldY, oldZ
        end
    end
    
    return oresFound
end

-- ========== FUEL MANAGEMENT ==========

function utils.getFuelPercent()
    local level = turtle.getFuelLevel()
    local limit = turtle.getFuelLimit()
    
    if level == "unlimited" then return 100 end
    if limit == 0 then return 0 end
    
    return math.floor((level / limit) * 100)
end

function utils.ensureFuel(minLevel)
    if turtle.getFuelLevel() >= minLevel then
        return true
    end
    
    -- Try to refuel from inventory
    for slot = 1, 16 do
        turtle.select(slot)
        local item = turtle.getItemDetail()
        
        if item and config.getFuelValue(item.name) > 0 then
            local needed = math.ceil((minLevel - turtle.getFuelLevel()) / config.getFuelValue(item.name))
            turtle.refuel(math.min(needed, item.count))
            
            if turtle.getFuelLevel() >= minLevel then
                return true
            end
        end
    end
    
    return turtle.getFuelLevel() >= minLevel
end

-- ========== INVENTORY MANAGEMENT ==========

function utils.getFreeSlots()
    local free = 0
    for slot = 1, 16 do
        if turtle.getItemCount(slot) == 0 then
            free = free + 1
        end
    end
    return free
end

function utils.findItem(itemName)
    for slot = 1, 16 do
        local item = turtle.getItemDetail(slot)
        if item and item.name == itemName then
            return slot, item.count
        end
    end
    return nil
end

function utils.findBuildingBlock()
    for slot = 1, 16 do
        local item = turtle.getItemDetail(slot)
        if item and config.isBuildingBlock(item.name) then
            turtle.select(slot)
            return slot, item.name
        end
    end
    return nil
end

function utils.needsResupply()
    -- Check free slots
    if utils.getFreeSlots() < config.MIN_FREE_SLOTS then
        return true, "inventory_full"
    end
    
    -- Check fuel
    if turtle.getFuelLevel() < config.MIN_FUEL then
        if not utils.ensureFuel(config.MIN_FUEL) then
            return true, "low_fuel"
        end
    end
    
    -- Check building blocks
    if not utils.findBuildingBlock() then
        return true, "no_building_blocks"
    end
    
    return false
end

function utils.sortInventory()
    -- Simple consolidation - move items to fill stacks
    for slot = 1, 16 do
        if turtle.getItemCount(slot) > 0 then
            turtle.select(slot)
            local item = turtle.getItemDetail(slot)
            
            if item and item.count < item.maxCount then
                -- Find another slot with same item
                for otherSlot = slot + 1, 16 do
                    local otherItem = turtle.getItemDetail(otherSlot)
                    if otherItem and otherItem.name == item.name then
                        turtle.select(otherSlot)
                        turtle.transferTo(slot)
                        break
                    end
                end
            end
        end
    end
    
    turtle.select(1)
end

-- ========== CHEST OPERATIONS ==========

function utils.depositInventory(keepBuildingBlocks)
    keepBuildingBlocks = keepBuildingBlocks ~= false
    
    local deposited = 0
    
    for slot = 1, 16 do
        turtle.select(slot)
        local item = turtle.getItemDetail(slot)
        
        if item then
            local isBuilding = config.isBuildingBlock(item.name)
            
            if isBuilding then
                -- Keep some building blocks, deposit rest to cobble chest below
                local keepAmount = keepBuildingBlocks and config.COBBLE_KEEP_AMOUNT or 0
                if item.count > keepAmount then
                    turtle.dropDown(item.count - keepAmount)
                    deposited = deposited + (item.count - keepAmount)
                end
            else
                -- Deposit valuable items/ores to item chest in front
                turtle.drop()
                deposited = deposited + item.count
            end
        end
    end
    
    turtle.select(1)
    return deposited
end

function utils.refuelFromChest()
    -- Try to take fuel from chest above
    turtle.select(16)  -- Use last slot for fuel
    local taken = turtle.suckUp(64)
    
    if taken then
        turtle.refuel()
    end
    
    return turtle.getFuelLevel()
end

function utils.restockBuildingBlocks()
    -- Try to get building blocks from chest below
    local slot = utils.findBuildingBlock() or 1
    turtle.select(slot)
    
    local before = turtle.getItemCount(slot)
    turtle.suckDown(64)
    local after = turtle.getItemCount(slot)
    
    return after - before
end

-- ========== PLACING BLOCKS ==========

function utils.placeBlock(direction)
    local slot = utils.findBuildingBlock()
    if not slot then return false end
    
    turtle.select(slot)
    
    if direction == "forward" then
        return turtle.place()
    elseif direction == "up" then
        return turtle.placeUp()
    elseif direction == "down" then
        return turtle.placeDown()
    end
    
    return false
end

function utils.placeTorch()
    local torchSlot = utils.findItem("minecraft:torch")
    if not torchSlot then return false end
    
    turtle.select(torchSlot)
    return turtle.place()
end

-- ========== UTILITY FUNCTIONS ==========

function utils.sleep(seconds)
    sleep(seconds)
end

function utils.getLabel()
    return os.getComputerLabel() or ("Turtle-" .. os.getComputerID())
end

return utils

