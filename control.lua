-- Advanced Branch Miner Pocket Computer Controller
-- Wireless GUI for monitoring and controlling turtle fleet

local config = require("config")
local protocol = require("protocol")
local projectServer = require("project-server")
local gui = require("gui")

-- ========== PROJECT MANAGEMENT ==========

local currentProject = nil
local availableProjects = {}

local function getProjectFilename(projectName)
    return "project_" .. projectName .. ".cfg"
end

local function listProjects()
    local projects = {}
    for _, file in ipairs(fs.list("/")) do
        if file:match("^project_(.+)%.cfg$") then
            local name = file:match("^project_(.+)%.cfg$")
            table.insert(projects, name)
        end
    end
    return projects
end

local function loadProjectConfig(projectName)
    local filename = getProjectFilename(projectName)
    if not fs.exists(filename) then
        return nil
    end
    
    local file = fs.open(filename, "r")
    if not file then
        return nil
    end
    
    local content = file.readAll()
    file.close()
    
    return textutils.unserialize(content)
end

local function switchProject(projectName)
    local projectConfig = loadProjectConfig(projectName)
    if not projectConfig then
        return false, "Project not found"
    end
    
    -- Close old modem connection
    if protocol.modem then
        protocol.close()
    end
    
    -- Switch to new project's channel
    currentProject = projectConfig
    config.MODEM_CHANNEL = projectConfig.channel or 42
    
    -- Reinitialize protocol with new channel
    protocol.init()
    
    -- Also keep discovery channel open for pairing
    if protocol.modem then
        protocol.modem.open(100)
    end
    
    -- Clear old turtle data
    turtles = {}
    selectedTurtle = nil
    
    return true
end

local function getNextAvailableChannel()
    -- Channel 100 is reserved for discovery
    -- Projects start at 101
    local baseChannel = 101
    local projects = listProjects()
    
    if #projects == 0 then
        return baseChannel
    end
    
    local maxChannel = baseChannel - 1
    for _, projName in ipairs(projects) do
        local cfg = loadProjectConfig(projName)
        if cfg and cfg.channel and cfg.channel > maxChannel then
            maxChannel = cfg.channel
        end
    end
    
    return maxChannel + 1
end

local function saveProjectConfig(projectName, projectConfig)
    local filename = getProjectFilename(projectName)
    local file = fs.open(filename, "w")
    if file then
        file.write(textutils.serialize(projectConfig))
        file.close()
        return true
    end
    return false
end

-- ========== COLORS & SCREEN HELPERS ==========

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

local function clearScreen()
    term.setBackgroundColor(colorScheme.background)
    term.setTextColor(colorScheme.text)
    term.clear()
    term.setCursorPos(1, 1)
end

local function createNewProject()
    clearScreen()
    local w, h = term.getSize()
    
    -- Fancy header
    term.setBackgroundColor(colors.lime)
    term.setTextColor(colors.black)
    term.setCursorPos(1, 1)
    term.clearLine()
    local title = " + CREATE NEW PROJECT + "
    term.setCursorPos(math.floor((w - #title) / 2), 1)
    term.write(title)
    
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    
    -- Cancel button at bottom
    gui.clearButtons()
    gui.createButton("cancel_create", 2, h - 2, w - 4, 1, "< CANCEL (Press Q)", nil, colors.red, colors.white)
    gui.drawAllButtons()
    
    term.setCursorPos(2, 3)
    print("Project name:")
    term.setTextColor(colors.gray)
    term.setCursorPos(2, 4)
    print("(or press Q to cancel)")
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.setCursorPos(2, 5)
    term.write(string.rep(" ", w - 3))
    term.setCursorPos(2, 5)
    
    -- Listen for both input and Q key
    local projectName = ""
    while true do
        local event, param1, param2, param3 = os.pullEvent()
        if event == "char" then
            if param1 == "q" or param1 == "Q" then
                return false  -- Cancel
            end
            projectName = projectName .. param1
            term.write(param1)
        elseif event == "key" then
            if param1 == keys.enter then
                break
            elseif param1 == keys.backspace and #projectName > 0 then
                projectName = projectName:sub(1, -2)
                local x, y = term.getCursorPos()
                term.setCursorPos(x - 1, y)
                term.write(" ")
                term.setCursorPos(x - 1, y)
            end
        elseif event == "mouse_click" then
            if gui.handleClick(param2, param3) then
                return false  -- Cancel button clicked
            end
        end
    end
    
    term.setBackgroundColor(colors.black)
    
    if projectName == "" then
        term.setCursorPos(2, 7)
        term.setTextColor(colors.red)
        print("Invalid name!")
        sleep(2)
        return false
    end
    
    -- Check if exists
    if loadProjectConfig(projectName) then
        term.setCursorPos(2, 7)
        term.setTextColor(colors.red)
        print("Project already exists!")
        sleep(2)
        return false
    end
    
    term.setTextColor(colors.white)
    term.setCursorPos(2, 7)
    print("Tunnel length [64]:")
    term.setCursorPos(2, 8)
    term.setTextColor(colors.gray)
    print("(or Q to cancel)")
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.setCursorPos(2, 9)
    term.write(string.rep(" ", w - 3))
    term.setCursorPos(2, 9)
    local lengthInput = read()
    if lengthInput:lower() == "q" then return false end
    local length = tonumber(lengthInput) or 64
    
    term.setBackgroundColor(colors.black)
    term.setCursorPos(2, 11)
    term.setTextColor(colors.white)
    print("Layers [3]:")
    term.setCursorPos(2, 12)
    term.setTextColor(colors.gray)
    print("(or Q to cancel)")
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.setCursorPos(2, 13)
    term.write(string.rep(" ", w - 3))
    term.setCursorPos(2, 13)
    local layersInput = read()
    if layersInput:lower() == "q" then return false end
    local layers = tonumber(layersInput) or 3
    
    term.setBackgroundColor(colors.black)
    term.setCursorPos(2, 15)
    term.setTextColor(colors.white)
    print("Start Y [-59]:")
    term.setCursorPos(2, 16)
    term.setTextColor(colors.gray)
    print("(or Q to cancel)")
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.setCursorPos(2, 17)
    term.write(string.rep(" ", w - 3))
    term.setCursorPos(2, 17)
    local startYInput = read()
    if startYInput:lower() == "q" then return false end
    local startY = tonumber(startYInput) or -59
    
    term.setBackgroundColor(colors.black)
    
    local channel = getNextAvailableChannel()
    
    local projectConfig = {
        name = projectName,
        channel = channel,
        tunnelLength = length,
        numLayers = layers,
        startY = startY,
        homeSet = false,
        createdAt = os.epoch("utc")
    }
    
    if saveProjectConfig(projectName, projectConfig) then
        term.setBackgroundColor(colors.black)
        term.setCursorPos(2, 19)
        term.setTextColor(colors.lime)
        print("\7 Created!")
        term.setCursorPos(2, 20)
        term.setTextColor(colors.cyan)
        print("Channel: " .. channel)
        sleep(2)
        
        -- Register with project server
        projectServer.createProject(projectName, projectConfig)
        return true
    else
        term.setBackgroundColor(colors.black)
        term.setCursorPos(2, 19)
        term.setTextColor(colors.red)
        print("Save failed!")
        sleep(2)
        return false
    end
end

local function deleteProject()
    clearScreen()
    local w, h = term.getSize()
    local selectedProject = nil
    local deleteRunning = true
    
    -- Fancy header
    term.setBackgroundColor(colors.red)
    term.setTextColor(colors.white)
    term.setCursorPos(1, 1)
    term.clearLine()
    local title = " - DELETE PROJECT - "
    term.setCursorPos(math.floor((w - #title) / 2), 1)
    term.write(title)
    
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    
    local projects = listProjects()
    if #projects == 0 then
        term.setCursorPos(2, 3)
        term.setTextColor(colors.orange)
        print("No projects to delete!")
        sleep(2)
        return false
    end
    
    term.setCursorPos(2, 3)
    print("Click a project to delete:")
    
    -- Clear buttons
    gui.clearButtons()
    
    -- Draw project buttons
    local startY = 5
    for i, proj in ipairs(projects) do
        if startY + (i-1) * 2 >= h - 4 then
            break  -- Don't overflow screen
        end
        
        gui.createButton("del_proj_" .. i, 2, startY + (i-1) * 2, w - 4, 2, proj, function()
            selectedProject = proj
        end, colors.gray, colors.white)
    end
    
    -- Cancel button
    gui.createButton("cancel_del", 2, h - 2, w - 4, 1, "< CANCEL", function()
        deleteRunning = false
    end, colors.lime, colors.black)
    
    gui.drawAllButtons()
    
    -- Handle selection
    while deleteRunning and not selectedProject do
        local event = {os.pullEvent()}
        if event[1] == "mouse_click" then
            gui.handleClick(event[3], event[4])
        elseif event[1] == "mouse_drag" then
            gui.updateHover(event[3], event[4])
        elseif event[1] == "key" and event[2] == keys.q then
            return false
        end
    end
    
    if not deleteRunning then
        return false
    end
    
    -- Confirmation screen
    clearScreen()
    term.setBackgroundColor(colors.red)
    term.setTextColor(colors.white)
    term.setCursorPos(1, 1)
    term.clearLine()
    term.setCursorPos(math.floor((w - #title) / 2), 1)
    term.write(title)
    
    term.setBackgroundColor(colors.black)
    term.setCursorPos(2, 3)
    term.setTextColor(colors.orange)
    print("WARNING!")
    term.setTextColor(colors.white)
    term.setCursorPos(2, 5)
    print("Delete this project?")
    term.setCursorPos(2, 6)
    term.setTextColor(colors.yellow)
    print(" '" .. selectedProject .. "'")
    term.setTextColor(colors.white)
    
    gui.clearButtons()
    
    -- Confirm button
    gui.createButton("confirm_del", 2, h - 5, w - 4, 2, "YES, DELETE IT", function()
        -- Delete project file
        local filename = getProjectFilename(selectedProject)
        if fs.exists(filename) then
            fs.delete(filename)
        end
        
        -- Show success message
        clearScreen()
        term.setBackgroundColor(colors.lime)
        term.setTextColor(colors.black)
        term.setCursorPos(1, 1)
        term.clearLine()
        term.setCursorPos(math.floor((w - 12) / 2), 1)
        term.write(" \7 DELETED \7 ")
        
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.lime)
        term.setCursorPos(2, 3)
        print("Project deleted!")
        sleep(2)
        
        deleteRunning = false
    end, colors.red, colors.white)
    
    -- Cancel button
    gui.createButton("cancel_confirm", 2, h - 2, w - 4, 1, "< NO, GO BACK", function()
        deleteRunning = false
    end, colors.gray, colors.white)
    
    gui.drawAllButtons()
    
    -- Handle confirmation
    while deleteRunning do
        local event = {os.pullEvent()}
        if event[1] == "mouse_click" then
            gui.handleClick(event[3], event[4])
        elseif event[1] == "mouse_drag" then
            gui.updateHover(event[3], event[4])
        elseif event[1] == "key" and event[2] == keys.q then
            return false
        end
    end
    
    return true
end

local function projectManagementMenu()
    local menuRunning = true
    
    while menuRunning do
        clearScreen()
        local w, h = term.getSize()
        
        -- Fancy header
        term.setBackgroundColor(colors.blue)
        term.setTextColor(colors.white)
        term.setCursorPos(1, 1)
        term.clearLine()
        local title = " \7 PROJECT MANAGEMENT \7 "
        term.setCursorPos(math.floor((w - #title) / 2), 1)
        term.write(title)
        
        term.setBackgroundColor(colors.black)
        term.setCursorPos(1, 3)
        term.setTextColor(colors.white)
        print("Manage your mining projects:")
        print("")
        
        -- Clear buttons
        gui.clearButtons()
        
        -- Create project button
        gui.createButton("create", 2, 7, w - 4, 3, "+ CREATE PROJECT", function()
            createNewProject()
        end, colors.lime, colors.black)
        
        -- Delete project button
        gui.createButton("delete", 2, 11, w - 4, 3, "- DELETE PROJECT", function()
            deleteProject()
        end, colors.red, colors.white)
        
        -- Back button
        gui.createButton("back", 2, h - 2, w - 4, 1, "< GO BACK", function()
            menuRunning = false
        end, colors.gray, colors.white)
        
        gui.drawAllButtons()
        
        -- Handle clicks
        while true do
            local event = {os.pullEvent()}
            if event[1] == "mouse_click" then
                gui.handleClick(event[3], event[4])
                break  -- Redraw after action
            elseif event[1] == "mouse_drag" then
                gui.updateHover(event[3], event[4])
            elseif event[1] == "key" and event[2] == keys.q then
                menuRunning = false
                break
            end
        end
        
        if not menuRunning then
            break
        end
    end
end

-- ========== GUI STATE ==========

local turtles = {}  -- Tracked turtles {id -> data}
local selectedTurtle = nil
local scrollOffset = 0
local running = true
local lastUpdate = 0

-- ========== SCREEN HELPERS (continued) ==========

local function drawBar(percent, maxWidth)
    local filled = math.floor((percent / 100) * maxWidth)
    local bar = string.rep("=", filled) .. string.rep("-", maxWidth - filled)
    return bar
end

local function drawHeader()
    local w, h = term.getSize()
    
    -- Fancy header with gradient effect (using different shades)
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.clearLine()
    
    local title = " \7 BRANCH MINER CONTROL \7 "
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
    
    -- Show project info with badges
    term.setCursorPos(1, 2)
    term.setBackgroundColor(colorScheme.background)
    term.clearLine()
    
    local projectName = currentProject and currentProject.name or "No Project"
    
    -- Project badge
    term.setTextColor(colorScheme.idle)
    term.write("Project: ")
    term.setBackgroundColor(colors.purple)
    term.setTextColor(colors.white)
    term.write(" " .. projectName .. " ")
    term.setBackgroundColor(colorScheme.background)
    
    -- Channel badge
    term.setTextColor(colorScheme.idle)
    term.write(" Ch:")
    term.setBackgroundColor(colors.cyan)
    term.setTextColor(colors.black)
    term.write(" " .. config.MODEM_CHANNEL .. " ")
    term.setBackgroundColor(colorScheme.background)
    
    term.setCursorPos(1, 3)
    term.clearLine()
    
    -- Status with colored indicators
    term.setTextColor(colorScheme.text)
    term.write("Active: ")
    term.setTextColor(activeCount > 0 and colors.lime or colors.red)
    term.write(activeCount)
    term.setTextColor(colorScheme.text)
    
    if miningCount > 0 then
        term.write("  Mining: ")
        term.setTextColor(colors.lime)
        term.write(miningCount)
        term.setTextColor(colorScheme.text)
    end
    if pausedCount > 0 then
        term.write("  Paused: ")
        term.setTextColor(colors.orange)
        term.write(pausedCount)
        term.setTextColor(colorScheme.text)
    end
end

local function drawTurtleList()
    local w, h = term.getSize()
    local listStart = 4
    local listHeight = h - 8  -- Leave room for header and 3-row controls
    
    -- List header with fancy colors and icons
    term.setCursorPos(1, listStart - 1)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(" ID  Label        Status       \9Fuel \7Inv ")
    term.setBackgroundColor(colorScheme.background)
    
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
            
            -- Status color and background
            local statusColor = colorScheme.idle
            local statusBg = colorScheme.background
            local statusText = "idle"
            
            if turtle.status == "mining" then
                statusColor = colorScheme.active
                statusText = "mining"
            elseif turtle.status == "paused" then
                statusColor = colorScheme.paused
                statusText = "paused"
            elseif turtle.status == "offline" then
                statusColor = colorScheme.error
                statusText = "OFFLINE"
            elseif turtle.status == "returning" then
                statusColor = colorScheme.warning
                statusText = "return"
            else
                statusText = turtle.status
            end
            
            -- Highlight selected with fancy colors
            if selectedTurtle == id then
                term.setBackgroundColor(colors.lightBlue)
            else
                term.setBackgroundColor(colorScheme.background)
            end
            
            term.setTextColor(colorScheme.text)
            
            -- Format line with visual badges
            local label = turtle.label or ("Turtle-" .. id)
            if #label > 10 then label = label:sub(1, 10) end
            label = label .. string.rep(" ", 10 - #label)
            
            local fuel = turtle.fuelPercent or 0
            local fuelStr = string.format("%3d%%", fuel)
            
            local inv = turtle.freeSlots or 0
            local invStr = string.format("%2d", inv)
            
            -- Draw turtle ID and label
            term.write(string.format(" %-2s ", id))
            term.write(label .. " ")
            
            -- Draw status badge
            term.setBackgroundColor(statusColor)
            term.setTextColor(colors.white)
            term.write(" " .. statusText .. " ")
            term.setBackgroundColor(selectedTurtle == id and colors.lightBlue or colorScheme.background)
            term.write(" ")
            
            -- Draw fuel bar
            local fuelColor = colors.lime
            if fuel < 20 then
                fuelColor = colors.red
            elseif fuel < 50 then
                fuelColor = colors.yellow
            end
            term.setTextColor(fuelColor)
            term.write(fuelStr)
            
            -- Draw inventory
            term.setTextColor(colorScheme.text)
            term.write(" " .. invStr .. " ")
            
            term.setBackgroundColor(colorScheme.background)
        end
    end
end

local function drawControls()
    local w, h = term.getSize()
    local controlY = h - 4  -- Changed to -4 for 3 rows
    
    -- Draw control panel separator
    term.setCursorPos(1, controlY)
    term.setBackgroundColor(colorScheme.background)
    term.setTextColor(colorScheme.idle)
    term.clearLine()
    term.write(string.rep("-", w))
    
    -- Clear button area
    gui.clearButtons()
    
    local buttonY = controlY + 1
    
    if selectedTurtle then
        -- Turtle-specific controls (3 rows, compact)
        -- Row 1
        gui.createButton("pause", 1, buttonY, 8, 1, "Pause", function()
            sendCommand(protocol.MSG_TYPES.CMD_PAUSE, selectedTurtle)
        end, colors.orange, colors.white)
        
        gui.createButton("resume", 10, buttonY, 8, 1, "Resume", function()
            sendCommand(protocol.MSG_TYPES.CMD_RESUME, selectedTurtle)
        end, colors.lime, colors.black)
        
        gui.createButton("home", 19, buttonY, 8, 1, "Home", function()
            sendCommand(protocol.MSG_TYPES.CMD_RETURN_BASE, selectedTurtle)
        end, colors.lightBlue, colors.black)
        
        -- Row 2
        gui.createButton("shutdown", 1, buttonY + 1, 8, 1, "Shutdown", function()
            sendCommand(protocol.MSG_TYPES.CMD_SHUTDOWN, selectedTurtle)
        end, colors.red, colors.white)
        
        gui.createButton("remove", 10, buttonY + 1, 8, 1, "Remove", function()
            removeTurtle(selectedTurtle)
        end, colors.pink, colors.white)
        
        gui.createButton("refresh", 19, buttonY + 1, 8, 1, "Refresh", function()
            requestAllStatus()
        end, colors.blue, colors.white)
        
        -- Row 3
        gui.createButton("deselect", 1, buttonY + 2, 26, 1, "X Cancel Selection", function()
            selectedTurtle = nil
        end, colors.gray, colors.white)
    else
        -- Global controls (3 rows)
        -- Row 1
        gui.createButton("pauseAll", 1, buttonY, 13, 1, "Pause All", function()
            sendCommand(protocol.MSG_TYPES.CMD_PAUSE, nil)
        end, colors.orange, colors.white)
        
        gui.createButton("resumeAll", 15, buttonY, 12, 1, "Resume All", function()
            sendCommand(protocol.MSG_TYPES.CMD_RESUME, nil)
        end, colors.lime, colors.black)
        
        -- Row 2
        gui.createButton("refresh", 1, buttonY + 1, 13, 1, "Refresh", function()
            requestAllStatus()
        end, colors.blue, colors.white)
        
        gui.createButton("clear", 15, buttonY + 1, 12, 1, "Clear", function()
            cleanupOffline()
        end, colors.gray, colors.white)
        
        -- Row 3
        gui.createButton("projects", 1, buttonY + 2, 13, 1, "Projects", function()
            showProjectSelector()
        end, colors.purple, colors.white)
        
        gui.createButton("quit", 15, buttonY + 2, 12, 1, "Quit", function()
            running = false
        end, colors.red, colors.white)
    end
    
    -- Draw all buttons
    gui.drawAllButtons()
end

local function drawScreen()
    clearScreen()
    drawHeader()
    drawTurtleList()
    drawControls()
end

-- ========== NETWORK FUNCTIONS ==========

local function sendCommand(cmd, targetID)
    -- Send command without blocking UI
    protocol.sendWithRetry(cmd, {}, targetID, true)
    -- Response will be handled automatically by message processing
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

local function requestAllStatus()
    protocol.send(protocol.MSG_TYPES.CMD_STATUS_ALL, {})
    -- Don't print or sleep - just send the request
    -- The turtles will respond and update automatically
end

-- ========== PROJECT SELECTOR ==========

local function showProjectSelector()
    clearScreen()
    local w, h = term.getSize()
    
    -- Fancy header
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.setCursorPos(1, 1)
    term.clearLine()
    local title = " \7 PROJECT SELECTOR \7 "
    term.setCursorPos(math.floor((w - #title) / 2), 1)
    term.write(title)
    
    term.setBackgroundColor(colors.black)
    term.setCursorPos(1, 3)
    
    availableProjects = listProjects()
    
    if #availableProjects == 0 then
        term.setTextColor(colors.red)
        print("No projects found!")
        term.setTextColor(colors.white)
        print("")
        print("Run installer to create a project first.")
        print("")
        
        gui.createButton("back", math.floor(w/2 - 5), h - 2, 10, 1, "Go Back", nil, colors.gray, colors.white)
        gui.drawAllButtons()
        
        while true do
            local event = {os.pullEvent()}
            if event[1] == "mouse_click" then
                if gui.handleClick(event[3], event[4]) then
                    return
                end
            elseif event[1] == "key" then
                return
            end
        end
    end
    
    term.setTextColor(colors.lime)
    print("Available Projects:")
    print("")
    
    local selectableProjects = {}
    local buttonY = 6
    gui.clearButtons()
    
    for i, projName in ipairs(availableProjects) do
        local summary = projectServer.getProjectSummary(projName)   
        local isCurrent = currentProject and currentProject.name == projName
        
        if summary and summary.turtleCount > 0 then
            table.insert(selectableProjects, i)
            
            -- Create clickable project button
            local bgColor = isCurrent and colors.purple or colors.gray
            local textColor = colors.white
            
            gui.createButton("proj_" .. i, 2, buttonY, w - 4, 3, "", function()
                switchProject(projName)
            end, bgColor, textColor)
            
            -- Draw custom project card
            term.setCursorPos(3, buttonY)
            term.setBackgroundColor(bgColor)
            term.setTextColor(colors.white)
            term.write(string.rep(" ", w - 6))
            
            term.setCursorPos(3, buttonY + 1)
            local nameText = (isCurrent and "\16 " or "  ") .. summary.name
            term.write(" " .. nameText)
            term.setCursorPos(w - 15, buttonY + 1)
            term.setBackgroundColor(colors.lightGray)
            term.setTextColor(colors.black)
            term.write(" Ch:" .. summary.channel .. " ")
            term.setBackgroundColor(bgColor)
            term.write(" ")
            
            term.setCursorPos(3, buttonY + 2)
            term.setTextColor(colors.lightGray)
            term.write("   " .. summary.turtleCount .. " turtle(s)")
            term.setTextColor(colors.white)
            term.setCursorPos(3, buttonY + 3)
            term.setBackgroundColor(bgColor)
            term.write(string.rep(" ", w - 6))
            
            buttonY = buttonY + 4
        end
    end
    
    if #selectableProjects == 0 then
        term.setTextColor(colors.red)
        print("No projects have turtles assigned!")
        term.setTextColor(colors.white)
    end
    
    -- Back/Cancel button (no callback needed, click will exit loop)
    gui.createButton("cancel", 2, h - 2, 12, 1, "< Go Back", nil, colors.red, colors.white)
    
    -- Management button
    gui.createButton("manage", w - 14, h - 2, 12, 1, "Manage >>", function()
        projectManagementMenu()
    end, colors.orange, colors.white)
    
    gui.drawAllButtons()
    
    -- Handle interactions with local loop variable
    local selectorRunning = true
    while selectorRunning do
        local event = {os.pullEvent()}
        if event[1] == "mouse_click" then
            local buttonClicked = gui.handleClick(event[3], event[4])
            if buttonClicked then
                selectorRunning = false
            end
        elseif event[1] == "mouse_drag" then
            gui.updateHover(event[3], event[4])
        elseif event[1] == "key" and event[2] == keys.q then
            selectorRunning = false
        end
    end
end

-- ========== INPUT HANDLING ==========

local function handleInput()
    local event, param1 = os.pullEvent()
    
    -- Handle keyboard input (kept for power users)
    if event ~= "key" then
        return
    end
    
    local key = param1
    
    if key == keys.q then
        running = false
        
    elseif key == keys.backspace or key == keys.delete then
        -- Deselect turtle
        selectedTurtle = nil
        
    elseif key == keys.p and not selectedTurtle then
        -- Project selector (only if no turtle selected)
        showProjectSelector()
        
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
        local maxScroll = math.max(0, turtleCount - (h - 8))
        
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
            -- Shutdown command - just send it (button has confirmation built in)
            sendCommand(protocol.MSG_TYPES.CMD_SHUTDOWN, selectedTurtle)
            
        elseif key == keys.x then
            -- Remove turtle
            removeTurtle(selectedTurtle)
        end
    end
end

-- ========== MESSAGE HANDLING ==========

local function checkForMessages()
    -- Check for modem messages from turtles
    local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
    
    if channel == config.MODEM_CHANNEL and type(message) == "table" then
        local msgType = message.type
        local turtleID = message.sender
        local data = message.data or {}
        
        if msgType == protocol.MSG_TYPES.HEARTBEAT then
            -- Update turtle status from heartbeat
            if not turtles[turtleID] then
                turtles[turtleID] = {}
            end
            
            turtles[turtleID] = {
                id = turtleID,
                label = message.senderLabel or ("Turtle-" .. turtleID),
                status = data.status or "idle",
                position = data.position or {x = 0, y = 0, z = 0},
                fuel = data.fuel and data.fuel.level or 0,
                fuelPercent = data.fuel and data.fuel.percent or 0,
                inventory = data.inventory and data.inventory.freeSlots or 0,
                lastSeen = os.epoch("utc"),
                currentTask = data.currentTask or "Idle"
            }
        end
    end
end

-- ========== OFFLINE DETECTION ==========

local function checkOfflineTurtles()
    local now = os.epoch("utc")
    local offlineThreshold = 30000 -- 30 seconds in milliseconds
    
    for turtleID, turtle in pairs(turtles) do
        local timeSinceLastSeen = now - (turtle.lastSeen or 0)
        
        if timeSinceLastSeen > offlineThreshold then
            -- Mark as offline
            if turtle.status ~= "offline" then
                turtle.status = "offline"
                turtle.currentTask = "Offline - no heartbeat"
            end
        end
    end
end

local function cleanupOffline()
    local now = os.epoch("utc")
    local removeThreshold = 300000 -- 5 minutes in milliseconds
    local removed = 0
    
    -- Find and remove very old offline turtles
    local toRemove = {}
    for turtleID, turtle in pairs(turtles) do
        local timeSinceLastSeen = now - (turtle.lastSeen or 0)
        
        if turtle.status == "offline" and timeSinceLastSeen > removeThreshold then
            table.insert(toRemove, turtleID)
        end
    end
    
    -- Remove them
    for _, turtleID in ipairs(toRemove) do
        turtles[turtleID] = nil
        
        -- Also remove from project server assignments
        if currentProject then
            projectServer.removeTurtle(currentProject.name, turtleID)
        end
        
        removed = removed + 1
    end
    
    -- Don't show result - just silently clean up
    -- The UI will automatically update on next refresh
end

local function removeTurtle(turtleID)
    -- Get turtle info
    local turtle = turtles[turtleID]
    if not turtle then
        return
    end
    
    -- Remove immediately (button click is the confirmation)
    -- Remove from local table
    turtles[turtleID] = nil
    
    -- Remove from project server
    if currentProject then
        projectServer.removeTurtle(currentProject.name, turtleID)
    end
    
    -- Clear selection
    selectedTurtle = nil
    
    -- UI will update automatically on next refresh
end

-- ========== MAIN LOOP ==========

local function mainLoop()
    local lastOfflineCheck = 0
    
    while running do
        -- Wrap everything in error handler
        local success, err = pcall(function()
            -- Update display
            local now = os.clock()
            if now - lastUpdate > 2 then
                drawScreen()
                lastUpdate = now
            end
        end)
        
        if not success then
            -- Display error
            term.setBackgroundColor(colors.black)
            term.clear()
            term.setCursorPos(1, 1)
            term.setBackgroundColor(colors.red)
            term.setTextColor(colors.white)
            term.clearLine()
            print(" ERROR IN MAIN LOOP - DRAW")
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.orange)
            print("")
            print(tostring(err))
            print("")
            term.setTextColor(colors.gray)
            print("Press any key to continue...")
            os.pullEvent("key")
        end
        
        -- Check for offline turtles every 10 seconds
        success, err = pcall(function()
            local nowEpoch = os.epoch("utc")
            if nowEpoch - lastOfflineCheck > 10000 then
                checkOfflineTurtles()
                lastOfflineCheck = nowEpoch
            end
        end)
        
        if not success then
            -- Display error
            term.setBackgroundColor(colors.black)
            term.clear()
            term.setCursorPos(1, 1)
            term.setBackgroundColor(colors.red)
            term.setTextColor(colors.white)
            term.clearLine()
            print(" ERROR IN OFFLINE CHECK")
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.orange)
            print("")
            print(tostring(err))
            print("")
            term.setTextColor(colors.gray)
            print("Press any key to continue...")
            os.pullEvent("key")
        end
        
        -- Pull any event without filtering
        local event = {os.pullEvent()}
        
        -- Wrap event handling in error handler
        success, err = pcall(function()
        
        if event[1] == "key" or event[1] == "char" then
            -- Handle keyboard input
            parallel.waitForAny(
                function()
                    handleInput()
                end,
                function()
                    sleep(0.1)
                end
            )
        elseif event[1] == "mouse_click" then
            -- Handle mouse clicks directly (don't use parallel to avoid blocking)
            local x = event[3]
            local y = event[4]
            
            -- Check for GUI button clicks first
            local buttonClicked = gui.handleClick(x, y)
            if buttonClicked then
                -- Force immediate redraw after button click
                drawScreen()
                lastUpdate = os.clock()
            else
                -- Not a button, check turtle list clicks
                local w, h = term.getSize()
                local listStart = 4
                local listHeight = h - 8
                
                if y >= listStart and y < listStart + listHeight then
                    local idx = (y - listStart + 1) + scrollOffset
                    
                    local turtleList = {}
                    for id, turtle in pairs(turtles) do
                        table.insert(turtleList, {id = id, data = turtle})
                    end
                    table.sort(turtleList, function(a, b) return a.id < b.id end)
                    
                    if turtleList[idx] then
                        local clickedID = turtleList[idx].id
                        if selectedTurtle == clickedID then
                            selectedTurtle = nil
                        else
                            selectedTurtle = clickedID
                        end
                        -- Force immediate redraw after selection change
                        drawScreen()
                        lastUpdate = os.clock()
                    end
                end
            end
        elseif event[1] == "mouse_drag" then
            -- Handle hover for buttons
            local x = event[3]
            local y = event[4]
            gui.updateHover(x, y)
            -- Force immediate redraw for hover effects
            drawScreen()
            lastUpdate = os.clock()
        elseif event[1] == "modem_message" then
            -- Process the message we just received
            local side, channel, replyChannel, message, distance = event[2], event[3], event[4], event[5], event[6]
            
            if channel == config.MODEM_CHANNEL and type(message) == "table" then
                local msgType = message.type
                local turtleID = message.sender
                local data = message.data or {}
                
                if msgType == protocol.MSG_TYPES.HEARTBEAT then
                    
                    -- Update turtle status from heartbeat
                    if not turtles[turtleID] then
                        turtles[turtleID] = {}
                    end
                    
                    turtles[turtleID] = {
                        id = turtleID,
                        label = message.senderLabel or ("Turtle-" .. turtleID),
                        status = data.status or "idle",
                        position = data.position or {x = 0, y = 0, z = 0},
                        fuel = data.fuel and data.fuel.level or 0,
                        fuelPercent = data.fuel and data.fuel.percent or 0,
                        inventory = data.inventory and data.inventory.freeSlots or 0,
                        lastSeen = os.epoch("utc"),
                        currentTask = data.currentTask or "Idle"
                    }
                end
            end
        end
        end) -- End of event handling pcall
        
        if not success then
            -- Display error
            term.setBackgroundColor(colors.black)
            term.clear()
            term.setCursorPos(1, 1)
            term.setBackgroundColor(colors.red)
            term.setTextColor(colors.white)
            term.clearLine()
            print(" ERROR IN EVENT HANDLING")
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.orange)
            print("")
            print("Event type: " .. tostring(event[1]))
            print("")
            print("Error:")
            print(tostring(err))
            print("")
            term.setTextColor(colors.gray)
            print("Press any key to continue...")
            os.pullEvent("key")
        end
    end
end

-- ========== INITIALIZATION ==========

local function init()
    -- Check for modem
    if not peripheral.find("modem") then
        clearScreen()
        local w, h = term.getSize()
        
        -- Error header
        term.setBackgroundColor(colors.red)
        term.setTextColor(colors.white)
        term.setCursorPos(1, 1)
        term.clearLine()
        local title = " ! ERROR ! "
        term.setCursorPos(math.floor((w - #title) / 2), 1)
        term.write(title)
        
        term.setBackgroundColor(colors.black)
        term.setCursorPos(2, 3)
        term.setTextColor(colors.orange)
        print("No wireless modem found!")
        term.setCursorPos(2, 5)
        term.setTextColor(colors.white)
        print("Attach an Ender Modem to")
        term.setCursorPos(2, 6)
        print("use this controller.")
        return false
    end
    
    clearScreen()
    local w, h = term.getSize()
    
    -- Fancy header
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.setCursorPos(1, 1)
    term.clearLine()
    local title = " \7 BRANCH MINER CONTROL \7 "
    term.setCursorPos(math.floor((w - #title) / 2), 1)
    term.write(title)
    
    term.setBackgroundColor(colors.black)
    
    -- Initialize project server (silent)
    projectServer.init()
    
    -- Load available projects
    availableProjects = listProjects()
    
    if #availableProjects == 0 then
        term.setCursorPos(2, 3)
        term.setTextColor(colors.orange)
        print("No projects found!")
        term.setTextColor(colors.white)
        term.setCursorPos(2, 5)
        print("Create your first project:")
        
        gui.clearButtons()
        
        -- Create project button
        gui.createButton("create_first", 2, 7, w - 4, 3, "+ CREATE PROJECT", function()
            if createNewProject() then
                -- Refresh and continue
                availableProjects = listProjects()
            end
        end, colors.lime, colors.black)
        
        -- Exit button
        gui.createButton("exit_first", 2, 11, w - 4, 2, "EXIT", function()
            return false
        end, colors.red, colors.white)
        
        gui.drawAllButtons()
        
        -- Handle clicks
        local initRunning = true
        while initRunning do
            local event = {os.pullEvent()}
            if event[1] == "mouse_click" then
                gui.handleClick(event[3], event[4])
                break
            elseif event[1] == "mouse_drag" then
                gui.updateHover(event[3], event[4])
            elseif event[1] == "key" and event[2] == keys.q then
                return false
            end
        end
        
        if #availableProjects == 0 then
            return false
        end
    end
    
    -- Build project list with turtle counts
    local selectableProjects = {}
    local projectsWithTurtles = {}
    local projectsWithoutTurtles = {}
    
    for i, projName in ipairs(availableProjects) do
        local summary = projectServer.getProjectSummary(projName)
        if summary then
            if summary.turtleCount > 0 then
                table.insert(projectsWithTurtles, {
                    index = i,
                    name = projName,
                    turtles = summary.turtleCount
                })
                table.insert(selectableProjects, i)
            else
                table.insert(projectsWithoutTurtles, {
                    index = i,
                    name = projName
                })
            end
        end
    end
    
    -- Don't print lists here - they'll be shown in the GUI selection screen below
    
    if #selectableProjects == 0 then
        term.setTextColor(colors.orange)
        print("No active projects!")
        term.setTextColor(colors.white)
        print("")
        print("Pair a turtle to get started:")
        
        gui.clearButtons()
        
        -- Pair turtle button
        gui.createButton("pair", 2, h - 8, w - 4, 2, "PAIR TURTLE", nil, colors.cyan, colors.white)
        
        -- Manage projects button
        gui.createButton("manage", 2, h - 5, w - 4, 2, "MANAGE PROJECTS", function()
            projectManagementMenu()
            return false
        end, colors.orange, colors.white)
        
        -- Exit button
        gui.createButton("exit_noproj", 2, h - 2, w - 4, 1, "EXIT", nil, colors.red, colors.white)
        
        gui.drawAllButtons()
        
        -- Handle clicks
        local choice = nil
        while not choice do
            local event = {os.pullEvent()}
            if event[1] == "mouse_click" then
                local buttonId = gui.handleClick(event[3], event[4])
                if buttonId == "pair" then
                    choice = "1"
                elseif buttonId == "manage" then
                    return false
                elseif buttonId == "exit_noproj" then
                    return false
                end
            elseif event[1] == "mouse_drag" then
                gui.updateHover(event[3], event[4])
            elseif event[1] == "key" and event[2] == keys.q then
                return false
            end
        end
        
        if choice == "1" then
            -- Interactive pairing mode
            print("")
            print("PAIRING MODE")
            print("Run installer on turtle")
            print("")
            print("Listening for turtles...")
            print("(Press Q to cancel)")
            print("")
            
            -- Pairing loop
            local startTime = os.clock()
            local timeout = 60 -- 60 seconds
            local lastBroadcast = 0
            
            while os.clock() - startTime < timeout do
                -- Broadcast every second
                local now = os.clock()
                if now - lastBroadcast >= 1 then
                    projectServer.broadcastProjects()
                    lastBroadcast = now
                end
                
                -- Check for events (with 0.5s timeout)
                local event, p1, p2, p3, p4, p5 = os.pullEvent()
                
                -- Handle quit key
                if event == "char" and p1 == "q" then
                    break
                end
                
                -- Check for join requests
                if event == "modem_message" and p2 == 100 and type(p4) == "table" then
                    local channel = p2
                    local message = p4
                    if message.type == "PROJECT_JOIN_REQUEST" then
                        local turtleID = message.senderId
                        local turtleLabel = message.label or ("Turtle-" .. turtleID)
                        local projectName = message.projectName
                        
                        print("")
                        print("Turtle requesting to join:")
                        print("  ID: " .. turtleID)
                        print("  Label: " .. turtleLabel)
                        print("  Project: " .. projectName)
                        print("")
                        print("Accept? (Y/N)")
                        
                        local accept = read()
                        
                        if accept:lower() == "y" then
                            -- Approve the turtle
                            local project = loadProjectConfig(projectName)
                            if project then
                                -- Check if first turtle BEFORE adding
                                local isFirstTurtle = projectServer.getTurtleCount(projectName) == 0
                                
                                -- Add turtle using proper method
                                projectServer.addTurtle(projectName, turtleID, turtleLabel)
                                
                                -- Send approval
                                protocol.modem.transmit(100, 100, {
                                    type = "PROJECT_JOIN_RESPONSE",
                                    senderId = os.getComputerID(),
                                    targetId = turtleID,
                                    projectName = projectName,
                                    channel = project.channel,
                                    isFirstTurtle = isFirstTurtle,
                                    success = true
                                })
                                
                                print("")
                                print("Turtle paired & saved!")
                                print("Count: " .. projectServer.getTurtleCount(projectName))
                                sleep(2)
                            end
                        else
                            -- Send rejection
                            protocol.modem.transmit(100, 100, {
                                type = "NACK",
                                senderId = os.getComputerID(),
                                targetId = turtleID,
                                reason = "Rejected by user"
                            })
                            
                            print("")
                            print("Turtle rejected.")
                            sleep(1)
                        end
                        
                        print("")
                        print("Continue pairing? (Y/N)")
                        local cont = read()
                        if cont:lower() ~= "y" then
                            break
                        end
                        
                        print("")
                        print("Listening for turtles...")
                    end
                end
            end
            
            print("")
            print("Pairing mode closed.")
            sleep(2)
            return false -- Return to restart
        elseif choice == "2" then
            projectManagementMenu()
            return false -- Return to restart
        else
            return false
        end
    end
    
    -- Select project with GUI
    clearScreen()
    
    -- Redraw header
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.setCursorPos(1, 1)
    term.clearLine()
    local title = " \7 BRANCH MINER CONTROL \7 "
    term.setCursorPos(math.floor((w - #title) / 2), 1)
    term.write(title)
    
    term.setBackgroundColor(colors.black)
    term.setCursorPos(2, 3)
    term.setTextColor(colors.lime)
    print("ACTIVE PROJECTS:")
    term.setTextColor(colors.white)
    term.setCursorPos(2, 4)
    term.setTextColor(colors.gray)
    print("Click to select:")
    
    local cy = 6  -- Start buttons here
    
    gui.clearButtons()
    
    -- Create project selection buttons
    local buttonY = cy + 3
    local selectedProjectName = nil
    
    for _, proj in ipairs(projectsWithTurtles) do
        local btnColor = colors.lime
        local btnText = colors.black
        local btnLabel = string.format("%s (%d)", proj.name, proj.turtles)
        
        gui.createButton("select_proj_" .. proj.index, 2, buttonY, w - 4, 2, btnLabel, function()
            selectedProjectName = proj.name
        end, btnColor, btnText)
        
        buttonY = buttonY + 3
    end
    
    -- Menu button
    gui.createButton("menu_btn", 2, h - 2, w - 4, 1, "M = MENU", function()
        projectManagementMenu()
        return false
    end, colors.purple, colors.white)
    
    gui.drawAllButtons()
    
    -- Handle selection
    while not selectedProjectName do
        local event = {os.pullEvent()}
        if event[1] == "mouse_click" then
            local buttonId = gui.handleClick(event[3], event[4])
            if buttonId == "menu_btn" then
                return false
            end
        elseif event[1] == "mouse_drag" then
            gui.updateHover(event[3], event[4])
        elseif event[1] == "char" and event[2] == "m" then
            projectManagementMenu()
            return false
        elseif event[1] == "key" and event[2] == keys.q then
            return false
        end
    end
    
    -- Switch to selected project
    local success, err = switchProject(selectedProjectName)
    
    if not success then
        term.setCursorPos(2, h - 4)
        term.setTextColor(colors.red)
        print("ERROR: " .. (err or "Unknown"))
        sleep(2)
        return false
    end
    
    print("")
    print("Loading " .. currentProject.name .. "...")
    sleep(0.5)
    
    -- Load turtles from assignments (initially marked offline)
    local assignments = projectServer.assignments[currentProject.name] or {}
    for turtleID, info in pairs(assignments) do
        turtles[turtleID] = {
            id = turtleID,
            label = info.label or ("Turtle-" .. turtleID),
            status = "offline",
            position = {x = 0, y = 0, z = 0},
            fuel = 0,
            fuelPercent = 0,
            inventory = 0,
            lastSeen = info.lastSeen or 0,  -- Old timestamp so they show as offline
            currentTask = "Waiting for heartbeat..."
        }
    end
    
    print("Loaded " .. projectServer.getTurtleCount(currentProject.name) .. " turtles")
    sleep(0.5)
    
    -- Force modem to open the channel (just to be absolutely sure)
    if protocol.modem then
        protocol.modem.open(config.MODEM_CHANNEL)
    end
    
    -- Request initial status from all turtles
    requestAllStatus()
    
    return true
end

-- ========== MAIN ==========

local function main()
    -- Loop until successful initialization
    while true do
        if init() then
            break
        end
        -- If init() returns false (e.g., from menu), loop back
        sleep(0.5)
    end
    
    -- Run controller and project server in parallel
    local success, err = pcall(function()
        parallel.waitForAny(
            mainLoop,
            function()
                -- Project server background loop
                while running do
                    projectServer.update()
                end
            end
        )
    end)
    
    if not success then
        clearScreen()
        term.setTextColor(colorScheme.error)
        print("ERROR: " .. tostring(err))
        term.setTextColor(colorScheme.text)
    end
    
    -- Cleanup
    clearScreen()
    projectServer.stop()
    protocol.close()
    print("Controller stopped")
end

-- Run
main()

