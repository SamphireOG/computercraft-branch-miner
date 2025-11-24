-- Advanced Branch Miner Installer
-- Easy setup for turtles and pocket computers

local GITHUB_BASE = "https://raw.githubusercontent.com/SamphireOG/computercraft-branch-miner/main/"

-- File list to download
local FILES = {
    turtle = {
        "config.lua",
        "protocol.lua",
        "state.lua",
        "utils.lua",
        "coordinator.lua",
        "miner.lua",
        "project-client.lua"
    },
    controller = {
        "config.lua",
        "protocol.lua",
        "control.lua",
        "project-server.lua"
    }
}

-- ========== DOWNLOAD FUNCTIONS ==========

local function downloadFile(url, filename)
    print("Downloading " .. filename .. "...")
    
    local response = http.get(url)
    if not response then
        return false, "Download failed"
    end
    
    local content = response.readAll()
    response.close()
    
    local file = fs.open(filename, "w")
    if not file then
        return false, "Could not create file"
    end
    
    file.write(content)
    file.close()
    
    return true
end

local function downloadFromGitHub(fileList)
    print("Downloading from GitHub...")
    print("")
    
    local failed = {}
    
    for _, filename in ipairs(fileList) do
        local url = GITHUB_BASE .. filename
        local success, err = downloadFile(url, filename)
        
        if not success then
            print("FAILED: " .. filename .. " - " .. err)
            table.insert(failed, filename)
        else
            print("OK: " .. filename)
        end
    end
    
    print("")
    
    if #failed > 0 then
        print("Failed to download " .. #failed .. " files:")
        for _, file in ipairs(failed) do
            print("  - " .. file)
        end
        return false
    end
    
    print("All files downloaded successfully!")
    return true
end

local function downloadFromPastebin(code, filename)
    local url = "https://pastebin.com/raw/" .. code
    return downloadFile(url, filename)
end

-- ========== SETUP FUNCTIONS ==========

-- ========== PROJECT MANAGEMENT ==========

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
        return nil, "Project not found"
    end
    
    local file = fs.open(filename, "r")
    if not file then
        return nil, "Could not read project"
    end
    
    local content = file.readAll()
    file.close()
    
    return textutils.unserialize(content)
end

local function saveProjectConfig(projectName, config)
    local filename = getProjectFilename(projectName)
    local file = fs.open(filename, "w")
    if file then
        file.write(textutils.serialize(config))
        file.close()
        return true
    end
    return false
end

local function getNextAvailableChannel()
    -- Channel 100 is reserved for discovery
    -- Projects start at 101
    local baseChannel = 101
    local projects = listProjects()
    
    if #projects == 0 then
        return baseChannel
    end
    
    -- Find highest used channel
    local maxChannel = baseChannel - 1
    for _, projName in ipairs(projects) do
        local config = loadProjectConfig(projName)
        if config and config.channel and config.channel > maxChannel then
            maxChannel = config.channel
        end
    end
    
    return maxChannel + 1
end

local function configureTurtle()
    -- Turtles use discovery protocol
    print("=== Turtle Project Discovery ===")
    print("")
    
    -- Load project client
    local client = require("project-client")
    client.init()
    
    -- Check for existing assignment
    local existing = client.loadAssignment()
    if existing then
        print("Already assigned to: " .. existing.projectName)
        print("Channel: " .. existing.channel)
        print("")
        print("1. Keep assignment")
        print("2. Join different project")
        print("")
        print("Enter choice (1 or 2):")
        local choice = read()
        
        if choice == "1" then
            return true, existing
        else
            client.clearAssignment()
        end
    end
    
    -- Discover available projects
    print("")
    print("Searching for projects...")
    print("(Make sure pocket computer is running!)")
    print("")
    
    local projects = client.discoverProjects(10)
    
    if #projects == 0 then
        print("ERROR: No projects found!")
        print("")
        print("Make sure:")
        print("1. Pocket computer is on")
        print("2. Projects have been created")
        print("3. You're in range")
        return false
    end
    
    -- Show available projects
    print("")
    print("Available projects:")
    print("")
    
    for i, proj in ipairs(projects) do
        print(i .. ". " .. proj.name)
        print("   Channel: " .. proj.channel)
        print("   Turtles: " .. proj.turtleCount)
        print("   Length: " .. proj.tunnelLength .. " blocks")
        print("")
    end
    
    print("Select project (1-" .. #projects .. "):")
    local choice = tonumber(read())
    
    if not choice or choice < 1 or choice > #projects then
        print("Invalid choice!")
        return false
    end
    
    local selectedProject = projects[choice]
    
    -- Join project
    print("")
    local success, result = client.joinProject(selectedProject.name)
    
    if not success then
        print("ERROR: Failed to join project")
        print("Reason: " .. (result or "Unknown"))
        return false
    end
    
    print("Successfully joined: " .. selectedProject.name)
    print("Channel: " .. result.channel)
    
    if result.isFirstTurtle then
        print("")
        print("=== FIRST TURTLE ===")
        print("This turtle will set the home base!")
        print("")
        print("IMPORTANT: Position this turtle at")
        print("the home base location before continuing.")
        print("")
        print("Press Enter when ready...")
        read()
    end
    
    return true, result
end


-- ========== STARTUP FILE ==========

local function createStartupFile(deviceType)
    print("Create startup file for auto-run? (Y/N)")
    local confirm = read()
    
    if confirm:lower() ~= "y" then
        return
    end
    
    local startupContent
    if deviceType == "turtle" then
        startupContent = [[-- Auto-start miner
print("Starting Branch Miner...")
shell.run("miner.lua")
]]
    else
        startupContent = [[-- Auto-start controller
print("Starting Branch Miner Controller...")
shell.run("control.lua")
]]
    end
    
    local file = fs.open("startup.lua", "w")
    if file then
        file.write(startupContent)
        file.close()
        print("Startup file created!")
    else
        print("ERROR: Could not create startup file")
    end
end

-- ========== LOCAL INSTALLATION ==========

local function installFromLocal(fileList)
    print("Installing from local files...")
    
    for _, filename in ipairs(fileList) do
        if not fs.exists(filename) then
            print("ERROR: " .. filename .. " not found!")
            print("All files must be in the same directory as installer.")
            return false
        end
    end
    
    print("All files found!")
    return true
end

-- ========== MANUAL INSTALLATION ==========

local function manualInstall(deviceType)
    print("=== Manual Installation ===")
    print("")
    print("Please download and place these files:")
    print("")
    
    local fileList = (deviceType == "turtle") and FILES.turtle or FILES.controller
    
    for _, filename in ipairs(fileList) do
        print("  - " .. filename)
    end
    
    print("")
    print("Place all files in the same directory as this installer.")
    print("")
    print("Press Enter when ready...")
    read()
    
    return installFromLocal(fileList)
end

-- ========== MAIN INSTALLER ==========

local function main()
    term.clear()
    term.setCursorPos(1, 1)
    
    print("================================")
    print("Advanced Branch Miner Installer")
    print("================================")
    print("")
    
    -- Detect device type
    local deviceType
    if turtle then
        print("Detected: Mining Turtle")
        print("")
        deviceType = "turtle"
    else
        print("Detected: Computer/Pocket Computer")
        print("")
        print("This will install the controller.")
        print("Use a Pocket Computer for wireless control.")
        print("")
        print("Continue? (Y/N)")
        local choice = read()
        
        if choice:lower() ~= "y" then
            print("Installation cancelled")
            return
        end
        
        deviceType = "controller"
    end
    
    print("")
    
    -- Check for local files
    local hasLocalFiles = true
    local fileList = (deviceType == "turtle") and FILES.turtle or FILES.controller
    
    for _, filename in ipairs(fileList) do
        if not fs.exists(filename) then
            hasLocalFiles = false
            break
        end
    end
    
    if hasLocalFiles then
        print("Found local installation files.")
        print("")
        print("Installation options:")
        print("1. Use local files")
        print("2. Re-download from GitHub")
        print("")
        print("Enter choice (1 or 2):")
        local choice = read()
        
        if choice ~= "1" then
            -- Delete old files and re-download
            print("")
            print("Removing old files...")
            for _, filename in ipairs(fileList) do
                if fs.exists(filename) then
                    fs.delete(filename)
                end
            end
            
            if not downloadFromGitHub(fileList) then
                print("")
                print("GitHub download failed!")
                return
            end
        else
            print("")
            print("Using local files...")
        end
    else
        print("Installation files not found locally.")
        print("")
        print("Download options:")
        print("1. Download from GitHub (automatic)")
        print("2. Manual installation")
        print("")
        print("Enter choice (1 or 2):")
        local choice = read()
        
        if choice == "1" then
            -- Download from GitHub
            if not downloadFromGitHub(fileList) then
                print("")
                print("GitHub download failed!")
                print("Try option 2 (manual installation)")
                return
            end
        else
            -- Manual installation
            if not manualInstall(deviceType) then
                print("Installation failed!")
                return
            end
        end
    end
    
    -- Project-based configuration
    if deviceType == "turtle" then
        local configSuccess, result = configureTurtle()
        
        if not configSuccess then
            print("Configuration failed!")
            return
        end
    end
    
    -- Create startup file
    createStartupFile(deviceType)
    
    print("")
    print("================================")
    print("Installation complete!")
    print("================================")
    print("")
    
    if deviceType == "turtle" then
        print("To start mining:")
        print("  1. Place turtle at home base")
        print("  2. Face north (towards mining area)")
        print("  3. Run: miner.lua")
        print("")
        print("Required setup:")
        print("  - Chest below: Cobblestone storage")
        print("  - Chest in front: Ore/item storage")
        print("  - Chest above: Fuel storage")
        print("")
        print("Press any key to exit installer...")
        os.pullEvent("key")
    else
        print("Launch controller now? (Y/N)")
        local launch = read()
        
        if launch:lower() == "y" then
            print("")
            print("Starting controller...")
            sleep(1)
            shell.run("control.lua")
        else
            print("")
            print("To start controller later:")
            print("  Run: control.lua")
            print("")
            print("Controls:")
            print("  [P] Switch projects")
            print("  [A] Pause all turtles")
            print("  [Z] Resume all turtles")
            print("  [F] Refresh status")
            print("  [Q] Quit")
            print("")
            print("Press any key to exit installer...")
            os.pullEvent("key")
        end
    end
end

-- Run installer
main()

