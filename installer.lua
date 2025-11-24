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
        "miner.lua"
    },
    controller = {
        "config.lua",
        "protocol.lua",
        "control.lua"
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

local function configureSystem(deviceType)
    print("=== Project Configuration ===")
    print("")
    
    -- Check for existing projects
    local projects = listProjects()
    
    print("Setup mode:")
    print("1. Create new project")
    print("2. Join existing project")
    print("")
    
    if #projects > 0 then
        print("Existing projects:")
        for i, proj in ipairs(projects) do
            print("  - " .. proj)
        end
        print("")
    end
    
    print("Enter choice (1 or 2):")
    local choice = read()
    
    local projectName
    local projectConfig
    
    if choice == "1" then
        -- Create new project
        print("")
        print("=== New Project Setup ===")
        print("")
        print("Enter project name:")
        projectName = read()
        
        if projectName == "" then
            print("Invalid project name")
            return false
        end
        
        print("")
        print("Enter tunnel configuration:")
        print("Tunnel length (default 64):")
        local length = tonumber(read()) or 64
        
        print("Number of layers (default 3):")
        local layers = tonumber(read()) or 3
        
        print("Starting Y-level relative to base (default -59):")
        local startY = tonumber(read()) or -59
        
        projectConfig = {
            name = projectName,
            tunnelLength = length,
            numLayers = layers,
            startY = startY,
            createdAt = os.epoch("utc")
        }
        
        print("")
        print("Project Configuration:")
        print("  Name: " .. projectName)
        print("  Tunnel length: " .. length)
        print("  Layers: " .. layers)
        print("  Start Y: " .. startY)
        print("")
        print("Save project? (Y/N)")
        
        local confirm = read()
        if confirm:lower() ~= "y" then
            print("Project creation cancelled")
            return false
        end
        
        if not saveProjectConfig(projectName, projectConfig) then
            print("ERROR: Could not save project")
            return false
        end
        
        print("Project '" .. projectName .. "' created!")
        
    else
        -- Join existing project
        print("")
        print("Enter project name:")
        projectName = read()
        
        projectConfig = loadProjectConfig(projectName)
        if not projectConfig then
            print("ERROR: Project '" .. projectName .. "' not found!")
            print("Available projects:")
            for i, proj in ipairs(projects) do
                print("  - " .. proj)
            end
            return false
        end
        
        print("")
        print("Loaded project: " .. projectName)
        print("  Tunnel length: " .. projectConfig.tunnelLength)
        print("  Layers: " .. projectConfig.numLayers)
        print("  Start Y: " .. projectConfig.startY)
    end
    
    print("")
    
    -- Device-specific setup
    if deviceType == "turtle" then
        print("=== Turtle Setup ===")
        print("")
        
        -- Check for wireless modem
        local modem = peripheral.find("modem", function(name, m)
            return m.isWireless()
        end)
        
        if not modem then
            print("ERROR: No wireless modem found!")
            print("Attach an Ender Modem to the turtle.")
            return false
        end
        
        print("Found wireless modem: " .. peripheral.getName(modem))
        print("")
        
        -- Set label
        print("Enter turtle label (or press Enter for default):")
        local label = read()
        
        if label and label ~= "" then
            os.setComputerLabel(label)
            print("Set label: " .. label)
        else
            print("Using default: " .. os.getComputerLabel())
        end
        
        print("")
        print("=== Home Base Position ===")
        print("")
        print("IMPORTANT: This turtle's current position")
        print("will become its HOME BASE (0,0,0)")
        print("")
        print("Make sure the turtle is where you want")
        print("it to start mining from!")
        print("")
        print("Press Enter to continue...")
        read()
    else
        -- Controller setup
        print("=== Controller Setup ===")
        print("")
        
        -- Check for wireless modem
        local modem = peripheral.find("modem")
        
        if not modem then
            print("ERROR: No wireless modem found!")
            print("Pocket computers have built-in modems.")
            return false
        end
        
        print("Found wireless modem")
        print("")
        
        -- Set label
        print("Enter controller label (or press Enter for default):")
        local label = read()
        
        if label and label ~= "" then
            os.setComputerLabel(label)
            print("Set label: " .. label)
        else
            print("Using default: " .. os.getComputerLabel())
        end
        
        print("")
    end
    
    local x = 0
    local y = 0
    local z = 0
    
    -- Update config file with project settings
    local configFile = fs.open("config.lua", "r")
    if not configFile then
        print("ERROR: config.lua not found!")
        return false
    end
    
    local content = configFile.readAll()
    configFile.close()
    
    -- Replace values from project config
    content = content:gsub("HOME_X = %d+", "HOME_X = " .. x)
    content = content:gsub("HOME_Y = %d+", "HOME_Y = " .. y)
    content = content:gsub("HOME_Z = %d+", "HOME_Z = " .. z)
    content = content:gsub("TUNNEL_LENGTH = %d+", "TUNNEL_LENGTH = " .. projectConfig.tunnelLength)
    content = content:gsub("NUM_LAYERS = %d+", "NUM_LAYERS = " .. projectConfig.numLayers)
    content = content:gsub("START_Y = %-?%d+", "START_Y = " .. projectConfig.startY)
    
    -- Update chest positions (relative to home)
    content = content:gsub(
        "CHEST_ORES = %{x = %-?%d+, y = %-?%d+, z = %-?%d+%}",
        string.format("CHEST_ORES = {x = %d, y = %d, z = %d}", x, y, z + 1)
    )
    content = content:gsub(
        "CHEST_COBBLE = %{x = %-?%d+, y = %-?%d+, z = %-?%d+%}",
        string.format("CHEST_COBBLE = {x = %d, y = %d, z = %d}", x, y - 1, z)
    )
    content = content:gsub(
        "CHEST_FUEL = %{x = %-?%d+, y = %-?%d+, z = %-?%d+%}",
        string.format("CHEST_FUEL = {x = %d, y = %d, z = %d}", x, y + 1, z)
    )
    
    -- Save updated config
    local configOut = fs.open("config.lua", "w")
    configOut.write(content)
    configOut.close()
    
    print("")
    print("Configuration saved!")
    print("Project: " .. projectName)
    return true
end

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
        print("Detected: Turtle")
        deviceType = "turtle"
    else
        print("Detected: Computer/Pocket Computer")
        print("")
        print("Install as:")
        print("1. Controller (Pocket Computer)")
        print("2. Coordinator (Desktop Computer)")
        print("")
        print("Enter choice (1 or 2):")
        local choice = read()
        
        if choice == "1" then
            deviceType = "controller"
        else
            print("Coordinator mode not yet implemented.")
            print("Please use a pocket computer for the controller.")
            return
        end
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
        print("Found local installation files!")
        print("Using local files...")
        print("")
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
    
    -- Project-based configuration (handles device-specific setup too)
    if not configureSystem(deviceType) then
        print("Configuration failed!")
        return
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
    else
        print("To start controller:")
        print("  Run: control.lua")
        print("")
        print("Controls:")
        print("  [A] Pause all turtles")
        print("  [Z] Resume all turtles")
        print("  [F] Refresh status")
        print("  [Q] Quit")
    end
    
    print("")
    print("Press any key to exit installer...")
    os.pullEvent("key")
end

-- Run installer
main()

