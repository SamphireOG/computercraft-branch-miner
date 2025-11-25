-- Diagnose control.lua syntax error
print("Reading control.lua...")

local file = fs.open("control.lua", "r")
if not file then
    print("ERROR: Cannot open control.lua")
    return
end

local content = file.readAll()
file.close()

print("File size: " .. #content .. " bytes")
print("")
print("Attempting to load...")
print("")

local func, err = load(content, "control.lua", "t", _ENV)

if not func then
    print("=== SYNTAX ERROR ===")
    print(err)
    print("===================")
else
    print("✓✓✓ NO SYNTAX ERROR! ✓✓✓")
    print("File is valid Lua!")
end

