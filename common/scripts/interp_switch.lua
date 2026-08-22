-- 定义四种模式
local modes = {
    {
        name = "Close",
        interp = "no",
        tscale = "oversample",
        blur = 0.0,
        videoSync = "audio"
    },

    {
        name = "Movie",
        interp = "yes",
        tscale = "oversample",
        blur = 0.0,
        videoSync = "display-resample"
    },

    {
        name = "Anime",
        interp = "yes",
        tscale = "sphinx",
        blur = 0.65,
        videoSync = "display-resample"
    },

    {
        name = "Smooth",
        interp = "yes",
        tscale = "bicubic",
        blur = -0.40,
        videoSync = "display-resample"
    }
}

-- 当前模式
local current = 1


-- 应用指定模式
local function apply_mode(index)
    if not modes[index] then
        mp.msg.warn("Invalid interpolation mode index: " .. tostring(index))
        return
    end

    current = index

    local mode = modes[current]

    -- 设置 mpv 参数
    mp.set_property("interpolation", mode.interp)
    mp.set_property("tscale", mode.tscale)
    mp.set_property("tscale-blur", mode.blur)
    mp.set_property("video-sync", mode.videoSync)

    -- OSD 提示
    mp.osd_message("VFI: " .. mode.name, 2)
end


-- 循环切换模式
local function cycle_interpolation()
    current = current % #modes + 1
    apply_mode(current)
end


-- 注册循环切换
mp.register_script_message("cycle_interp", cycle_interpolation)

-- 注册快捷模式
mp.register_script_message("cycle_interp/close", function()
    apply_mode(1)
end)

mp.register_script_message("cycle_interp/movie", function()
    apply_mode(2)
end)

mp.register_script_message("cycle_interp/anime", function()
    apply_mode(3)
end)

mp.register_script_message("cycle_interp/resample", function()
    apply_mode(4)
end)