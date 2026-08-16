-- mpv-menu-plugin: cross-platform mpv.net-inspired menu backend (v43)
-- Rendering model:
--   * bind the ASS overlay canvas to the CURRENT valid OSD dimensions
--   * never render while the OSD size is 0x0
--   * all menu geometry, hit-testing and mouse coordinates use the same canvas
-- This keeps drawing/hit-testing aligned and avoids the giant-vector fallback seen on startup.

local mp = require('mp')
local msg = require('mp.msg')
local opts = require('mp.options')
local utils = require('mp.utils')

local o = {
    font = '',
    font_name = '',
    font_size = 22,
    bold = false,
    italic = false,
    background = '#303030',
    border = '#6F6F6F',
    text = '#F2F2F2',
    disabled_text = '#8A8A8A',
    hover = '#4E4E4E',
    hover_bg = '',
    hover_text = '',
    hover_corner_radius = 7,
    hover_margin_x = 1,
    hover_margin_y = 0,
    shortcut = '#D0D0D0',
    hover_shortcut = '',
    separator = '#BEBEBE',
    submenu_arrow = '#F0F0F0',
    arrow = '',
    arrow_alpha = 0,
    hover_arrow = '',
    hover_arrow_alpha = 0,
    check = '#F0F0F0',
    shadow = '#000000',
    bg_alpha = 8,
    shadow_alpha = 100,
    radius = 7,
    border_width = 1,
    hover_border_width = 0.5,
    hover_border = '#656565',
    shadow_blur = 6,
    row_height = 42,
    min_row_height = 32,
    separator_height = 8,
    padding_x = 14,
    padding_y = 4,
    shortcut_gap = 8,
    arrow_width = 18,
    arrow_font_size = 34,
    submenu_gap = 4,
    screen_margin = 6,
    min_width = 360,
    max_width = 640,
    max_visible_rows = 0,
    scroll_threshold = 0.80,
    scrollbar_width = 6,
    scrollbar_gap = 4,
    scrollbar_min_thumb = 24,
    scrollbar_right_gap = 2,
    scrollbar_track = '#555555',
    scrollbar_thumb = '#222222',
    scrollbar_track_alpha = 150,
    scrollbar_thumb_alpha = 115,
    scroll_step = 1,
    click_to_show_submenus = false,
    hide_root_separators = true,
    child_indent_chars = 2,
    root_indent_chars = 1.5,
    playlist_header_indent_chars = 1,
    modal_mask = true,
    modal_mask_alpha = 255,
    modal_z = 1000000,
}
opts.read_options(o)
-- Style aliases for macOS-like menu.conf files.
if o.font_name ~= '' then o.font = o.font_name end
if o.hover_bg ~= '' then o.hover = o.hover_bg end
if o.hover_text == '' then o.hover_text = o.text end
if o.arrow ~= '' then o.submenu_arrow = o.arrow end
if o.hover_arrow == '' then o.hover_arrow = o.submenu_arrow end
if o.hover_shortcut == '' then o.hover_shortcut = o.shortcut end

local platform = mp.get_property('platform') or ''
if o.font == '' then
    if platform == 'windows' then
        o.font = 'Microsoft YaHei UI'
    elseif platform == 'darwin' then
        o.font = 'PingFang SC'
    else
        o.font = 'Noto Sans CJK SC'
    end
end

local REF_W, REF_H = 1280, 720
local current_ow, current_oh = 0, 0
local menu_prop = 'user-data/menu/items'
local BACKEND_NAME = 'menu'

local overlay = mp.create_osd_overlay('ass-events')
overlay.res_x = REF_W
overlay.res_y = REF_H
-- Keep the modal layer above OSC/uosc/ModernZ when the mpv build exposes a z-order.
pcall(function() overlay.z = tonumber(o.modal_z) or 1000000 end)

local visible = false
local items = {}
local open_path = {}
local rects = {}
local hover_level, hover_index = nil, nil
local selected_level, selected_index = 1, nil
local anchor_x, anchor_y = nil, nil
local key_bindings = {}
local scroll_offsets = {}
local geometry_timer = nil
local show_timer = nil
local schedule_hover_open
local last_osd_w, last_osd_h = 0, 0

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function parse_hex(c)
    c = tostring(c or '#FFFFFF'):gsub('#', '')
    if #c == 3 then
        c = c:sub(1,1)..c:sub(1,1)..c:sub(2,2)..c:sub(2,2)..c:sub(3,3)..c:sub(3,3)
    end
    if #c ~= 6 then c = 'FFFFFF' end
    return tonumber(c:sub(1,2),16) or 255, tonumber(c:sub(3,4),16) or 255, tonumber(c:sub(5,6),16) or 255
end

local function ass_color(c)
    local r,g,b = parse_hex(c)
    return string.format('&H%02X%02X%02X&', b,g,r)
end

local function ass_text(s)
    s = tostring(s or '')
    s = s:gsub('\\', '\\\\'):gsub('{','\\{'):gsub('}','\\}')
    s = s:gsub('\r',' '):gsub('\n',' ')
    s = s:gsub('^%s+', ''):gsub('%s+$', '')
    return s
end

local function ui_scale(ow, oh)
    -- Menu geometry is deliberately fixed in current OSD pixels.
    -- This keeps drawing and hit-testing exact instead of introducing
    -- non-uniform scaling on portrait/small windows.
    return 1
end


local function text_width(s, scale)
    local fs = o.font_size * (scale or 1)
    local w = 0
    for ch in tostring(s or ''):gmatch('[%z\1-\127\194-\244][\128-\191]*') do
        if ch:match('%s') then w = w + 0.32
        elseif ch:match('[%w]') then w = w + 0.56
        elseif ch:byte(1) and ch:byte(1) < 128 then w = w + 0.50
        else w = w + 1.0 end
    end
    return w * fs
end

local function truncate_text(text, maxw, scale)
    text = tostring(text or '')
    if maxw <= 0 then return '' end
    if text_width(text, scale) <= maxw then return text end
    local ellipsis = '…'
    local ew = text_width(ellipsis, scale)
    if ew >= maxw then return ellipsis end
    local chars = {}
    for ch in text:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
        chars[#chars + 1] = ch
    end
    local out = ''
    for i, ch in ipairs(chars) do
        local candidate = out .. ch .. ellipsis
        if text_width(candidate, scale) > maxw then
            break
        end
        out = out .. ch
    end
    if out == '' then return ellipsis end
    return out .. ellipsis
end


local function round_rect(x,y,w,h,r)
    r = math.min(r, w/2, h/2)
    local k = 0.55228475 * r
    return table.concat({
        string.format('m %.2f %.2f', x+r,y),
        string.format('l %.2f %.2f', x+w-r,y),
        string.format('b %.2f %.2f %.2f %.2f %.2f %.2f', x+w-r+k,y,x+w,y+r-k,x+w,y+r),
        string.format('l %.2f %.2f', x+w,y+h-r),
        string.format('b %.2f %.2f %.2f %.2f %.2f %.2f', x+w,y+h-r+k,x+w-r+k,y+h,x+w-r,y+h),
        string.format('l %.2f %.2f', x+r,y+h),
        string.format('b %.2f %.2f %.2f %.2f %.2f %.2f', x+r-k,y+h,x,y+h-r+k,x,y+h-r),
        string.format('l %.2f %.2f', x,y+r),
        string.format('b %.2f %.2f %.2f %.2f %.2f %.2f', x,y+r-k,x+r-k,y,x+r,y),
        'c'
    }, ' ')
end

local function draw_path(path, color, alpha, bord, blur, border_color)
    return string.format('{\\an7\\pos(0,0)\\p1\\1c%s\\3c%s\\1a&H%02X&\\bord%.1f\\blur%.1f\\shad0}%s{\\p0}',
        ass_color(color), ass_color(border_color or color), clamp(alpha or 0,0,255), bord or 0, blur or 0, path)
end

local function draw_line(x1,y1,x2,y2,color,alpha,width)
    local p = string.format('m %.2f %.2f l %.2f %.2f',x1,y1,x2,y2)
    return draw_path(p,color,alpha,width or 1,0)
end

local function text_tag(x,y,text,color,size,align,bold,italic,alpha)
    local fn = o.font or ''
    local b = bold == nil and o.bold or bold
    local i = italic == nil and o.italic or italic
    local a = alpha == nil and 0 or alpha
    return string.format('{\\an%s\\pos(%.2f,%.2f)\\fn%s\\fs%.1f\\b%s\\i%s\\bord0\\shad0\\1c%s\\1a&H%02X&}%s',
        align or '5', x,y,fn,size,b and '1' or '0',i and '1' or '0',ass_color(color),clamp(a,0,255),ass_text(text))
end


local function get_osd()
    local d = mp.get_property_native('osd-dimensions')
    if type(d) == 'table' and tonumber(d.w) and tonumber(d.h) then
        local w,h = tonumber(d.w),tonumber(d.h)
        if w > 0 and h > 0 then return w,h end
    end
    if mp.get_osd_size then
        local ok,w,h = pcall(mp.get_osd_size)
        if ok and w and h and w > 0 and h > 0 then return w,h end
    end
    return nil,nil
end

local function get_mouse()
    local p = mp.get_property_native('mouse-pos')
    local mx,my
    if type(p) == 'table' then mx,my = tonumber(p.x),tonumber(p.y) end
    mx = mx or mp.get_property_number('mouse-pos-x',0)
    my = my or mp.get_property_number('mouse-pos-y',0)
    local ow,oh = get_osd()
    if not ow or not oh then return 0,0,nil,nil end
    return mx, my, ow, oh
end


local function is_hidden(item)
    return type(item) == 'table' and item.hidden == true
end

-- Must be defined before normalize_menu(): normalize_menu() calls this
-- function and Lua local-function scope begins at the declaration site.
local function split_title(title)
    local a,b = tostring(title or ''):match('^(.-)\t(.*)$')
    return a or tostring(title or ''), b or ''
end

local function normalize_menu(list)
    if type(list) ~= 'table' then return 0 end
    local visible_count = 0
    for _, it in ipairs(list) do
        it.hidden = false
        if it.type == 'submenu' then
            local child_count = normalize_menu(it.submenu or {})
            if child_count == 0 then
                it.hidden = true
            else
                visible_count = visible_count + 1
            end
        elseif it.type == 'separator' then
            -- separators are normalized below after real items are known
        else
            local title = split_title(it.title)
            title = tostring(title or ''):gsub('^%s+', ''):gsub('%s+$', '')
            if title == '' then
                it.hidden = true
            else
                visible_count = visible_count + 1
            end
        end
    end

    -- Remove leading/trailing/consecutive separators and separators adjacent to hidden items.
    local pending_sep = nil
    local has_prev_item = false
    for _, it in ipairs(list) do
        if it.type == 'separator' then
            it.hidden = true
            pending_sep = it
        elseif not it.hidden then
            if pending_sep and has_prev_item then
                pending_sep.hidden = false
            end
            pending_sep = nil
            has_prev_item = true
        end
    end

    -- Recount after separator cleanup.
    visible_count = 0
    for _, it in ipairs(list) do
        if not it.hidden and it.type ~= 'separator' then
            visible_count = visible_count + 1
        end
    end
    return visible_count
end

local function state_has(item, value)
    if is_hidden(item) then return false end
    for _,s in ipairs(item.state or {}) do if s == value then return true end end
    return false
end

local function actual_cmd(cmd)
    if type(cmd) ~= 'string' then return nil end
    local s = cmd:gsub('%s+#menu:.*$', ''):gsub('%s+#@.*$', ''):gsub('%s+#!.*$', '')
    return s
end

local function menu_at(level)
    if level == 1 then return items end
    local cur = items
    for i=1,level-1 do
        local idx = open_path[i]
        local it = cur[idx]
        if not it or it.type ~= 'submenu' then return {} end
        cur = it.submenu or {}
    end
    return cur
end

local function is_non_interactive(item)
    return item and (item.type == 'separator' or item.type == 'header')
end

local function first_selectable(list)
    for i,it in ipairs(list or {}) do
        if not is_hidden(it) and not is_non_interactive(it) and not state_has(it,'disabled') then
            return i
        end
    end
    return nil
end

local function next_selectable(list,idx,dir)
    if not list or #list==0 then return nil end
    local i = idx or (dir>0 and 0 or #list+1)
    for _=1,#list do
        i=i+dir
        if i<1 then i=#list elseif i>#list then i=1 end
        if not is_hidden(list[i]) and not is_non_interactive(list[i]) and not state_has(list[i],'disabled') then
            return i
        end
    end
    return nil
end

local function get_playlist_header(list, level)
    -- Playlist metadata is stored on the parent menu item, not on the
    -- submenu array itself. mpv's native property serializer requires
    -- submenu arrays to use numeric keys only; mixing string metadata keys
    -- into the array causes 'key must be a string, but got number'.
    if not level or level <= 1 then return nil end
    local parent_list = menu_at(level - 1)
    local parent_index = open_path[level - 1]
    local parent = parent_list and parent_list[parent_index]
    if parent and type(parent._playlist_header) == 'string' then
        return parent._playlist_header
    end
    return nil
end

local function build_layout(list, scale, level)
    scale = scale or 1
    local layout = {}
    local desired_row_h = o.row_height * scale
    local row_h = desired_row_h
    local sep_h = o.separator_height * scale
    local pad_y = o.padding_y * scale
    local top_pad = pad_y
    local bottom_pad = pad_y
    local playlist_header = get_playlist_header(list, level)
    local header_h = playlist_header and row_h or 0

    level = level or 1
    for _, it in ipairs(list or {}) do
        if not is_hidden(it) then
            if not (it.type == 'separator' and level == 1 and o.hide_root_separators) then
                local h = (it.type == 'separator') and sep_h or row_h
                layout[#layout + 1] = { index = _, y = 0, h = h }
            end
        end
    end

    local total_h = top_pad + header_h
    for _, g in ipairs(layout) do
        g.y = total_h
        total_h = total_h + g.h
    end
    total_h = total_h + bottom_pad
    return layout, total_h, row_h, top_pad, bottom_pad, header_h
end

local function panel_max_height(oh, scale)
    local margin = o.screen_margin * scale
    local by_ratio = oh * tonumber(o.scroll_threshold or 0.80)
    local by_bounds = math.max(1, oh - 2 * margin)
    return math.max(1, math.min(by_ratio, by_bounds))
end

local function measure(list, ow, oh, level)
    local scale = ui_scale(ow, oh)
    level = level or 1
    local px = o.padding_x * scale
    local child_indent = (level > 1) and (o.child_indent_chars * o.font_size * scale) or (o.root_indent_chars * o.font_size * scale)
    local gap = o.shortcut_gap * scale
    local arrow = o.arrow_width * scale
    local min_w = o.min_width * scale
    local max_w = o.max_width * scale
    local max_screen_w = math.max(min_w, ow - 2*(o.screen_margin*scale))
    local maxw = min_w
    for _,it in ipairs(list or {}) do
        if not is_hidden(it) and it.type ~= 'separator' then
            local title, shortcut = split_title(it.title)
            local w = text_width(title, scale) + px*2 + child_indent
            if state_has(it,'checked') then w = w + 20*scale end
            if shortcut ~= '' then w = w + gap + text_width(shortcut, scale) end
            if it.type == 'submenu' then w = w + arrow end
            maxw = math.max(maxw, w)
        end
    end
    maxw = clamp(maxw, min_w, math.min(max_w, max_screen_w))

    local layout, desired_h, row_h, top_pad, bottom_pad, header_h = build_layout(list, scale, level)
    local playlist_header = get_playlist_header(list, level)
    if playlist_header then
        maxw = math.max(maxw, text_width(playlist_header, scale) + px * 2)
    end
    local max_h = panel_max_height(oh, scale)
    local scrollable = desired_h > max_h + 0.01
    local h = scrollable and max_h or desired_h
    local max_scroll = math.max(0, desired_h - h)
    local scroll_offset = clamp(tonumber(scroll_offsets[level]) or 0, 0, max_scroll)
    if not scrollable then
        scroll_offset = 0
        scroll_offsets[level] = 0
    else
        scroll_offsets[level] = scroll_offset
    end
    local meta = {
        scrollable = scrollable,
        scroll_offset = scroll_offset,
        max_scroll = max_scroll,
        row_h = row_h,
        top_pad = top_pad,
        bottom_pad = bottom_pad,
        header_h = header_h,
        content_h = math.max(1, h - top_pad - bottom_pad - header_h),
        desired_h = desired_h,
        scrollbar_width = o.scrollbar_width * scale,
        scrollbar_gap = o.scrollbar_gap * scale,
        scrollbar_right_gap = o.scrollbar_right_gap * scale,
    }
    return maxw,h,layout,scale,meta
end

local function ensure_visible(level, index)
    local r = rects[level]
    if not r or not r.scrollable then return end
    local g
    for _, item in ipairs(r.layout or {}) do
        if item.index == index then g=item; break end
    end
    if not g then return end
    local top = r.top_pad + (r.header_h or 0)
    local bottom = r.h - r.bottom_pad
    local offset = r.scroll_offset or 0
    local top_screen = g.y - offset
    local bottom_screen = g.y + g.h - offset
    if top_screen < top then
        offset = g.y - top
    elseif bottom_screen > bottom then
        offset = g.y + g.h - bottom
    end
    r.scroll_offset = clamp(offset, 0, r.max_scroll or 0)
    scroll_offsets[level] = r.scroll_offset
end

local function hit_test(x,y)
    for level=#rects,1,-1 do
        local r = rects[level]
        if r and x>=r.x and x<=r.x+r.w and y>=r.y and y<=r.y+r.h then
            local ly = y-r.y
            if r.scrollable then
                local sbw = r.scrollbar_width or 0
                local sbg = r.scrollbar_gap or 0
                local sb_left = r.x + r.w - r.padding_x - sbg - sbw
                if x >= sb_left - sbg and x <= r.x + r.w then
                    return level,nil
                end
            end
            for _,g in ipairs(r.layout) do
                local gy = r.top_pad + g.y - r.top_pad - (r.scroll_offset or 0)
                -- g.y is in panel coordinates; subtract the current scroll offset.
                if ly >= gy and ly < gy + g.h then
                    if r.items[g.index].type == 'separator' then return level,nil end
                    return level,g.index
                end
            end
            return level,nil
        end
    end
    return nil,nil
end

local function panel_level_at(x,y)
    for level=#rects,1,-1 do
        local r=rects[level]
        if r and x>=r.x and x<=r.x+r.w and y>=r.y and y<=r.y+r.h then
            return level,r
        end
    end
    return nil,nil
end

local function scroll_panel(level, delta)
    local r=rects[level]
    if not r or not r.scrollable then return false end
    local step = (r.row_h or o.row_height) * tonumber(o.scroll_step or 1)
    if step <= 0 then step = r.row_h or 1 end
    local new_offset = clamp((r.scroll_offset or 0) + delta*step, 0, r.max_scroll or 0)
    if math.abs(new_offset - (r.scroll_offset or 0)) < 0.01 then return false end
    r.scroll_offset = new_offset
    scroll_offsets[level] = new_offset
    return true
end

local function draw_modal_mask(ow, oh)
    if not o.modal_mask then return '' end
    -- Fully transparent full-window ASS shape.  It is intentionally present in
    -- the same top-level overlay as the menu; mouse input is captured by the
    -- forced modal bindings below.  The mask therefore covers OSC/uosc/ModernZ
    -- visually without dimming the picture.
    local path = string.format('m 0 0 l %.2f 0 l %.2f %.2f l 0 %.2f c', ow, ow, oh, oh)
    return draw_path(path, o.background, o.modal_mask_alpha, 0, 0, o.background)
end

local function draw_menu(list,x,y,level,ow,oh)
    local w,h,layout,scale,meta = measure(list,ow,oh,level)
    local margin = o.screen_margin * scale
    x=clamp(x,margin,ow-w-margin)
    y=clamp(y,margin,oh-h-margin)
    rects[level]={
        x=x,y=y,w=w,h=h,items=list,layout=layout,scale=scale,
        scrollable=meta.scrollable,scroll_offset=meta.scroll_offset,max_scroll=meta.max_scroll,
        row_h=meta.row_h,top_pad=meta.top_pad,bottom_pad=meta.bottom_pad,header_h=meta.header_h or 0,content_h=meta.content_h,
        scrollbar_width=meta.scrollbar_width,scrollbar_gap=meta.scrollbar_gap,padding_x=o.padding_x*scale,
    }
    local out={}
    local radius=o.radius*scale
    out[#out+1] = draw_path(round_rect(x+2*scale,y+3*scale,w,h,radius),o.shadow,85,0,4*scale,o.shadow)
    out[#out+1] = draw_path(round_rect(x,y,w,h,radius),o.background,o.bg_alpha,o.border_width*scale,0,o.border)

    local content_top = y + meta.top_pad + (meta.header_h or 0)
    local content_bottom = y + h - meta.bottom_pad
    local scroll_offset = meta.scroll_offset or 0

    local playlist_header = get_playlist_header(list, level)
    if meta.header_h and meta.header_h > 0 and playlist_header then
        local header_y = y + meta.top_pad + meta.header_h / 2
        local header_indent = o.playlist_header_indent_chars * o.font_size * scale
        local header_x = x + o.padding_x*scale + header_indent
        out[#out+1] = text_tag(header_x, header_y, playlist_header, o.text, o.font_size*scale, '4')
        -- mpv.net-style header separator: the left edge follows the text
        -- indentation, while the right edge remains aligned with the panel.
        local line_y = y + meta.top_pad + meta.header_h - 0.5*scale
        local line_right = x + w - o.padding_x*scale
        out[#out+1] = draw_line(header_x, line_y, line_right, line_y, o.separator, 110, math.max(1,scale))
    end

    for _,g in ipairs(layout) do
        local idx = g.index
        local it = list[idx]
        local ry = y + g.y - scroll_offset
        if ry + g.h >= content_top and ry <= content_bottom then
            local row_out = {}
            local clip_tag = string.format('{\\clip(%.2f,%.2f,%.2f,%.2f)}', x, content_top, x+w, content_bottom)
            if it.type == 'separator' then
                local sy = ry + g.h/2
                local indent = (level > 1) and (o.child_indent_chars * o.font_size * scale) or 0
                local sep_left = x + o.padding_x * scale + indent
                local sep_right = x + w - 1 * scale
                row_out[#row_out+1]=draw_line(sep_left,sy,sep_right,sy,o.separator,110,math.max(1,scale))
            else
                local path_selected = (open_path[level] == idx)
                local path_hovered = (hover_level == level and hover_index == idx)
                local ih = path_selected or path_hovered
                if ih then
                    local hm_x = math.max(0, tonumber(o.hover_margin_x or 1) * scale)
                    local hm_y = math.max(0, tonumber(o.hover_margin_y or 0) * scale)
                    local sel_x = x + hm_x
                    local sel_y = ry + hm_y
                    local sel_w = math.max(0, w - 2 * hm_x)
                    local sel_h = math.max(0, g.h - 2 * hm_y)
                    local hr = tonumber(o.hover_corner_radius or o.radius or 0) * scale
                    row_out[#row_out+1]=draw_path(round_rect(sel_x,sel_y,sel_w,sel_h,hr),o.hover,0,
                        (tonumber(o.hover_border_width) or 0)*scale,0,o.hover_border)
                end
                local title,shortcut=split_title(it.title)
                local disabled=state_has(it,'disabled')
                local c=disabled and o.disabled_text or (ih and o.hover_text or o.text)
                local px=o.padding_x*scale
                local child_indent = (level > 1) and (o.child_indent_chars * o.font_size * scale) or (o.root_indent_chars * o.font_size * scale)
                local text_y=ry+g.h/2
                local fs=o.font_size*scale
                local left_x=x+px+child_indent
                local check_w=0
                if state_has(it,'checked') then
                    row_out[#row_out+1]=text_tag(left_x,text_y,'✓',disabled and o.disabled_text or (ih and o.hover_text or o.check),fs-1*scale,'4')
                    check_w=20*scale
                    left_x=left_x+check_w
                end
                local right_edge = x + w - o.padding_x * scale
                if meta.scrollable then
                    right_edge = right_edge - meta.scrollbar_width - meta.scrollbar_gap
                end
                local arrow_center = nil
                local shortcut_x = nil
                local shortcut_w = shortcut ~= '' and text_width(shortcut, scale) or 0
                if it.type == 'submenu' then
                    arrow_center = right_edge - (o.arrow_width * scale) / 2
                    local arrow_left = right_edge - o.arrow_width * scale
                    if shortcut ~= '' then
                        shortcut_x = arrow_left - o.shortcut_gap * scale - shortcut_w
                        right_edge = shortcut_x - o.shortcut_gap * scale
                    else
                        right_edge = arrow_left - o.shortcut_gap * scale
                    end
                else
                    if shortcut ~= '' then
                        shortcut_x = right_edge - shortcut_w
                        right_edge = shortcut_x - o.shortcut_gap * scale
                    end
                end
                local display_title=truncate_text(title,math.max(1,right_edge-left_x),scale)
                row_out[#row_out+1]=text_tag(left_x,text_y,display_title,c,fs,'4')
                if shortcut ~= '' then
                    row_out[#row_out+1]=text_tag(shortcut_x,text_y,shortcut,disabled and o.disabled_text or (ih and o.hover_shortcut or o.shortcut),fs,'4')
                end
                if it.type == 'submenu' then
                    local arrow_fs=o.arrow_font_size*scale
                    row_out[#row_out+1]=text_tag(arrow_center,text_y,'›',ih and o.hover_arrow or o.submenu_arrow,arrow_fs,'5',nil,nil,ih and o.hover_arrow_alpha or o.arrow_alpha)
                end
            end
            if #row_out > 0 then
                for _, line in ipairs(row_out) do out[#out+1] = clip_tag .. line end
            end
        end
    end

    if meta.scrollable then
        -- Keep the scrollbar visually attached to the panel's right border.
        -- The text/content area still reserves scrollbar_gap on its right side.
        local track_x = x + w - meta.scrollbar_width - meta.scrollbar_right_gap
        local track_y = content_top
        local track_h = math.max(1, content_bottom - content_top)
        local total_content_h = math.max(track_h, meta.desired_h - meta.top_pad - meta.bottom_pad - (meta.header_h or 0))
        local thumb_h = math.max(o.scrollbar_min_thumb*scale, track_h * (track_h / total_content_h))
        thumb_h = math.min(track_h, thumb_h)
        local travel = math.max(0, track_h - thumb_h)
        local ratio = (meta.max_scroll > 0) and (meta.scroll_offset / meta.max_scroll) or 0
        local thumb_y = track_y + travel * ratio
        local rr = math.max(1, meta.scrollbar_width/2)
        out[#out+1]=draw_path(round_rect(track_x,track_y,meta.scrollbar_width,track_h,rr),o.scrollbar_track,o.scrollbar_track_alpha,0,0,o.scrollbar_track)
        out[#out+1]=draw_path(round_rect(track_x,thumb_y,meta.scrollbar_width,thumb_h,rr),o.scrollbar_thumb,o.scrollbar_thumb_alpha,0,0,o.scrollbar_thumb)
    end
    return table.concat(out,'\n'),w,h
end

local function clear()
    local ow,oh=get_osd()
    if ow and oh then
        overlay.res_x=ow
        overlay.res_y=oh
        current_ow,current_oh=ow,oh
    else
        overlay.res_x=REF_W
        overlay.res_y=REF_H
    end
    overlay.data=''
    overlay:update()
end

local render

local function prepare_playlist_scroll_for_open(level, item)
    -- Calculate the playlist scroll offset BEFORE the submenu is rendered.
    -- This is deliberately synchronous: the first frame of the opened submenu
    -- is already positioned at the current item, with no visible jump.
    if not item or type(item._playlist_current_menu_index) ~= 'number' then
        return false
    end
    if level <= 1 or type(item.submenu) ~= 'table' then
        return false
    end

    local ow, oh = get_osd()
    if not ow or not oh or ow <= 0 or oh <= 0 then
        return false
    end

    local _, _, layout, _, meta = measure(item.submenu, ow, oh, level)
    if not meta or not meta.scrollable then
        scroll_offsets[level] = 0
        return false
    end

    local target
    for _, g in ipairs(layout or {}) do
        if g.index == item._playlist_current_menu_index then
            target = g
            break
        end
    end
    if not target then
        return false
    end

    -- target.y already includes top padding and the playlist header. Align the
    -- current item to the top edge of the scroll viewport, immediately below
    -- the header when one exists. Clamp at max_scroll so the last items cannot
    -- be pushed beyond the panel's bottom edge.
    local top = meta.top_pad + (meta.header_h or 0)
    local desired = target.y - top
    local offset = clamp(desired, 0, meta.max_scroll or 0)
    scroll_offsets[level] = offset
    return true
end

local function prepare_initial_playlist_scrolls(list, ow, oh, level)
    -- Pre-position long playlist panels BEFORE the submenu is opened.
    -- Do not rely on open_path here: at menu invocation time the playlist
    -- submenu has not been opened yet, so get_playlist_header() cannot resolve
    -- its parent through open_path. Metadata is available directly on `it`.
    level = level or 1
    if type(list) ~= 'table' then return end

    for _, it in ipairs(list) do
        if type(it) == 'table' and not is_hidden(it) and it.type == 'submenu' then
            local child = it.submenu or {}
            local child_level = level + 1

            if type(it._playlist_current_index) == 'number'
                and type(it._playlist_current_menu_index) == 'number'
                and type(it._playlist_total) == 'number'
                and it._playlist_total > 1 then

                local _, _, layout, scale = measure(child, ow, oh, child_level)
                local row_h = o.row_height * scale
                local sep_h = o.separator_height * scale
                local pad_y = o.padding_y * scale
                local header_h = (type(it._playlist_header) == 'string' and it._playlist_header ~= '') and row_h or 0

                -- Rebuild the content height including the playlist header, since
                -- measure() cannot resolve the parent while open_path is empty.
                local desired_h = pad_y + header_h + pad_y
                for _, g in ipairs(layout or {}) do
                    desired_h = desired_h + g.h
                end
                local max_h = panel_max_height(oh, scale)
                local panel_h = math.min(desired_h, max_h)
                local max_scroll = math.max(0, desired_h - panel_h)

                if max_scroll > 0 then
                    local target = it._playlist_current_menu_index
                    local target_g
                    for _, g in ipairs(layout or {}) do
                        if g.index == target then target_g = g; break end
                    end

                    if target_g then
                        -- Put the current item at the top of the visible list,
                        -- directly below the 4/50 header when one exists.
                        local target_top = pad_y + header_h
                        local offset = target_g.y - target_top
                        scroll_offsets[child_level] = clamp(offset, 0, max_scroll)
                    end
                else
                    scroll_offsets[child_level] = 0
                end
            end

            prepare_initial_playlist_scrolls(child, ow, oh, child_level)
        end
    end
end

render = function()
    if not visible then clear(); return end
    local ow,oh=get_osd()
    if not ow or not oh or ow <= 0 or oh <= 0 then return end
    current_ow,current_oh=ow,oh

    local mx,my=get_mouse()
    local l,i=hit_test(mx,my)
    if l and i then
        hover_level,hover_index=l,i
    elseif not l then
        hover_level,hover_index=nil,nil
    end

    rects={}
    local root=items
    if type(root)~='table' or #root==0 then clear(); return end
    if normalize_menu(root) == 0 then clear(); return end

    local rw,rh,_,scale=measure(root,ow,oh,1)
    local margin=o.screen_margin*scale
    local x = anchor_x or (mx+2*scale)
    local y = anchor_y or (my+2*scale)
    if x+rw>ow-margin then x=(anchor_x and anchor_x-rw-2*scale) or (mx-rw-2*scale) end
    if y+rh>oh-margin then y=(anchor_y and anchor_y-rh-2*scale) or (my-rh-2*scale) end
    x=clamp(x,margin,ow-rw-margin)
    y=clamp(y,margin,oh-rh-margin)

    local ass={}
    ass[#ass+1]=draw_modal_mask(ow,oh)
    ass[#ass+1]=select(1,draw_menu(root,x,y,1,ow,oh))

    for level=2,#open_path+1 do
        local parent=rects[level-1]
        local pitems=menu_at(level-1)
        local pidx=open_path[level-1]
        local child=pitems[pidx] and pitems[pidx].submenu or {}
        if parent and child then
            local cw,ch,_,cscale=measure(child,ow,oh,level)
            local gap=o.submenu_gap*cscale
            local cx=parent.x+parent.w+gap
            if cx+cw>ow-o.screen_margin*cscale then cx=parent.x-cw-gap end
            local pg=nil
            for _,g in ipairs(parent.layout or {}) do if g.index==pidx then pg=g;break end end
            local cy=pg and (parent.y+pg.y-(parent.scroll_offset or 0)) or parent.y+o.padding_y*cscale
            cy=clamp(cy,o.screen_margin*cscale,oh-ch-o.screen_margin*cscale)
            ass[#ass+1]=select(1,draw_menu(child,cx,cy,level,ow,oh))
        end
    end

    overlay.res_x=ow
    overlay.res_y=oh
    overlay.data=table.concat(ass,'\n')
    overlay:update()
end

local function remove_bindings()
    for n,_ in pairs(key_bindings) do pcall(mp.remove_key_binding,n) end
    key_bindings={}
end

local function cancel_hover_timer()
    -- 子菜单采用同步展开，不再使用 hover 定时器。
end

local function hide()
    if show_timer then show_timer:kill(); show_timer=nil end
    if geometry_timer then geometry_timer:kill(); geometry_timer=nil end
    cancel_hover_timer()
    if not visible then clear(); return end
    visible=false
    open_path={}
    scroll_offsets={}
    rects={}
    anchor_x,anchor_y=nil,nil
    hover_level,hover_index=nil,nil
    selected_level,selected_index=1,nil
    last_osd_w,last_osd_h=0,0
    remove_bindings()
    clear()
end

local function bind(key,name,fn,opt)
    mp.add_forced_key_binding(key,name,fn,opt or {repeatable=false})
    key_bindings[name]=true
end

local function activate_selected()
    local list=menu_at(selected_level)
    local it=list and list[selected_index]
    if not it or it.type=='separator' or state_has(it,'disabled') then return end
    if it.type=='submenu' then
        open_path[selected_level]=selected_index
        selected_level=selected_level+1
        selected_index=first_selectable(it.submenu)
        if it._playlist_current_menu_index then
            prepare_playlist_scroll_for_open(selected_level, it)
        end
        render()
        return
    end
    local cmd=actual_cmd(it.cmd)
    hide()
    if not cmd or cmd == '' then return end

    -- Execute exactly the command stored by dyn_menu.lua from input.conf.
    -- mp.command() supports normal mpv input.conf command syntax, including
    -- semicolon-separated command chains and script-message/script-binding.
    local ok, err = pcall(mp.command, cmd)
    if not ok then
        msg.error('menu command failed: ' .. tostring(err))
        mp.osd_message('菜单命令执行失败: ' .. tostring(err), 2)
    end
end

local function setup_bindings()
    remove_bindings()
    bind('ESC','menu-esc',hide)
    bind('ENTER','menu-enter',activate_selected)
    bind('UP','menu-up',function()
        selected_index=next_selectable(menu_at(selected_level),selected_index,-1)
        render()
        ensure_visible(selected_level, selected_index)
        render()
    end,{repeatable=true})
    bind('DOWN','menu-down',function()
        selected_index=next_selectable(menu_at(selected_level),selected_index,1)
        render()
        ensure_visible(selected_level, selected_index)
        render()
    end,{repeatable=true})
    bind('RIGHT','menu-right',function()
        local it=menu_at(selected_level)[selected_index]
        if it and it.type=='submenu' and not state_has(it,'disabled') then
            open_path[selected_level]=selected_index
            selected_level=selected_level+1
            selected_index=first_selectable(it.submenu)
            if it._playlist_current_menu_index then
                prepare_playlist_scroll_for_open(selected_level, it)
            end
            render()
        end
    end)
    bind('LEFT','menu-left',function()
        if selected_level>1 then
            local old=selected_level-1
            selected_level=old
            selected_index=open_path[old] or first_selectable(menu_at(old))
            open_path[selected_level]=nil
            render()
        else hide() end
    end)
    bind('MBTN_LEFT','menu-left-click',function()
        local mx,my=get_mouse()
        local l,i=hit_test(mx,my)
        -- A left click outside an actual option closes the whole menu.
        -- This includes the rounded-panel padding and separator rows.
        if not l or not i then
            hide()
            return
        end
        local it=menu_at(l)[i]
        if not it or it.type=='separator' or state_has(it,'disabled') then
            hide()
            return
        end
        selected_level,selected_index=l,i
        activate_selected()
    end)
    bind('MBTN_RIGHT','menu-right-click',hide)
    -- Modal shield: consume mouse buttons used by OSC/uosc/ModernZ while the
    -- menu is open. Left click is handled above (menu item => action, outside
    -- menu => close). Other buttons are intentionally swallowed.
    bind('MBTN_MID','menu-middle-block',function() end)
    bind('MBTN_MID_DBL','menu-middle-dbl-block',function() end)
    bind('MBTN_LEFT_DBL','menu-left-dbl-block',function()
        -- Treat a double-click like a normal menu click on the current target.
        local mx,my=get_mouse()
        local l,i=hit_test(mx,my)
        if not l or not i then hide(); return end
        local it=menu_at(l)[i]
        if not it or it.type=='separator' or state_has(it,'disabled') then hide(); return end
        selected_level,selected_index=l,i
        activate_selected()
    end)
    bind('MBTN_RIGHT_DBL','menu-right-dbl-block',hide)
    bind('WHEEL_UP','menu-wheel-up',function()
        local mx,my=get_mouse()
        local l,r=panel_level_at(mx,my)
        if l and r and r.scrollable then
            if scroll_panel(l,-1) then render() end
            return
        end
        selected_index=next_selectable(menu_at(selected_level),selected_index,-1)
        render()
        ensure_visible(selected_level, selected_index)
        render()
    end)
    bind('WHEEL_DOWN','menu-wheel-down',function()
        local mx,my=get_mouse()
        local l,r=panel_level_at(mx,my)
        if l and r and r.scrollable then
            if scroll_panel(l,1) then render() end
            return
        end
        selected_index=next_selectable(menu_at(selected_level),selected_index,1)
        render()
        ensure_visible(selected_level, selected_index)
        render()
    end)
end

local function clear_deeper_path(level)
    for k=#open_path, level+1, -1 do
        open_path[k]=nil
    end
end

local function on_mouse_move()
    if not visible then return end
    local x,y=get_mouse()
    local l,i=hit_test(x,y)
    if not l or not i then
        -- Preserve the current submenu while the pointer crosses the small gap
        -- between parent and child panels. A click outside still closes it.
        return
    end

    local list=menu_at(l)
    local it=list and list[i]
    if not it or it.type=='separator' or is_hidden(it) then return end

    local changed=(hover_level~=l or hover_index~=i)
    hover_level,hover_index=l,i
    selected_level,selected_index=l,i

    -- Once the pointer enters another level/item, discard deeper branches that
    -- no longer belong to the current hover path. This prevents stale child
    -- panels from remaining visible after moving to another item.
    if open_path[l] ~= i then
        clear_deeper_path(l)
        open_path[l]=nil
    end

    if it.type=='submenu' and not state_has(it,'disabled') then
        open_path[l]=i
        if changed then
            schedule_hover_open(l,i)
        end
    else
        clear_deeper_path(l-1)
        open_path[l]=nil
        cancel_hover_timer()
    end

    if changed then render() end
end

local function refresh_menu_snapshot()
    -- Dynamic menus are updated synchronously by dyn_menu.lua.  Reading the
    -- property immediately after the script-message gives us the same menu
    -- snapshot that will be rendered on this frame, without a second visual pass.
    pcall(mp.commandv, 'script-message', 'menu-refresh-dynamic')
    local ok, data = pcall(mp.get_property_native, menu_prop)
    if ok and type(data) == 'table' then
        items = data
        normalize_menu(items)
        return true
    end
    return false
end

local function open_hover_now(l, i)
    if not visible or not l or not i then return end
    local list=menu_at(l)
    local it=list and list[i]
    if not it or it.type~='submenu' or state_has(it,'disabled') then
        clear_deeper_path(l-1)
        open_path[l]=nil
        render()
        return
    end
    if o.click_to_show_submenus then return end

    -- Playlist data can change between right-click and hover. Refresh it before
    -- opening the submenu so the current item and its scroll target are known
    -- before the first frame is rendered.
    if it._playlist_total or it._playlist_current_menu_index then
        refresh_menu_snapshot()
        list=menu_at(l)
        it=list and list[i]
        if not it or it.type~='submenu' then return end
    end

    open_path[l]=i
    for k=#open_path,l+1,-1 do open_path[k]=nil end
    selected_level=l+1
    selected_index=first_selectable(it.submenu)

    if it._playlist_current_menu_index then
        -- Synchronous pre-layout: compute the scroll offset before render().
        -- No post-render corrective pass, so the submenu never visibly jumps.
        prepare_playlist_scroll_for_open(selected_level, it)
    end
    render()
end

schedule_hover_open = function(l, i)
    if o.click_to_show_submenus or not l or not i then return end
    local list=menu_at(l)
    local it=list and list[i]
    if not it or it.type~='submenu' or state_has(it,'disabled') then return end

    -- 子菜单立即打开，不使用 hover timer / add_timeout。
    -- 播放列表在 open_hover_now() 中同步预布局，首帧即定位。
    open_hover_now(l, i)
end

local function show(attempt)
    attempt = attempt or 1
    -- Rebuild dynamic menus first, then wait one event-loop tick before taking the
    -- snapshot. Dynamic playlist data can be committed by dyn_menu.lua on the next
    -- idle cycle; calculating scroll against the pre-commit table is too early.
    pcall(mp.commandv,'script-message','menu-refresh-dynamic')

    if show_timer then show_timer:kill(); show_timer=nil end
    local delay = (attempt == 1) and 0.03 or 0.05
    show_timer = mp.add_timeout(delay, function()
        show_timer = nil
        refresh_menu_snapshot()

        local ready = type(items)=='table' and #items>0 and first_selectable(items) ~= nil
        if not ready then
            if attempt < 6 then
                show(attempt + 1)
            else
                msg.warn('menu data is empty')
            end
            return
        end

        local mx,my=get_mouse()
        anchor_x,anchor_y=(mx or 0)+2,(my or 0)+2
        visible=true
        open_path={}
        scroll_offsets={}
        rects={}
        hover_level,hover_index=nil,nil
        selected_level=1
        selected_index=first_selectable(items)
        local sow, soh = get_osd()
        if sow and soh then
            last_osd_w,last_osd_h=sow,soh
            prepare_initial_playlist_scrolls(items, sow, soh, 1)
        end
        setup_bindings()
        render()
        if geometry_timer then geometry_timer:kill() end
        -- No periodic hover polling: mouse-pos and the scheduled hover timer
        -- drive submenu opening directly. This avoids the old 100 ms polling
        -- latency and eliminates the visible delayed playlist jump.
        geometry_timer=nil
    end)
end

mp.register_script_message('show',show)
mp.register_script_message('hide',hide)
mp.register_script_message('geometry-debug',function()
    local ow,oh=get_osd()
    local x,y= get_mouse()
    msg.info(string.format('OSD=%s | canvas=OSD | mouse=%.1f,%.1f | overlay.res=%d,%d',
        ow and oh and (ow..'x'..oh) or '0x0',x,y,overlay.res_x,overlay.res_y))
    mp.osd_message(string.format('OSD %s | canvas OSD | mouse %.0f,%.0f',ow and oh and (ow..'x'..oh) or '0x0',x,y),2)
end)

mp.add_timeout(0,function()
    mp.commandv('script-message','menu-init',BACKEND_NAME)
end)

mp.observe_property(menu_prop,'native',function(_,v)
    if type(v)=='table' then items=v else items={} end
    if type(items)=='table' then normalize_menu(items) end
    if visible then render() end
end)
mp.observe_property('mouse-pos','native',function() on_mouse_move() end)
local function recompute_open_playlist_scrolls(ow, oh)
    if not ow or not oh then return end
    for level=2,#open_path+1 do
        local parent_list=menu_at(level-1)
        local idx=open_path[level-1]
        local parent=parent_list and parent_list[idx]
        if parent and parent.type=='submenu' and (parent._playlist_total or parent._playlist_current_menu_index) then
            prepare_playlist_scroll_for_open(level,parent)
        end
    end
end

mp.observe_property('osd-dimensions','native',function()
    if not visible then return end
    local ow,oh=get_osd()
    if not ow or not oh then return end
    local changed=(ow~=last_osd_w or oh~=last_osd_h)
    last_osd_w,last_osd_h=ow,oh
    if changed then
        -- Recompute the 80% viewport and the current playlist target against the
        -- new OSD size BEFORE the next render. This keeps resize/fullscreen changes
        -- from producing an old-position frame followed by a correcting frame.
        recompute_open_playlist_scrolls(ow,oh)
        if #open_path > 0 then
            for level=2,#open_path+1 do
                if not scroll_offsets[level] then
                    local parent_list=menu_at(level-1)
                    local idx=open_path[level-1]
                    local parent=parent_list and parent_list[idx]
                    if parent and parent.submenu then
                        local _,_,_,_,meta=measure(parent.submenu,ow,oh,level)
                        if meta and not meta.scrollable then scroll_offsets[level]=0 end
                    end
                end
            end
        end
    end
    render()
end)
mp.observe_property('playlist-playing-pos','number',function()
    if not visible then return end
    local ow,oh=get_osd()
    if not ow or not oh then return end
    -- Refresh the dynamic playlist snapshot and recompute before rendering so a
    -- newly selected playlist item never appears at an old scroll position.
    refresh_menu_snapshot()
    recompute_open_playlist_scrolls(ow,oh)
    render()
end)

-- Cross-platform dialog/clipboard backend.
-- Windows-only APIs are isolated to the Windows branch and are executed in a
-- separate STA PowerShell process. No WinForms/PowerShell code is invoked on
-- macOS/Linux. macOS uses osascript; Linux uses zenity/kdialog/yad.
local function submit_async(args, cb, stdin_data)
    mp.command_native_async({
        name='subprocess',
        args=args,
        capture_stdout=true,
        capture_stderr=true,
        stdin_data=stdin_data,
    }, function(success,res,err)
        if not success or not res then
            cb(nil,err or 'subprocess failed')
            return
        end
        if res.status ~= 0 then
            local e = (res.stderr or ''):gsub('[\r\n]+$','')
            cb(nil,e ~= '' and e or ('subprocess exited with status '..tostring(res.status)))
            return
        end
        cb(res.stdout or '',nil)
    end)
end

local function split_lines(s)
    local t={}
    for line in tostring(s or ''):gmatch('[^\r\n]+') do t[#t+1]=line end
    return t
end

local function get_filters()
    return mp.get_property_native('user-data/menu/dialog/filters') or {}
end

local function reply(src,name,...)
    local a={'script-message-to',src,name}
    for _,v in ipairs({...}) do a[#a+1]=v end
    mp.commandv(unpack(a))
end

local function ps_literal(v)
    -- PowerShell single-quoted literal. Suitable for UTF-8 .ps1 files.
    return "'" .. tostring(v or ''):gsub("'", "''") .. "'"
end

local function build_windows_filter()
    local parts={}
    for _,f in ipairs(get_filters()) do
        if type(f)=='table' and f.name and f.spec then
            parts[#parts+1]=tostring(f.name)
            parts[#parts+1]=tostring(f.spec)
        end
    end
    if #parts==0 then return '' end
    return table.concat(parts,'|')
end

local function write_utf8_file(path,text)
    local f,err=io.open(path,'wb')
    if not f then return false,err end
    -- UTF-8 BOM makes Windows PowerShell 5.1 parse Chinese text correctly.
    f:write('\239\187\191',text)
    f:close()
    return true
end

local function windows_ps_executable()
    local candidates = {}
    local windir = os.getenv('WINDIR') or os.getenv('windir')
    if windir and windir ~= '' then
        candidates[#candidates+1] = windir .. '\\System32\\WindowsPowerShell\\v1.0\\powershell.exe'
    end
    local program_files = os.getenv('ProgramFiles')
    if program_files and program_files ~= '' then
        candidates[#candidates+1] = program_files .. '\\PowerShell\\7\\pwsh.exe'
    end
    candidates[#candidates+1] = 'powershell.exe'
    candidates[#candidates+1] = 'pwsh.exe'
    for _, exe in ipairs(candidates) do
        if exe == 'powershell.exe' or exe == 'pwsh.exe' or utils.file_info(exe) then
            return exe
        end
    end
    return nil
end

local function run_windows_ps1(script,cb)
    local nonce=string.format('%d-%06d',os.time(),math.random(0,999999))
    local base=mp.command_native({'expand-path','~~/menu-dialog-'..nonce})
    local script_path=base..'.ps1'
    local out_path=base..'.out'
    local ok,err=write_utf8_file(script_path,script)
    if not ok then cb(nil,'cannot create temporary PowerShell script: '..tostring(err));return end
    local ps = windows_ps_executable()
    if not ps then
        os.remove(script_path); os.remove(out_path)
        cb(nil,'PowerShell not found (Windows PowerShell 5.1 or PowerShell 7 required)')
        return
    end

    -- The dialog is a real WinForms window.  Running it in a separate STA
    -- process makes it independent from whether mpv currently has a video
    -- or an active render window.  Results are written as UTF-8 by the PS1
    -- script itself, so Windows console code pages are never involved.
    local script_with_params = "param([string]$OutputFile)\n" .. script
    local ok2,err2=write_utf8_file(script_path,script_with_params)
    if not ok2 then
        os.remove(script_path); os.remove(out_path)
        cb(nil,'cannot update temporary PowerShell script: '..tostring(err2));return
    end

    submit_async({
        ps,'-NoLogo','-NoProfile','-STA','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',script_path,'-OutputFile',out_path
    },function(_,e)
        local out=nil
        if not e then
            local f=io.open(out_path,'rb')
            if f then
                out=f:read('*a');f:close()
                out=out:gsub('^\239\187\191','')
            else
                out=''
            end
        end
        os.remove(script_path); os.remove(out_path)
        cb(out,e)
    end)
end

local function build_windows_filter_wpf()
    local parts = {}
    for _, f in ipairs(get_filters()) do
        if type(f) == 'table' and f.name and f.spec then
            parts[#parts + 1] = tostring(f.name)
            parts[#parts + 1] = tostring(f.spec)
        end
    end
    if #parts == 0 then
        return 'All Files|*.*'
    end
    parts[#parts + 1] = 'All Files'
    parts[#parts + 1] = '*.*'
    return table.concat(parts, '|')
end

local function ps_single_quote(v)
    return "'" .. tostring(v or ''):gsub("'", "''") .. "'"
end

-- Primary Windows dialog implementation, based on the user-provided
-- open-file-dialog.lua. It deliberately uses mp.utils.subprocess() with
-- the simple `powershell` executable invocation and PresentationFramework,
-- because that path works even when mpv is still idle and no video is loaded.
local open_windows_legacy

local function open_windows_primary(multi, folder, save, default_name, src)
    -- Primary Windows implementation intentionally mirrors the user's known-good
    -- open-file-dialog.lua approach: mp.utils.subprocess() + powershell + WPF.
    -- Keep the PowerShell body static to avoid Lua/PowerShell quote or newline
    -- concatenation bugs. Filters are left to the native dialog/fallback path.
    local was_ontop = mp.get_property_native("ontop")
    if was_ontop then mp.set_property_native("ontop", false) end

    local script
    if folder then
        script = [[& {
    Trap {
        Write-Error -ErrorRecord $_
        Exit 1
    }
    Add-Type -AssemblyName System.Windows.Forms

    $u8 = [System.Text.Encoding]::UTF8
    $out = [Console]::OpenStandardOutput()

    $fbd = New-Object -TypeName System.Windows.Forms.FolderBrowserDialog
    $fbd.ShowNewFolderButton = $true

    If ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $u8filename = $u8.GetBytes("$($fbd.SelectedPath)`n")
        $out.Write($u8filename, 0, $u8filename.Length)
    }
}]]
    elseif save then
        local name = tostring(default_name or 'file'):gsub('\\', '\\\\'):gsub('"', '\\"')
        script = [[& {
    Trap {
        Write-Error -ErrorRecord $_
        Exit 1
    }
    Add-Type -AssemblyName PresentationFramework

    $u8 = [System.Text.Encoding]::UTF8
    $out = [Console]::OpenStandardOutput()

    $sfd = New-Object -TypeName Microsoft.Win32.SaveFileDialog
    $sfd.FileName = "]] .. name .. [["

    If ($sfd.ShowDialog() -eq $true) {
        $u8filename = $u8.GetBytes("$($sfd.FileName)`n")
        $out.Write($u8filename, 0, $u8filename.Length)
    }
}]]
    else
        -- This is deliberately the same stable code pattern as the supplied
        -- open-file-dialog.lua. The only dynamic part is Multiselect, inserted
        -- as an already-valid PowerShell literal on its own line.
        local multi_line = multi and '$true' or '$false'
        script = [[& {
    Trap {
        Write-Error -ErrorRecord $_
        Exit 1
    }
    Add-Type -AssemblyName PresentationFramework

    $u8 = [System.Text.Encoding]::UTF8
    $out = [Console]::OpenStandardOutput()

    $ofd = New-Object -TypeName Microsoft.Win32.OpenFileDialog
    $ofd.Multiselect = ]] .. multi_line .. [[

    If ($ofd.ShowDialog() -eq $true) {
        ForEach ($filename in $ofd.FileNames) {
            $u8filename = $u8.GetBytes("$filename`n")
            $out.Write($u8filename, 0, $u8filename.Length)
        }
    }
}]]
    end

    local ok_call, res = pcall(utils.subprocess, {
        args = {'powershell', '-NoProfile', '-Command', script},
        cancellable = false,
    })

    if was_ontop then mp.set_property_native("ontop", true) end

    if not ok_call then
        return false, tostring(res)
    end
    if not res or res.status ~= 0 then
        return false, (res and res.stderr) or ('subprocess exited with status ' .. tostring(res and res.status or 'unknown'))
    end

    local paths = split_lines(res.stdout or '')
    if #paths == 0 then return true, nil end

    if folder or save then
        reply(src, save and 'dialog-save-reply' or 'dialog-open-folder-reply', paths[1])
    else
        local a = {'script-message-to', src, 'dialog-open-multi-reply'}
        for _, path in ipairs(paths) do a[#a + 1] = path end
        mp.commandv(unpack(a))
    end
    return true, nil
end

local function open_windows(multi, folder, save, default_name, src)
    -- Try the proven WPF/WinForms implementation first.
    local ok, err = open_windows_primary(multi, folder, save, default_name, src)
    if ok then return end
    msg.warn('primary Windows dialog failed: ' .. tostring(err))
    -- Fallback to the newer STA/temp-file implementation.
    open_windows_legacy(multi, folder, save, default_name, src)
end

open_windows_legacy = function(multi,folder,save,default_name,src)
    local filters=build_windows_filter()
    local common={
        '$ErrorActionPreference = "Stop"',
        'Add-Type -AssemblyName System.Windows.Forms',
        '[System.Windows.Forms.Application]::EnableVisualStyles()',
        '$utf8 = New-Object System.Text.UTF8Encoding($false)',
        'function Write-DialogResult([string[]]$Lines) { [System.IO.File]::WriteAllLines($OutputFile, $Lines, $utf8) }',
    }
    local body={}
    if folder then
        body={
            '$d = New-Object System.Windows.Forms.FolderBrowserDialog',
            '$d.ShowNewFolderButton = $true',
            '$d.AutoUpgradeEnabled = $true',
            '$r = $d.ShowDialog()',
            'if ($r -eq [System.Windows.Forms.DialogResult]::OK) { Write-DialogResult @($d.SelectedPath) }',
            '$d.Dispose()',
        }
    elseif save then
        body={
            '$d = New-Object System.Windows.Forms.SaveFileDialog',
            '$d.AutoUpgradeEnabled = $true',
            '$d.OverwritePrompt = $true',
            '$d.AddExtension = $true',
            '$d.FileName = '..ps_literal(default_name or ''),
            '$filter = '..ps_literal(filters),
            'if ($filter -ne "") { $d.Filter = $filter }',
            '$r = $d.ShowDialog()',
            'if ($r -eq [System.Windows.Forms.DialogResult]::OK) { Write-DialogResult @($d.FileName) }',
            '$d.Dispose()',
        }
    else
        body={
            '$d = New-Object System.Windows.Forms.OpenFileDialog',
            '$d.AutoUpgradeEnabled = $true',
            '$d.Multiselect = '..(multi and '$true' or '$false'),
            '$d.CheckFileExists = $true',
            '$d.CheckPathExists = $true',
            '$filter = '..ps_literal(filters),
            'if ($filter -ne "") { $d.Filter = $filter }',
            '$r = $d.ShowDialog()',
            'if ($r -eq [System.Windows.Forms.DialogResult]::OK) { Write-DialogResult @($d.FileNames) }',
            '$d.Dispose()',
        }
    end
    table.insert(common,1,'Set-StrictMode -Version 2.0')
    local script=table.concat(common,'\n')..'\n'..table.concat(body,'\n')..'\n'
    run_windows_ps1(script,function(out,err)
        if err then msg.error('dialog: '..tostring(err));mp.osd_message('打开文件对话框失败: '..tostring(err),3);return end
        local paths=split_lines(out)
        if #paths==0 then return end
        if folder or save then
            reply(src,save and 'dialog-save-reply' or 'dialog-open-folder-reply',paths[1])
        else
            local a={'script-message-to',src,'dialog-open-multi-reply'}
            for _,p in ipairs(paths) do a[#a+1]=p end
            mp.commandv(unpack(a))
        end
    end)
end

local function as_escape(v)
    return tostring(v or ''):gsub('\\','\\\\'):gsub('"','\\"')
end

local function open_macos(multi,folder,save,default_name,src)
    local code
    if folder then
        code='set picked to choose folder with prompt "Select Folder"\nreturn POSIX path of picked'
    elseif save then
        code='set picked to choose file name with prompt "Save As" default name "'..as_escape(default_name or 'file')..'"\nreturn POSIX path of picked'
    elseif multi then
        code='set picked to choose file with prompt "Open" with multiple selections allowed\nset outText to ""\nrepeat with f in picked\nset outText to outText & POSIX path of f & linefeed\nend repeat\nreturn outText'
    else
        code='set picked to choose file with prompt "Open"\nreturn POSIX path of picked'
    end
    submit_async({'osascript','-e',code},function(out,err)
        if err then mp.osd_message('文件对话框: '..tostring(err),3);return end
        local paths=split_lines(out)
        if #paths==0 then return end
        if folder or save then reply(src,save and 'dialog-save-reply' or 'dialog-open-folder-reply',paths[1])
        else
            local a={'script-message-to',src,'dialog-open-multi-reply'}
            for _,p in ipairs(paths) do a[#a+1]=p end
            mp.commandv(unpack(a))
        end
    end)
end

local linux_tool_cache=nil
local function linux_command_exists(name)
    local r=utils.subprocess({args={'sh','-c','command -v '..name},cancellable=false,capture_stdout=true,capture_stderr=true})
    return r and r.status==0
end

local function linux_dialog_tool()
    if linux_tool_cache then return linux_tool_cache end
    for _,name in ipairs({'zenity','kdialog','yad'}) do
        if linux_command_exists(name) then linux_tool_cache=name;return name end
    end
    return nil
end

local function filter_specs_for_zenity()
    local args={}
    for _,f in ipairs(get_filters()) do
        if type(f)=='table' and f.name and f.spec then
            local spec=tostring(f.spec):gsub(';',' ')
            args[#args+1]='--file-filter='..tostring(f.name)..' | '..spec
        end
    end
    return args
end

local function filter_for_kdialog()
    local parts={}
    for _,f in ipairs(get_filters()) do
        if type(f)=='table' and f.name and f.spec then
            parts[#parts+1]=tostring(f.spec):gsub(';',' ')..'|'..tostring(f.name)
        end
    end
    return table.concat(parts,';')
end

local function open_linux(multi,folder,save,default_name,src)
    local tool=linux_dialog_tool()
    if not tool then
        mp.osd_message('Linux 文件对话框需要 zenity、kdialog 或 yad',4)
        return
    end
    local args
    if tool=='zenity' or tool=='yad' then
        args={tool,'--file-selection','--title='..(folder and '选择文件夹' or save and '保存文件' or '打开文件')}
        if folder then args[#args+1]='--directory' end
        if save then args[#args+1]='--save';args[#args+1]='--confirm-overwrite' end
        if multi and not folder and not save then args[#args+1]='--multiple';args[#args+1]='--separator=\n' end
        if default_name and default_name~='' then args[#args+1]='--filename='..default_name end
        for _,v in ipairs(filter_specs_for_zenity()) do args[#args+1]=v end
    else
        if folder then
            args={'kdialog','--getexistingdirectory'}
        elseif save then
            args={'kdialog','--getsavefilename',default_name or '',filter_for_kdialog()}
        else
            args={'kdialog','--getopenfilename','.',filter_for_kdialog()}
            if multi then args[#args+1]='--multiple' end
        end
    end
    submit_async(args,function(out,err)
        if err then mp.osd_message('文件对话框: '..tostring(err),3);return end
        local paths=split_lines((out or ''):gsub('\0','\n'))
        if #paths==0 then return end
        if folder or save then reply(src,save and 'dialog-save-reply' or 'dialog-open-folder-reply',paths[1])
        else
            local a={'script-message-to',src,'dialog-open-multi-reply'}
            for _,p in ipairs(paths) do a[#a+1]=p end
            mp.commandv(unpack(a))
        end
    end)
end

local function platform_name()
    return mp.get_property('platform') or 'linux'
end

mp.register_script_message('dialog/open-multi',function(src)
    local p=platform_name()
    if p=='windows' then open_windows(true,false,false,nil,src)
    elseif p=='darwin' then open_macos(true,false,false,nil,src)
    else open_linux(true,false,false,nil,src) end
end)

mp.register_script_message('dialog/open-folder',function(src)
    local p=platform_name()
    if p=='windows' then open_windows(false,true,false,nil,src)
    elseif p=='darwin' then open_macos(false,true,false,nil,src)
    else open_linux(false,true,false,nil,src) end
end)

mp.register_script_message('dialog/save',function(src)
    local default_name=mp.get_property('user-data/menu/dialog/default-name') or ''
    local p=platform_name()
    if p=='windows' then open_windows(false,false,true,default_name,src)
    elseif p=='darwin' then open_macos(false,false,true,default_name,src)
    else open_linux(false,false,true,default_name,src) end
end)

local function command_exists(name)
    local p=platform_name()
    if p=='windows' then return nil end
    local r=utils.subprocess({args={'sh','-c','command -v '..name},cancellable=false,capture_stdout=true,capture_stderr=true})
    return r and r.status==0
end

-- Windows clipboard deliberately uses utils.subprocess(), matching the known-good
-- open-file-dialog.lua approach. This avoids the -2 process-launch failures that
-- can occur with command_native_async() while mpv is still idle.
local function windows_clipboard_get(src)
    local was_ontop = mp.get_property_native('ontop')
    if was_ontop then mp.set_property_native('ontop', false) end

    local ps = windows_ps_executable()
    if not ps then
        if was_ontop then mp.set_property_native('ontop', true) end
        mp.osd_message('找不到 PowerShell，无法读取剪贴板',3)
        return
    end

    -- Use an STA PowerShell process and the WinForms clipboard API first,
    -- with a WPF fallback. No stdin is involved, so idle mpv is supported.
    local script = [[Add-Type -AssemblyName System.Windows.Forms
$u8 = [System.Text.Encoding]::UTF8
$out = [Console]::OpenStandardOutput()
try {
    $text = [System.Windows.Forms.Clipboard]::GetText()
    if ($null -eq $text) { $text = '' }
    $bytes = $u8.GetBytes([string]$text)
    $out.Write($bytes, 0, $bytes.Length)
    exit 0
} catch {
    try {
        Add-Type -AssemblyName PresentationCore
        $text = [System.Windows.Clipboard]::GetText()
        if ($null -eq $text) { $text = '' }
        $bytes = $u8.GetBytes([string]$text)
        $out.Write($bytes, 0, $bytes.Length)
        exit 0
    } catch {
        [Console]::Error.WriteLine($_.Exception.Message)
        exit 1
    }
}]]

    local ok,res = pcall(utils.subprocess,{
        args={ps,'-NoLogo','-NoProfile','-STA','-ExecutionPolicy','Bypass','-Command',script},
        cancellable=false, capture_stdout=true, capture_stderr=true,
    })

    if was_ontop then mp.set_property_native('ontop', true) end
    if not ok or not res or res.status ~= 0 then
        local err=(res and res.stderr) or 'subprocess failed'
        mp.osd_message('读取剪贴板失败: '..tostring(err),3)
        return
    end

    mp.commandv('script-message-to',src,'clipboard-get-reply',res.stdout or '')
end

local function windows_clipboard_set(text)
    local was_ontop = mp.get_property_native('ontop')
    if was_ontop then mp.set_property_native('ontop', false) end

    local ps = windows_ps_executable()
    if not ps then
        if was_ontop then mp.set_property_native('ontop', true) end
        mp.osd_message('找不到 PowerShell，无法设置剪贴板',3)
        return
    end

    local nonce=string.format('%d-%06d',os.time(),math.random(0,999999))
    local base=mp.command_native({'expand-path','~~/menu-clipboard-'..nonce})
    local input_path=base..'.txt'
    local ok_write,err=write_utf8_file(input_path,tostring(text or ''))
    if not ok_write then
        if was_ontop then mp.set_property_native('ontop', true) end
        mp.osd_message('设置剪贴板失败: '..tostring(err),3)
        return
    end

    -- Windows clipboard APIs require an STA thread. Use WinForms Clipboard
    -- with a file-backed payload, which avoids the null-value failure from
    -- Set-Clipboard when stdin is unavailable. Retry with WPF if necessary.
    local path_literal=ps_single_quote(input_path)
    local script = [[Add-Type -AssemblyName System.Windows.Forms
$path = ]]..path_literal..[[
try {
    $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    if ($null -eq $text) { $text = '' }
    [System.Windows.Forms.Clipboard]::SetText([string]$text, [System.Windows.Forms.TextDataFormat]::UnicodeText)
    exit 0
} catch {
    try {
        Add-Type -AssemblyName PresentationCore
        [System.Windows.Clipboard]::SetText([string]$text)
        exit 0
    } catch {
        [Console]::Error.WriteLine($_.Exception.Message)
        exit 1
    }
}]]

    local ok,res = pcall(utils.subprocess,{
        args={ps,'-NoLogo','-NoProfile','-STA','-ExecutionPolicy','Bypass','-Command',script},
        cancellable=false, capture_stdout=true, capture_stderr=true,
    })
    os.remove(input_path)
    if was_ontop then mp.set_property_native('ontop', true) end

    if not ok or not res or res.status ~= 0 then
        local err=(res and res.stderr) or 'subprocess failed'
        mp.osd_message('设置剪贴板失败: '..tostring(err),3)
        return
    end
end

-- Clipboard backend for menu commands such as:
--   script-message-to dialog set-clipboard ${path}
-- This follows the user's known-good copy-path.lua implementation: Windows
-- passes text as a PowerShell Set-Clipboard argument, while macOS/Linux use
-- stdin_data with their native clipboard utility. playback_only=false makes
-- the operation available even when mpv is still idle.
local function copy_path_platform()
    if package.config:sub(1, 1) == '\\' then
        return 'windows'
    end
    local p = mp.get_property('platform', 'unknown')
    if p == 'darwin' then return 'macos' end
    return 'linux'
end

local function copy_text_to_clipboard(text)
    if not text or text == '' then
        return false, 'No text to copy'
    end

    local p = copy_path_platform()
    local args
    local stdin = nil

    if p == 'windows' then
        -- Deliberately match the known-good copy-path.lua behavior.
        local escaped = tostring(text):gsub('"', '""')
        local cmd = 'Set-Clipboard -Value "' .. escaped .. '"'
        args = { 'powershell', '-Command', cmd }
    elseif p == 'macos' then
        args = { 'pbcopy' }
        stdin = text
    else
        local x = utils.subprocess({ args = { 'which', 'xclip' }, playback_only = false })
        if x and x.status == 0 then
            args = { 'xclip', '-selection', 'clipboard' }
        else
            local wl = utils.subprocess({ args = { 'which', 'wl-copy' }, playback_only = false })
            if wl and wl.status == 0 then
                args = { 'wl-copy' }
            else
                return false, 'No clipboard tool found (install xclip or wl-copy)'
            end
        end
        stdin = text
    end

    local result = utils.subprocess({
        args = args,
        stdin_data = stdin,
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
    })

    if result and result.status == 0 then
        return true, nil
    end

    local err = result and (result.error or result.stderr) or 'Unknown error'
    return false, err
end

mp.register_script_message('clipboard/get',function(src)
    local p=platform_name()
    if p=='windows' then
        windows_clipboard_get(src)
        return
    end

    local args
    if p=='darwin' then
        args={'pbpaste'}
    elseif command_exists('wl-paste') then
        args={'wl-paste','--no-newline'}
    elseif command_exists('xclip') then
        args={'xclip','-selection','clipboard','-o'}
    elseif command_exists('xsel') then
        args={'xsel','--clipboard','--output'}
    else
        mp.osd_message('找不到剪贴板工具（wl-paste/xclip/xsel）',3)
        return
    end
    submit_async(args,function(out,err)
        if not err then mp.commandv('script-message-to',src,'clipboard-get-reply',out or '')
        else mp.osd_message('读取剪贴板失败: '..tostring(err),3) end
    end)
end)

mp.register_script_message('clipboard/set',function(text)
    if text==nil then return end
    local value=tostring(text):gsub('\xFD.-\xFE','')
    local ok,err=copy_text_to_clipboard(value)
    if not ok then
        mp.osd_message('设置剪贴板失败: '..tostring(err),3)
        msg.error('clipboard/set failed: '..tostring(err))
    end
end)

mp.register_event('end-file',hide)
mp.register_event('shutdown',hide)
-- mouse-pos is observed directly. Keep a lightweight fallback sampler for mpv builds
-- that coalesce mouse-pos notifications during OSD interaction; it never performs
-- submenu polling/scroll correction itself.
mp.add_periodic_timer(0.08,function() if visible then on_mouse_move() end end)

msg.info('cross-platform menu backend v43 loaded as '..BACKEND_NAME)
