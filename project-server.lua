-- Project Discovery Server (Pocket Computer)
-- Manages project creation, turtle assignments, and discovery protocol

local protocol = require("protocol")

local server = {}

-- Discovery channel (all devices listen here)
local DISCOVERY_CHANNEL = 100

-- Server state
server.projects = {}  -- {projectName -> projectConfig}
server.assignments = {}  -- {projectName -> {turtleID -> {label, lastSeen}}}
server.isRunning = false

-- ========== PROJECT MANAGEMENT ==========

local function getProjectFilename(projectName)
    return "project_" .. projectName .. ".cfg"
end

local function getAssignmentsFilename()
    return "project_assignments.cfg"
end

function server.loadProjects()
    server.projects = {}
    
    for _, file in ipairs(fs.list("/")) do
        if file:match("^project_(.+)%.cfg$") then
            local name = file:match("^project_(.+)%.cfg$")
            local filename = getProjectFilename(name)
            
            if fs.exists(filename) then
                local f = fs.open(filename, "r")
                if f then
                    local content = f.readAll()
                    f.close()
                    
                    local config = textutils.unserialize(content)
                    if config then
                        server.projects[name] = config
                    end
                end
            end
        end
    end
end

function server.loadAssignments()
    local filename = getAssignmentsFilename()
    
    if not fs.exists(filename) then
        server.assignments = {}
        return
    end
    
    local file = fs.open(filename, "r")
    if not file then
        server.assignments = {}
        return
    end
    
    local content = file.readAll()
    file.close()
    
    server.assignments = textutils.unserialize(content) or {}
end

function server.saveAssignments()
    local filename = getAssignmentsFilename()
    local file = fs.open(filename, "w")
    
    if file then
        file.write(textutils.serialize(server.assignments))
        file.close()
        return true
    end
    
    return false
end

function server.createProject(projectName, projectConfig)
    -- Register a new project with the server
    server.projects[projectName] = projectConfig
    
    -- Initialize assignments table for this project
    if not server.assignments[projectName] then
        server.assignments[projectName] = {}
    end
    
    return true
end

function server.getTurtleCount(projectName)
    if not server.assignments[projectName] then
        return 0
    end
    
    local count = 0
    for _ in pairs(server.assignments[projectName]) do
        count = count + 1
    end
    
    return count
end

function server.getProjectSummary(projectName)
    local project = server.projects[projectName]
    if not project then
        return nil
    end
    
    return {
        name = projectName,
        channel = project.channel or 42,
        tunnelLength = project.tunnelLength,
        numLayers = project.numLayers,
        startY = project.startY,
        turtleCount = server.getTurtleCount(projectName),
        hasHomeBase = project.homeBase ~= nil
    }
end

-- ========== DISCOVERY PROTOCOL ==========

function server.broadcastProjects()
    -- Build project list with turtle counts
    local projectList = {}
    
    for name, _ in pairs(server.projects) do
        table.insert(projectList, server.getProjectSummary(name))
    end
    
    -- Broadcast on discovery channel
    if protocol.modem then
        protocol.modem.transmit(DISCOVERY_CHANNEL, DISCOVERY_CHANNEL, {
            type = protocol.MSG_TYPES.PROJECT_ANNOUNCE,
            senderId = os.getComputerID(),
            timestamp = os.epoch("utc"),
            projects = projectList
        })
    end
end

function server.handleJoinRequest(message)
    local turtleID = message.senderId
    local projectName = message.projectName
    local turtleLabel = message.label or ("Turtle-" .. turtleID)
    
    -- Validate project exists
    local project = server.projects[projectName]
    if not project then
        -- Send NACK
        protocol.modem.transmit(DISCOVERY_CHANNEL, DISCOVERY_CHANNEL, {
            type = protocol.MSG_TYPES.NACK,
            senderId = os.getComputerID(),
            targetId = turtleID,
            reason = "Project not found"
        })
        return
    end
    
    -- Initialize assignments for project if needed
    if not server.assignments[projectName] then
        server.assignments[projectName] = {}
    end
    
    -- Check if this is the first turtle
    local isFirstTurtle = server.getTurtleCount(projectName) == 0
    
    -- Add turtle to project
    server.assignments[projectName][turtleID] = {
        label = turtleLabel,
        lastSeen = os.epoch("utc"),
        joinedAt = os.epoch("utc")
    }
    
    server.saveAssignments()
    
    -- Send response
    protocol.modem.transmit(DISCOVERY_CHANNEL, DISCOVERY_CHANNEL, {
        type = protocol.MSG_TYPES.PROJECT_JOIN_RESPONSE,
        senderId = os.getComputerID(),
        targetId = turtleID,
        projectName = projectName,
        channel = project.channel,
        isFirstTurtle = isFirstTurtle,
        success = true
    })
    
    -- Silent operation for clean UX
    -- (Turtle join logged internally)
end

function server.handleMessage(message)
    if not message or not message.type then
        return
    end
    
    if message.type == protocol.MSG_TYPES.PROJECT_LIST_REQUEST then
        -- Send current project list
        server.broadcastProjects()
        
    elseif message.type == protocol.MSG_TYPES.PROJECT_JOIN_REQUEST then
        -- Handle turtle joining project
        server.handleJoinRequest(message)
        
    elseif message.type == protocol.MSG_TYPES.TURTLE_ONLINE then
        -- Update last seen time
        local projectName = message.projectName
        local turtleID = message.senderId
        
        if server.assignments[projectName] and server.assignments[projectName][turtleID] then
            server.assignments[projectName][turtleID].lastSeen = os.epoch("utc")
        end
    end
end

-- ========== SERVER LOOP ==========

function server.init()
    -- Load projects and assignments
    server.loadProjects()
    server.loadAssignments()
    
    -- Open discovery channel
    if not protocol.modem then
        protocol.init()
    end
    
    if protocol.modem then
        protocol.modem.open(DISCOVERY_CHANNEL)
        -- Silent listening for clean UX
    end
    
    server.isRunning = true
end

function server.stop()
    server.isRunning = false
    
    if protocol.modem then
        protocol.modem.close(DISCOVERY_CHANNEL)
    end
end

function server.update()
    -- Check for messages on discovery channel
    local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
    
    if channel == DISCOVERY_CHANNEL and type(message) == "table" then
        server.handleMessage(message)
    end
end

-- Background server that runs alongside controller
-- Only handles incoming messages (no auto-broadcast)
-- Use manual pairing via "Pair turtle" button
function server.runBackground()
    server.init()
    
    while server.isRunning do
        -- Handle incoming messages (non-blocking)
        local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
        
        if channel == DISCOVERY_CHANNEL and type(message) == "table" then
            server.handleMessage(message)
        end
        
        sleep(0.1)
    end
end

return server

