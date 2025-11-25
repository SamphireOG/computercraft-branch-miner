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

-- ========== ORIENTATION DETECTION ==========

function utils.isChest(direction)
    -- Check if there's a chest in the specified direction
    local inspectFunc = direction == "forward" and turtle.inspect or
                       direction == "up" and turtle.inspectUp or
                       turtle.inspectDown
    
    local success, blockData = inspectFunc()
    if success and blockData and blockData.name then
        return blockData.name:match("chest") ~= nil
    end
    return false
end

function utils.detectOrientation()
    -- Detect turtle's facing direction by checking for chests
    -- Expected setup: Ores chest in FRONT (south/+Z), Fuel chest ABOVE, Cobble chest BELOW
    
    print("Detecting orientation from chests...")
    print("Checking: Up=" .. tostring(utils.isChest("up")) .. 
          " Down=" .. tostring(utils.isChest("down")))
    
    -- First verify we have chests above/below (confirms we're at home base)
    local hasChestAbove = utils.isChest("up")
    local hasChestBelow = utils.isChest("down")
    
    if not (hasChestAbove or hasChestBelow) then
        print("⚠ No chests above/below - not at home base?")
        return false
    end
    
    print("✓ Chests detected above/below (at home base)")
    
    -- Now check all 4 directions for the ores chest in front
    local startFacing = utils.position.facing or 0
    
    for turn = 0, 3 do
        print("Checking direction " .. turn .. "...")
        
        if utils.isChest("forward") then
            -- Found ores chest in front
            -- Ores chest is at HOME_Z + 1 (south of home)
            -- Mining tunnels go north (negative Z), so we need to face NORTH (away from chest)
            turtle.turnRight()
            turtle.turnRight()  -- Turn 180° to face away from chest
            
            utils.position.facing = 0  -- Facing NORTH (toward mining tunnels, negative Z)
            print("✓ Orientation set: Facing North (toward mining area)")
            print("  (Ores chest is behind/south of us)")
            return true
        end
        
        turtle.turnRight()
    end
    
    print("⚠ Could not find ores chest in any direction")
    print("  Make sure ores chest is placed adjacent to turtle")
    return false
end

function utils.isNearHomeBase(x, y, z)
    -- Check if position is within 3 blocks of home base (generous protection zone)
    local dx = math.abs(x - config.HOME_X)
    local dy = math.abs(y - config.HOME_Y)
    local dz = math.abs(z - config.HOME_Z)
    
    -- Extra generous on Y-axis to protect fuel chest above and cobble chest below
    return dx <= 3 and dy <= 3 and dz <= 3
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
    local moveFunc, digFunc, detectFunc, attackFunc, inspectFunc
    if direction == "forward" then
        moveFunc = turtle.forward
        digFunc = turtle.dig
        detectFunc = turtle.detect
        attackFunc = turtle.attack
        inspectFunc = turtle.inspect
    elseif direction == "up" then
        moveFunc = turtle.up
        digFunc = turtle.digUp
        detectFunc = turtle.detectUp
        attackFunc = turtle.attackUp
        inspectFunc = turtle.inspectUp
    elseif direction == "down" then
        moveFunc = turtle.down
        digFunc = turtle.digDown
        detectFunc = turtle.detectDown
        attackFunc = turtle.attackDown
        inspectFunc = turtle.inspectDown
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
            -- CHEST PROTECTION: NEVER dig chests (they're our supply chests!)
            local success, blockData = inspectFunc()
            if success and blockData and blockData.name then
                local isChest = blockData.name:match("chest") ~= nil
                
                if isChest then
                    -- Calculate where we are and where we're trying to go
                    local targetX, targetY, targetZ = utils.position.x, utils.position.y, utils.position.z
                    if direction == "forward" then
                        if utils.position.facing == 0 then targetZ = targetZ - 1
                        elseif utils.position.facing == 1 then targetX = targetX + 1
                        elseif utils.position.facing == 2 then targetZ = targetZ + 1
                        else targetX = targetX - 1 end
                    elseif direction == "up" then
                        targetY = targetY + 1
                    elseif direction == "down" then
                        targetY = targetY - 1
                    end
                    
                    -- Check if chest is near home (within 3 blocks)
                    local nearHome = utils.isNearHomeBase(targetX, targetY, targetZ)
                    
                    -- CRITICAL: Protect ALL chests near home, especially up/down/forward from start position
                    if nearHome then
                        print("⚠ CHEST PROTECTED at " .. targetX .. "," .. targetY .. "," .. targetZ)
                        print("  Current pos: " .. utils.position.x .. "," .. utils.position.y .. "," .. utils.position.z)
                        return false, "Blocked by protected supply chest (won't dig)"
                    end
                    
                    -- Also protect any chest when we're very close to home position
                    local atHome = (math.abs(utils.position.x) <= 1 and 
                                   math.abs(utils.position.y - config.HOME_Y) <= 1 and 
                                   math.abs(utils.position.z) <= 1)
                    
                    if atHome then
                        print("⚠ CHEST PROTECTED (at home base)")
                        return false, "Blocked by supply chest at home"
                    end
                end
            end
            
            -- Block detected - try to dig it (not a protected chest)
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
    
    -- Check if we're already at target
    if utils.position.x == targetX and utils.position.y == targetY and utils.position.z == targetZ then
        return true  -- Already there!
    end
    
    -- CRITICAL: If both current position and target are at/near home, don't move!
    -- This prevents breaking supply chests when tunnel starts at home base
    local currentNearHome = (math.abs(utils.position.x - config.HOME_X) <= 1 and
                            math.abs(utils.position.y - config.HOME_Y) <= 1 and
                            math.abs(utils.position.z - config.HOME_Z) <= 1)
    
    local targetNearHome = (math.abs(targetX - config.HOME_X) <= 1 and
                           math.abs(targetY - config.HOME_Y) <= 1 and
                           math.abs(targetZ - config.HOME_Z) <= 1)
    
    if currentNearHome and targetNearHome then
        print("⚠ Both current and target near home - skipping navigation")
        print("  (Prevents breaking supply chests)")
        return true  -- Treat as success, we're close enough
    end
    
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
    
    -- Try to refuel from inventory (slots 1-15 first, slot 16 is emergency reserve)
    for slot = 1, 15 do
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
    
    -- Last resort: use fuel from slot 16 (emergency reserve)
    if turtle.getFuelLevel() < minLevel then
        turtle.select(16)
        local item = turtle.getItemDetail()
        
        if item and config.getFuelValue(item.name) > 0 then
            local needed = math.ceil((minLevel - turtle.getFuelLevel()) / config.getFuelValue(item.name))
            turtle.refuel(math.min(needed, item.count))
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
        -- SKIP SLOT 16: This is our fuel storage, don't deposit it!
        if slot == 16 then
            -- Keep fuel items in slot 16
        else
            turtle.select(slot)
            local item = turtle.getItemDetail(slot)
            
            if item then
                local isBuilding = config.isBuildingBlock(item.name)
                local isFuel = config.getFuelValue(item.name) > 0
                
                if isBuilding then
                    -- Keep building blocks in slot 1, deposit rest to cobble chest below
                    if slot == 1 then
                        local keepAmount = keepBuildingBlocks and config.COBBLE_KEEP_AMOUNT or 0
                        if item.count > keepAmount then
                            turtle.dropDown(item.count - keepAmount)
                            deposited = deposited + (item.count - keepAmount)
                        end
                    else
                        -- Building blocks in other slots -> deposit to cobble chest
                        turtle.dropDown()
                        deposited = deposited + item.count
                    end
                elseif isFuel then
                    -- Fuel items found in slots 2-15 -> deposit to fuel chest above
                    turtle.dropUp()
                    deposited = deposited + item.count
                else
                    -- Valuable items/ores -> deposit to item chest in front
                    turtle.drop()
                    deposited = deposited + item.count
                end
            end
        end
    end
    
    turtle.select(1)
    return deposited
end

function utils.refuelFromChest()
    -- Take fuel items from chest above and store in slot 16
    turtle.select(16)
    
    -- First, refuel if we're critically low (below minimum)
    local currentFuel = turtle.getFuelLevel()
    if currentFuel < config.MIN_FUEL then
        -- Refuel enough to reach safe level
        local fuelNeeded = config.MIN_FUEL - currentFuel + config.FUEL_BUFFER
        local itemsInSlot = turtle.getItemCount(16)
        
        if itemsInSlot > 0 then
            -- Use existing fuel items first
            local itemDetail = turtle.getItemDetail(16)
            if itemDetail then
                local fuelValue = config.getFuelValue(itemDetail.name)
                if fuelValue > 0 then
                    local itemsToUse = math.ceil(fuelNeeded / fuelValue)
                    itemsToUse = math.min(itemsToUse, itemsInSlot)
                    turtle.refuel(itemsToUse)
                end
            end
        end
    end
    
    -- Then, take MORE fuel items from chest to keep slot 16 stocked
    -- Only take if slot 16 has less than 32 items
    local currentCount = turtle.getItemCount(16)
    if currentCount < 32 then
        local spaceLeft = 64 - currentCount
        turtle.suckUp(spaceLeft)
    end
    
    return turtle.getFuelLevel()
end

function utils.restockBuildingBlocks()
    -- Restock building blocks in slot 1 (target: 32-64 items)
    turtle.select(1)
    
    local currentCount = turtle.getItemCount(1)
    local targetMin = 32
    local targetMax = 64
    
    -- If we already have enough, we're good
    if currentCount >= targetMin then
        return 0
    end
    
    -- Take from chest below to reach target range
    local needed = targetMax - currentCount
    local before = currentCount
    turtle.suckDown(needed)
    local after = turtle.getItemCount(1)
    
    local restocked = after - before
    
    -- Verify we got at least the minimum
    if after < targetMin then
        -- Not enough cobble in chest!
        return restocked
    end
    
    return restocked
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

