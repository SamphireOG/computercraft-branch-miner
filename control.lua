-- Advanced Branch Miner Pocket Computer Controller
-- Wireless GUI for monitoring and controlling turtle fleet

local config = require("config")
local protocol = require("protocol")
local projectServer = require("project-server")

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
    print("------------------------")
    print(" CREATE NEW PROJECT")
    print("------------------------")
    print("")
    
    print("Project name:")
    local projectName = read()
    
    if projectName == "" then
        print("")
        print("Invalid name!")
        sleep(2)
        return false
    end
    
    -- Check if exists
    if loadProjectConfig(projectName) then
        print("")
        print("Project already exists!")
        sleep(2)
        return false
    end
    
    print("")
    print("Tunnel length [64]:")
    local length = tonumber(read()) or 64
    
    print("Layers [3]:")
    local layers = tonumber(read()) or 3
    
    print("Start Y [-59]:")
    local startY = tonumber(read()) or -59
    
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
        print("")
        print("Created!")
        print("Channel: " .. channel)
        sleep(2)
        
        -- Register with project server
        projectServer.createProject(projectName, projectConfig)
        return true
    else
        print("")
        print("Save failed!")
        sleep(2)
        return false
    end
end

local function deleteProject()
    clearScreen()
    print("------------------------")
    print(" DELETE PROJECT")
    print("------------------------")
    print("")
    
    local projects = listProjects()
    if #projects == 0 then
        print("No projects to delete!")
        sleep(2)
        return false
    end
    
    print("Projects:")
    for i, proj in ipairs(projects) do
        print(string.format(" %d. %s", i, proj))
    end
    print("")
    
    print("Delete which? (0=cancel)")
    local choice = tonumber(read())
    
    if not choice or choice == 0 then
        return false
    end
    
    if choice < 1 or choice > #projects then
        print("")
        print("Invalid choice!")
        sleep(2)
        return false
    end
    
    local projectName = projects[choice]
    
    print("")
    print("Delete '" .. projectName .. "'?")
    print("Type YES to confirm:")
    local confirm = read()
    
    if confirm ~= "YES" then
        print("")
        print("Cancelled.")
        sleep(1)
        return false
    end
    
    -- Delete project file
    local filename = getProjectFilename(projectName)
    if fs.exists(filename) then
        fs.delete(filename)
    end
    
    print("")
    print("Project deleted!")
    sleep(2)
    return true
end

local function projectManagementMenu()
    while true do
        clearScreen()
        print("------------------------")
        print(" PROJECT MANAGEMENT")
        print("------------------------")
        print("")
        print("1. Create project")
        print("2. Delete project")
        print("3. Back")
        print("")
        print("Choice:")
        
        local choice = read()
        
        if choice == "1" then
            createNewProject()
        elseif choice == "2" then
            deleteProject()
        elseif choice == "3" then
            return
        end
    end
end

-- ========== GUI STATE ==========

local turtles = {}  -- Tracked turtles {id -> data}
local selectedTurtle = nil
local scrollOffset = 0
local running = true
local lastUpdate = 0
local showProjectSelector = false

-- ========== SCREEN HELPERS (continued) ==========

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
    
    -- Show project info
    local projectName = currentProject and currentProject.name or "No Project"
    term.write("Project: " .. projectName .. " | Ch:" .. config.MODEM_CHANNEL)
    
    term.setCursorPos(1, 3)
    term.clearLine()
    
    local status = "Turtles: " .. activeCount .. " active"
    if miningCount > 0 then
        status = status .. ", " .. miningCount .. " mining"
    end
    if pausedCount > 0 then
        status = status .. ", " .. pausedCount .. " paused"
    end
    
    term.write(status)
    term.setTextColor(colorScheme.idle)
    term.write(" | Press 'P' for projects")
    term.setTextColor(colorScheme.text)
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

-- ========== PROJECT SELECTOR ==========

local function showProjectSelector()
    clearScreen()
    
    print("=== Project Selector ===")
    print("")
    
    availableProjects = listProjects()
    
    if #availableProjects == 0 then
        print("No projects found!")
        print("Run installer to create a project first.")
        print("")
        print("Press any key to continue...")
        os.pullEvent("key")
        return
    end
    
    print("Available projects:")
    print("")
    
    local selectableProjects = {}
    for i, projName in ipairs(availableProjects) do
        local summary = projectServer.getProjectSummary(projName)
        local isCurrent = currentProject and currentProject.name == projName
        local marker = isCurrent and "> " or "  "
        
        if summary then
            local status = ""
            local selectable = false
            
            if summary.turtleCount > 0 then
                status = summary.turtleCount .. " turtles"
                selectable = true
                table.insert(selectableProjects, i)
            else
                status = "No turtles (not ready)"
            end
            
            print(marker .. i .. ". " .. summary.name .. " (Ch:" .. summary.channel .. ")")
            print("      Status: " .. status)
            print("")
        end
    end
    
    if #selectableProjects == 0 then
        print("No projects have turtles assigned!")
        print("")
        print("Press any key to continue...")
        os.pullEvent("key")
        return
    end
    
    print("Enter project number (" .. table.concat(selectableProjects, ", ") .. ") or Q to cancel:")
    
    local input = read()
    if input:lower() == "q" then
        return
    end
    
    local choice = tonumber(input)
    
    -- Validate selection
    local isValid = false
    for _, validChoice in ipairs(selectableProjects) do
        if choice == validChoice then
            isValid = true
            break
        end
    end
    
    if isValid then
        local projName = availableProjects[choice]
        print("")
        print("Switching to project: " .. projName)
        
        local success, err = switchProject(projName)
        if success then
            print("Switched successfully!")
            sleep(1)
        else
            print("ERROR: " .. (err or "Unknown error"))
            print("Press any key to continue...")
            os.pullEvent("key")
        end
    else
        print("Invalid choice! Project has no turtles or doesn't exist.")
        print("Press any key to continue...")
        os.pullEvent("key")
    end
end

-- ========== INPUT HANDLING ==========

local function handleInput()
    local event, key = os.pullEvent("key")
    
    if key == keys.q then
        running = false
        
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
        clearScreen()
        print("ERROR: No wireless modem found!")
        print("")
        print("Attach an Ender Modem to use this controller.")
        return false
    end
    
    clearScreen()
    print("------------------------")
    print(" BRANCH MINER CONTROL")
    print("------------------------")
    print("")
    
    -- Initialize project server (silent)
    projectServer.init()
    
    -- Load available projects
    availableProjects = listProjects()
    
    if #availableProjects == 0 then
        print("No projects found!")
        print("")
        print("1. Create new project")
        print("2. Exit")
        print("")
        print("Choice:")
        local choice = read()
        
        if choice == "1" then
            if createNewProject() then
                -- Refresh and continue
                availableProjects = listProjects()
                if #availableProjects == 0 then
                    return false
                end
            else
                return false
            end
        else
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
    
    -- Show active projects
    if #projectsWithTurtles > 0 then
        print("ACTIVE PROJECTS:")
        for _, proj in ipairs(projectsWithTurtles) do
            print(string.format(" %d. %s (%d turtles)", proj.index, proj.name, proj.turtles))
        end
        print("")
    end
    
    -- Show inactive projects
    if #projectsWithoutTurtles > 0 then
        print("INACTIVE:")
        for _, proj in ipairs(projectsWithoutTurtles) do
            print(string.format(" %d. %s (no turtles)", proj.index, proj.name))
        end
        print("")
    end
    
    if #selectableProjects == 0 then
        print("No active projects!")
        print("")
        print("1. Wait for turtles")
        print("2. Manage projects")
        print("3. Exit")
        print("")
        print("Choice:")
        local choice = read()
        
        if choice == "2" then
            projectManagementMenu()
            return false -- Return to restart
        else
            return false
        end
    end
    
    -- Select project
    print("Select project")
    print("(or M for menu): ")
    local input = read()
    
    if input:lower() == "m" then
        projectManagementMenu()
        return false -- Return to restart
    end
    
    local choice = tonumber(input)
    
    -- Validate selection
    local isValid = false
    for _, validChoice in ipairs(selectableProjects) do
        if choice == validChoice then
            isValid = true
            break
        end
    end
    
    if not isValid then
        print("")
        print("Invalid choice!")
        print("No turtles in that")
        print("project.")
        sleep(2)
        return false
    end
    
    local projName = availableProjects[choice]
    local success, err = switchProject(projName)
    
    if not success then
        print("ERROR: " .. (err or "Unknown error"))
        return false
    end
    
    print("")
    print("Loading " .. currentProject.name .. "...")
    sleep(0.5)
    
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

