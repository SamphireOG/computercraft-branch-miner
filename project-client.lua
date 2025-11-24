-- Project Discovery Client (Turtle)
-- Discovers and joins projects via discovery protocol

local protocol = require("protocol")

local client = {}

-- Discovery channel (all devices listen here)
local DISCOVERY_CHANNEL = 100

-- Client state
client.availableProjects = {}
client.assignment = nil  -- {projectName, channel, assignedAt}

-- ========== ASSIGNMENT PERSISTENCE ==========

local function getAssignmentFilename()
    return "turtle_assignment.cfg"
end

function client.saveAssignment(projectName, channel)
    local assignment = {
        projectName = projectName,
        channel = channel,
        assignedAt = os.epoch("utc"),
        turtleID = os.getComputerID(),
        label = os.getComputerLabel()
    }
    
    local file = fs.open(getAssignmentFilename(), "w")
    if file then
        file.write(textutils.serialize(assignment))
        file.close()
        
        client.assignment = assignment
        return true
    end
    
    return false
end

function client.loadAssignment()
    local filename = getAssignmentFilename()
    
    if not fs.exists(filename) then
        return nil
    end
    
    local file = fs.open(filename, "r")
    if not file then
        return nil
    end
    
    local content = file.readAll()
    file.close()
    
    client.assignment = textutils.unserialize(content)
    return client.assignment
end

function client.clearAssignment()
    local filename = getAssignmentFilename()
    if fs.exists(filename) then
        fs.delete(filename)
    end
    
    client.assignment = nil
end

-- ========== DISCOVERY PROTOCOL ==========

function client.requestProjectList()
    if not protocol.modem then
        return false
    end
    
    -- Request project list
    protocol.modem.transmit(DISCOVERY_CHANNEL, DISCOVERY_CHANNEL, {
        type = protocol.MSG_TYPES.PROJECT_LIST_REQUEST,
        senderId = os.getComputerID(),
        timestamp = os.epoch("utc")
    })
    
    return true
end

function client.waitForProjects(timeout)
    timeout = timeout or 5
    client.availableProjects = {}
    
    local timer = os.startTimer(timeout)
    
    while true do
        local event, p1, p2, p3, p4, p5 = os.pullEvent()
        
        if event == "timer" and p1 == timer then
            break
            
        elseif event == "modem_message" then
            local channel = p2
            local message = p4
            
            if channel == DISCOVERY_CHANNEL and type(message) == "table" then
                if message.type == protocol.MSG_TYPES.PROJECT_ANNOUNCE or 
                   message.type == protocol.MSG_TYPES.PROJECT_LIST_RESPONSE then
                    
                    if message.projects then
                        client.availableProjects = message.projects
                        os.cancelTimer(timer)
                        return true
                    end
                end
            end
        end
    end
    
    return #client.availableProjects > 0
end

function client.discoverProjects(timeout)
    timeout = timeout or 10
    
    -- Request projects
    client.requestProjectList()
    
    print("Discovering projects...")
    
    -- Wait for response
    local success = client.waitForProjects(timeout)
    
    if success then
        print("Found " .. #client.availableProjects .. " projects")
        return client.availableProjects
    else
        print("No projects found")
        return {}
    end
end

function client.joinProject(projectName)
    if not protocol.modem then
        return false, "No modem"
    end
    
    -- Send join request
    protocol.modem.transmit(DISCOVERY_CHANNEL, DISCOVERY_CHANNEL, {
        type = protocol.MSG_TYPES.PROJECT_JOIN_REQUEST,
        senderId = os.getComputerID(),
        label = os.getComputerLabel(),
        projectName = projectName,
        timestamp = os.epoch("utc")
    })
    
    print("Requesting to join " .. projectName .. "...")
    
    -- Wait for response
    local timer = os.startTimer(10)
    
    while true do
        local event, p1, p2, p3, p4, p5 = os.pullEvent()
        
        if event == "timer" and p1 == timer then
            return false, "Timeout waiting for response"
            
        elseif event == "modem_message" then
            local channel = p2
            local message = p4
            
            if channel == DISCOVERY_CHANNEL and type(message) == "table" then
                if message.type == protocol.MSG_TYPES.PROJECT_JOIN_RESPONSE then
                    if message.targetId == os.getComputerID() then
                        os.cancelTimer(timer)
                        
                        if message.success then
                            -- Save assignment
                            client.saveAssignment(message.projectName, message.channel)
                            
                            -- Send confirmation
                            protocol.modem.transmit(DISCOVERY_CHANNEL, DISCOVERY_CHANNEL, {
                                type = protocol.MSG_TYPES.PROJECT_JOIN_CONFIRM,
                                senderId = os.getComputerID(),
                                projectName = message.projectName,
                                channel = message.channel,
                                timestamp = os.epoch("utc")
                            })
                            
                            return true, message
                        else
                            return false, message.reason or "Join rejected"
                        end
                    end
                    
                elseif message.type == protocol.MSG_TYPES.NACK then
                    if message.targetId == os.getComputerID() then
                        os.cancelTimer(timer)
                        return false, message.reason or "Request denied"
                    end
                end
            end
        end
    end
end

function client.announceOnline()
    if not client.assignment or not protocol.modem then
        return
    end
    
    protocol.modem.transmit(DISCOVERY_CHANNEL, DISCOVERY_CHANNEL, {
        type = protocol.MSG_TYPES.TURTLE_ONLINE,
        senderId = os.getComputerID(),
        projectName = client.assignment.projectName,
        channel = client.assignment.channel,
        timestamp = os.epoch("utc")
    })
end

function client.announceOffline()
    if not client.assignment or not protocol.modem then
        return
    end
    
    protocol.modem.transmit(DISCOVERY_CHANNEL, DISCOVERY_CHANNEL, {
        type = protocol.MSG_TYPES.TURTLE_OFFLINE,
        senderId = os.getComputerID(),
        projectName = client.assignment.projectName,
        timestamp = os.epoch("utc")
    })
end

-- ========== INITIALIZATION ==========

function client.init()
    -- Initialize protocol
    if not protocol.modem then
        protocol.init()
    end
    
    if protocol.modem then
        -- Open discovery channel
        protocol.modem.open(DISCOVERY_CHANNEL)
    end
    
    -- Load existing assignment
    client.loadAssignment()
    
    return client.assignment ~= nil
end

function client.reconnect()
    if not client.assignment then
        return false, "No assignment to reconnect to"
    end
    
    print("Reconnecting to project: " .. client.assignment.projectName)
    print("Channel: " .. client.assignment.channel)
    
    -- Switch to project channel
    if protocol.modem then
        protocol.modem.close(DISCOVERY_CHANNEL)
        protocol.modem.open(client.assignment.channel)
    end
    
    -- Announce we're online
    client.announceOnline()
    
    return true
end

return client

