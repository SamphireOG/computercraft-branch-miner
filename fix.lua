-- Emergency fix script for control.lua syntax error
-- Run this if you get "Unexpected end of file" error

print("=== EMERGENCY FIX ===")
print("Downloading fixed files...")
print("")

local GITHUB_BASE = "https://raw.githubusercontent.com/SamphireOG/computercraft-branch-miner/main/"

-- Force super aggressive cache-busting
local megaBuster = "?cb=" .. os.epoch("utc") .. "&rand=" .. math.random(1, 999999)

local files = {
    "project-server.lua",
    "control.lua"
}

for _, filename in ipairs(files) do
    print("Downloading: " .. filename)
    
    -- Delete old file
    if fs.exists(filename) then
        fs.delete(filename)
    end
    
    -- Download with mega cache-busting
    local url = GITHUB_BASE .. filename .. megaBuster
    local response = http.get(url)
    
    if response then
        local content = response.readAll()
        response.close()
        
        local file = fs.open(filename, "w")
        file.write(content)
        file.close()
        
        print("✓ Fixed: " .. filename)
    else
        print("✗ Failed: " .. filename)
    end
    
    sleep(0.5)
end

print("")
print("===================")
print("Fix applied!")
print("")
print("Now run: control.lua")
print("===================")

