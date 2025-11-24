-- Bootstrap installer - Run with: pastebin run <code>
-- This downloads the full installer from GitHub

local GITHUB_URL = "https://raw.githubusercontent.com/SamphireOG/computercraft-branch-miner/main/installer.lua"

print("=== Branch Miner Bootstrap ===")
print("Downloading installer...")

local response = http.get(GITHUB_URL)
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

