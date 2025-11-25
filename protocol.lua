-- Advanced Branch Miner Network Protocol
-- Handles all modem communication, collision avoidance, and control commands

local config = require("config")

local protocol = {}

-- ========== MESSAGE TYPES ==========

protocol.MSG_TYPES = {
    -- Turtle registration and work management
    REGISTER = "REGISTER",                    -- Turtle announces presence
    CLAIM_TUNNEL = "CLAIM_TUNNEL",           -- Request tunnel assignment
    TUNNEL_ASSIGNED = "TUNNEL_ASSIGNED",     -- Tunnel assignment response
    TUNNEL_COMPLETE = "TUNNEL_COMPLETE",     -- Tunnel finished notification
    
    -- Status and monitoring
    HEARTBEAT = "HEARTBEAT",                 -- Regular status update
    STATUS_QUERY = "STATUS_QUERY",           -- Request status from turtle(s)
    STATUS_RESPONSE = "STATUS_RESPONSE",     -- Status information reply
    
    -- Collision avoidance
    COLLISION_WARNING = "COLLISION_WARNING", -- Broadcast position before move
    POSITION_UPDATE = "POSITION_UPDATE",     -- Position changed notification
    MOVEMENT_CLEAR = "MOVEMENT_CLEAR",       -- OK to move confirmation
    
    -- Help and coordination
    HELP_REQUEST = "HELP_REQUEST",           -- Request assistance
    HELP_RESPONSE = "HELP_RESPONSE",         -- Offer help
    
    -- Control commands (from pocket computer)
    CMD_PAUSE = "CMD_PAUSE",                 -- Pause mining
    CMD_RESUME = "CMD_RESUME",               -- Resume mining
    CMD_RETURN_BASE = "CMD_RETURN_BASE",     -- Return to home
    CMD_SHUTDOWN = "CMD_SHUTDOWN",           -- Graceful shutdown
    CMD_STATUS_ALL = "CMD_STATUS_ALL",       -- Get all turtle status
    
    -- Acknowledgments
    ACK = "ACK",                             -- Generic acknowledgment
    NACK = "NACK",                           -- Negative acknowledgment
    
    -- Project Discovery Protocol (Channel 100)
    PROJECT_ANNOUNCE = "PROJECT_ANNOUNCE",           -- PC broadcasts available projects
    PROJECT_LIST_REQUEST = "PROJECT_LIST_REQUEST",   -- Turtle requests project list
    PROJECT_LIST_RESPONSE = "PROJECT_LIST_RESPONSE", -- PC sends project list with turtle counts
    PROJECT_JOIN_REQUEST = "PROJECT_JOIN_REQUEST",   -- Turtle wants to join project
    PROJECT_JOIN_RESPONSE = "PROJECT_JOIN_RESPONSE", -- PC assigns channel & approves
    PROJECT_JOIN_CONFIRM = "PROJECT_JOIN_CONFIRM",   -- Turtle confirms joining
    TURTLE_ONLINE = "TURTLE_ONLINE",                 -- Turtle announces it's online
    TURTLE_OFFLINE = "TURTLE_OFFLINE",               -- Turtle announces it's going offline
}

-- ========== MODEM MANAGEMENT ==========

protocol.modem = nil

function protocol.init()
    -- Find and open wireless modem
    protocol.modem = peripheral.find("modem", function(name, modem)
        return modem.isWireless()
    end)
    
    if not protocol.modem then
        error("No wireless modem found! Ender Modem required.")
    end
    
    -- Open communication channel
    protocol.modem.open(config.MODEM_CHANNEL)
    
    -- Silent initialization for clean UX
    return true
end

function protocol.close()
    if protocol.modem then
        protocol.modem.close(config.MODEM_CHANNEL)
    end
end

-- ========== MESSAGE CONSTRUCTION ==========

function protocol.createMessage(msgType, data)
    local msg = {
        type = msgType,
        version = config.PROTOCOL_VERSION,
        timestamp = os.epoch("utc"),
        sender = os.getComputerID(),
        senderLabel = os.getComputerLabel() or ("ID-" .. os.getComputerID()),
        data = data or {}
    }
    return msg
end

-- ========== MESSAGE SENDING ==========

function protocol.send(msgType, data, targetID)
    if not protocol.modem then
        error("Protocol not initialized. Call protocol.init() first.")
    end
    
    local msg = protocol.createMessage(msgType, data)
    
    -- DEBUG: Log transmission
    print("TX Ch:" .. config.MODEM_CHANNEL .. " Type:" .. msgType .. " To:" .. tostring(targetID or "ALL"))
    
    if targetID then
        -- Targeted message
        protocol.modem.transmit(config.MODEM_CHANNEL, config.MODEM_CHANNEL, msg)
    else
        -- Broadcast message
        protocol.modem.transmit(config.MODEM_CHANNEL, config.MODEM_CHANNEL, msg)
    end
    
    return msg
end

function protocol.sendWithRetry(msgType, data, targetID, expectAck)
    local attempts = 0
    local maxAttempts = config.MAX_MESSAGE_RETRIES
    
    while attempts < maxAttempts do
        attempts = attempts + 1
        
        local msg = protocol.send(msgType, data, targetID)
        
        if not expectAck then
            return true, msg
        end
        
        -- Wait for ACK
        local timer = os.startTimer(config.CONTROLLER_TIMEOUT)
        
        while true do
            local event, side, channel, replyChannel, message, distance = os.pullEvent()
            
            if event == "timer" and side == timer then
                -- Timeout - retry
                break
            elseif event == "modem_message" then
                if type(message) == "table" and message.type == protocol.MSG_TYPES.ACK then
                    if not targetID or message.sender == targetID then
                        os.cancelTimer(timer)
                        return true, msg, message
                    end
                end
            end
        end
    end
    
    return false, nil, "No ACK received after " .. maxAttempts .. " attempts"
end

-- ========== MESSAGE RECEIVING ==========

function protocol.receive(timeout)
    if not protocol.modem then
        error("Protocol not initialized. Call protocol.init() first.")
    end
    
    local timer = nil
    if timeout then
        timer = os.startTimer(timeout)
    end
    
    while true do
        local event, side, channel, replyChannel, message, distance = os.pullEvent()
        
        if event == "timer" and side == timer then
            return nil, "timeout"
        elseif event == "modem_message" and channel == config.MODEM_CHANNEL then
            if type(message) == "table" and message.version == config.PROTOCOL_VERSION then
                -- Valid protocol message
                if timer then
                    os.cancelTimer(timer)
                end
                return message, nil, distance
            end
        end
    end
end

function protocol.receiveNonBlocking()
    -- Check for messages without blocking
    local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
    
    if channel == config.MODEM_CHANNEL and type(message) == "table" then
        if message.version == config.PROTOCOL_VERSION then
            return message, distance
        end
    end
    
    return nil
end

-- ========== ACKNOWLEDGMENTS ==========

function protocol.sendAck(originalMsg, data)
    local ackData = data or {}
    ackData.ackFor = originalMsg.type
    ackData.ackTimestamp = originalMsg.timestamp
    
    return protocol.send(protocol.MSG_TYPES.ACK, ackData, originalMsg.sender)
end

function protocol.sendNack(originalMsg, reason)
    local nackData = {
        nackFor = originalMsg.type,
        nackTimestamp = originalMsg.timestamp,
        reason = reason
    }
    
    return protocol.send(protocol.MSG_TYPES.NACK, nackData, originalMsg.sender)
end

-- ========== COLLISION AVOIDANCE ==========

-- Broadcast current position before moving
function protocol.broadcastPosition(x, y, z, facing, intent)
    local data = {
        x = x,
        y = y,
        z = z,
        facing = facing,
        intent = intent or "stationary"  -- "moving_forward", "moving_up", etc.
    }
    
    return protocol.send(protocol.MSG_TYPES.COLLISION_WARNING, data)
end

-- Check if movement is safe (no nearby turtles in path)
function protocol.checkMovementClear(x, y, z, direction, timeout)
    timeout = timeout or config.COLLISION_TIMEOUT
    
    -- Broadcast intent
    protocol.broadcastPosition(x, y, z, direction, "intent_move_" .. direction)
    
    -- Calculate target position
    local targetX, targetY, targetZ = x, y, z
    if direction == "forward" then
        -- Would need facing direction to calculate
        -- For now, just use approximate collision detection
    elseif direction == "up" then
        targetY = targetY + 1
    elseif direction == "down" then
        targetY = targetY - 1
    end
    
    -- Wait for collision warnings from other turtles
    local timer = os.startTimer(timeout)
    local collisionDetected = false
    
    while true do
        local event, side, channel, replyChannel, message, distance = os.pullEvent()
        
        if event == "timer" and side == timer then
            -- Timeout - assume clear
            break
        elseif event == "modem_message" and channel == config.MODEM_CHANNEL then
            if type(message) == "table" and message.type == protocol.MSG_TYPES.COLLISION_WARNING then
                -- Check if turtle is too close
                if distance and distance < 5 then
                    -- Check if positions conflict
                    local otherX = message.data.x
                    local otherY = message.data.y
                    local otherZ = message.data.z
                    
                    if otherX == targetX and otherY == targetY and otherZ == targetZ then
                        collisionDetected = true
                        os.cancelTimer(timer)
                        break
                    end
                end
            end
        end
    end
    
    return not collisionDetected
end

-- ========== HEARTBEAT SYSTEM ==========

function protocol.sendHeartbeat(status, position, fuel, inventory, currentTask)
    local data = {
        status = status,  -- "mining", "returning", "idle", "paused"
        position = position,  -- {x, y, z, facing}
        fuel = fuel,  -- {level, max, percent}
        inventory = inventory,  -- {freeSlots, totalSlots}
        currentTask = currentTask,  -- {layer, tunnel, block}
        uptime = os.clock()
    }
    
    return protocol.send(protocol.MSG_TYPES.HEARTBEAT, data)
end

-- ========== CONTROL COMMANDS ==========

function protocol.sendCommand(command, targetID, data)
    local cmdData = data or {}
    cmdData.command = command
    
    return protocol.sendWithRetry(command, cmdData, targetID, true)
end

-- ========== TUNNEL MANAGEMENT ==========

function protocol.registerTurtle()
    local data = {
        computerID = os.getComputerID(),
        label = os.getComputerLabel() or ("Turtle-" .. os.getComputerID()),
        fuelLevel = turtle.getFuelLevel(),
        fuelLimit = turtle.getFuelLimit()
    }
    
    return protocol.send(protocol.MSG_TYPES.REGISTER, data)
end

function protocol.claimTunnel()
    local data = {
        requesting = true
    }
    
    return protocol.sendWithRetry(protocol.MSG_TYPES.CLAIM_TUNNEL, data, nil, true)
end

function protocol.reportTunnelComplete(layer, tunnel, blocksMined, oresFound)
    local data = {
        layer = layer,
        tunnel = tunnel,
        blocksMined = blocksMined,
        oresFound = oresFound,
        completedAt = os.epoch("utc")
    }
    
    return protocol.send(protocol.MSG_TYPES.TUNNEL_COMPLETE, data)
end

-- ========== HELP SYSTEM ==========

function protocol.requestHelp(reason, position)
    local data = {
        reason = reason,
        position = position,
        fuel = turtle.getFuelLevel(),
        urgent = true
    }
    
    return protocol.send(protocol.MSG_TYPES.HELP_REQUEST, data)
end

-- ========== MESSAGE FILTERING ==========

function protocol.filterMessages(messageTypes, timeout)
    -- Wait for specific message type(s)
    if type(messageTypes) == "string" then
        messageTypes = {messageTypes}
    end
    
    local timer = nil
    if timeout then
        timer = os.startTimer(timeout)
    end
    
    while true do
        local event, side, channel, replyChannel, message, distance = os.pullEvent()
        
        if event == "timer" and side == timer then
            return nil, "timeout"
        elseif event == "modem_message" and channel == config.MODEM_CHANNEL then
            if type(message) == "table" and message.version == config.PROTOCOL_VERSION then
                for _, msgType in ipairs(messageTypes) do
                    if message.type == msgType then
                        if timer then
                            os.cancelTimer(timer)
                        end
                        return message, nil, distance
                    end
                end
            end
        end
    end
end

return protocol

