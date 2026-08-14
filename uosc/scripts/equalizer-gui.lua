-- [[
--  名称: mpv-equalizer-gui (全功能持久化自动保存版 - 含极简开关)
--  特性: 1080p-4K自适应、uosc风格推子、胶囊开关、配置自动保存与启动自动加载
-- ]]

local mp = require("mp")
local utils = require("mp.utils")

-- EQ 总开关状态 (默认开启)
local eq_enabled = true

-- 10 段 EQ 配置 (对应 FFmpeg equalizer 滤镜频率)
local bands = {
    { label = "31.5", freq = "31.25", val = 0 },
    { label = "63",   freq = "62.5",  val = 0 },
    { label = "125",  freq = "125",   val = 0 },
    { label = "250",  freq = "250",   val = 0 },
    { label = "500",  freq = "500",   val = 0 },
    { label = "1k",   freq = "1000",  val = 0 },
    { label = "2k",   freq = "2000",  val = 0 },
    { label = "4k",   freq = "4000",  val = 0 },
    { label = "8k",   freq = "8000",  val = 0 },
    { label = "16k",  freq = "16000", val = 0 }
}

-- 配置文件存储路径解析 (使用 mpv 标准 expand-path 接口)
local CONFIG_PATH = mp.command_native({"expand-path", "~~/script-opts/equalizer-gui.json"})
local ALT_CONFIG_PATH = mp.command_native({"expand-path", "~~/equalizer-gui.json"})

local overlay = mp.create_osd_overlay("ass-events")
local is_visible = false

-- 基准虚拟画布尺寸
local BASE_W, BASE_H = 1280, 720
local PANEL_W, PANEL_H = 680, 380

local ui = {
    px = 0, py = 0,
    dragging_band = nil,
    hover_band = nil,
    selected_band = 1
}

local mouse = { x = 0, y = 0, vx = 0, vy = 0, down = false }

-- 按钮组件配置 (添加 toggle 开关)
local btns = {
    reset  = { label = "重置 (Reset)", x = 0, y = 0, w = 110, h = 36, radius = 18 },
    save   = { label = "保存（Save）", x = 0, y = 0, w = 110, h = 36, radius = 18 },
    close  = { label = "✕",           x = 0, y = 0, w = 32,  h = 32, radius = 16 },
    toggle = { label = "",            x = 0, y = 0, w = 44,  h = 22, radius = 11 }
}

-- ASS 颜色定义
local colors = {
    bg = "&H221C1C&",
    btn = "&H333333&",
    btn_hover = "&H444444&",
    btn_border = "&H666666&",
    close_hover = "&H3333CC&",
    track = "&H111111&",
    active = "&H53C531&",     -- 绿色
    hover = "&H78FF55&",      -- 高亮绿
    text = "&HAAAAAA&",
    text_hi = "&HFFFFFF&",
    line = "&H444444&"
}

-- 应用音频 EQ 滤镜到 mpv 引擎
local function apply_audio_eq()
    if not eq_enabled then
        mp.commandv("af", "remove", "@eq_gui")
        return
    end

    local filters = {}
    for _, b in ipairs(bands) do
        table.insert(filters, string.format("equalizer=f=%s:width_type=o:w=1:g=%.1f", b.freq, b.val))
    end
    local filter_str = "@eq_gui:lavfi=[" .. table.concat(filters, ",") .. "]"
    mp.commandv("af", "set", filter_str)
end

-- 将增益数据与开关状态写入本地 JSON 配置文件
local function save_config()
    local band_vals = {}
    for i, b in ipairs(bands) do
        band_vals[i] = b.val
    end

    local data = {
        enabled = eq_enabled,
        bands = band_vals
    }

    local json_str, _ = utils.format_json(data)
    if json_str then
        local file = io.open(CONFIG_PATH, "w")
        -- 若 script-opts 文件夹不存在，回退写入配置根目录
        if not file then
            CONFIG_PATH = ALT_CONFIG_PATH
            file = io.open(CONFIG_PATH, "w")
        end

        if file then
            file:write(json_str)
            file:close()
            mp.osd_message("EQ has been saved locally", 2)
            return true
        end
    end
    mp.osd_message("Save failed: Unable to write to configuration file", 2)
    return false
end

-- 启动/换集时读取本地 JSON 配置并自动启用
local function load_config()
    local file = io.open(CONFIG_PATH, "r")
    if not file then
        file = io.open(ALT_CONFIG_PATH, "r")
    end

    if not file then return end

    local content = file:read("*a")
    file:close()

    if not content or content == "" then return end

    local data, _ = utils.parse_json(content)
    if data and type(data) == "table" then
        if data.bands and type(data.bands) == "table" then
            for i, val in ipairs(data.bands) do
                if bands[i] and type(val) == "number" then
                    bands[i].val = val
                end
            end
            if type(data.enabled) == "boolean" then
                eq_enabled = data.enabled
            end
        else
            -- 兼容旧版纯数组格式
            for i, val in ipairs(data) do
                if bands[i] and type(val) == "number" then
                    bands[i].val = val
                end
            end
        end
        apply_audio_eq()
    end
end

-- 实时更新鼠标坐标并做矩阵映射 (物理 ➔ 虚拟)
local function update_mouse_pos()
    local m = mp.get_property_native("mouse-pos")
    local osd = mp.get_property_native("osd-dimensions")
    if m and osd and osd.w > 0 and osd.h > 0 then
        mouse.x = m.x
        mouse.y = m.y
        mouse.vx = m.x * (BASE_W / osd.w)
        mouse.vy = m.y * (BASE_H / osd.h)
    end
end

-- 贝塞尔绘制圆角矩形路径
local function draw_round_rect(x, y, w, h, r)
    r = math.min(r, w / 2, h / 2)
    local k = 0.55228 * r
    return string.format(
        "m %f %f l %f %f b %f %f %f %f %f %f l %f %f b %f %f %f %f %f %f l %f %f b %f %f %f %f %f %f l %f %f b %f %f %f %f %f %f ",
        x + r, y,
        x + w - r, y,
        x + w - r + k, y,  x + w, y + r - k,  x + w, y + r,
        x + w, y + h - r,
        x + w, y + h - r + k,  x + w - r + k, y + h,  x + w - r, y + h,
        x + r, y + h,
        x + r - k, y + h,  x, y + h - r + k,  x, y + h - r,
        x, y + r,
        x, y + r - k,  x + r - k, y,  x + r, y
    )
end

-- 贝塞尔绘制圆形
local function draw_circle(x, y, r)
    local k = 0.55228 * r
    return string.format(
        "m %f %f b %f %f %f %f %f %f b %f %f %f %f %f %f b %f %f %f %f %f %f b %f %f %f %f %f %f ",
        x, y - r, 
        x + k, y - r, x + r, y - k, x + r, y, 
        x + r, y + k, x + k, y + r, x, y + r, 
        x - k, y + r, x - r, y + k, x - r, y, 
        x - r, y - k, x - k, y - r, x, y - r
    )
end

-- 核心渲染逻辑
local function render()
    if not is_visible then return end

    local osd = mp.get_property_native("osd-dimensions")
    if not osd or osd.w == 0 or osd.h == 0 then return end

    overlay.res_x = BASE_W
    overlay.res_y = BASE_H

    ui.px = math.floor((BASE_W - PANEL_W) / 2)
    ui.py = math.floor((BASE_H - PANEL_H) / 2)
    local px, py = ui.px, ui.py

    btns.save.x = px + PANEL_W - 145
    btns.save.y = py + PANEL_H - 52
    btns.reset.x = btns.save.x - 135
    btns.reset.y = py + PANEL_H - 52

    btns.close.x = px + PANEL_W - 44
    btns.close.y = py + 12

    btns.toggle.x = btns.close.x - 56
    btns.toggle.y = py + 17

    local ass = ""

    -- 1. 弹窗背景底板 (14px 圆角)
    local panel_path = draw_round_rect(px, py, PANEL_W, PANEL_H, 14)
    ass = ass .. string.format("{\\pos(0,0)\\an7\\p1\\1c%s\\1a&H0F&\\3c&H555555&\\bord2}%s{\\p0}\n", colors.bg, panel_path)

    -- 2. 标题
    ass = ass .. string.format("{\\pos(%d,%d)\\an7\\fs20\\1c%s\\b1} Equalizer{\\b0}\n", px + 20, py + 18, colors.text_hi)

    -- 3. 右上角“✕”关闭按钮
    local close_hover = (mouse.vx >= btns.close.x and mouse.vx <= btns.close.x + btns.close.w and mouse.vy >= btns.close.y and mouse.vy <= btns.close.y + btns.close.h)
    local close_path = draw_round_rect(btns.close.x, btns.close.y, btns.close.w, btns.close.h, btns.close.radius)
    
    if close_hover then
        ass = ass .. string.format("{\\pos(0,0)\\an7\\p1\\1c%s\\bord0}%s{\\p0}\n", colors.close_hover, close_path)
    end
    ass = ass .. string.format("{\\pos(%d,%d)\\an5\\fs20\\1c%s\\b1}%s{\\b0}\n",
        btns.close.x + btns.close.w / 2, btns.close.y + btns.close.h / 2, close_hover and colors.text_hi or colors.text, btns.close.label)

    -- 4. 极简胶囊开关 (无文字 uosc/iOS 风格)
    local toggle_hover = (mouse.vx >= btns.toggle.x and mouse.vx <= btns.toggle.x + btns.toggle.w and mouse.vy >= btns.toggle.y and mouse.vy <= btns.toggle.y + btns.toggle.h)
    
    local pill_color, knob_color
    if eq_enabled then
        pill_color = toggle_hover and colors.hover or colors.active
        knob_color = colors.text_hi
    else
        pill_color = toggle_hover and "&H555555&" or "&H333333&"
        knob_color = toggle_hover and "&HABABAB&" or "&H888888&"
    end

    local toggle_path = draw_round_rect(btns.toggle.x, btns.toggle.y, btns.toggle.w, btns.toggle.h, btns.toggle.radius)
    ass = ass .. string.format("{\\pos(0,0)\\an7\\p1\\1c%s\\bord0}%s{\\p0}\n", pill_color, toggle_path)

    local knob_x = eq_enabled and (btns.toggle.x + btns.toggle.w - 11) or (btns.toggle.x + 11)
    local knob_y = btns.toggle.y + btns.toggle.h / 2
    local knob_path = draw_circle(knob_x, knob_y, 8)
    ass = ass .. string.format("{\\pos(0,0)\\an7\\p1\\1c%s\\bord0}%s{\\p0}\n", knob_color, knob_path)

    -- 5. 刻度参考线
    local line_y_15 = py + 75
    local line_y_m15 = py + PANEL_H - 95
    local line_y_0 = line_y_15 + (line_y_m15 - line_y_15) / 2

    local line_fmt = "{\\pos(0,0)\\an7\\p1\\1c%s\\1a&H88&}m %d %d l %d %d l %d %d l %d %d{\\p0}\n"
    ass = ass .. string.format(line_fmt, colors.line, px + 45, line_y_15 - 1, px + PANEL_W - 45, line_y_15 - 1, px + PANEL_W - 45, line_y_15, px + 45, line_y_15)
    ass = ass .. string.format(line_fmt, colors.line, px + 45, line_y_0 - 1, px + PANEL_W - 45, line_y_0 - 1, px + PANEL_W - 45, line_y_0, px + 45, line_y_0)
    ass = ass .. string.format(line_fmt, colors.line, px + 45, line_y_m15 - 1, px + PANEL_W - 45, line_y_m15 - 1, px + PANEL_W - 45, line_y_m15, px + 45, line_y_m15)

    ass = ass .. string.format("{\\pos(%d,%d)\\an6\\fs12\\1c%s\\b1}+15dB{\\b0}\n", px + 40, line_y_15, colors.text_hi)
    ass = ass .. string.format("{\\pos(%d,%d)\\an6\\fs12\\1c%s\\b1}-15dB{\\b0}\n", px + 40, line_y_m15, colors.text_hi)

    -- 6. 10 段推子渲染 (关闭时呈现暗灰色，开启时亮起)
    local gap = (PANEL_W - 90) / #bands
    local start_x = px + 45 + gap / 2

    for i, b in ipairs(bands) do
        local sx = start_x + (i - 1) * gap
        local val_clamped = math.max(-15, math.min(15, b.val))
        local sy = line_y_0 - (val_clamped / 15) * ((line_y_m15 - line_y_15) / 2)

        local is_active = (i == ui.dragging_band or i == ui.hover_band or i == ui.selected_band)
        
        local act_color
        if not eq_enabled then
            act_color = "&H666666&"
        else
            act_color = is_active and colors.hover or colors.active
        end

        -- 轨道底色
        ass = ass .. string.format("{\\pos(0,0)\\an7\\p1\\1c%s\\1a&H00&}m %d %d l %d %d l %d %d l %d %d{\\p0}\n",
            colors.track, sx - 3, line_y_15, sx + 3, line_y_15, sx + 3, line_y_m15, sx - 3, line_y_m15)

        -- 动态增益填充条
        ass = ass .. string.format("{\\pos(0,0)\\an7\\p1\\1c%s\\1a&H00&}m %d %d l %d %d l %d %d l %d %d{\\p0}\n",
            act_color, sx - 3, line_y_0, sx + 3, line_y_0, sx + 3, sy, sx - 3, sy)

        -- 推进把手
        local ring = draw_circle(sx, sy, is_active and 11 or 9)
        local inner = draw_circle(sx, sy, is_active and 5 or 4)
        ass = ass .. string.format("{\\pos(0,0)\\an7\\p1\\1c%s\\3c%s\\bord3\\1a&H00&}%s{\\p0}\n", colors.bg, act_color, ring)
        ass = ass .. string.format("{\\pos(0,0)\\an7\\p1\\1c%s\\bord0}%s{\\p0}\n", act_color, inner)

        -- 数值与频段标签
        ass = ass .. string.format("{\\pos(%d,%d)\\an2\\fs13\\1c%s\\b1}%.1f{\\b0}\n", sx, line_y_15 - 12, colors.text_hi, b.val)
        ass = ass .. string.format("{\\pos(%d,%d)\\an8\\fs13\\1c%s\\b1}%s{\\b0}\n", sx, line_y_m15 + 12, is_active and colors.text_hi or colors.text, b.label)
    end

    -- 7. 底部胶囊按钮绘制
    local reset_hover = (mouse.vx >= btns.reset.x and mouse.vx <= btns.reset.x + btns.reset.w and mouse.vy >= btns.reset.y and mouse.vy <= btns.reset.y + btns.reset.h)
    local save_hover = (mouse.vx >= btns.save.x and mouse.vx <= btns.save.x + btns.save.w and mouse.vy >= btns.save.y and mouse.vy <= btns.save.y + btns.save.h)

    -- 重置按钮
    local reset_path = draw_round_rect(btns.reset.x, btns.reset.y, btns.reset.w, btns.reset.h, btns.reset.radius)
    ass = ass .. string.format("{\\pos(0,0)\\an7\\p1\\1c%s\\3c%s\\bord1}%s{\\p0}\n", reset_hover and colors.btn_hover or colors.btn, colors.btn_border, reset_path)
    ass = ass .. string.format("{\\pos(%d,%d)\\an5\\fs14\\1c%s}%s\n", btns.reset.x + btns.reset.w/2, btns.reset.y + btns.reset.h/2, colors.text_hi, btns.reset.label)

    -- 保存按钮
    local save_path = draw_round_rect(btns.save.x, btns.save.y, btns.save.w, btns.save.h, btns.save.radius)
    ass = ass .. string.format("{\\pos(0,0)\\an7\\p1\\1c%s\\3c%s\\bord1}%s{\\p0}\n", save_hover and colors.btn_hover or colors.btn, colors.btn_border, save_path)
    ass = ass .. string.format("{\\pos(%d,%d)\\an5\\fs14\\1c%s}%s\n", btns.save.x + btns.save.w/2, btns.save.y + btns.save.h/2, colors.active, btns.save.label)

    overlay.data = ass
    overlay:update()
end

-- 根据虚拟 Y 坐标计算增益值
local function calc_gain_from_vy(vy)
    local line_y_15 = ui.py + 75
    local line_y_m15 = ui.py + PANEL_H - 95
    local line_y_0 = line_y_15 + (line_y_m15 - line_y_15) / 2
    local half_h = (line_y_m15 - line_y_15) / 2

    local val = (line_y_0 - vy) / half_h * 15
    val = math.max(-15, math.min(15, val))
    return math.floor(val * 2 + 0.5) / 2
end

-- 检测鼠标悬停在哪个频段
local function check_hover_band()
    local gap = (PANEL_W - 90) / #bands
    local start_x = ui.px + 45 + gap / 2

    local hit_top = ui.py + 45
    local hit_bottom = ui.py + PANEL_H - 65

    ui.hover_band = nil
    for i, _ in ipairs(bands) do
        local sx = start_x + (i - 1) * gap
        if mouse.vx >= sx - (gap/2) and mouse.vx <= sx + (gap/2) and 
           mouse.vy >= hit_top and mouse.vy <= hit_bottom then
            ui.hover_band = i
            break
        end
    end
end

local toggle_ui

-- 鼠标左键按下
local function on_mouse_down()
    if not is_visible then return end
    update_mouse_pos()
    mouse.down = true

    -- 点击右上角“✕”关闭按钮
    if mouse.vx >= btns.close.x and mouse.vx <= btns.close.x + btns.close.w and
       mouse.vy >= btns.close.y and mouse.vy <= btns.close.y + btns.close.h then
        toggle_ui()
        return
    end

    -- 点击胶囊开关按钮
    if mouse.vx >= btns.toggle.x and mouse.vx <= btns.toggle.x + btns.toggle.w and
       mouse.vy >= btns.toggle.y and mouse.vy <= btns.toggle.y + btns.toggle.h then
        eq_enabled = not eq_enabled
        apply_audio_eq()
        render()
        return
    end

    -- 点击重置按钮
    if mouse.vx >= btns.reset.x and mouse.vx <= btns.reset.x + btns.reset.w and
       mouse.vy >= btns.reset.y and mouse.vy <= btns.reset.y + btns.reset.h then
        for _, b in ipairs(bands) do b.val = 0 end
        apply_audio_eq()
        render()
        return
    end

    -- 点击保存按钮 (写盘并关闭)
    if mouse.vx >= btns.save.x and mouse.vx <= btns.save.x + btns.save.w and
       mouse.vy >= btns.save.y and mouse.vy <= btns.save.y + btns.save.h then
        save_config()
        toggle_ui()
        return
    end

    -- 推子点击与拖拽锁
    check_hover_band()
    if ui.hover_band then
        ui.dragging_band = ui.hover_band
        ui.selected_band = ui.hover_band
        bands[ui.dragging_band].val = calc_gain_from_vy(mouse.vy)
        apply_audio_eq()
        render()
    end
end

-- 鼠标左键抬起
local function on_mouse_up()
    mouse.down = false
    ui.dragging_band = nil
    render()
end

-- 鼠标右键点击 (重置单个频段)
local function on_right_click()
    if not is_visible then return end
    update_mouse_pos()
    check_hover_band()
    if ui.hover_band then
        bands[ui.hover_band].val = 0
        apply_audio_eq()
        render()
    end
end

-- 滚轮调节
local function on_wheel(delta)
    if not is_visible then return end
    local idx = ui.hover_band or ui.selected_band
    if idx then
        local new_val = math.max(-15, math.min(15, bands[idx].val + delta * 0.5))
        bands[idx].val = new_val
        apply_audio_eq()
        render()
    end
end

-- 键盘方向键调节
local function on_key_nav(dir)
    if not is_visible then return end
    if dir == "left" then
        ui.selected_band = math.max(1, ui.selected_band - 1)
    elseif dir == "right" then
        ui.selected_band = math.min(#bands, ui.selected_band + 1)
    elseif dir == "up" then
        bands[ui.selected_band].val = math.min(15, bands[ui.selected_band].val + 0.5)
        apply_audio_eq()
    elseif dir == "down" then
        bands[ui.selected_band].val = math.max(-15, bands[ui.selected_band].val - 0.5)
        apply_audio_eq()
    end
    render()
end

-- 高频监听鼠标移动
mp.observe_property("mouse-pos", "native", function(name, val)
    if not is_visible or not val then return end
    update_mouse_pos()

    if mouse.down and ui.dragging_band then
        bands[ui.dragging_band].val = calc_gain_from_vy(mouse.vy)
        apply_audio_eq()
    else
        check_hover_band()
    end
    render()
end)

-- 监听分辨率/窗口大小改变
mp.observe_property("osd-dimensions", "native", function()
    if is_visible then render() end
end)

-- 关键事件绑定：播放器装载文件时，自动加载本地保存的配置文件
mp.register_event("file-loaded", function()
    load_config()
end)

-- UI 显示/隐藏切换
toggle_ui = function()
    is_visible = not is_visible
    if is_visible then
        update_mouse_pos()

        -- 独占按键与屏蔽冲突行为
        mp.add_forced_key_binding("MBTN_LEFT", "eq-click", function(t)
            if t.event == "down" then on_mouse_down()
            elseif t.event == "up" then on_mouse_up() end
        end, {complex = true})

        mp.add_forced_key_binding("MBTN_LEFT_DBL", "eq-dblclick-block", function() end)
        mp.add_forced_key_binding("MBTN_RIGHT", "eq-right-click", on_right_click)

        -- 滚轮与键盘绑定
        mp.add_forced_key_binding("WHEEL_UP", "eq-wheel-up", function() on_wheel(1) end)
        mp.add_forced_key_binding("WHEEL_DOWN", "eq-wheel-down", function() on_wheel(-1) end)
        
        mp.add_forced_key_binding("LEFT", "eq-left", function() on_key_nav("left") end)
        mp.add_forced_key_binding("RIGHT", "eq-right", function() on_key_nav("right") end)
        mp.add_forced_key_binding("UP", "eq-up", function() on_key_nav("up") end)
        mp.add_forced_key_binding("DOWN", "eq-down", function() on_key_nav("down") end)
        
        mp.add_forced_key_binding("ENTER", "eq-enter", function()
            save_config()
            toggle_ui()
        end)
        mp.add_forced_key_binding("r", "eq-reset", function()
            for _, b in ipairs(bands) do b.val = 0 end
            apply_audio_eq()
            render()
        end)

        render()
    else
        ui.dragging_band = nil
        mouse.down = false

        -- 解除按键独占
        mp.remove_key_binding("eq-click")
        mp.remove_key_binding("eq-dblclick-block")
        mp.remove_key_binding("eq-right-click")
        mp.remove_key_binding("eq-wheel-up")
        mp.remove_key_binding("eq-wheel-down")
        mp.remove_key_binding("eq-left")
        mp.remove_key_binding("eq-right")
        mp.remove_key_binding("eq-up")
        mp.remove_key_binding("eq-down")
        mp.remove_key_binding("eq-enter")
        mp.remove_key_binding("eq-reset")
        overlay:remove()
    end
end

-- 打开/关闭 快捷键
mp.register_script_message("toggle-equalizer-gui", toggle_ui)
-- mp.add_key_binding("e", "toggle-equalizer-gui", toggle_ui)
mp.add_key_binding("ESC", "close-equalizer-gui", function()
    if is_visible then toggle_ui() end
end)