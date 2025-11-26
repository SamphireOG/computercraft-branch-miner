-- Turtle GUI System
-- Provides menu-based interface for turtle operations and project management

local gui = require("gui")
local protocol = require("protocol")
local projectClient = require("project-client")
local config = require("config")

local turtleGUI = {}

-- ========== PROJECT MANAGEMENT SCREENS ==========

local function drawHeader(title)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.setCursorPos(1, 1)
    term.clearLine()
    term.setCursorPos(math.floor((term.getSize() - #title) / 2) + 1, 1)
    term.write(title)
end

local function drawFooter(text)
    local w, h = term.getSize()
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.setCursorPos(1, h)
    term.clearLine()
    term.setCursorPos(2, h)
    term.write(text)
end

function turtleGUI.showProjectList()
    term.setBackgroundColor(colors.black)
    term.clear()
    
    drawHeader("Available Projects")
    
    -- Initialize project client
    projectClient.init()
    
    term.setCursorPos(2, 3)
    term.setTextColor(colors.white)
    print("Searching for projects...")
    print("")
    print("Make sure pocket computer")
    print("is running!")
    
    -- Discover projects
    local projects = projectClient.discoverProjects(10)
    
    term.setBackgroundColor(colors.black)
    term.clear()
    drawHeader("Available Projects")
    
    if #projects == 0 then
        term.setCursorPos(2, 3)
        term.setTextColor(colors.red)
        print("No projects found!")
        print("")
        term.setTextColor(colors.white)
        print("Make sure:")
        print("- Pocket computer is on")
        print("- Projects created")
        print("- You're in range")
        print("")
        
        drawFooter("Press any key to go back")
        os.pullEvent("key")
        return nil
    end
    
    -- Clear buttons
    gui.clearButtons()
    
    -- Create project selection buttons
    local y = 3
    for i, proj in ipairs(projects) do
        gui.createButton(
            "project_" .. i,
            2, y, 47, 4,
            proj.name,
            function()
                return proj
            end,
            colors.gray,
            colors.white
        )
        
        -- Draw additional info
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.lightGray)
        term.setCursorPos(4, y + 1)
        term.write("Channel: " .. proj.channel)
        term.setCursorPos(4, y + 2)
        term.write("Turtles: " .. proj.turtleCount .. " | Length: " .. proj.tunnelLength)
        
        y = y + 5
    end
    
    -- Back button
    gui.createButton(
        "back",
        2, y, 47, 3,
        "Cancel",
        function() return nil end,
        colors.red,
        colors.white
    )
    
    drawFooter("Click project to join")
    gui.drawAllButtons()
    
    -- Wait for selection
    while true do
        local event, button, x, y = os.pullEvent()
        
        if event == "mouse_click" then
            local result = gui.handleClick(x, y)
            
            if result then
                local clickedButton = gui.buttons[result]
                if clickedButton and clickedButton.callback then
                    local selectedProject = clickedButton.callback()
                    if selectedProject then
                        return selectedProject
                    else
                        return nil
                    end
                end
            end
        elseif event == "mouse_drag" then
            gui.updateHover(x, y)
            gui.drawAllButtons()
        end
    end
end

function turtleGUI.joinProject()
    local selectedProject = turtleGUI.showProjectList()
    
    if not selectedProject then
        return false
    end
    
    -- Show joining screen
    term.setBackgroundColor(colors.black)
    term.clear()
    drawHeader("Joining Project")
    
    term.setCursorPos(2, 3)
    term.setTextColor(colors.white)
    print("Project: " .. selectedProject.name)
    print("Channel: " .. selectedProject.channel)
    print("")
    print("Enter turtle name:")
    print("(or press Enter for auto)")
    
    term.setCursorPos(2, 9)
    term.write("> ")
    local turtleName = read()
    
    if turtleName == "" then
        turtleName = "Miner-" .. os.getComputerID()
    end
    
    os.setComputerLabel(turtleName)
    
    term.setCursorPos(2, 11)
    print("Label set to: " .. turtleName)
    print("")
    print("Joining project...")
    
    -- Join project
    local success, result = projectClient.joinProject(selectedProject.name)
    
    if not success then
        term.setTextColor(colors.red)
        print("")
        print("ERROR: Failed to join!")
        print("Reason: " .. (result or "Unknown"))
        print("")
        drawFooter("Press any key to continue")
        os.pullEvent("key")
        return false
    end
    
    term.setTextColor(colors.lime)
    print("")
    print("Successfully joined!")
    print("Channel: " .. result.channel)
    
    if result.isFirstTurtle then
        print("")
        term.setTextColor(colors.yellow)
        print("=== FIRST TURTLE ===")
        term.setTextColor(colors.white)
        print("You will set the home base!")
        print("")
        print("IMPORTANT:")
        print("Position this turtle at the")
        print("home base before starting.")
    end
    
    print("")
    drawFooter("Press any key to continue")
    os.pullEvent("key")
    
    return true
end

function turtleGUI.leaveProject()
    local assignment = projectClient.loadAssignment()
    
    if not assignment then
        term.setBackgroundColor(colors.black)
        term.clear()
        drawHeader("Leave Project")
        
        term.setCursorPos(2, 3)
        term.setTextColor(colors.red)
        print("Not in any project!")
        print("")
        drawFooter("Press any key to continue")
        os.pullEvent("key")
        return
    end
    
    term.setBackgroundColor(colors.black)
    term.clear()
    drawHeader("Leave Project")
    
    term.setCursorPos(2, 3)
    term.setTextColor(colors.white)
    print("Current project:")
    term.setTextColor(colors.yellow)
    print(assignment.projectName)
    print("")
    term.setTextColor(colors.white)
    print("Channel: " .. assignment.channel)
    print("")
    print("Are you sure you want")
    print("to leave this project?")
    print("")
    
    gui.clearButtons()
    
    gui.createButton(
        "confirm",
        2, 13, 22, 3,
        "Yes, Leave",
        function() return true end,
        colors.red,
        colors.white
    )
    
    gui.createButton(
        "cancel",
        26, 13, 22, 3,
        "Cancel",
        function() return false end,
        colors.gray,
        colors.white
    )
    
    drawFooter("Confirm your choice")
    gui.drawAllButtons()
    
    -- Wait for selection
    while true do
        local event, button, x, y = os.pullEvent()
        
        if event == "mouse_click" then
            local result = gui.handleClick(x, y)
            
            if result then
                local clickedButton = gui.buttons[result]
                if clickedButton and clickedButton.callback then
                    local confirmed = clickedButton.callback()
                    
                    if confirmed then
                        -- Announce offline
                        projectClient.announceOffline()
                        
                        -- Clear assignment
                        projectClient.clearAssignment()
                        
                        term.setBackgroundColor(colors.black)
                        term.clear()
                        drawHeader("Left Project")
                        
                        term.setCursorPos(2, 3)
                        term.setTextColor(colors.lime)
                        print("Successfully left project!")
                        print("")
                        term.setTextColor(colors.white)
                        print("You can now join a")
                        print("different project.")
                        print("")
                        drawFooter("Press any key to continue")
                        os.pullEvent("key")
                    end
                    
                    return
                end
            end
        elseif event == "mouse_drag" then
            gui.updateHover(x, y)
            gui.drawAllButtons()
        end
    end
end

function turtleGUI.showProjectInfo()
    local assignment = projectClient.loadAssignment()
    
    term.setBackgroundColor(colors.black)
    term.clear()
    drawHeader("Project Info")
    
    if not assignment then
        term.setCursorPos(2, 3)
        term.setTextColor(colors.red)
        print("Not in any project!")
        print("")
        term.setTextColor(colors.white)
        print("Use 'Join Project' to")
        print("connect to a project.")
    else
        term.setCursorPos(2, 3)
        term.setTextColor(colors.white)
        print("Project Name:")
        term.setTextColor(colors.yellow)
        print(assignment.projectName)
        print("")
        
        term.setTextColor(colors.white)
        print("Channel: " .. assignment.channel)
        print("Turtle ID: " .. assignment.turtleID)
        print("Label: " .. (assignment.label or "None"))
        
        if assignment.startY then
            print("Y Level: " .. assignment.startY)
        end
        
        print("")
        local timestamp = assignment.assignedAt or 0
        local days = math.floor(timestamp / 86400000)
        print("Joined: " .. days .. " days ago")
    end
    
    print("")
    drawFooter("Press any key to go back")
    os.pullEvent("key")
end

-- ========== MAIN MENU ==========

function turtleGUI.showMainMenu()
    local assignment = projectClient.loadAssignment()
    
    term.setBackgroundColor(colors.black)
    term.clear()
    
    drawHeader("Turtle Control")
    
    -- Show current status
    term.setCursorPos(2, 3)
    term.setTextColor(colors.white)
    if assignment then
        term.write("Project: ")
        term.setTextColor(colors.lime)
        print(assignment.projectName)
    else
        term.setTextColor(colors.red)
        print("No Project Assigned")
    end
    
    gui.clearButtons()
    
    local y = 5
    
    -- Start Mining button (only if assigned)
    if assignment then
        gui.createButton(
            "start_mining",
            2, y, 47, 3,
            "Start Mining",
            function() return "start_mining" end,
            colors.lime,
            colors.white
        )
        y = y + 4
    end
    
    -- Project Management section
    if assignment then
        gui.createButton(
            "project_info",
            2, y, 47, 3,
            "Project Info",
            function() return "project_info" end,
            colors.blue,
            colors.white
        )
        y = y + 4
        
        gui.createButton(
            "leave_project",
            2, y, 47, 3,
            "Leave Project",
            function() return "leave_project" end,
            colors.orange,
            colors.white
        )
        y = y + 4
    else
        gui.createButton(
            "join_project",
            2, y, 47, 3,
            "Join Project",
            function() return "join_project" end,
            colors.blue,
            colors.white
        )
        y = y + 4
    end
    
    -- Exit button
    gui.createButton(
        "exit",
        2, y, 47, 3,
        "Exit",
        function() return "exit" end,
        colors.red,
        colors.white
    )
    
    drawFooter("Select an option")
    gui.drawAllButtons()
    
    -- Event loop
    while true do
        local event, button, x, y = os.pullEvent()
        
        if event == "mouse_click" then
            local result = gui.handleClick(x, y)
            
            if result then
                local clickedButton = gui.buttons[result]
                if clickedButton and clickedButton.callback then
                    return clickedButton.callback()
                end
            end
        elseif event == "mouse_drag" then
            gui.updateHover(x, y)
            gui.drawAllButtons()
        end
    end
end

-- ========== MAIN GUI LOOP ==========

function turtleGUI.run()
    while true do
        local action = turtleGUI.showMainMenu()
        
        if action == "start_mining" then
            return "start_mining"
        elseif action == "join_project" then
            turtleGUI.joinProject()
        elseif action == "leave_project" then
            turtleGUI.leaveProject()
        elseif action == "project_info" then
            turtleGUI.showProjectInfo()
        elseif action == "exit" then
            term.setBackgroundColor(colors.black)
            term.clear()
            term.setCursorPos(1, 1)
            term.setTextColor(colors.white)
            print("Goodbye!")
            return "exit"
        end
    end
end

return turtleGUI

