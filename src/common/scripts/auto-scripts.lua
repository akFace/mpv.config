mp.add_forced_key_binding("SPACE", "space-smart", function()
    if mp.get_property_bool("idle-active", false) then
        mp.commandv("script-binding", "recentmenu/last")
    else
        mp.commandv("cycle", "pause")
    end
end)