-- Bootstrap installer - Run with: pastebin run <code>
-- This downloads the full installer from GitHub

local GITHUB_URL = "https://raw.githubusercontent.com/SamphireOG/computercraft-branch-miner/main/installer.lua"

print("=== Branch Miner Bootstrap ===")
print("Cleaning old files...")

-- Delete old installation files to ensure fresh download
local files = {
    "config.lua", "protocol.lua", "state.lua", "utils.lua",
    "coordinator.lua", "miner.lua", "control.lua", "installer.lua",
    "project-server.lua", "project-client.lua"
}

for _, file in ipairs(files) do
    if fs.exists(file) then
        fs.delete(file)
        print("Removed old: " .. file)
    end
end

print("")
print("Downloading latest installer...")

-- Add cache-busting to force fresh download
local cacheBuster = "?t=" .. os.epoch("utc")
local response = http.get(GITHUB_URL .. cacheBuster)
if not response then
    print("ERROR: Could not download installer")
    print("Check your internet connection and GitHub URL")
    return
end

local content = response.readAll()
response.close()

print("Downloaded! Running installer...")
print("")

-- Run the installer
local func, err = load(content, "installer", "t", _ENV)
if not func then
    print("ERROR: Could not load installer")
    print(err)
    return
end

func()

