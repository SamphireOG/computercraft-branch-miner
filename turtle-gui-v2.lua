-- Advanced Turtle GUI - Dynamic & Responsive
-- No terminal bleeding through - full screen control

local gui = require("gui-advanced")
local protocol = require("protocol")
local projectClient = require("project-client")
local config = require("config")

local turtleGUI = {}

-- ========== STATE ==========

local currentView = "main_menu"
local viewData = {}
local refreshTimer = nil

-- ========== SCREEN LAYOUTS ==========

local function drawHeader(title, subtitle)
    -- Header panel
    gui.drawBox(1, 1, gui.width, 3, gui.theme.primary)
    gui.drawText(math.floor(gui.width / 2), 2, title, gui.theme.text, gui.theme.primary, "center")
    
    if subtitle then
        gui.drawText(gui.width - #subtitle - 1, 2, subtitle, gui.theme.textDim, gui.theme.primary, "right")
    end
end

local function drawFooter(text)
    gui.drawBox(1, gui.height, gui.width, 1, gui.theme.surface)
    gui.drawText(2, gui.height, text, gui.theme.textDim, gui.theme.surface, "left")
end

local function drawStatusBar()
    local assignment = projectClient.loadAssignment()
    local status = assignment and ("Project: " .. assignment.projectName) or "No Project"
    
    gui.drawBox(1, 4, gui.width, 1, gui.theme.surface)
    gui.drawText(2, 4, status, gui.theme.text, gui.theme.surface, "left")
    
    -- Draw status indicator
    local statusX = gui.width - 10
    local statusColor = assignment and gui.theme.success or gui.theme.danger
    local statusText = assignment and " ONLINE " or " OFFLINE "
    gui.drawText(statusX, 4, statusText, gui.theme.text, statusColor, "left")
end

-- ========== MAIN MENU VIEW ==========

local function showMainMenu()
    gui.clearScreen()
    gui.clearWidgets()
    
    local assignment = projectClient.loadAssignment()
    
    drawHeader("TURTLE CONTROL", "v2.0")
    drawStatusBar()
    drawFooter("Use mouse to interact | Press Q to quit")
    
    -- Calculate button positions (centered)
    local buttonWidth = 36
    local buttonHeight = 3
    local buttonX = math.floor((gui.width - buttonWidth) / 2)
    local startY = 7
    local spacing = 4
    
    -- Dynamic buttons based on project status
    if assignment then
        -- Start Mining button
        gui.createButton({
            id = "start_mining",
            x = buttonX,
            y = startY,
            width = buttonWidth,
            height = buttonHeight,
            text = "Start Mining",
            icon = ">",
            color = gui.theme.success,
            hoverColor = colors.green,
            callback = function()
                return "start_mining"
            end
        })
        
        -- Project Info button
        gui.createButton({
            id = "project_info",
            x = buttonX,
            y = startY + spacing,
            width = buttonWidth,
            height = buttonHeight,
            text = "Project Info",
            icon = "i",
            color = gui.theme.info,
            hoverColor = colors.lightBlue,
            callback = function()
                currentView = "project_info"
                return "refresh"
            end
        })
        
        -- Leave Project button
        gui.createButton({
            id = "leave_project",
            x = buttonX,
            y = startY + spacing * 2,
            width = buttonWidth,
            height = buttonHeight,
            text = "Leave Project",
            icon = "x",
            color = gui.theme.warning,
            hoverColor = colors.yellow,
            callback = function()
                currentView = "leave_confirm"
                return "refresh"
            end
        })
    else
        -- Join Project button
        gui.createButton({
            id = "join_project",
            x = buttonX,
            y = startY + spacing,
            width = buttonWidth,
            height = buttonHeight,
            text = "Join Project",
            icon = "+",
            color = gui.theme.primary,
            hoverColor = gui.theme.secondary,
            callback = function()
                currentView = "project_list"
                viewData = {}
                return "refresh"
            end
        })
    end
    
    -- Exit button (always shown)
    local exitY = assignment and (startY + spacing * 3) or (startY + spacing * 2)
    gui.createButton({
        id = "exit",
        x = buttonX,
        y = exitY,
        width = buttonWidth,
        height = buttonHeight,
        text = "Exit",
        icon = "!",
        color = gui.theme.danger,
        hoverColor = colors.red,
        callback = function()
            return "exit"
        end
    })
    
    gui.renderAllWidgets()
    gui.render()
end

-- ========== PROJECT LIST VIEW ==========

local function showProjectList()
    gui.clearScreen()
    gui.clearWidgets()
    
    drawHeader("AVAILABLE PROJECTS", "Searching...")
    drawFooter("Select project | ESC to go back")
    
    -- Loading panel
    local panelX = math.floor((gui.width - 40) / 2)
    local panelY = 8
    
    gui.createPanel({
        id = "loading_panel",
        x = panelX,
        y = panelY,
        width = 40,
        height = 8,
        color = gui.theme.surface,
        borderColor = gui.theme.primary,
        borderStyle = "single"
    })
    
    gui.createLabel({
        id = "loading_text",
        x = math.floor(gui.width / 2),
        y = panelY + 3,
        text = "Searching for projects...",
        color = gui.theme.text,
        align = "center"
    })
    
    gui.createLabel({
        id = "loading_sub",
        x = math.floor(gui.width / 2),
        y = panelY + 4,
        text = "Make sure controller is online",
        color = gui.theme.textDim,
        align = "center"
    })
    
    gui.renderAllWidgets()
    gui.render()
    
    -- Discover projects
    projectClient.init()
    local projects = projectClient.discoverProjects(10)
    
    -- Refresh screen with results
    gui.clearScreen()
    gui.clearWidgets()
    
    if #projects == 0 then
        drawHeader("NO PROJECTS FOUND", "Error")
        drawFooter("Press any key to go back")
        
        local errorPanel = gui.createPanel({
            x = panelX,
            y = panelY,
            width = 40,
            height = 10,
            color = gui.theme.surface,
            borderColor = gui.theme.danger,
            borderStyle = "single",
            title = "Error"
        })
        
        gui.createLabel({
            x = panelX + 2,
            y = panelY + 2,
            text = "No projects found!",
            color = gui.theme.danger
        })
        
        gui.createLabel({
            x = panelX + 2,
            y = panelY + 4,
            text = "Make sure:",
            color = gui.theme.text
        })
        
        gui.createLabel({
            x = panelX + 2,
            y = panelY + 5,
            text = "- Controller is running",
            color = gui.theme.textDim
        })
        
        gui.createLabel({
            x = panelX + 2,
            y = panelY + 6,
            text = "- Projects have been created",
            color = gui.theme.textDim
        })
        
        gui.createLabel({
            x = panelX + 2,
            y = panelY + 7,
            text = "- You're in wireless range",
            color = gui.theme.textDim
        })
        
        gui.renderAllWidgets()
        gui.render()
        
        viewData.waitForKey = true
        return
    end
    
    -- Show projects list
    drawHeader("SELECT PROJECT", #projects .. " found")
    drawFooter("Click to select | ESC to cancel")
    
    local listX = math.floor((gui.width - 44) / 2)
    local listY = 6
    
    -- Create list items with formatted text
    local listItems = {}
    for i, proj in ipairs(projects) do
        local text = proj.name .. " (Ch:" .. proj.channel .. " T:" .. proj.turtleCount .. " L:" .. proj.tunnelLength .. ")"
        table.insert(listItems, text)
    end
    
    gui.createList({
        id = "project_list",
        x = listX,
        y = listY,
        width = 44,
        height = gui.height - listY - 2,
        items = listItems,
        color = gui.theme.surface,
        selectedColor = gui.theme.primary,
        onSelect = function(widget, item, index)
            viewData.selectedProject = projects[index]
            currentView = "join_project"
            return "refresh"
        end
    })
    
    -- Back button
    gui.createButton({
        id = "back",
        x = listX,
        y = gui.height - 1,
        width = 20,
        height = 1,
        text = "< Back",
        color = gui.theme.surface,
        callback = function()
            currentView = "main_menu"
            return "refresh"
        end
    })
    
    viewData.projects = projects
    gui.renderAllWidgets()
    gui.render()
end

-- ========== JOIN PROJECT VIEW ==========

local function showJoinProject()
    gui.clearScreen()
    gui.clearWidgets()
    
    local project = viewData.selectedProject
    if not project then
        currentView = "main_menu"
        return "refresh"
    end
    
    drawHeader("JOIN PROJECT", project.name)
    drawFooter("Enter name or press Enter for auto")
    
    local panelX = math.floor((gui.width - 40) / 2)
    local panelY = 8
    
    gui.createPanel({
        id = "join_panel",
        x = panelX,
        y = panelY,
        width = 40,
        height = 12,
        color = gui.theme.surface,
        borderColor = gui.theme.primary,
        borderStyle = "rounded",
        title = "Turtle Name"
    })
    
    gui.createLabel({
        x = panelX + 2,
        y = panelY + 2,
        text = "Joining: " .. project.name,
        color = gui.theme.success
    })
    
    gui.createLabel({
        x = panelX + 2,
        y = panelY + 3,
        text = "Channel: " .. project.channel,
        color = gui.theme.textDim
    })
    
    gui.createLabel({
        x = panelX + 2,
        y = panelY + 5,
        text = "Enter turtle name:",
        color = gui.theme.text
    })
    
    local input = gui.createTextInput({
        id = "name_input",
        x = panelX + 2,
        y = panelY + 7,
        width = 36,
        height = 3,
        placeholder = "Miner-" .. os.getComputerID(),
        maxLength = 30
    })
    input.focused = true
    
    gui.createButton({
        id = "join_btn",
        x = panelX + 2,
        y = panelY + 11,
        width = 18,
        height = 1,
        text = "Join",
        color = gui.theme.success,
        callback = function()
            local nameWidget = gui.getWidget("name_input")
            local turtleName = nameWidget.text
            if turtleName == "" then
                turtleName = "Miner-" .. os.getComputerID()
            end
            
            os.setComputerLabel(turtleName)
            
            -- Show joining status
            currentView = "joining"
            viewData.turtleName = turtleName
            return "refresh"
        end
    })
    
    gui.createButton({
        id = "cancel_btn",
        x = panelX + 20,
        y = panelY + 11,
        width = 18,
        height = 1,
        text = "Cancel",
        color = gui.theme.danger,
        callback = function()
            currentView = "project_list"
            return "refresh"
        end
    })
    
    gui.renderAllWidgets()
    gui.render()
end

-- ========== JOINING PROJECT VIEW ==========

local function showJoining()
    gui.clearScreen()
    gui.clearWidgets()
    
    drawHeader("JOINING PROJECT", "Please wait...")
    
    local panelX = math.floor((gui.width - 40) / 2)
    local panelY = 10
    
    gui.createPanel({
        x = panelX,
        y = panelY,
        width = 40,
        height = 6,
        color = gui.theme.surface,
        borderColor = gui.theme.primary,
        borderStyle = "single"
    })
    
    gui.createLabel({
        x = math.floor(gui.width / 2),
        y = panelY + 2,
        text = "Connecting to project...",
        color = gui.theme.text,
        align = "center"
    })
    
    gui.drawProgressBar(panelX + 4, panelY + 4, 32, 50, gui.theme.primary, gui.theme.surface, false)
    
    gui.renderAllWidgets()
    gui.render()
    
    -- Actually join
    local success, result = projectClient.joinProject(viewData.selectedProject.name)
    
    if success then
        viewData.joinResult = result
        currentView = "join_success"
    else
        viewData.joinError = result or "Unknown error"
        currentView = "join_error"
    end
    
    return "refresh"
end

-- ========== JOIN SUCCESS/ERROR VIEWS ==========

local function showJoinSuccess()
    gui.clearScreen()
    gui.clearWidgets()
    
    drawHeader("SUCCESS!", "Joined Project")
    drawFooter("Press any key to continue")
    
    local panelX = math.floor((gui.width - 40) / 2)
    local panelY = 8
    
    gui.createPanel({
        x = panelX,
        y = panelY,
        width = 40,
        height = 10,
        color = gui.theme.surface,
        borderColor = gui.theme.success,
        borderStyle = "rounded"
    })
    
    gui.createLabel({
        x = math.floor(gui.width / 2),
        y = panelY + 2,
        text = "Successfully joined!",
        color = gui.theme.success,
        align = "center"
    })
    
    local result = viewData.joinResult
    gui.createLabel({
        x = panelX + 2,
        y = panelY + 4,
        text = "Project: " .. (result.projectName or "Unknown"),
        color = gui.theme.text
    })
    
    gui.createLabel({
        x = panelX + 2,
        y = panelY + 5,
        text = "Channel: " .. (result.channel or 0),
        color = gui.theme.textDim
    })
    
    if result.isFirstTurtle then
        gui.createLabel({
            x = panelX + 2,
            y = panelY + 7,
            text = "*** FIRST TURTLE ***",
            color = gui.theme.warning
        })
        
        gui.createLabel({
            x = panelX + 2,
            y = panelY + 8,
            text = "You will set the home base!",
            color = gui.theme.text
        })
    end
    
    gui.renderAllWidgets()
    gui.render()
    
    viewData.waitForKey = true
end

local function showJoinError()
    gui.clearScreen()
    gui.clearWidgets()
    
    drawHeader("ERROR", "Failed to Join")
    drawFooter("Press any key to go back")
    
    local panelX = math.floor((gui.width - 40) / 2)
    local panelY = 10
    
    gui.createPanel({
        x = panelX,
        y = panelY,
        width = 40,
        height = 6,
        color = gui.theme.surface,
        borderColor = gui.theme.danger,
        borderStyle = "single",
        title = "Error"
    })
    
    gui.createLabel({
        x = panelX + 2,
        y = panelY + 2,
        text = "Failed to join project!",
        color = gui.theme.danger
    })
    
    gui.createLabel({
        x = panelX + 2,
        y = panelY + 4,
        text = viewData.joinError or "Unknown error",
        color = gui.theme.textDim
    })
    
    gui.renderAllWidgets()
    gui.render()
    
    viewData.waitForKey = true
end

-- ========== PROJECT INFO VIEW ==========

local function showProjectInfo()
    gui.clearScreen()
    gui.clearWidgets()
    
    local assignment = projectClient.loadAssignment()
    
    drawHeader("PROJECT INFO", assignment and assignment.projectName or "None")
    drawFooter("Press any key to go back")
    
    local panelX = math.floor((gui.width - 40) / 2)
    local panelY = 7
    
    gui.createPanel({
        x = panelX,
        y = panelY,
        width = 40,
        height = 12,
        color = gui.theme.surface,
        borderColor = gui.theme.info,
        borderStyle = "rounded",
        title = "Details"
    })
    
    if assignment then
        local y = panelY + 2
        
        gui.createLabel({x = panelX + 2, y = y, text = "Project: " .. assignment.projectName, color = gui.theme.success})
        y = y + 2
        
        gui.createLabel({x = panelX + 2, y = y, text = "Channel: " .. assignment.channel, color = gui.theme.text})
        y = y + 1
        
        gui.createLabel({x = panelX + 2, y = y, text = "Turtle ID: " .. assignment.turtleID, color = gui.theme.text})
        y = y + 1
        
        gui.createLabel({x = panelX + 2, y = y, text = "Label: " .. (assignment.label or "None"), color = gui.theme.text})
        y = y + 1
        
        if assignment.startY then
            gui.createLabel({x = panelX + 2, y = y, text = "Y-Level: " .. assignment.startY, color = gui.theme.text})
            y = y + 1
        end
        
        if assignment.assignedAt then
            local days = math.floor(assignment.assignedAt / 86400000)
            gui.createLabel({x = panelX + 2, y = y, text = "Joined: " .. days .. " days ago", color = gui.theme.textDim})
        end
    else
        gui.createLabel({
            x = math.floor(gui.width / 2),
            y = panelY + 5,
            text = "No project assigned",
            color = gui.theme.danger,
            align = "center"
        })
    end
    
    gui.renderAllWidgets()
    gui.render()
    
    viewData.waitForKey = true
end

-- ========== LEAVE CONFIRM VIEW ==========

local function showLeaveConfirm()
    gui.clearScreen()
    gui.clearWidgets()
    
    local assignment = projectClient.loadAssignment()
    
    drawHeader("LEAVE PROJECT", "Confirmation Required")
    drawFooter("Are you sure?")
    
    local panelX = math.floor((gui.width - 40) / 2)
    local panelY = 9
    
    gui.createPanel({
        x = panelX,
        y = panelY,
        width = 40,
        height = 9,
        color = gui.theme.surface,
        borderColor = gui.theme.warning,
        borderStyle = "rounded",
        title = "Warning"
    })
    
    gui.createLabel({
        x = panelX + 2,
        y = panelY + 2,
        text = "Leave: " .. (assignment and assignment.projectName or "Unknown"),
        color = gui.theme.warning
    })
    
    gui.createLabel({
        x = panelX + 2,
        y = panelY + 4,
        text = "Are you sure you want to leave?",
        color = gui.theme.text
    })
    
    gui.createLabel({
        x = panelX + 2,
        y = panelY + 5,
        text = "You can rejoin later.",
        color = gui.theme.textDim
    })
    
    gui.createButton({
        id = "confirm_leave",
        x = panelX + 2,
        y = panelY + 7,
        width = 18,
        height = 1,
        text = "Yes, Leave",
        color = gui.theme.danger,
        callback = function()
            projectClient.announceOffline()
            projectClient.clearAssignment()
            currentView = "leave_success"
            return "refresh"
        end
    })
    
    gui.createButton({
        id = "cancel_leave",
        x = panelX + 20,
        y = panelY + 7,
        width = 18,
        height = 1,
        text = "Cancel",
        color = gui.theme.success,
        callback = function()
            currentView = "main_menu"
            return "refresh"
        end
    })
    
    gui.renderAllWidgets()
    gui.render()
end

-- ========== LEAVE SUCCESS VIEW ==========

local function showLeaveSuccess()
    gui.clearScreen()
    gui.clearWidgets()
    
    drawHeader("LEFT PROJECT", "Success")
    drawFooter("Press any key to continue")
    
    local panelX = math.floor((gui.width - 40) / 2)
    local panelY = 11
    
    gui.createPanel({
        x = panelX,
        y = panelY,
        width = 40,
        height = 6,
        color = gui.theme.surface,
        borderColor = gui.theme.success,
        borderStyle = "single"
    })
    
    gui.createLabel({
        x = math.floor(gui.width / 2),
        y = panelY + 2,
        text = "Successfully left project!",
        color = gui.theme.success,
        align = "center"
    })
    
    gui.createLabel({
        x = math.floor(gui.width / 2),
        y = panelY + 4,
        text = "You can join another project now.",
        color = gui.theme.textDim,
        align = "center"
    })
    
    gui.renderAllWidgets()
    gui.render()
    
    viewData.waitForKey = true
end

-- ========== MAIN GUI LOOP ==========

function turtleGUI.run()
    gui.initScreen()
    currentView = "main_menu"
    viewData = {}
    
    while true do
        -- Render current view
        if currentView == "main_menu" then
            showMainMenu()
        elseif currentView == "project_list" then
            showProjectList()
        elseif currentView == "join_project" then
            showJoinProject()
        elseif currentView == "joining" then
            showJoining()
        elseif currentView == "join_success" then
            showJoinSuccess()
        elseif currentView == "join_error" then
            showJoinError()
        elseif currentView == "project_info" then
            showProjectInfo()
        elseif currentView == "leave_confirm" then
            showLeaveConfirm()
        elseif currentView == "leave_success" then
            showLeaveSuccess()
        end
        
        -- Handle events
        if viewData.waitForKey then
            os.pullEvent("key")
            currentView = "main_menu"
            viewData = {}
        else
            local eventType, p1, p2, p3 = gui.pollEvent()
            
            if eventType == "click" then
                local result = gui.handleClick(p1, p2)
                if result == "start_mining" then
                    return "start_mining"
                elseif result == "exit" then
                    gui.clearScreen()
                    gui.render()
                    return "exit"
                elseif result == "refresh" then
                    -- Screen will refresh on next loop
                end
            elseif eventType == "drag" then
                gui.clearScreen()
                if currentView == "main_menu" then
                    showMainMenu()
                elseif currentView == "project_list" then
                    -- Redraw with hover states
                    gui.renderAllWidgets()
                    gui.render()
                end
            elseif eventType == "scroll" then
                gui.handleScroll(p1, p2, p3)
                gui.clearScreen()
                gui.renderAllWidgets()
                gui.render()
            elseif eventType == "char" then
                gui.handleChar(p1)
                gui.clearScreen()
                if currentView == "join_project" then
                    showJoinProject()
                end
            elseif eventType == "key" then
                gui.handleKey(p1)
                if p1 == keys.q and currentView == "main_menu" then
                    return "exit"
                elseif p1 == keys.backspace then
                    gui.clearScreen()
                    if currentView == "join_project" then
                        showJoinProject()
                    end
                end
            end
        end
    end
end

return turtleGUI
