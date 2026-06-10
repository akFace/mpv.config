-- 定义四种模式，加入了最适合该算法的 blur 值
local modes = {
    { name = "关闭插帧", interp = "no",  tscale = "oversample", blur = 0.0  },
    -- 电影模式：oversample 不需要也不支持模糊控制，设为 0.0 即可
    { name = "电影模式", interp = "yes", tscale = "oversample", blur = 0.0  },
    -- 动漫模式：sphinx 配合 0.65 模糊度，既丝滑又能收紧二次元的线条，不发糊
    { name = "动漫模式", interp = "yes", tscale = "sphinx",     blur = 0.65 },
    -- 极致丝滑：bicubic 默认稍糊，设定为 -0.40 稍微锐化一下，压制过度黏糊感
    { name = "极致丝滑", interp = "yes", tscale = "bicubic",    blur = -0.40}
}

local current = 1 -- 默认从第1个开始

function cycle_interpolation()
    current = current + 1
    if current > #modes then current = 1 end
    
    local mode = modes[current]
    
    -- 一键强行锁死并设置 mpv 的三个核心参数
    mp.set_property("interpolation", mode.interp)
    mp.set_property("tscale", mode.tscale)
    mp.set_property("tscale-blur", mode.blur)
    
    -- OSD 屏幕提示词
    mp.osd_message("插帧模式: " .. mode.name, 2)
end

mp.register_script_message("cycle_interp", cycle_interpolation)