-- scripts/menu/main.lua
local function safe_dofile(file)
    local ok, err = pcall(dofile, file)
    if not ok then
        mp.msg.error("Failed to load " .. file .. ": " .. tostring(err))
    else
        mp.msg.log("info", "Loaded " .. file)
    end
end

local dir = mp.get_script_directory()   -- 返回 scripts/menu/
if not dir then
    mp.msg.error("Cannot get script directory")
    return
end

mp.msg.log("info", "Loading menu plugin from " .. dir)

safe_dofile(dir .. "/dialog.lua")
safe_dofile(dir .. "/dyn_menu.lua")
safe_dofile(dir .. "/menu.lua")

mp.msg.log("info", "Menu plugin loaded")