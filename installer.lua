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

local function setupTurtle()
    print("=== Turtle Setup ===")
    print("")
    
    -- Check for advanced mining turtle
    if not turtle then
        print("ERROR: This must be run on a turtle!")
        return false
    end
    
    -- Check for wireless modem
    local modem = peripheral.find("modem", function(name, modem)
        return modem.isWireless()
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
        local defaultLabel = "Miner-" .. os.getComputerID()
        os.setComputerLabel(defaultLabel)
        print("Set label: " .. defaultLabel)
    end
    
    print("")
    print("Turtle ID: " .. os.getComputerID())
    print("Label: " .. os.getComputerLabel())
    print("")
    
    return true
end

local function setupController()
    print("=== Controller Setup ===")
    print("")
    
    -- Check for pocket computer
    if turtle then
        print("ERROR: This appears to be a turtle!")
        print("Run installer on a pocket computer for controller setup.")
        return false
    end
    
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
        os.setComputerLabel("Controller")
        print("Set label: Controller")
    end
    
    print("")
    return true
end

local function configureSystem()
    print("=== System Configuration ===")
    print("")
    
    -- Ask for home base coordinates
    print("Enter home base coordinates:")
    print("X coordinate (default 0):")
    local x = tonumber(read()) or 0
    
    print("Y coordinate (default 64):")
    local y = tonumber(read()) or 64
    
    print("Z coordinate (default 0):")
    local z = tonumber(read()) or 0
    
    print("")
    print("Enter tunnel configuration:")
    print("Tunnel length (default 64):")
    local length = tonumber(read()) or 64
    
    print("Number of layers (default 3):")
    local layers = tonumber(read()) or 3
    
    print("Starting Y-level (default -59):")
    local startY = tonumber(read()) or -59
    
    print("")
    print("Configuration:")
    print("  Home: " .. x .. "," .. y .. "," .. z)
    print("  Tunnel length: " .. length)
    print("  Layers: " .. layers)
    print("  Start Y: " .. startY)
    print("")
    print("Save configuration? (Y/N)")
    
    local confirm = read()
    if confirm:lower() ~= "y" then
        print("Configuration cancelled")
        return false
    end
    
    -- Update config file
    local configFile = fs.open("config.lua", "r")
    if not configFile then
        print("ERROR: config.lua not found!")
        return false
    end
    
    local content = configFile.readAll()
    configFile.close()
    
    -- Replace values
    content = content:gsub("HOME_X = %d+", "HOME_X = " .. x)
    content = content:gsub("HOME_Y = %d+", "HOME_Y = " .. y)
    content = content:gsub("HOME_Z = %d+", "HOME_Z = " .. z)
    content = content:gsub("TUNNEL_LENGTH = %d+", "TUNNEL_LENGTH = " .. length)
    content = content:gsub("NUM_LAYERS = %d+", "NUM_LAYERS = " .. layers)
    content = content:gsub("START_Y = %-?%d+", "START_Y = " .. startY)
    
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
    
    print("Configuration saved!")
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
    
    -- Device-specific setup
    local setupSuccess
    if deviceType == "turtle" then
        setupSuccess = setupTurtle()
    else
        setupSuccess = setupController()
    end
    
    if not setupSuccess then
        print("Setup failed!")
        return
    end
    
    -- Configuration
    if not configureSystem() then
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

