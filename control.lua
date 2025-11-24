-- Advanced Branch Miner Pocket Computer Controller
-- Wireless GUI for monitoring and controlling turtle fleet

local config = require("config")
local protocol = require("protocol")

-- ========== GUI STATE ==========

local turtles = {}  -- Tracked turtles {id -> data}
local selectedTurtle = nil
local scrollOffset = 0
local running = true
local lastUpdate = 0

-- ========== COLORS ==========

local colorScheme = {
    header = colors.blue,
    active = colors.lime,
    warning = colors.yellow,
    error = colors.red,
    idle = colors.lightGray,
    paused = colors.orange,
    background = colors.black,
    text = colors.white
}

-- ========== SCREEN HELPERS ==========

local function clearScreen()
    term.setBackgroundColor(colorScheme.background)
    term.setTextColor(colorScheme.text)
    term.clear()
    term.setCursorPos(1, 1)
end

local function drawBar(percent, maxWidth)
    local filled = math.floor((percent / 100) * maxWidth)
    local bar = string.rep("=", filled) .. string.rep("-", maxWidth - filled)
    return bar
end

local function drawHeader()
    local w, h = term.getSize()
    
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colorScheme.header)
    term.setTextColor(colorScheme.text)
    term.clearLine()
    
    local title = " Branch Miner Control "
    term.setCursorPos(math.floor((w - #title) / 2), 1)
    term.write(title)
    
    -- Status line
    term.setCursorPos(1, 2)
    term.setBackgroundColor(colorScheme.background)
    term.setTextColor(colorScheme.text)
    term.clearLine()
    
    local activeCount = 0
    local miningCount = 0
    local pausedCount = 0
    
    for _, turtle in pairs(turtles) do
        if turtle.status ~= "offline" then
            activeCount = activeCount + 1
            if turtle.status == "mining" then
                miningCount = miningCount + 1
            elseif turtle.status == "paused" then
                pausedCount = pausedCount + 1
            end
        end
    end
    
    local status = "Turtles: " .. activeCount .. " active"
    if miningCount > 0 then
        status = status .. ", " .. miningCount .. " mining"
    end
    if pausedCount > 0 then
        status = status .. ", " .. pausedCount .. " paused"
    end
    
    term.write(status)
end

local function drawTurtleList()
    local w, h = term.getSize()
    local listStart = 4
    local listHeight = h - 7  -- Leave room for header and controls
    
    -- List header
    term.setCursorPos(1, listStart - 1)
    term.setBackgroundColor(colorScheme.background)
    term.setTextColor(colorScheme.idle)
    term.clearLine()
    term.write("ID  Label         Status      Fuel  Inv  Position")
    
    -- Draw turtles
    local turtleList = {}
    for id, turtle in pairs(turtles) do
        table.insert(turtleList, {id = id, data = turtle})
    end
    
    table.sort(turtleList, function(a, b) return a.id < b.id end)
    
    for i = 1, listHeight do
        local idx = i + scrollOffset
        local y = listStart + i - 1
        
        term.setCursorPos(1, y)
        term.setBackgroundColor(colorScheme.background)
        term.clearLine()
        
        if turtleList[idx] then
            local turtle = turtleList[idx].data
            local id = turtleList[idx].id
            
            -- Status color
            local statusColor = colorScheme.idle
            if turtle.status == "mining" then
                statusColor = colorScheme.active
            elseif turtle.status == "paused" then
                statusColor = colorScheme.paused
            elseif turtle.status == "offline" then
                statusColor = colorScheme.error
            elseif turtle.status == "returning" then
                statusColor = colorScheme.warning
            end
            
            -- Highlight selected
            if selectedTurtle == id then
                term.setBackgroundColor(colors.gray)
            end
            
            term.setTextColor(colorScheme.text)
            
            -- Format line
            local label = turtle.label or ("Turtle-" .. id)
            if #label > 12 then label = label:sub(1, 12) end
            label = label .. string.rep(" ", 12 - #label)
            
            local status = turtle.status or "unknown"
            if #status > 10 then status = status:sub(1, 10) end
            status = status .. string.rep(" ", 10 - #status)
            
            local fuel = turtle.fuelPercent or 0
            local fuelStr = string.format("%3d%%", fuel)
            
            local inv = turtle.freeSlots or 0
            local invStr = string.format("%2d", inv)
            
            local pos = turtle.position or {x = 0, y = 0, z = 0}
            local posStr = string.format("%d,%d,%d", pos.x, pos.y, pos.z)
            
            term.write(string.format("%-3s ", id))
            term.write(label .. " ")
            term.setTextColor(statusColor)
            term.write(status .. " ")
            term.setTextColor(colorScheme.text)
            term.write(fuelStr .. " ")
            term.write(invStr .. "  ")
            term.write(posStr)
            
            term.setBackgroundColor(colorScheme.background)
        end
    end
end

local function drawControls()
    local w, h = term.getSize()
    local controlY = h - 3
    
    -- Draw control panel
    term.setCursorPos(1, controlY)
    term.setBackgroundColor(colorScheme.background)
    term.setTextColor(colorScheme.idle)
    term.clearLine()
    term.write(string.rep("-", w))
    
    term.setCursorPos(1, controlY + 1)
    term.clearLine()
    term.setTextColor(colorScheme.text)
    
    if selectedTurtle then
        term.write("[P]ause [R]esume [H]ome [S]hutdown")
    else
        term.write("[A]ll Pause [Z]All Resume [Q]uit [Up/Down]Select")
    end
    
    term.setCursorPos(1, controlY + 2)
    term.clearLine()
    term.write("[F]Refresh Status [C]lear Offline")
end

local function drawScreen()
    clearScreen()
    drawHeader()
    drawTurtleList()
    drawControls()
end

-- ========== NETWORK FUNCTIONS ==========

local function sendCommand(cmd, targetID)
    print("Sending " .. cmd .. " to " .. (targetID or "ALL"))
    
    local success, msg, ack = protocol.sendWithRetry(cmd, {}, targetID, true)
    
    if success then
        term.setTextColor(colorScheme.active)
        print("Command acknowledged!")
        term.setTextColor(colorScheme.text)
        sleep(1)
    else
        term.setTextColor(colorScheme.error)
        print("Command failed: No ACK")
        term.setTextColor(colorScheme.text)
        sleep(2)
    end
end

local function updateTurtleData(msg)
    if msg.type == protocol.MSG_TYPES.HEARTBEAT then
        local id = msg.sender
        local data = msg.data
        
        if not turtles[id] then
            turtles[id] = {
                label = msg.senderLabel,
                lastSeen = os.epoch("utc")
            }
        end
        
        local turtle = turtles[id]
        turtle.label = msg.senderLabel
        turtle.status = data.status or "unknown"
        turtle.position = data.position or {x = 0, y = 0, z = 0}
        turtle.fuelLevel = data.fuel and data.fuel.level or 0
        turtle.fuelPercent = data.fuel and data.fuel.percent or 0
        turtle.freeSlots = data.inventory and data.inventory.freeSlots or 0
        turtle.currentTask = data.currentTask
        turtle.lastSeen = os.epoch("utc")
    end
end

local function checkForMessages()
    -- Non-blocking check for messages
    local hasEvent = os.pullEvent("modem_message")
    
    if hasEvent then
        local event, side, channel, replyChannel, message, distance = hasEvent, side, channel, replyChannel, message, distance
        
        if channel == config.MODEM_CHANNEL and type(message) == "table" then
            if message.version == config.PROTOCOL_VERSION then
                updateTurtleData(message)
            end
        end
    end
end

local function requestAllStatus()
    protocol.send(protocol.MSG_TYPES.CMD_STATUS_ALL, {})
    print("Requesting status from all turtles...")
    sleep(1)
end

local function cleanupOffline()
    local now = os.epoch("utc")
    local removed = 0
    
    for id, turtle in pairs(turtles) do
        local ageSeconds = (now - turtle.lastSeen) / 1000
        
        if ageSeconds > config.OFFLINE_THRESHOLD * 2 then
            turtles[id] = nil
            removed = removed + 1
        end
    end
    
    if removed > 0 then
        print("Removed " .. removed .. " offline turtles")
        sleep(1)
    end
end

-- ========== INPUT HANDLING ==========

local function handleInput()
    local event, key = os.pullEvent("key")
    
    if key == keys.q then
        running = false
        
    elseif key == keys.f then
        requestAllStatus()
        
    elseif key == keys.c then
        cleanupOffline()
        
    elseif key == keys.up then
        if scrollOffset > 0 then
            scrollOffset = scrollOffset - 1
        end
        
    elseif key == keys.down then
        local turtleCount = 0
        for _ in pairs(turtles) do turtleCount = turtleCount + 1 end
        
        local w, h = term.getSize()
        local maxScroll = math.max(0, turtleCount - (h - 7))
        
        if scrollOffset < maxScroll then
            scrollOffset = scrollOffset + 1
        end
        
    elseif key == keys.a then
        -- Pause all
        sendCommand(protocol.MSG_TYPES.CMD_PAUSE, nil)
        
    elseif key == keys.z then
        -- Resume all
        sendCommand(protocol.MSG_TYPES.CMD_RESUME, nil)
        
    elseif selectedTurtle then
        -- Commands for selected turtle
        if key == keys.p then
            sendCommand(protocol.MSG_TYPES.CMD_PAUSE, selectedTurtle)
            
        elseif key == keys.r then
            sendCommand(protocol.MSG_TYPES.CMD_RESUME, selectedTurtle)
            
        elseif key == keys.h then
            sendCommand(protocol.MSG_TYPES.CMD_RETURN_BASE, selectedTurtle)
            
        elseif key == keys.s then
            -- Confirm shutdown
            term.setCursorPos(1, 1)
            term.setTextColor(colorScheme.error)
            term.write("Shutdown turtle " .. selectedTurtle .. "? (Y/N)")
            
            local confirm = os.pullEvent("char")
            if confirm == "y" or confirm == "Y" then
                sendCommand(protocol.MSG_TYPES.CMD_SHUTDOWN, selectedTurtle)
            end
        end
    end
end

-- ========== MAIN LOOP ==========

local function mainLoop()
    while running do
        -- Update display
        local now = os.clock()
        if now - lastUpdate > 2 then
            drawScreen()
            lastUpdate = now
        end
        
        -- Handle events
        parallel.waitForAny(
            function()
                handleInput()
            end,
            function()
                checkForMessages()
            end,
            function()
                sleep(0.1)
            end
        )
    end
end

-- ========== INITIALIZATION ==========

local function init()
    -- Check for modem
    if not peripheral.find("modem") then
        print("ERROR: No wireless modem found!")
        print("Attach an Ender Modem to use this controller.")
        return false
    end
    
    -- Initialize protocol
    protocol.init()
    
    print("=== Branch Miner Controller ===")
    print("Listening on channel " .. config.MODEM_CHANNEL)
    print("Press any key to start...")
    os.pullEvent("key")
    
    -- Request initial status from all turtles
    requestAllStatus()
    sleep(1)
    
    return true
end

-- ========== MAIN ==========

local function main()
    if not init() then
        return
    end
    
    local success, err = pcall(mainLoop)
    
    if not success then
        clearScreen()
        term.setTextColor(colorScheme.error)
        print("ERROR: " .. tostring(err))
        term.setTextColor(colorScheme.text)
    end
    
    -- Cleanup
    clearScreen()
    protocol.close()
    print("Controller stopped")
end

-- Run
main()

