local mp = require("mp")
local utils = require("mp.utils")

-- EQ 总开关状态 (默认开启)
local eq_enabled = false

-- 音频声道模式
-- auto   = 自动
-- stereo = 立体声
-- left   = 左声道
-- right  = 右声道
local channel_mode = "auto"

local channel_mode_labels = {
    auto = "Auto",
    stereo = "Stereo",
    left = "Left",
    right = "Right"
}

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

-- ============================================================
-- 常用 EQ 预设 (增益单位 dB, 顺序对应 bands 10 段)
-- 31.5 / 63 / 125 / 250 / 500 / 1k / 2k / 4k / 8k / 16k
-- ============================================================
local presets = {
    { name = "平直 Flat",         vals = {  0,   0,   0,   0,   0,   0,   0,   0,   0,   0 } },
    { name = "流行 Pop",          vals = { -1,   2,   4,   5,   3,   0,  -1,  -1,   1,   2 } },
    { name = "摇滚 Rock",         vals = {  5,   4,   2,   0,  -1,  -1,   1,   3,   4,   5 } },
    { name = "爵士 Jazz",         vals = {  3,   2,   1,   2,  -1,  -1,   0,   1,   2,   3 } },
    { name = "古典 Classical",    vals = {  4,   3,   2,   1,  -1,  -1,   0,   2,   3,   4 } },
    { name = "舞曲 Dance",        vals = {  6,   5,   3,   0,   0,  -2,  -3,  -2,   1,   2 } },
    { name = "嘻哈 Hip-Hop",      vals = {  5,   4,   2,   3,  -1,  -1,   1,  -1,   2,   3 } },
    { name = "人声 Vocal",        vals = { -3,  -2,  -1,   1,   4,   5,   4,   2,   0,  -1 } },
    { name = "低音增强 Bass",     vals = {  7,   6,   5,   3,   1,   0,   0,   0,   0,   0 } },
    { name = "高音增强 Treble",   vals = {  0,   0,   0,   0,   0,   1,   3,   5,   6,   7 } },
    { name = "响度 Loudness",     vals = {  6,   4,   0,  -1,  -2,  -1,   0,   2,   5,   6 } },
    { name = "原声 Acoustic",     vals = {  3,   3,   2,   1,   1,   1,   2,   3,   3,   2 } },
    { name = "金属 Metal",        vals = {  5,   4,   3,   0,  -2,  -1,   1,   3,   5,   6 } },
    { name = "电子 Electronic",   vals = {  4,   3,   2,   0,  -2,   2,   1,   2,   4,   5 } },
}

-- 当前选中的预设索引 (nil = 自定义)
local current_preset = nil

-- 通过当前曲线反查匹配的预设 (允许 ±0.01 浮点误差)
local function detect_preset()
    for i, p in ipairs(presets) do
        local match = true
        for j = 1, #bands do
            if math.abs(bands[j].val - p.vals[j]) > 0.01 then
                match = false
                break
            end
        end
        if match then return i end
    end
    return nil
end

-- 配置文件存储路径解析 (使用 mpv 标准 expand-path 接口)
local CONFIG_PATH = mp.command_native({"expand-path", "~~/script-opts/equalizer-gui.json"})
local ALT_CONFIG_PATH = mp.command_native({"expand-path", "~~/equalizer-gui.json"})

local overlay = mp.create_osd_overlay("ass-events")
local is_visible = false

-- 基准虚拟画布尺寸
local BASE_W = 1280
local PANEL_W, PANEL_H = 680, 380

-- 预设下拉列表项高度与内边距
local PRESET_ITEM_H = 22
local PRESET_PAD = 4

local ui = {
    px = 0, py = 0,
    dragging_band = nil,
    hover_band = nil,
    selected_band = 1,
    preset_open = false
}

local mouse = { x = 0, y = 0, vx = 0, vy = 0, down = false }

-- 按钮组件配置 (添加 toggle 开关 + preset 下拉)
local btns = {
    reset  = { label = "重置 (Reset)", x = 0, y = 0, w = 110, h = 36, radius = 18 },
    save   = { label = "保存 (Save)", x = 0, y = 0, w = 110, h = 36, radius = 18 },
    close  = { label = "✕",           x = 0, y = 0, w = 32,  h = 32, radius = 16 },
    toggle = { label = "",            x = 0, y = 0, w = 44,  h = 22, radius = 11 },
    preset = { label = "",            x = 0, y = 0, w = 160, h = 36, radius = 18 }
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

-- 获取当前声道模式对应的 pan 滤镜
local function get_channel_filter()
    if channel_mode == "left" then
        return "pan=stereo|c0=c0|c1=c0"
    elseif channel_mode == "right" then
        return "pan=stereo|c0=c1|c1=c1"
    end
    return nil
end

-- 应用音频 EQ + 声道模式到 mpv 引擎
local function apply_audio_eq()
    local codec = (mp.get_property("audio-codec-name") or ""):lower()
    local sample_rate_text = mp.get_property("audio-params/samplerate")
    local sample_rate = tonumber(sample_rate_text)
    if not sample_rate and sample_rate_text then
        sample_rate = tonumber(tostring(sample_rate_text):match("(%d+)"))
    end
    local replaygain = (mp.get_property("replaygain") or "no"):lower()

    local is_dsd = codec:find("dsd", 1, true) ~= nil
    if is_dsd then
        local channel_filter = get_channel_filter()
        if channel_filter then
            mp.commandv("af", "set", "@eq_gui:lavfi=[" .. channel_filter .. "]")
        else
            mp.commandv("af", "remove", "@eq_gui")
        end
        return
    end

    if channel_mode == "auto" then
        mp.set_property("audio-channels", "auto")
    else
        mp.set_property("audio-channels", "stereo")
    end

    local channel_filter = get_channel_filter()

    if not eq_enabled then
        if channel_filter then
            mp.commandv("af", "set", "@eq_gui:lavfi=[" .. channel_filter .. "]")
        else
            mp.commandv("af", "remove", "@eq_gui")
        end
        return
    end

    local filters = {}
    local max_positive_gain = 0
    local nyquist = sample_rate and sample_rate > 0 and sample_rate / 2 or nil

    for i, b in ipairs(bands) do
        local freq = tonumber(b.freq)
        local above_nyquist = nyquist and freq and freq >= nyquist
        local low_rate_16k = sample_rate and sample_rate < 44100 and i == #bands
        local unsafe_unknown_rate = (not nyquist) and i == #bands
        if not above_nyquist and not low_rate_16k and not unsafe_unknown_rate then
            table.insert(filters, string.format("equalizer=f=%s:width_type=o:w=1:g=%.1f", b.freq, b.val))
            if b.val > max_positive_gain then
                max_positive_gain = b.val
            end
        end
    end

    local rg_enabled = replaygain ~= "no" and replaygain ~= "false"
        and replaygain ~= "off" and replaygain ~= ""
    local headroom_db = max_positive_gain
    if rg_enabled and headroom_db > 0 then
        headroom_db = headroom_db + 6
    end
    if headroom_db > 0 then
        table.insert(filters, 1, string.format("volume=%.2fdB", -headroom_db))
    end

    if channel_filter then
        table.insert(filters, channel_filter)
    end

    if #filters == 0 then
        mp.commandv("af", "remove", "@eq_gui")
        return
    end

    local filter_str = "@eq_gui:lavfi=[" .. table.concat(filters, ",") .. "]"
    mp.commandv("af", "set", filter_str)
end

local function set_channel_mode(mode)
    if not channel_mode_labels[mode] then return end
    channel_mode = mode
    apply_audio_eq()
    mp.osd_message("Audio Channel: " .. channel_mode_labels[mode], 2)
end

local function save_config()
    local band_vals = {}
    for i, b in ipairs(bands) do band_vals[i] = b.val end
    local data = { enabled = eq_enabled, bands = band_vals }
    local json_str, _ = utils.format_json(data)
    if json_str then
        local file = io.open(CONFIG_PATH, "w")
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

local function load_config()
    local file = io.open(CONFIG_PATH, "r")
    if not file then file = io.open(ALT_CONFIG_PATH, "r") end
    if not file then return end
    local content = file:read("*a")
    file:close()
    if not content or content == "" then return end
    local data, _ = utils.parse_json(content)
    if data and type(data) == "table" then
        if data.bands and type(data.bands) == "table" then
            for i, val in ipairs(data.bands) do
                if bands[i] and type(val) == "number" then bands[i].val = val end
            end
            if type(data.enabled) == "boolean" then eq_enabled = data.enabled end
        else
            for i, val in ipairs(data) do
                if bands[i] and type(val) == "number" then bands[i].val = val end
            end
        end
        current_preset = detect_preset()
        apply_audio_eq()
    end
end

local function update_mouse_pos()
    local m = mp.get_property_native("mouse-pos")
    local osd = mp.get_property_native("osd-dimensions")
    if m and osd and osd.w > 0 and osd.h > 0 then
        mouse.x = m.x
        mouse.y = m.y
        local virtual_h = BASE_W * osd.h / osd.w
        mouse.vx = m.x * (BASE_W / osd.w)
        mouse.vy = m.y * (virtual_h / osd.h)
    end
end

local function draw_round_rect(x, y, w, h, r)
    r = math.min(r, w / 2, h / 2)
    local k = 0.55228 * r
    return string.format(
        "m %f %f l %f %f b %f %f %f %f %f %f l %f %f b %f %f %f %f %f %f l %f %f b %f %f %f %f %f %f l %f %f b %f %f %f %f %f %f ",
        x + r, y, x + w - r, y, x + w - r + k, y,  x + w, y + r - k,  x + w, y + r,
        x + w, y + h - r, x + w, y + h - r + k,  x + w - r + k, y + h,  x + w - r, y + h,
        x + r, y + h, x + r - k, y + h,  x, y + h - r + k,  x, y + h - r,
        x, y + r, x, y + r - k,  x + r - k, y,  x + r, y
    )
end

local function draw_circle(x, y, r)
    local k = 0.55228 * r
    return string.format(
        "m %f %f b %f %f %f %f %f %f b %f %f %f %f %f %f b %f %f %f %f %f %f b %f %f %f %f %f %f ",
        x, y - r, x + k, y - r, x + r, y - k, x + r, y, x + r, y + k, x + k, y + r, x, y + r,
        x - k, y + r, x - r, y + k, x - r, y, x - r, y - k, x - k, y - r, x, y - r
    )
end

local function get_preset_list_geom()
    local n = #presets
    local w = btns.preset.w
    local h = n * PRESET_ITEM_H + PRESET_PAD * 2
    local x = btns.preset.x
    local y = btns.preset.y - 6 - h
    return x, y, w, h
end

local function hit_preset_item(vx, vy)
    if not ui.preset_open then return nil end
    local lx, ly, lw = get_preset_list_geom()
    if vx < lx or vx > lx + lw then return nil end
    for i = 1, #presets do
        local iy = ly + PRESET_PAD + (i - 1) * PRESET_ITEM_H
        if vy >= iy and vy <= iy + PRESET_ITEM_H then return i end
    end
    return nil
end

local function render()
    if not is_visible then return end

    local osd = mp.get_property_native("osd-dimensions")
    if not osd or osd.w == 0 or osd.h == 0 then return end

    local virtual_h = BASE_W * osd.h / osd.w
    overlay.res_x = BASE_W
    overlay.res_y = math.floor(virtual_h + 0.5)

    ui.px = math.floor((BASE_W - PANEL_W) / 2)
    ui.py = math.floor((virtual_h - PANEL_H) / 2)
    local px, py = ui.px, ui.py

    local btn_gap = 16
    btns.preset.x = px + PANEL_W - 432
    btns.reset.x = btns.preset.x + btns.preset.w + btn_gap
    btns.save.x = btns.reset.x + btns.reset.w + btn_gap
    btns.preset.y = py + PANEL_H - 52
    btns.reset.y = py + PANEL_H - 52
    btns.save.y = py + PANEL_H - 52
    btns.close.x = px + PANEL_W - 44
    btns.close.y = py + 12
    btns.toggle.x = btns.close.x - 56
    btns.toggle.y = py + 17

    local ass = ""

    -- 1. 弹窗背景底板
    local panel_path = draw_round_rect(px, py, PANEL_W, PANEL_H, 14)
    ass = ass .. string.format("{\\pos(0,0)\\an7\\p1\\1c%s\\1a&H0F&\\3c&H555555&\\bord2}%s{\\p0}\n", colors.bg, panel_path)

    -- 2. 标题 (强制取消粗体和边框)
    ass = ass .. string.format("{\\pos(%d,%d)\\an7\\fs20\\1c%s\\b1\\bord0\\shad0} Equalizer{\\b0}\n", px + 20, py + 18, colors.text_hi)

    -- 3. 关闭按钮
    local close_hover = (mouse.vx >= btns.close.x and mouse.vx <= btns.close.x + btns.close.w and mouse.vy >= btns.close.y and mouse.vy <= btns.close.y + btns.close.h)
    local close_path = draw_round_rect(btns.close.x, btns.close.y, btns.close.w, btns.close.h, btns.close.radius)
    if close_hover then
        ass = ass .. string.format("{\\pos(0,0)\\an7\\p1\\1c%s\\bord0}%s{\\p0}\n", colors.close_hover, close_path)
    end
    ass = ass .. string.format("{\\pos(%d,%d)\\an5\\fs20\\1c%s\\b1\\bord0\\shad0}%s{\\b0}\n",
        btns.close.x + btns.close.w / 2, btns.close.y + btns.close.h / 2, close_hover and colors.text_hi or colors.text, btns.close.label)

    -- 4. 胶囊开关
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

    local line_fmt = "{\\pos(0,0)\\an7\\p1\\1c%s\\1a&H88&\\bord0}m %d %d l %d %d l %d %d l %d %d{\\p0}\n"
    ass = ass .. string.format(line_fmt, colors.line, px + 45, line_y_15 - 1, px + PANEL_W - 45, line_y_15 - 1, px + PANEL_W - 45, line_y_15, px + 45, line_y_15)
    ass = ass .. string.format(line_fmt, colors.line, px + 45, line_y_0 - 1, px + PANEL_W - 45, line_y_0 - 1, px + PANEL_W - 45, line_y_0, px + 45, line_y_0)
    ass = ass .. string.format(line_fmt, colors.line, px + 45, line_y_m15 - 1, px + PANEL_W - 45, line_y_m15 - 1, px + PANEL_W - 45, line_y_m15, px + 45, line_y_m15)

    -- 刻度文字
    ass = ass .. string.format("{\\pos(%d,%d)\\an6\\fs12\\1c%s\\b1\\bord0\\shad0}+15dB{\\b0}\n", px + 40, line_y_15, colors.text_hi)
    ass = ass .. string.format("{\\pos(%d,%d)\\an6\\fs12\\1c%s\\b1\\bord0\\shad0}-15dB{\\b0}\n", px + 40, line_y_m15, colors.text_hi)

    -- 6. 推子渲染
    local gap = (PANEL_W - 90) / #bands
    local start_x = px + 45 + gap / 2

    for i, b in ipairs(bands) do
        local sx = start_x + (i - 1) * gap
        local val_clamped = math.max(-15, math.min(15, b.val))
        local sy = line_y_0 - (val_clamped / 15) * ((line_y_m15 - line_y_15) / 2)
        local is_active = (i == ui.dragging_band or i == ui.hover_band or i == ui.selected_band)
        local act_color = not eq_enabled and "&H666666&" or (is_active and colors.hover or colors.active)

        ass = ass .. string.format("{\\pos(0,0)\\an7\\p1\\1c%s\\3c%s\\bord0\\1a&H00&}m %d %d l %d %d l %d %d l %d %d{\\p0}\n",
            colors.track, colors.track, sx - 3, line_y_15, sx + 3, line_y_15, sx + 3, line_y_m15, sx - 3, line_y_m15)
        ass = ass .. string.format("{\\pos(0,0)\\an7\\p1\\1c%s\\bord0\\1a&H00&}m %d %d l %d %d l %d %d l %d %d{\\p0}\n",
            act_color, sx - 3, line_y_0, sx + 3, line_y_0, sx + 3, sy, sx - 3, sy)

        local ring = draw_circle(sx, sy, is_active and 11 or 9)
        local inner = draw_circle(sx, sy, is_active and 5 or 4)
        ass = ass .. string.format("{\\pos(0,0)\\an7\\p1\\1c%s\\3c%s\\bord3\\1a&H00&}%s{\\p0}\n", colors.bg, act_color, ring)
        ass = ass .. string.format("{\\pos(0,0)\\an7\\p1\\1c%s\\bord0}%s{\\p0}\n", act_color, inner)

        -- 数值与频段标签 (强制取消边框和阴影，正确复位粗体)
        ass = ass .. string.format("{\\pos(%d,%d)\\an2\\fs13\\1c%s\\b1\\bord0\\shad0}%.1f{\\b0}\n", sx, line_y_15 - 12, colors.text_hi, b.val)
        ass = ass .. string.format("{\\pos(%d,%d)\\an8\\fs13\\1c%s\\b1\\bord0\\shad0}%s{\\b0}\n", sx, line_y_m15 + 12, is_active and colors.text_hi or colors.text, b.label)
    end

    -- 7. 底部按钮
    local reset_hover = (mouse.vx >= btns.reset.x and mouse.vx <= btns.reset.x + btns.reset.w and mouse.vy >= btns.reset.y and mouse.vy <= btns.reset.y + btns.reset.h)
    local save_hover = (mouse.vx >= btns.save.x and mouse.vx <= btns.save.x + btns.save.w and mouse.vy >= btns.save.y and mouse.vy <= btns.save.y + btns.save.h)

    local reset_path = draw_round_rect(btns.reset.x, btns.reset.y, btns.reset.w, btns.reset.h, btns.reset.radius)
    ass = ass .. string.format("{\\pos(0,0)\\an7\\p1\\1c%s\\3c%s\\bord1}%s{\\p0}\n", reset_hover and colors.btn_hover or colors.btn, colors.btn_border, reset_path)
    ass = ass .. string.format("{\\pos(%d,%d)\\an5\\fs14\\1c%s\\bord0\\shad0}%s\n", btns.reset.x + btns.reset.w/2, btns.reset.y + btns.reset.h/2, colors.text_hi, btns.reset.label)

    local save_path = draw_round_rect(btns.save.x, btns.save.y, btns.save.w, btns.save.h, btns.save.radius)
    ass = ass .. string.format("{\\pos(0,0)\\an7\\p1\\1c%s\\3c%s\\bord1}%s{\\p0}\n", save_hover and colors.btn_hover or colors.btn, colors.btn_border, save_path)
    ass = ass .. string.format("{\\pos(%d,%d)\\an5\\fs14\\1c%s\\bord0\\shad0}%s\n", btns.save.x + btns.save.w/2, btns.save.y + btns.save.h/2, colors.active, btns.save.label)

    -- 8. 预设下拉
    local preset_hover = (mouse.vx >= btns.preset.x and mouse.vx <= btns.preset.x + btns.preset.w and
                          mouse.vy >= btns.preset.y and mouse.vy <= btns.preset.y + btns.preset.h)

    local preset_path = draw_round_rect(btns.preset.x, btns.preset.y, btns.preset.w, btns.preset.h, btns.preset.radius)
    local preset_bg = (preset_hover or ui.preset_open) and colors.btn_hover or colors.btn
    ass = ass .. string.format("{\\pos(0,0)\\an7\\p1\\1c%s\\3c%s\\bord1}%s{\\p0}\n", preset_bg, colors.btn_border, preset_path)

    local preset_name = current_preset and presets[current_preset].name or "自定义 Custom"
    ass = ass .. string.format("{\\pos(%d,%d)\\an5\\fs14\\1c%s\\bord0\\shad0}%s\n", btns.preset.x + btns.preset.w / 2 - 8, btns.preset.y + btns.preset.h / 2, colors.text_hi, preset_name)

    local aax = btns.preset.x + btns.preset.w - 18
    local aay = btns.preset.y + btns.preset.h / 2 - 1
    local arrow = string.format("m %f %f l %f %f l %f %f ", aax - 5, aay - 2, aax + 5, aay - 2, aax, aay + 4)
    ass = ass .. string.format("{\\pos(0,0)\\an7\\p1\\1c%s\\bord0}%s{\\p0}\n", colors.text, arrow)

    -- 9. 下拉列表
    if ui.preset_open then
        local lx, ly, lw, lh = get_preset_list_geom()
        local list_path = draw_round_rect(lx, ly, lw, lh, 10)
        ass = ass .. string.format("{\\pos(0,0)\\an7\\p1\\1c%s\\3c%s\\bord1\\1a&H08&}%s{\\p0}\n", colors.bg, colors.btn_border, list_path)

        for i, p in ipairs(presets) do
            local iy = ly + PRESET_PAD + (i - 1) * PRESET_ITEM_H
            local hov = (mouse.vx >= lx and mouse.vx <= lx + lw and mouse.vy >= iy and mouse.vy <= iy + PRESET_ITEM_H)

            if hov then
                local hpath = draw_round_rect(lx + 3, iy + 1, lw - 6, PRESET_ITEM_H - 2, 6)
                ass = ass .. string.format("{\\pos(0,0)\\an7\\p1\\1c%s\\bord0\\1a&H50&}%s{\\p0}\n", colors.active, hpath)
            end

            local col = colors.text
            if current_preset == i then col = colors.active
            elseif hov then col = colors.text_hi end

            ass = ass .. string.format("{\\pos(%d,%d)\\an4\\fs14\\1c%s\\bord0\\shad0}%s\n", lx + 14, iy + PRESET_ITEM_H / 2, col, p.name)
        end
    end

    overlay.data = ass
    overlay:update()
end

local function calc_gain_from_vy(vy)
    local line_y_15 = ui.py + 75
    local line_y_m15 = ui.py + PANEL_H - 95
    local line_y_0 = line_y_15 + (line_y_m15 - line_y_15) / 2
    local half_h = (line_y_m15 - line_y_15) / 2
    local val = (line_y_0 - vy) / half_h * 15
    val = math.max(-15, math.min(15, val))
    return math.floor(val * 2 + 0.5) / 2
end

local function apply_preset(idx)
    local p = presets[idx]
    if not p then return end
    for i = 1, #bands do bands[i].val = p.vals[i] or 0 end
    current_preset = idx
    apply_audio_eq()
    render()
    mp.osd_message("EQ 预设: " .. p.name, 2)
end

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

local function on_mouse_down()
    if not is_visible then return end
    update_mouse_pos()
    mouse.down = true

    local preset_btn_hit = (mouse.vx >= btns.preset.x and mouse.vx <= btns.preset.x + btns.preset.w and
                            mouse.vy >= btns.preset.y and mouse.vy <= btns.preset.y + btns.preset.h)

    if ui.preset_open then
        local idx = hit_preset_item(mouse.vx, mouse.vy)
        if idx then
            ui.preset_open = false
            apply_preset(idx)
            return
        end
        if not preset_btn_hit then
            ui.preset_open = false
            render()
        end
    end

    if preset_btn_hit then
        ui.preset_open = not ui.preset_open
        render()
        return
    end

    if mouse.vx >= btns.close.x and mouse.vx <= btns.close.x + btns.close.w and
       mouse.vy >= btns.close.y and mouse.vy <= btns.close.y + btns.close.h then
        toggle_ui()
        return
    end

    if mouse.vx >= btns.toggle.x and mouse.vx <= btns.toggle.x + btns.toggle.w and
       mouse.vy >= btns.toggle.y and mouse.vy <= btns.toggle.y + btns.toggle.h then
        eq_enabled = not eq_enabled
        apply_audio_eq()
        render()
        return
    end

    if mouse.vx >= btns.reset.x and mouse.vx <= btns.reset.x + btns.reset.w and
       mouse.vy >= btns.reset.y and mouse.vy <= btns.reset.y + btns.reset.h then
        for _, b in ipairs(bands) do b.val = 0 end
        current_preset = detect_preset()
        apply_audio_eq()
        render()
        return
    end

    if mouse.vx >= btns.save.x and mouse.vx <= btns.save.x + btns.save.w and
       mouse.vy >= btns.save.y and mouse.vy <= btns.save.y + btns.save.h then
        save_config()
        toggle_ui()
        return
    end

    check_hover_band()
    if ui.hover_band then
        ui.dragging_band = ui.hover_band
        ui.selected_band = ui.hover_band
        bands[ui.dragging_band].val = calc_gain_from_vy(mouse.vy)
        current_preset = detect_preset()
        apply_audio_eq()
        render()
    end
end

local function on_mouse_up()
    mouse.down = false
    ui.dragging_band = nil
    render()
end

local function on_right_click()
    if not is_visible then return end
    update_mouse_pos()
    check_hover_band()
    if ui.hover_band then
        bands[ui.hover_band].val = 0
        current_preset = detect_preset()
        apply_audio_eq()
        render()
    end
end

local function on_wheel(delta)
    if not is_visible then return end
    local idx = ui.hover_band or ui.selected_band
    if idx then
        local new_val = math.max(-15, math.min(15, bands[idx].val + delta * 0.5))
        bands[idx].val = new_val
        current_preset = detect_preset()
        apply_audio_eq()
        render()
    end
end

local function on_key_nav(dir)
    if not is_visible then return end
    if dir == "left" then
        ui.selected_band = math.max(1, ui.selected_band - 1)
    elseif dir == "right" then
        ui.selected_band = math.min(#bands, ui.selected_band + 1)
    elseif dir == "up" then
        bands[ui.selected_band].val = math.min(15, bands[ui.selected_band].val + 0.5)
        current_preset = detect_preset()
        apply_audio_eq()
    elseif dir == "down" then
        bands[ui.selected_band].val = math.max(-15, bands[ui.selected_band].val - 0.5)
        current_preset = detect_preset()
        apply_audio_eq()
    end
    render()
end

mp.observe_property("mouse-pos", "native", function(name, val)
    if not is_visible or not val then return end
    update_mouse_pos()
    if mouse.down and ui.dragging_band then
        bands[ui.dragging_band].val = calc_gain_from_vy(mouse.vy)
        current_preset = detect_preset()
        apply_audio_eq()
    else
        check_hover_band()
    end
    render()
end)

mp.observe_property("osd-dimensions", "native", function()
    if is_visible then render() end
end)

mp.register_event("file-loaded", function()
    load_config()
end)

toggle_ui = function()
    is_visible = not is_visible
    if is_visible then
        update_mouse_pos()
        mp.add_forced_key_binding("MBTN_LEFT", "eq-click", function(t)
            if t.event == "down" then on_mouse_down()
            elseif t.event == "up" then on_mouse_up() end
        end, {complex = true})
        mp.add_forced_key_binding("MBTN_LEFT_DBL", "eq-dblclick-block", function() end)
        mp.add_forced_key_binding("MBTN_RIGHT", "eq-right-click", on_right_click)
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
            current_preset = detect_preset()
            apply_audio_eq()
            render()
        end)
        render()
    else
        ui.dragging_band = nil
        ui.preset_open = false
        mouse.down = false
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

mp.register_script_message("toggle-equalizer-gui", toggle_ui)
mp.register_script_message("audio-channel-auto", function() set_channel_mode("auto") end)
mp.register_script_message("audio-channel-stereo", function() set_channel_mode("stereo") end)
mp.register_script_message("audio-channel-left", function() set_channel_mode("left") end)
mp.register_script_message("audio-channel-right", function() set_channel_mode("right") end)

mp.add_key_binding("ESC", "close-equalizer-gui", function()
    if not is_visible then return end
    if ui.preset_open then
        ui.preset_open = false
        render()
        return
    end
    toggle_ui()
end)