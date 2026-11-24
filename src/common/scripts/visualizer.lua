-- ==============================================================================
-- visualizer.lua — 音频频谱可视化生成器（独立格式圆角框）
-- ==============================================================================
local options = require 'mp.options'
local assdraw = require 'mp.assdraw'

local opts = { mode = "novideo", name = "avectorscope", quality = "medium", forcewindow = true }

if not (mp.get_property("options/lavfi-complex", "") == "") then return end

-- ==============================================================================
-- 通用常量
-- ==============================================================================
local GOLD       = "00A5C8"   -- 沉稳金标色 #C8A500
local GREY_WHITE = "E0E0E0"   -- 灰白色 #E0E0E0
local GREY       = "AAAAAA"   -- 灰色 #AAAAAA
local FONT       = "Arial"
local WHITE      = "FFFFFF"

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

local function text_width(str, font_size)
    local width = 0
    for _, char in ipairs(utf8_chars(str)) do
        width = width + char_width(char, font_size)
    end
    return width
end

local function wrap_text(str, font_size, max_width)
    local lines = {}
    local current_line = ""
    local current_w = 0

    local tokens = {}
    local i = 1
    while i <= #str do
        local char = str:sub(i, i)
        local byte = string.byte(char)
        if byte < 128 and char:match("[%w%-']") then
            local word = str:match("^[%w%-']+", i)
            table.insert(tokens, word)
            i = i + #word
        elseif char:match("%s") then
            table.insert(tokens, " ")
            i = i + 1
            while i <= #str and str:sub(i, i):match("%s") do i = i + 1 end
        else
            local utf8_char = str:match("[%z\1-\127\194-\244][\128-\191]*", i)
            table.insert(tokens, utf8_char)
            i = i + #utf8_char
        end
    end

    local idx = 1
    while idx <= #tokens do
        local token = tokens[idx]
        local w_w = text_width(token, font_size)
        local is_space = (token == " ")

        if current_w + w_w > max_width and current_line ~= "" then
            if is_space then
                table.insert(lines, current_line)
                if #lines >= 2 then break end
                current_line = ""
                current_w = 0
                idx = idx + 1
            else
                table.insert(lines, current_line)
                if #lines >= 2 then break end
                current_line = ""
                current_w = 0
            end
        else
            if is_space and current_line == "" then
                idx = idx + 1
            else
                current_line = current_line .. token
                current_w = current_w + w_w
                idx = idx + 1
            end
        end
    end

    local truncated = idx <= #tokens
    if current_line ~= "" and #lines < 2 then table.insert(lines, current_line) end
    if #lines == 0 then lines[1] = "" end

    if truncated and not lines[#lines]:match("%.%.%.$") then
        local last = #lines
        local chars = utf8_chars(lines[last])
        while text_width(table.concat(chars) .. "...", font_size) > max_width and #chars > 0 do
            table.remove(chars)
        end
        lines[last] = table.concat(chars) .. "..."
    end

    return table.concat(lines, "\\N")
end

-- ==============================================================================
-- 音频元信息 (强化读取)
-- ==============================================================================
local function get_audio_bitrate()
    local br = mp.get_property_number("audio-bitrate", 0)
    if br and br > 0 then return br end
    local t = mp.get_property_native("current-tracks/audio")
    if t and t.bitrate and t.bitrate > 0 then return t.bitrate end
    br = mp.get_property_number("demuxer-bitrate", 0)
    if br and br > 0 then return br end
    local size = mp.get_property_number("file-size", 0)
    local dur  = mp.get_property_number("duration", 0)
    if size and size > 0 and dur and dur > 0 then
        return size * 8 / dur
    end
    return 0
end

local function get_file_format()
    local filename = mp.get_property("filename", "")
    local ext = filename:match("%.([^%.]+)$")
    return ext and ext:upper() or "AUDIO"
end

local function get_bit_depth()
    local fmt = mp.get_property("audio-params/format", "")
    local n = fmt:match("^(%d+)")
    if n then return tonumber(n) end
    if fmt:match("^flt") then return 32 end
    if fmt:match("^dbl") then return 64 end
    return nil
end

local function get_audio_info_separated()
    local fmt = escape_ass_text(get_file_format())
    local br  = get_audio_bitrate()
    local sr  = mp.get_property_number("audio-params/samplerate", 0)
    local bits = get_bit_depth()

    local lossless = fmt:match("^(FLAC|ALAC|WAV|APE|AIFF|DSD|DSF|DFF)$") ~= nil
    local hires = (bits and bits >= 24) or (sr and sr > 48000)

    local info
    if br <= 0 then
        info = "N/A"
    elseif lossless or hires or br > 320000 then
        local parts = {}
        if sr and sr > 0 then
            local khz = sr / 1000
            parts[#parts + 1] = string.format(khz % 1 == 0 and "%dkHz" or "%.1f kHz", khz)
        end
        if bits then parts[#parts + 1] = bits .. "bit" end
        parts[#parts + 1] = string.format("%d kbps", math.floor(br / 1000 + 0.5))
        info = table.concat(parts, " ")
        if hires then info = "Hi-Res " .. info end
    else
        info = string.format("%d kbps", math.floor(br / 1000 + 0.5))
    end

    return fmt, "•", info
end

-- ==============================================================================
-- 通用绘图工具
-- ==============================================================================
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
    return string.format("%02X%02X%02X",
        math.floor(bb * 255), math.floor(gg * 255), math.floor(rr * 255))
end

local function draw_ring(ass, cx, cy, r, outer, inner, alpha, segments)
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
            local px, py = center + outer * math.cos(a), center + outer * math.sin(a)
            if j == 0 then ass:move_to(px, py) else ass:line_to(px, py) end
        end
        for j = arc_steps, 0, -1 do
            local a = a0 + (a1 - a0) * j / arc_steps
            ass:line_to(center + inner * math.cos(a), center + inner * math.sin(a))
        end
        ass:draw_stop()
    end
end

local function draw_circle(ass, cx, cy, radius, color, alpha)
    local k = radius * 0.5522847498
    ass:new_event()
    ass:pos(cx - radius, cy - radius)
    ass:append(string.format("{\\an7\\1c&H%s&\\1a&H%02X&\\bord0\\shad0}", color, alpha))
    ass:draw_start()
    ass:move_to(radius, 0)
    ass:bezier_curve(radius + k, 0, 2 * radius, radius - k, 2 * radius, radius)
    ass:bezier_curve(2 * radius, radius + k, radius + k, 2 * radius, radius, 2 * radius)
    ass:bezier_curve(radius - k, 2 * radius, 0, radius + k, 0, radius)
    ass:bezier_curve(0, radius - k, radius - k, 0, radius, 0)
    ass:draw_stop()
end

-- 修正后的圆角矩形路径（原点在左上角 0,0，强制偏移宽高一半以居中）
local function round_rect_path(w, h, rad)
    rad = math.min(rad, w / 2, h / 2)
    local x0, y0 = 0, 0
    local offset_x, offset_y = -w/2, -h/2
    local k = rad * 0.5522847498
    local p = {}
    local function mv(x, y) p[#p + 1] = string.format("m %d %d", x + offset_x, y + offset_y) end
    local function ln(x, y) p[#p + 1] = string.format("l %d %d", x + offset_x, y + offset_y) end
    local function bc(c1x, c1y, c2x, c2y, x, y) 
        p[#p + 1] = string.format("b %d %d %d %d %d %d", 
            c1x + offset_x, c1y + offset_y, c2x + offset_x, c2y + offset_y, x + offset_x, y + offset_y) 
    end
    
    mv(x0 + rad, y0)
    ln(x0 + w - rad, y0)
    bc(x0 + w - rad + k, y0, x0 + w, y0 + rad - k, x0 + w, y0 + rad)
    ln(x0 + w, y0 + h - rad)
    bc(x0 + w, y0 + h - rad + k, x0 + w - rad + k, y0 + h, x0 + w - rad, y0 + h)
    ln(x0 + rad, y0 + h)
    bc(x0 + rad - k, y0 + h, x0, y0 + h - rad + k, x0, y0 + h - rad)
    ln(x0, y0 + rad)
    bc(x0, y0 + rad - k, x0 + rad - k, y0, x0 + rad, y0)
    return table.concat(p, " ")
end

-- ==============================================================================
-- 核心状态判断
-- ==============================================================================
local function is_vis_needed()
    if opts.mode == "off" then return false end
    if mp.get_property_number("track-list/count", -1) <= 0 then return false end

    local atrack = mp.get_property_native("current-tracks/audio")
    local vtrack = mp.get_property_native("current-tracks/video")

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
    if opts.mode == "novideo" then return (vtrack == nil or vtrack.albumart) end
    return false
end

-- ==============================================================================
-- 模式一：avectorscope
-- ==============================================================================
local function draw_avectorscope_original()
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

    draw_ring(ass, cx, cy, r, r + 11, r - 1, 0xD0, 96)
    draw_ring(ass, cx, cy, r, r + 7,  r - 1, 0xA0, 96)
    draw_circle(ass, cx, cy, r, "000000", 0x00)
    draw_ring(ass, cx, cy, r, r + 2, r - 2, 0x00, 120)

    local title = mp.get_property("metadata/by-key/title", "")
    local artist = mp.get_property("metadata/by-key/artist", "")
    if title == "" then title = (mp.get_property("filename", "Unknown"):gsub("%.[^%.]+$", "")) end
    if artist == "" then artist = "Unknown Artist" end
    title, artist = escape_ass_text(title), escape_ass_text(artist)

    local title_size  = math.max(12, math.floor(diameter * 0.08))
    local artist_size = math.max(10, math.floor(diameter * 0.055))
    local text_max_width = diameter * 0.82

    local title_text  = wrap_text(title,  title_size,  text_max_width)
    local artist_text = wrap_text(artist, artist_size, text_max_width)
    
    local fmt, dot, info = get_audio_info_separated()
    
    local title_lines  = select(2, title_text:gsub("\\N", "")) + 1
    local artist_lines = select(2, artist_text:gsub("\\N", "")) + 1

    local title_h  = title_size  * 1.2 * title_lines
    local artist_h = artist_size * 1.2 * artist_lines
    local meta_h   = artist_size * 1.2

    local spacing  = diameter * 0.06
    local total_h  = title_h + spacing + artist_h + spacing + meta_h
    local base_y   = cy - total_h / 2

    local title_y  = base_y + title_h / 2
    local artist_y = base_y + title_h + spacing + artist_h / 2
    local meta_y   = base_y + title_h + spacing + artist_h + spacing + meta_h / 2

    -- Title / Artist
    ass:new_event(); ass:pos(cx, title_y)
    ass:append(string.format("{\\an5\\fn%s\\fs%d\\b0\\1c&H%s&\\1a&H00&\\bord0\\shad0}%s", FONT, title_size, WHITE, title_text))
    ass:new_event(); ass:pos(cx, artist_y)
    ass:append(string.format("{\\an5\\fn%s\\fs%d\\b0\\1c&H%s&\\1a&H00&\\bord0\\shad0}%s", FONT, artist_size, WHITE, artist_text))

    -- Meta: 独立格式框 + 分散文字排版
    local fmt_w = text_width(fmt, artist_size)
    local info_w = text_width(info, artist_size)
    local total_w = fmt_w + info_w
    
    local start_x = cx - total_w / 2 + 10
    local fmt_center = start_x + fmt_w / 2 - 10
    local info_center = start_x + fmt_w + info_w / 2
    local fw, fh, rad = fmt_w + artist_size*0.8, artist_size * 1.2, artist_size

    -- 1. 画单独的框
    ass:new_event(); ass:pos(fmt_center, meta_y)
    ass:append(string.format("{\\an7\\p1\\1c&H%s&\\1a&HFF&\\3c&H%s&\\3a&H00&\\bord1.5\\shad0}", GOLD, GOLD))
    ass:append(round_rect_path(fw, fh, rad))
    ass:append("{\\p0}")

    -- 2. 框内文字 (金标)
    ass:new_event(); ass:pos(fmt_center, meta_y)
    ass:append(string.format("{\\an5\\fn%s\\fs%d\\b0\\1c&H%s&\\1a&H00\\bord0\\shad0}%s", FONT, artist_size*0.8, GOLD, fmt))

    -- 4. 参数文字 (灰白)
    ass:new_event(); ass:pos(info_center, meta_y)
    ass:append(string.format("{\\an5\\fn%s\\fs%d\\b0\\1c&H%s&\\1a&H00\\bord0\\shad0}%s", FONT, artist_size, GREY_WHITE, info))

    mp.set_osd_ass(w, h, ass.text)
end

-- ==============================================================================
-- 模式二：avectorscope-cd
-- ==============================================================================
local cd_ring_overlay, cd_disc_overlay, cd_text_overlay
local cd_cache_key

local function clear_cd_overlays()
    for _, o in ipairs({ cd_ring_overlay, cd_disc_overlay, cd_text_overlay }) do
        if o then o.data = ""; o:update() end
    end
    cd_cache_key = nil
end

local function arc_text(ass, str, fs, rad, cx, cy, color)
    local chars = utf8_chars(str)
    local spacing = fs * 0.02
    local limit = rad * math.rad(275)
    local function width(list)
        local n = 0
        for i, c in ipairs(list) do n = n + char_width(c, fs) + (i > 1 and spacing or 0) end
        return n
    end
    local cut = false
    while #chars > 0 and width(chars) > limit do table.remove(chars); cut = true end
    if cut then
        while #chars > 0 and width(chars) + fs * 0.9 > limit do table.remove(chars) end
        chars[#chars + 1], chars[#chars + 1], chars[#chars + 1] = ".", ".", "."
    end
    local widths, total = {}, 0
    for i, c in ipairs(chars) do
        widths[i] = char_width(c, fs)
        total = total + widths[i] + (i > 1 and spacing or 0)
    end
    local pos = -total / 2
    for i, c in ipairs(chars) do
        local off = pos + widths[i] / 2
        local a = -math.pi / 2 + off / rad
        local x, y = cx + rad * math.cos(a), cy + rad * math.sin(a)
        local tangent = math.deg(a) + 90
        ass:new_event(); ass:pos(x, y)
        ass:append(string.format("{\\an5\\fn%s\\fs%d\\b0\\1c&H%s&\\1a&H00&\\bord0.5\\3c&H000000&\\shad0\\frz%.2f}", FONT, fs, color, -tangent))
        ass:append(escape_ass_text(c))
        pos = pos + widths[i] + spacing
    end
end

local function draw_avectorscope_cd()
    if not is_vis_needed() then clear_cd_overlays(); mp.set_osd_ass(0, 0, ""); return end
    local w, h = mp.get_osd_size()
    if not w or w <= 0 then return end

    local diameter = math.min(w, h) * (230 / 720)
    local r = diameter / 2
    local cx, cy = w / 2, h * 0.5

    local title = mp.get_property("metadata/by-key/title", "")
    local artist = mp.get_property("metadata/by-key/artist", "")
    if title == "" then title = mp.get_property("filename", "Unknown"):gsub("%.[^%.]+$", "") end
    if artist == "" then artist = "Unknown Artist" end
    
    local fmt, dot, info = get_audio_info_separated()
    local meta_plain = fmt .. " " .. dot .. " " .. info

    local key = table.concat({ w, h, title, artist, diameter, meta_plain }, "|")
    if not cd_ring_overlay then cd_ring_overlay = mp.create_osd_overlay("ass-events"); cd_ring_overlay.z = 10 end
    if not cd_disc_overlay then cd_disc_overlay = mp.create_osd_overlay("ass-events"); cd_disc_overlay.z = 20 end
    if not cd_text_overlay then cd_text_overlay = mp.create_osd_overlay("ass-events"); cd_text_overlay.z = 30 end
    if key == cd_cache_key then return end
    mp.set_osd_ass(w, h, "")

    local ra, da, ta = assdraw.ass_new(), assdraw.ass_new(), assdraw.ass_new()

    draw_ring(ra, cx, cy, r, r + 11, r - 1, 0xD0, 96)
    draw_ring(ra, cx, cy, r, r + 7,  r - 1, 0xA0, 96)

    draw_circle(da, cx, cy, r - 1, "000000", 0x40)
    draw_circle(da, cx, cy, r * .94, "000000", 0xB0)
    draw_circle(da, cx, cy, r * .88, "000000", 0x80)
    draw_circle(da, cx, cy, r * .68, "000000", 0xA8)
    draw_circle(da, cx, cy, r * .42, "666666", 0xA0)
    draw_circle(da, cx, cy, r * .255, "414141", 0x70)
    draw_circle(da, cx, cy, r * .235, "252525", 0x00)
    draw_circle(da, cx, cy, r * .185, "383838", 0x80)
    draw_circle(da, cx, cy, r * .16, "252525", 0x00)

    local seed = 30
    local function rnd() seed = (seed * 16807) % 2147483647; return seed / 2147483647 end
    for _ = 1, 32 do
        local a = rnd() * 2 * math.pi
        local d = r * math.sqrt(.12 + rnd() * .78)
        local z = .5 + rnd() * .6
        da:new_event(); da:pos(cx + d * math.cos(a) - z, cy + d * math.sin(a) - z)
        da:append("{\\an7\\1c&H777777&\\1a&HC8&\\bord0\\shad0}")
        da:draw_start()
        da:move_to(z, 0); da:line_to(z * 2, z); da:line_to(z, z * 2); da:line_to(0, z); da:line_to(z, 0)
        da:draw_stop()
    end

    local title_fs  = math.max(12, math.floor(diameter * .085))
    local artist_fs = math.max(10, math.floor(diameter * .045))
    arc_text(ta, title,  title_fs,  r * .70, cx, cy, WHITE)
    arc_text(ta, artist, artist_fs, r * .33, cx, cy, GREY_WHITE)

    -- Meta: 独立格式框
    local meta_fs = artist_fs
    local fmt_w = text_width(fmt, meta_fs)
    local info_w = text_width(info, meta_fs)
    local total_w = fmt_w + info_w
    
    local start_x = cx - total_w / 2 + 10
    local fmt_center = start_x + fmt_w / 2 - 10
    local info_center = start_x + fmt_w + info_w / 2

    local fw, fh, rad = fmt_w + meta_fs * 0.8, meta_fs * 1.2, meta_fs
    local cyf = cy + r * 0.6

    -- 1. 画单独的框
    ta:new_event(); ta:pos(fmt_center, cyf)
    ta:append(string.format("{\\an7\\p1\\1c&H%s&\\1a&HFF&\\3c&H%s&\\3a&H00&\\bord1\\shad0}", GOLD, GOLD))
    ta:append(round_rect_path(fw, fh, rad))
    ta:append("{\\p0}")

    -- 2. 框内格式文字 (金标)
    ta:new_event(); ta:pos(fmt_center, cyf)
    ta:append(string.format("{\\an5\\fn%s\\fs%d\\b0\\1c&H%s&\\1a&H00\\bord0\\shad0}%s", FONT, meta_fs*0.8, GOLD, fmt))

    -- 4. 参数文字 (灰白)
    ta:new_event(); ta:pos(info_center, cyf)
    ta:append(string.format("{\\an5\\fn%s\\fs%d\\b0\\1c&H%s&\\1a&H00\\bord0\\shad0}%s", FONT, meta_fs, GREY_WHITE, info))

    cd_ring_overlay.res_x, cd_ring_overlay.res_y, cd_ring_overlay.data = w, h, ra.text
    cd_disc_overlay.res_x, cd_disc_overlay.res_y, cd_disc_overlay.data = w, h, da.text
    cd_text_overlay.res_x, cd_text_overlay.res_y, cd_text_overlay.data = w, h, ta.text
    cd_ring_overlay:update(); cd_disc_overlay:update(); cd_text_overlay:update()
    cd_cache_key = key
end

local function draw_black_circle()
    if opts.name == "avectorscope" then
        clear_cd_overlays()
        draw_avectorscope_original()
    elseif opts.name == "avectorscope-cd" then
        mp.set_osd_ass(0, 0, "")
        draw_avectorscope_cd()
    else
        clear_cd_overlays()
        mp.set_osd_ass(0, 0, "")
    end
end

-- ==============================================================================
-- 挂载与更新
-- ==============================================================================
local visualizer_name_list = { "avectorscope", "avectorscope-cd", "showfreqs", "linefreqs", "off" }

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
        return string.format("[aid1] asplit [ao] [a_vis];[a_vis] showfreqs=s=%dx%d:mode=bar:fscale=log:ascale=cbrt:colors=0x00FFFF|0xFF00FF|0xFF00FF format=gray,pad=%d:%d:%d:%d:black, format=yuv420p, setsar=1 [vo]", spec_w, spec_h, w, h, x, y)
    elseif name == "avectorscope" or name == "avectorscope-cd" then
        local cw = math.min(w, math.floor(h * 0.8))
        local cx, cy = math.floor((w - cw) / 2), math.floor(h * 0.5 - cw / 2)
        if cy < 0 then cy = 0 end
        return string.format("[aid1] asplit [ao] [a_vis];[a_vis] aresample=%d,aformat=channel_layouts=stereo,stereowiden=delay=20:feedback=0.2:crossfeed=0.2:drymix=0.8,avectorscope=s=%dx%d:mode=lissajous:zoom=1.1:draw=line:rc=120:gc=0:bc=160,pad=%d:%d:%d:%d:black,format=yuv420p,setsar=1 [vo]", 8000, cw, cw, w, h, cx, cy)
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
mp.observe_property("audio-params", "native", visualizer_hook)
mp.observe_property("file-size", "number", visualizer_hook)

-- ==============================================================================
-- 快捷键与消息绑定
-- ==============================================================================
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

local function close_visualizer()
    opts.name = "off"
    visualizer_hook()
    draw_black_circle()
    mp.osd_message("visualizer: off")
end

mp.add_key_binding("c", "cycle-visualizer", cycle_visualizer)

mp.register_script_message("visualizer", function(arg)
    if arg == "off" then
        close_visualizer()
    else
        cycle_visualizer()
    end
end)