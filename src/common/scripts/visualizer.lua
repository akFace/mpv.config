-- ==============================================================================
-- visualizer.lua — 音频频谱可视化生成器
-- ==============================================================================
local options = require 'mp.options'
local assdraw = require 'mp.assdraw'

local opts = { mode = "novideo", name = "avectorscope", quality = "medium", forcewindow = true }

if not (mp.get_property("options/lavfi-complex", "") == "") then return end

-- ==============================================================================
-- ASS 文字处理辅助
-- ==============================================================================
local function escape_ass_text(str)
    str = tostring(str or ""):gsub("\\", "\\\\"):gsub("{", "\\{"):gsub("}", "\\}"):gsub("[\r\n]", " ")
    return str
end

local function utf8_chars(str)
    local chars = {}
    for char in str:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = char end
    return chars
end

local function char_width(char, font_size)
    local byte = char:byte()
    if byte and byte >= 0xE0 then return font_size end
    if char:match("[%a%d]") then return font_size * 0.55
    elseif char:match("%s") then return font_size * 0.3
    else return font_size * 0.45 end
end

local function wrap_text(str, font_size, max_width)
    local chars, lines, line, width, index = utf8_chars(str), {}, "", 0, 1
    while index <= #chars do
        local char = chars[index]
        local cw = char_width(char, font_size)
        if width + cw > max_width and line ~= "" then
            lines[#lines + 1] = line
            if #lines >= 2 then break end
            line, width = "", 0
        else
            line = line .. char
            width = width + cw
            index = index + 1
        end
    end
    local truncated = index <= #chars
    if line ~= "" and #lines < 2 then lines[#lines + 1] = line end
    if #lines == 0 then lines[1] = "" end
    
    if truncated then
        local last, ellipsis = #lines, "..."
        while #lines[last] > 0 do
            local chars_last, current_width = utf8_chars(lines[last]), 0
            for _, c in ipairs(chars_last) do current_width = current_width + char_width(c, font_size) end
            if current_width + font_size * 1.5 <= max_width then break end
            table.remove(chars_last)
            lines[last] = table.concat(chars_last)
        end
        lines[last] = lines[last] .. ellipsis
    end
    return table.concat(lines, "\\N")
end

-- ==============================================================================
-- 核心状态判断：当前是否需要绘制频谱
-- ==============================================================================
local function is_vis_needed()
    if opts.mode == "off" then return false end
    if mp.get_property_number("track-list/count", -1) <= 0 then return false end

    local atrack = mp.get_property_native("current-tracks/audio")
    local vtrack = mp.get_property_native("current-tracks/video")

    -- 兜底遍历
    if atrack == nil and vtrack == nil then
        for _, track in ipairs(mp.get_property_native("track-list")) do
            if track.type == "video" and (vtrack == nil or vtrack.albumart == true) and mp.get_property("vid") ~= "no" then
                vtrack = track
            elseif track.type == "audio" then 
                atrack = track 
            end
        end
    end

    if atrack == nil then return false end

    if opts.mode == "force" then return true end
    if opts.mode == "novideo" then
        return (vtrack == nil or vtrack.albumart)
    end
    return false
end

-- ==============================================================================
-- 核心：ASS 绘制 (黑底 + 彩虹环 + 文字)
-- ==============================================================================
local function draw_black_circle()
    -- 如果不是 avectorscope，或者当前不应显示频谱（例如正在播放真实视频），则清空 OSD
    if opts.name ~= "avectorscope" or not is_vis_needed() then
        mp.set_osd_ass(0, 0, "")
        return
    end

    local w, h = mp.get_osd_size()
    if not w or w <= 0 then return end

    local diameter = math.min(w, h) * (200 / 720)
    local r = diameter / 2
    local cx, cy = w / 2, h * 0.5
    local ass = assdraw.ass_new()

    local function rainbow_color(hue)
        local h6, rr, gg, bb = hue * 6, 0, 0, 0
        local i, f = math.floor(h6), h6 % 1
        local q, t = 1 - f, f
        if i == 0 then rr, gg, bb = 1, t, 0
        elseif i == 1 then rr, gg, bb = q, 1, 0
        elseif i == 2 then rr, gg, bb = 0, 1, t
        elseif i == 3 then rr, gg, bb = 0, q, 1
        elseif i == 4 then rr, gg, bb = t, 0, 1
        else rr, gg, bb = 1, 0, q end
        return string.format("%02X%02X%02X", math.floor(bb * 255), math.floor(gg * 255), math.floor(rr * 255))
    end

    local function draw_ring(outer_r, inner_r, alpha, segments)
        local max_r = r + 12
        local center = max_r
        local step = math.pi * 2 / segments
        for i = 0, segments - 1 do
            local color = rainbow_color(i / segments)
            local a0, a1 = i * step - 0.003, (i + 1) * step + 0.003
            ass:new_event()
            ass:pos(cx - max_r, cy - max_r)
            ass:append(string.format("{\\an7\\1c&H%s&\\1a&H%02X&\\bord0\\shad0}", color, alpha))
            ass:draw_start()
            local arc_steps = 3
            for j = 0, arc_steps do
                local a = a0 + (a1 - a0) * j / arc_steps
                local px, py = center + outer_r * math.cos(a), center + outer_r * math.sin(a)
                if j == 0 then ass:move_to(px, py) else ass:line_to(px, py) end
            end
            for j = arc_steps, 0, -1 do
                local a = a0 + (a1 - a0) * j / arc_steps
                local px, py = center + inner_r * math.cos(a), center + inner_r * math.sin(a)
                ass:line_to(px, py)
            end
            ass:draw_stop()
        end
    end

    -- 绘制光环
    draw_ring(r + 11, r - 1, 0xD0, 96)
    draw_ring(r + 7, r - 1, 0xA0, 96)

    -- 绘制中心黑圆
    ass:new_event()
    ass:pos(cx - r, cy - r)
    ass:append("{\\an7\\1c&H000000&\\1a&H00&\\bord0\\shad0}")
    local k = r * 0.5522847498
    ass:draw_start()
    ass:move_to(r, 0)
    ass:bezier_curve(r + k, 0, 2 * r, r - k, 2 * r, r)
    ass:bezier_curve(2 * r, r + k, r + k, 2 * r, r, 2 * r)
    ass:bezier_curve(r - k, 2 * r, 0, r + k, 0, r)
    ass:bezier_curve(0, r - k, r - k, 0, r, 0)
    ass:draw_stop()
    draw_ring(r + 2, r - 2, 0x00, 120)

    -- 绘制文字
    local title = mp.get_property("metadata/by-key/title", "")
    local artist = mp.get_property("metadata/by-key/artist", "")
    if title == "" then title = (mp.get_property("filename", "Unknown"):gsub("%.[^%.]+$", "")) end
    if artist == "" then artist = "Unknown Artist" end
    title, artist = escape_ass_text(title), escape_ass_text(artist)

    local title_size = math.max(12, math.floor(diameter * 0.08))
    local artist_size = math.max(10, math.floor(diameter * 0.055))
    local text_max_width = diameter * 0.82

    local title_text = wrap_text(title, title_size, text_max_width)
    local artist_text = wrap_text(artist, artist_size, text_max_width)
    local title_lines = select(2, title_text:gsub("\\N", "")) + 1
    local artist_lines = select(2, artist_text:gsub("\\N", "")) + 1
    local title_h = title_size * 1.2 * title_lines
    local artist_h = artist_size * 1.2 * artist_lines

    local spacing = diameter * 0.045
    local total_h = title_h + spacing + artist_h
    local title_y = cy - total_h / 2 + title_h / 2
    local artist_y = cy - total_h / 2 + title_h + spacing + artist_h / 2

    ass:new_event()
    ass:pos(cx, title_y)
    ass:append(string.format("{\\an5\\fnArial\\fs%d\\1c&HFFFFFF&\\1a&H00&\\bord0\\shad0}%s", title_size, title_text))
    ass:new_event()
    ass:pos(cx, artist_y)
    ass:append(string.format("{\\an5\\fnArial\\fs%d\\1c&HFFFFFF&\\1a&H00&\\bord0\\shad0}%s", artist_size, artist_text))

    mp.set_osd_ass(w, h, ass.text)
end

-- ==============================================================================
-- 可视化滤镜生成
-- ==============================================================================
local visualizer_name_list = { "avectorscope", "showfreqs", "linefreqs", "off" }

local function get_visualizer(name, quality)
    local w, fps
    if quality == "verylow" then w = 640; fps = 30
    elseif quality == "low" then w = 960; fps = 30
    elseif quality == "medium" then w = 1280; fps = 60
    elseif quality == "high" then w = 1920; fps = 60
    elseif quality == "veryhigh" then w = 2560; fps = 60
    else w = 1280; fps = 60 end
    local h = math.floor(w * 9 / 16)

    local spec_w, spec_h = w, math.floor(h * 0.45)
    local x, y = math.floor((w - spec_w) / 2), math.floor(h * 0.7 - spec_h / 2)
    if y < 0 then y = 0 end

    if name == "showfreqs" then
        return string.format("[aid1] asplit [ao] [a_vis];[a_vis] showfreqs=s=%dx%d:mode=bar:fscale=log:ascale=cbrt:colors=0x00FFFF|0xFF00FF|0xFF00FFformat=gray,pad=%d:%d:%d:%d:black, format=yuv420p, setsar=1 [vo]", spec_w, spec_h, w, h, x, y)
    elseif name == "avectorscope" then
        local cw = math.min(w, math.floor(h * 0.8))
        local cx, cy = math.floor((w - cw) / 2), math.floor(h * 0.5 - cw / 2)
        if cy < 0 then cy = 0 end
        return string.format("[aid1] asplit [ao] [a_vis];[a_vis] aformat=channel_layouts=stereo, stereowiden=delay=20:feedback=0.2:crossfeed=0.2:drymix=0.8, avectorscope=s=%dx%d:mode=lissajous:zoom=1.1:draw=line:rc=120:gc=0:bc=160,pad=%d:%d:%d:%d:black, format=yuv420p, setsar=1 [vo]", cw, cw, w, h, cx, cy)
    elseif name == "linefreqs" then
        local lh = math.floor(h * 0.35)
        local ly = math.floor(h * 0.7 - lh / 2)
        if ly < 0 then ly = 0 end
        return string.format("[aid1] asplit [ao] [a_vis];[a_vis] showfreqs=s=%dx%d:mode=line:cmode=combined:ascale=log:fscale=log:win_func=hann,format=gray,pad=%d:%d:%d:%d:black, format=yuv420p, setsar=1 [vo]", spec_w, lh, w, h, x, ly)
    elseif name == "off" then
        local hasvideo = false
        for _, track in ipairs(mp.get_property_native("track-list")) do
            if track.type == "video" then hasvideo = true; break end
        end
        if hasvideo then return "[aid1] asetpts=PTS [ao]; [vid1] setpts=PTS [vo]"
        else return string.format("[aid1] asetpts=PTS [ao]; color=c=Black:s=%dx%d, format=yuv420p [vo]", w, h) end
    end
    return ""
end

-- ==============================================================================
-- 挂载与更新
-- ==============================================================================
local function visualizer_hook()
    local lavfi = ""
    if is_vis_needed() then
        lavfi = get_visualizer(opts.name, opts.quality)
    end

    if lavfi ~= "" and lavfi ~= mp.get_property("lavfi-complex", "") then
        mp.set_property("file-local-options/lavfi-complex", lavfi)
    end
    draw_black_circle()
end

options.read_options(opts, nil, visualizer_hook)
if not opts.forcewindow and mp.get_property('force-window') == "no" then return end

mp.add_hook("on_preloaded", 50, visualizer_hook)
mp.observe_property("current-tracks/audio", "native", visualizer_hook)
mp.observe_property("current-tracks/video", "native", visualizer_hook)

-- ==============================================================================
-- 快捷键与消息绑定
-- ==============================================================================

-- 切换/循环可视化
local function cycle_visualizer()
    local index = 1
    for i = 1, #visualizer_name_list do
        if visualizer_name_list[i] == opts.name then
            index = i % #visualizer_name_list + 1
            break
        end
    end
    opts.name = visualizer_name_list[index]
    visualizer_hook()
    draw_black_circle()
    mp.osd_message("visualizer: " .. opts.name)
end

-- 直接关闭可视化 (设 name 为 off)
local function close_visualizer()
    opts.name = "off"
    visualizer_hook()
    draw_black_circle()
    mp.osd_message("visualizer: off")
end

-- 兼容旧的内部绑定 (默认按键 c)
mp.add_key_binding("c", "cycle-visualizer", cycle_visualizer)

-- 注册 script-message 接口供 input.conf 调用
mp.register_script_message("visualizer", function(arg)
    if arg == "off" then
        close_visualizer()
    else
        cycle_visualizer()
    end
end)