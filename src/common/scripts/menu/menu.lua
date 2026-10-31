-- mpv-menu-plugin-next: cross-platform menu backend for mpv.
-- Rendering model:
--   * bind the ASS overlay canvas to the CURRENT valid OSD dimensions
--   * never render while the OSD size is 0x0
--   * all menu geometry, hit-testing and mouse coordinates use the same canvas
-- Scaling model (uosc-style baselines + automatic resolution adaptation):
--   * Windowed baseline: 36px, fullscreen baseline: 50px (uosc defaults).
--   * Both baselines scale linearly with OSD height relative to 1080p,
--     clamped to [1.0x, 2.8x]. This adapts to 4K/8K without any manual
--     configuration while preserving uosc's default look at 1080p.
--   * Setting menu_item_height / menu_item_height_fullscreen to a number
--     disables the automatic scaling for that mode (explicit override).
--   * BASE_ROW_HEIGHT (48) is the nominal reference the rest of this script's
--     dimensions were written against. ui_scale() returns
--     item_height / BASE_ROW_HEIGHT, so font/padding/arrow sizes all scale
--     proportionally with the row height.
--   * menu_font_scale is applied on top of all menu text, matching uosc.

local mp = require('mp')
local msg = require('mp.msg')
local opts = require('mp.options')
local utils = require('mp.utils')

------------------------------------------------------------
-- 默认配置（每次 reload 都从这份默认值重新开始）
------------------------------------------------------------
local o_defaults = {
    font = '',
    font_name = '',
    font_size = 29,
    bold = false,
    italic = false,
    background = '#2C2C2E',
    border = '#5A5A5F',
    text = '#F2F2F7',
    disabled_text = '#8E8E93',
    hover = '#505050',
    hover_bg = '#505050',
    hover_text = '#FFFFFF',
    hover_corner_radius = 0,
    hover_margin_x = 2,
    hover_margin_y = 0,
    shortcut = '#D1D1D6',
    hover_shortcut = '#FFFFFF',
    separator = '#636366',
    submenu_arrow = '#E5E5EA',
    arrow = '#E5E5EA',
    arrow_alpha = 0,
    hover_arrow = '#FFFFFF',
    hover_arrow_alpha = 0,
    check = '#F2F2F7',
    shadow = '#000000',
    bg_alpha = 0,
    shadow_alpha = 90,
    radius = 13,
    border_width = 2,
    hover_border_width = 0,
    hover_border = '#00000000',
    shadow_blur = 7,

    -- ===== Liquid Glass =====
    glass_enabled = false,               -- 总开关；关闭后回退到原始菜单样式
    glass_color = '#17181C',             -- 玻璃底色
    glass_opacity = 38,                  -- 着色强度：0=清透，100=实色
    glass_border_opacity = 8,            -- 边缘亮度/不透明度：0=不显示，100=完全显示
    glass_shadow = true,                 -- 软阴影
    glass_blur = true,                   -- GLSL 真模糊（需 vo=gpu-next）
    glass_refraction = true,             -- 边缘折射
    glass_increase_contrast = false,     -- 无障碍：黑玻璃 + 可见描边
    glass_reduce_transparency = false,   -- 无障碍：磨砂近不透明
    reduce_motion = false,               -- 关闭弹簧/缩放动画（当前菜单本身不使用此类动画）
    -- uosc-aligned menu sizing. 'auto' = scale uosc's 36/50 baselines with
    -- OSD height relative to 1080p (clamped 1.0x .. 2.8x). A positive number
    -- disables auto scaling for that mode and pins the row height.
    menu_item_height = 47,
    menu_item_height_fullscreen = 50,
    menu_font_scale = 1,
    separator_height = 13,
    padding_x = 12,
    padding_y = 13,
    shortcut_gap = 7,
    shortcut_right_gap = 4,
    playlist_shortcut_right_gap = 4,
    arrow_width = 32,
    arrow_font_size = 43,
    arrow_char = '›',
    submenu_gap = 7,
    screen_margin = 11,
    min_width = 350,
    max_width = 1080,
    max_visible_rows = 0,
    scroll_threshold = 0.80,
    scrollbar_width = 9,
    scrollbar_gap = 0,
    scrollbar_min_thumb = 36,
    scrollbar_right_gap = 2,
    scrollbar_track = '#48484A',
    scrollbar_thumb = '#8E8E93',
    scrollbar_track_alpha = 70,
    scrollbar_thumb_alpha = 145,
    scroll_step = 2,
    click_to_show_submenus = false,
    hide_root_separators = true,
    child_indent_chars = 1,
    root_indent_chars = 1,
    playlist_header_indent_chars = 2,
    modal_mask = true,
    modal_mask_alpha = 255,
    modal_z = 1000000,
    macos_font_scale = 1.4,
}

-- Nominal reference the whole layout was authored against.
local BASE_ROW_HEIGHT = 47
local WINDOW_ITEM_HEIGHT_1080 = 36
local FULLSCREEN_ITEM_HEIGHT_1080 = 50
local AUTO_SCALE_MIN = 1.0
local AUTO_SCALE_MAX = 2.8

local o = {}
local ui = {} -- 统一的绘制样式表，隔离 if-else

local platform = mp.get_property('platform') or ''

-- 预先计算所有渲染所需的最终颜色与透明度
local function apply_style()
    -- 默认（非 glass）参数
    ui.background = o.background
    ui.bg_alpha = o.bg_alpha
    ui.border = o.border
    ui.border_width = o.border_width
    ui.border_alpha = nil
    ui.shadow = o.shadow
    ui.shadow_alpha = o.shadow_alpha
    ui.shadow_blur = o.shadow_blur
    ui.hover = o.hover
    ui.hover_alpha = 0
    ui.hover_border = o.hover_border
    ui.hover_border_width = o.hover_border_width
    ui.glass_top_highlight = false
    ui.glass_highlight_alpha = 0

    if o.glass_enabled then
        local opacity = math.max(0, math.min(100, tonumber(o.glass_opacity) or 38))
        if o.glass_reduce_transparency then opacity = math.max(opacity, 88) end
        if o.glass_increase_contrast then opacity = math.max(opacity, 65) end

        ui.background = o.glass_increase_contrast and '#000000' or (o.glass_color or '#17181C')
        ui.border = o.glass_increase_contrast and '#FFFFFF' or o.border
        ui.bg_alpha = math.floor(255 * (1 - opacity / 100) + 0.5)

        ui.border_width = (o.border_width == o_defaults.border_width) and 1 or o.border_width
        if o.glass_increase_contrast then ui.border_width = math.max(ui.border_width, 1.5) end

        ui.hover_alpha = 105
        ui.hover_border = (o.hover_border == o_defaults.hover_border) and '#DCE8FA' or o.hover_border
        ui.hover_border_width = (o.hover_border_width == o_defaults.hover_border_width) and 1 or o.hover_border_width

        local border_opacity = math.max(0, math.min(100, tonumber(o.glass_border_opacity) or 8))
        ui.border_alpha = math.floor(255 * (1 - border_opacity / 100) + 0.5)
        if o.glass_increase_contrast then ui.border_alpha = 55 end
        if o.glass_reduce_transparency then ui.border_alpha = math.min(ui.border_alpha, 100) end

        ui.shadow_alpha = 155
        ui.shadow_blur = 7
        ui.glass_top_highlight = border_opacity > 0
        ui.glass_highlight_alpha = ui.border_alpha or 235
    end
end

local function load_options()
    for k in pairs(o) do o[k] = nil end
    for k, v in pairs(o_defaults) do o[k] = v end
    opts.read_options(o, 'menu_style')

    if o.font_name ~= '' then o.font = o.font_name end
    if o.hover_bg ~= '' then o.hover = o.hover_bg end
    if o.hover_text == '' then o.hover_text = o.text end
    if o.arrow ~= '' then o.submenu_arrow = o.arrow end
    if o.hover_arrow == '' then o.hover_arrow = o.submenu_arrow end
    if o.hover_shortcut == '' then o.hover_shortcut = o.shortcut end

    if o.font == '' then
        if platform == 'windows' then
            o.font = 'Microsoft YaHei UI'
        elseif platform == 'darwin' then
            o.font = 'PingFang SC'
        else
            o.font = 'Noto Sans CJK SC'
        end
    end

    apply_style()
end

load_options()

local REF_W, REF_H = 1280, 720
local current_ow, current_oh = 0, 0
local menu_prop = 'user-data/menu/items'
local BACKEND_NAME = 'menu'

local overlay = mp.create_osd_overlay('ass-events')
overlay.res_x = REF_W
overlay.res_y = REF_H
pcall(function() overlay.z = tonumber(o.modal_z) or 1000000 end)

local visible = false
local items = {}
local items_dirty = true
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
local current_vo = mp.get_property('current-vo')
local video_track_present = mp.get_property_native('current-tracks/video') ~= nil

------------------------------------------------------------
-- Liquid Glass background shader (mpv vo=gpu-next)
------------------------------------------------------------
local MENU_GLASS_SHADER = [==[
// Menu glass for vo=gpu-next: frosts and refracts the video behind Menu's glass
// surfaces, adds the light catching their rim and the shadow they cast.
// ModernZ loads this itself and moves the surfaces through glsl-shader-opts.
// Up to four rounded rectangles, in fractions of the video area.

//!PARAM mng_on
//!TYPE DYNAMIC int
//!MINIMUM 0
//!MAXIMUM 1
0

//!PARAM mng_strength
//!TYPE DYNAMIC float
//!MINIMUM 0.0
//!MAXIMUM 1.0
1.0

//!PARAM mng_unit
//!TYPE DYNAMIC float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.0014

//!PARAM mng_lens
//!TYPE DYNAMIC float
//!MINIMUM 0.0
//!MAXIMUM 1.0
1.0

//!PARAM mng_shadow
//!TYPE DYNAMIC float
//!MINIMUM 0.0
//!MAXIMUM 1.0
1.0

//!PARAM mng_tone
//!TYPE DYNAMIC float
//!MINIMUM 0.0
//!MAXIMUM 1.0
1.0

//!PARAM mng_0x
//!TYPE DYNAMIC float
0.0
//!PARAM mng_0y
//!TYPE DYNAMIC float
0.0
//!PARAM mng_0w
//!TYPE DYNAMIC float
0.0
//!PARAM mng_0h
//!TYPE DYNAMIC float
0.0
//!PARAM mng_0r
//!TYPE DYNAMIC float
0.0
//!PARAM mng_0a
//!TYPE DYNAMIC float
1.0
//!PARAM mng_0f
//!TYPE DYNAMIC float
0.0
//!PARAM mng_1x
//!TYPE DYNAMIC float
0.0
//!PARAM mng_1y
//!TYPE DYNAMIC float
0.0
//!PARAM mng_1w
//!TYPE DYNAMIC float
0.0
//!PARAM mng_1h
//!TYPE DYNAMIC float
0.0
//!PARAM mng_1r
//!TYPE DYNAMIC float
0.0
//!PARAM mng_1a
//!TYPE DYNAMIC float
1.0
//!PARAM mng_1f
//!TYPE DYNAMIC float
0.0
//!PARAM mng_2x
//!TYPE DYNAMIC float
0.0
//!PARAM mng_2y
//!TYPE DYNAMIC float
0.0
//!PARAM mng_2w
//!TYPE DYNAMIC float
0.0
//!PARAM mng_2h
//!TYPE DYNAMIC float
0.0
//!PARAM mng_2r
//!TYPE DYNAMIC float
0.0
//!PARAM mng_2a
//!TYPE DYNAMIC float
1.0
//!PARAM mng_2f
//!TYPE DYNAMIC float
0.0
//!PARAM mng_3x
//!TYPE DYNAMIC float
0.0
//!PARAM mng_3y
//!TYPE DYNAMIC float
0.0
//!PARAM mng_3w
//!TYPE DYNAMIC float
0.0
//!PARAM mng_3h
//!TYPE DYNAMIC float
0.0
//!PARAM mng_3r
//!TYPE DYNAMIC float
0.0
//!PARAM mng_3a
//!TYPE DYNAMIC float
1.0
//!PARAM mng_3f
//!TYPE DYNAMIC float
0.0

//!HOOK OUTPUT
//!BIND HOOKED
//!SAVE MZG_A
//!WIDTH HOOKED.w 270 * HOOKED.h /
//!HEIGHT 270
//!WHEN mng_on
//!DESC [Menu] glass: downscale
// a fixed 270 rows, so the frost looks the same at any window size
vec4 hook() {
    // box filter over the source texels under this one, two by two with bilinear taps
    int n = clamp(int(ceil(HOOKED_size.y / 540.0)), 1, 8);
    vec4 sum = vec4(0.0);
    for (int y = 0; y < n; y++) {
        for (int x = 0; x < n; x++) {
            vec2 o = (vec2(float(x), float(y)) - 0.5 * float(n - 1)) * 2.0;
            sum += HOOKED_tex(HOOKED_pos + o * HOOKED_pt);
        }
    }
    return sum / float(n * n);
}

//!HOOK OUTPUT
//!BIND MZG_A
//!SAVE MZG_B
//!WIDTH MZG_A.w
//!HEIGHT MZG_A.h
//!WHEN mng_on
//!DESC [Menu] glass: horizontal blur
vec4 hook() {
    // gaussian, sigma 3 texels (about 12 px at 1080p), as 11 bilinear taps: frosted lightly,
    // so the picture stays recognizable through the clear glass
    const float w[6] = float[](0.13304, 0.23238, 0.13539, 0.05118, 0.01254, 0.00199);
    const float o[6] = float[](0.0, 1.4584, 3.4040, 5.3518, 7.3029, 9.2582);
    vec4 c = MZG_A_tex(MZG_A_pos) * w[0];
    for (int i = 1; i < 6; i++) {
        vec2 d = vec2(o[i] * MZG_A_pt.x, 0.0);
        c += (MZG_A_tex(MZG_A_pos + d) + MZG_A_tex(MZG_A_pos - d)) * w[i];
    }
    return c;
}

//!HOOK OUTPUT
//!BIND MZG_B
//!SAVE MZG_C
//!WIDTH MZG_B.w
//!HEIGHT MZG_B.h
//!WHEN mng_on
//!DESC [Menu] glass: vertical blur
vec4 hook() {
    const float w[6] = float[](0.13304, 0.23238, 0.13539, 0.05118, 0.01254, 0.00199);
    const float o[6] = float[](0.0, 1.4584, 3.4040, 5.3518, 7.3029, 9.2582);
    vec4 c = MZG_B_tex(MZG_B_pos) * w[0];
    for (int i = 1; i < 6; i++) {
        vec2 d = vec2(0.0, o[i] * MZG_B_pt.y);
        c += (MZG_B_tex(MZG_B_pos + d) + MZG_B_tex(MZG_B_pos - d)) * w[i];
    }
    return c;
}

//!HOOK OUTPUT
//!BIND HOOKED
//!BIND MZG_C
//!WHEN mng_on
//!DESC [Menu] glass: composite

// signed distance (in pixels) to a rounded rectangle given in fractions of the video
float mng_box(vec2 p, float x, float y, float w, float h, float r) {
    vec2 half_size = 0.5 * vec2(w, h) * HOOKED_size;
    float rad = r * HOOKED_size.y;
    vec2 q = abs(p - (vec2(x, y) * HOOKED_size + half_size)) - half_size + rad;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rad;
}

// distance to the nearest surface; its opacity (it may be fading in or out) goes to a,
// its frost to f
float mng_sdf_a(vec2 p, out float a, out float f) {
    float d = 1e6, k;
    a = 1.0;
    f = 0.0;
    if (mng_0w > 0.0) { k = mng_box(p, mng_0x, mng_0y, mng_0w, mng_0h, mng_0r); if (k < d) { d = k; a = mng_0a; f = mng_0f; } }
    if (mng_1w > 0.0) { k = mng_box(p, mng_1x, mng_1y, mng_1w, mng_1h, mng_1r); if (k < d) { d = k; a = mng_1a; f = mng_1f; } }
    if (mng_2w > 0.0) { k = mng_box(p, mng_2x, mng_2y, mng_2w, mng_2h, mng_2r); if (k < d) { d = k; a = mng_2a; f = mng_2f; } }
    if (mng_3w > 0.0) { k = mng_box(p, mng_3x, mng_3y, mng_3w, mng_3h, mng_3r); if (k < d) { d = k; a = mng_3a; f = mng_3f; } }
    return d;
}

float mng_sdf(vec2 p) {
    float a, f;
    return mng_sdf_a(p, a, f);
}

vec4 hook() {
    const vec3 luma = vec3(0.2126, 0.7152, 0.0722);
    vec4 c = HOOKED_tex(HOOKED_pos);
    vec2 p = HOOKED_pos * HOOKED_size;
    float u = max(mng_unit * HOOKED_size.y, 0.25); // pixels per ModernZ layout unit
    float alpha, frost;
    float d = mng_sdf_a(p, alpha, frost);
    if (d > 48.0 * u)
        return c;

    if (d > 0.0) {
        // the shadow the glass casts: wide, soft, and a little deeper over bright pictures
        if (mng_shadow > 0.0) {
            float sa, sf;
            float ds = max(mng_sdf_a(p - vec2(0.0, 8.0 * u), sa, sf), 0.0) / (18.0 * u);
            float under = dot(MZG_C_tex(HOOKED_pos).rgb, luma);
            float k = mng_shadow * sa * mix(0.05, 0.13, smoothstep(0.15, 0.85, under));
            c.rgb *= 1.0 - k * exp(-0.5 * ds * ds);
        }
        if (d >= 0.5)
            return c;
    }

    // outward normal of the nearest edge
    vec2 nx = vec2(1.0, 0.0);
    vec2 n = vec2(mng_sdf(p + nx.xy) - mng_sdf(p - nx.xy), mng_sdf(p + nx.yx) - mng_sdf(p - nx.yx));
    n = dot(n, n) > 1e-8 ? normalize(n) : vec2(0.0, -1.0);

    // a slab whose edge rounds off like a lens: near the rim it takes the picture from
    // further inside and squeezes it toward the edge; the middle stays true
    float e = clamp(1.0 + min(d, 0.0) / (20.0 * u), 0.0, 1.0); // 1 at the edge, 0 inside
    float slope = e / sqrt(max(1.0 - e * e, 0.05));
    // it materializes: the bending and the light grow in with it
    float bend = alpha * mng_lens * 3.2 * u * slope;
    vec2 q = clamp((p - n * bend) / HOOKED_size, vec2(0.0), vec2(1.0));
    vec3 g = MZG_C_tex(q).rgb;
    // menus are regular glass, frostier than the clear controls: a ring of taps widens the blur
    if (frost > 0.0) {
        vec3 ring = vec3(0.0);
        for (int i = 0; i < 8; i++) {
            float an = 0.7854 * float(i) + 0.3927;
            ring += MZG_C_tex(q + vec2(cos(an), sin(an)) * 4.5 * MZG_C_pt).rgb;
        }
        g = mix(g, (g + ring) / 9.0, frost);
    }

    // vibrancy
    float l = dot(g, luma);
    g = clamp(mix(vec3(l), g, 1.35), 0.0, 1.0);

    // legibility: the brighter the picture around it, the deeper the glass (measured over an
    // area, so a bright spot stays brighter than what is around it); dark ones a faint lift
    vec2 o = 10.0 * MZG_C_pt;
    float under = dot(MZG_C_tex(q).rgb + MZG_C_tex(q + vec2(o.x, 0.0)).rgb + MZG_C_tex(q - vec2(o.x, 0.0)).rgb
                      + MZG_C_tex(q + vec2(0.0, o.y)).rgb + MZG_C_tex(q - vec2(0.0, o.y)).rgb, luma) / 5.0;
    g = g * (1.0 - mng_tone * 0.52 * smoothstep(0.30, 1.0, under)) + mng_tone * 0.035 * (1.0 - under);

    // the rounded edge darkens toward the rim, so the shape holds over bright pictures
    g *= 1.0 - alpha * mng_lens * 0.20 * e * e;

    // light: a hairline along the rim, brightest where it faces the light (upper left) and
    // where the light leaves again (lower right), and a soft glow across the rounded edge
    float f = dot(n, vec2(-0.6, -0.8));
    float lit = 0.25 + 0.75 * max(f, 0.0) * max(f, 0.0) + 0.45 * max(-f, 0.0) * max(-f, 0.0);
    float line = exp(-2.0 * (d + 0.8) * (d + 0.8));
    g += alpha * mng_lens * lit * (1.05 * line + 0.10 * e * e * e);

    float m = clamp(0.5 - d, 0.0, 1.0) * mng_strength * alpha;
    return vec4(mix(c.rgb, g, m), c.a);
}
]==]
local menu_glass = { path = nil, loaded = false, failed = false, sig = nil, unload_timer = nil }

local function menu_glass_install()
    if not o.glass_enabled or not o.glass_blur or menu_glass.path or menu_glass.failed then return end
    if mp.get_property('current-vo') ~= 'gpu-next' then return end
    
    local dir = mp.command_native({'expand-path', '~~cache/'})
    if not dir or not utils.file_info(dir) then
        dir = os.getenv('TEMP') or os.getenv('TMPDIR') or '/tmp'
    end
    
    local path = utils.join_path(dir, 'menu-liquid-glass.glsl')
    local f = io.open(path, 'wb')
    if not f then
        menu_glass.failed = true
        msg.warn('menu liquid glass: could not write shader; using translucent panels')
        return
    end
    f:write(MENU_GLASS_SHADER)
    f:close()
    menu_glass.path = path
    for _, p in ipairs(mp.get_property_native('glsl-shaders') or {}) do
        if p == path then menu_glass.loaded = true end
    end
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function menu_glass_update()
    if not menu_glass.path or menu_glass.failed then return end
    
    local should_blur = o.glass_enabled and o.glass_blur and visible and current_ow > 0 and current_oh > 0 and #rects > 0
    local kv = { mng_on = should_blur and '1' or '0' }
    
    if should_blur then
        local d = mp.get_property_native('osd-dimensions')
        local ml, mt, vw, vh = 0, 0, current_ow, current_oh
        if type(d) == 'table' then
            local dw, dh = tonumber(d.w) or 0, tonumber(d.h) or 0
            if dw > 0 and dh > 0 then
                local ml0, mt0 = tonumber(d.ml) or 0, tonumber(d.mt) or 0
                local mr0, mb0 = tonumber(d.mr) or 0, tonumber(d.mb) or 0
                local sx, sy = current_ow / dw, current_oh / dh
                ml, mt = ml0 * sx, mt0 * sy
                vw = math.max(1, (dw - ml0 - mr0) * sx)
                vh = math.max(1, (dh - mt0 - mb0) * sy)
            end
        end
        kv.mng_unit = string.format('%.6f', 1 / vh)
        kv.mng_strength = '1.0'
        kv.mng_lens = (o.glass_refraction and not o.glass_increase_contrast and not o.glass_reduce_transparency) and '1' or '0'
        kv.mng_shadow = o.glass_shadow and '1' or '0'
        kv.mng_tone = o.glass_increase_contrast and '1' or '0'
        for i = 0, 3 do
            local r = rects[i + 1]
            local p = 'mng_' .. i
            if r then
                kv[p .. 'x'] = string.format('%.6f', (r.x - ml) / vw)
                kv[p .. 'y'] = string.format('%.6f', (r.y - mt) / vh)
                kv[p .. 'w'] = string.format('%.6f', r.w / vw)
                kv[p .. 'h'] = string.format('%.6f', r.h / vh)
                kv[p .. 'r'] = string.format('%.6f', (o.radius * (r.scale or 1)) / vh)
                kv[p .. 'a'] = '1.0'
                kv[p .. 'f'] = (not o.glass_increase_contrast and not o.glass_reduce_transparency) and '1.0' or '0.0'
            else
                kv[p .. 'w'] = '0.0'
            end
        end
    end
    
    local keys = {}
    for k in pairs(kv) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. '=' .. kv[k] end
    local sig = table.concat(parts, ',')
    
    if sig == menu_glass.sig then return end
    menu_glass.sig = sig
    
    local function send(...)
        mp.command_native_async({'change-list', ...}, function() end)
    end
    
    if should_blur then
        if menu_glass.unload_timer then
            menu_glass.unload_timer:kill()
            menu_glass.unload_timer = nil
        end
        send('glsl-shader-opts', 'add', sig)
        if not menu_glass.loaded then
            send('glsl-shaders', 'append', menu_glass.path)
            menu_glass.loaded = true
        end
        return
    end
    
    -- 关闭模糊逻辑
    if not menu_glass.loaded then return end
    send('glsl-shader-opts', 'append', 'mng_on=0')
    if not menu_glass.unload_timer then
        menu_glass.unload_timer = mp.add_timeout(5, function()
            menu_glass.unload_timer = nil
            if menu_glass.loaded and menu_glass.sig and menu_glass.sig:find('mng_on=0', 1, true) then
                send('glsl-shaders', 'remove', menu_glass.path)
                menu_glass.loaded = false
            end
        end)
    end
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

local function numeric_or_nil(v)
    if v == nil or v == 'auto' or v == '' then return nil end
    local n = tonumber(v)
    if n and n > 0 then return n end
    return nil
end

local function resolve_item_height(ow, oh)
    local fullscreen = mp.get_property_native('fullscreen')
    if fullscreen then
        local explicit = numeric_or_nil(o.menu_item_height_fullscreen)
        if explicit then return explicit end
    else
        local explicit = numeric_or_nil(o.menu_item_height)
        if explicit then return explicit end
    end

    local h = tonumber(oh) or 1080
    if h <= 0 then h = 1080 end
    local f = clamp(h / 1080, AUTO_SCALE_MIN, AUTO_SCALE_MAX)

    if fullscreen then
        return FULLSCREEN_ITEM_HEIGHT_1080 * f
    end
    return WINDOW_ITEM_HEIGHT_1080 * f
end

local function ui_scale(ow, oh)
    if not ow or not oh or ow <= 0 or oh <= 0 then return 1 end
    local s = resolve_item_height(ow, oh) / BASE_ROW_HEIGHT
    if platform == 'darwin' then
        s = s * (tonumber(o.macos_font_scale) or 1.0)
    end
    return s
end

local function menu_font_scale_factor()
    local m = tonumber(o.menu_font_scale)
    if not m or m <= 0 then return 1 end
    return m
end

local function text_width(s, scale)
    local fs = o.font_size * (scale or 1) * menu_font_scale_factor()
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
        if text_width(candidate, scale) > maxw then break end
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

local function draw_path(path, color, alpha, bord, blur, border_color, border_alpha)
    return string.format('{\\an7\\pos(0,0)\\p1\\1c%s\\3c%s\\1a&H%02X&\\3a&H%02X&\\bord%.1f\\blur%.1f\\shad0}%s{\\p0}',
        ass_color(color), ass_color(border_color or color), clamp(alpha or 0,0,255), clamp(border_alpha == nil and (alpha or 0) or border_alpha,0,255), bord or 0, blur or 0, path)
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
    local s = size * menu_font_scale_factor()
    return string.format('{\\an%s\\pos(%.2f,%.2f)\\fn%s\\fs%.1f\\b%s\\i%s\\bord0\\shad0\\1c%s\\1a&H%02X&}%s',
        align or '5', x,y,fn,s,b and '1' or '0',i and '1' or '0',ass_color(color),clamp(a,0,255),ass_text(text))
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
            if normalize_menu(it.submenu or {}) == 0 then
                it.hidden = true
            else
                visible_count = visible_count + 1
            end
        elseif it.type ~= 'separator' then
            local title = split_title(it.title)
            if tostring(title or ''):gsub('^%s+', ''):gsub('%s+$', '') == '' then
                it.hidden = true
            else
                visible_count = visible_count + 1
            end
        end
    end

    local pending_sep = nil
    local has_prev_item = false
    for _, it in ipairs(list) do
        if it.type == 'separator' then
            it.hidden = true
            pending_sep = it
        elseif not it.hidden then
            if pending_sep and has_prev_item then pending_sep.hidden = false end
            pending_sep = nil
            has_prev_item = true
        end
    end

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
    return s:gsub('script%-message%-to%s+dialog(%s)', 'script-message-to ' .. BACKEND_NAME .. '%1')
end

local function menu_at(level)
    if level == 1 then return items end
    local cur = items
    for i=1,level-1 do
        local it = cur[open_path[i]]
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
    if not level or level <= 1 then return nil end
    local parent = menu_at(level - 1)[open_path[level - 1]]
    if parent and type(parent._playlist_header) == 'string' then
        return parent._playlist_header
    end
    return nil
end

local function build_layout(list, scale, level)
    scale = scale or 1
    local layout = {}
    local row_h = BASE_ROW_HEIGHT * scale
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
    local sr_gap = math.max(0, tonumber(o.shortcut_right_gap) or 0) * scale

    local content_w = min_w
    for _,it in ipairs(list or {}) do
        if not is_hidden(it) and it.type ~= 'separator' then
            local title, shortcut = split_title(it.title)
            local w = text_width(title, scale) + px*2 + child_indent
            if state_has(it,'checked') then w = w + 20*scale end
            if shortcut ~= '' then w = w + gap + text_width(shortcut, scale) + sr_gap end
            if it.type == 'submenu' then w = w + arrow end
            content_w = math.max(content_w, w)
        end
    end

    local layout, desired_h, row_h, top_pad, bottom_pad, header_h = build_layout(list, scale, level)
    local playlist_header = get_playlist_header(list, level)
    if playlist_header then content_w = math.max(content_w, text_width(playlist_header, scale) + px * 2) end

    local max_h = panel_max_height(oh, scale)
    local scrollable = desired_h > max_h + 0.01

    if scrollable then content_w = content_w + (o.scrollbar_width + o.scrollbar_gap) * scale end
    content_w = content_w + 1 * scale

    local maxw = clamp(content_w, min_w, math.min(max_w, max_screen_w))
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
        scrollable = scrollable, scroll_offset = scroll_offset, max_scroll = max_scroll,
        row_h = row_h, top_pad = top_pad, bottom_pad = bottom_pad, header_h = header_h,
        content_h = math.max(1, h - top_pad - bottom_pad - header_h), desired_h = desired_h,
        scrollbar_width = o.scrollbar_width * scale, scrollbar_gap = o.scrollbar_gap * scale,
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
                if x >= sb_left - sbg and x <= r.x + r.w then return level,nil end
            end
            for _,g in ipairs(r.layout) do
                local gy = r.top_pad + g.y - r.top_pad - (r.scroll_offset or 0)
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
        if r and x>=r.x and x<=r.x+r.w and y>=r.y and y<=r.y+r.h then return level,r end
    end
    return nil,nil
end

local function scroll_panel(level, delta)
    local r=rects[level]
    if not r or not r.scrollable then return false end
    local step = (r.row_h or BASE_ROW_HEIGHT) * tonumber(o.scroll_step or 1)
    if step <= 0 then step = r.row_h or 1 end
    local new_offset = clamp((r.scroll_offset or 0) + delta*step, 0, r.max_scroll or 0)
    if math.abs(new_offset - (r.scroll_offset or 0)) < 0.01 then return false end
    r.scroll_offset = new_offset
    scroll_offsets[level] = new_offset
    return true
end

local modal_mask_cache = { w = 0, h = 0, s = '' }
local function draw_modal_mask(ow, oh)
    if not o.modal_mask then return '' end
    if modal_mask_cache.w == ow and modal_mask_cache.h == oh then
        return modal_mask_cache.s
    end
    local path = string.format('m 0 0 l %.2f 0 l %.2f %.2f l 0 %.2f c', ow, ow, oh, oh)
    modal_mask_cache.s = draw_path(path, ui.background, o.modal_mask_alpha, 0, 0, ui.background)
    modal_mask_cache.w, modal_mask_cache.h = ow, oh
    return modal_mask_cache.s
end

-- 根据层级计算嵌套子菜单的透明度 (隔绝 if-else)
local function calc_panel_alpha(level)
    if not o.glass_enabled then return ui.bg_alpha end
    local opacity = math.max(0, math.min(100, tonumber(o.glass_opacity) or 38))
    if o.glass_reduce_transparency then opacity = math.max(opacity, 88) end
    if o.glass_increase_contrast then opacity = math.max(opacity, 65) end
    if level > 1 then
        opacity = math.min(82, opacity + math.min(22, (level - 1) * 12))
    end
    return math.floor(255 * (1 - opacity / 100) + 0.5)
end

local function draw_menu(list,x,y,level,ow,oh,w,h,layout,scale,meta)
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

    -- 阴影 (直接读取预先计算好的 ui)
    out[#out+1] = draw_path(round_rect(x+2*scale,y+3*scale,w,h,radius), ui.shadow, ui.shadow_alpha, 0, ui.shadow_blur*scale, ui.shadow)

    -- 面板背景 (读取 ui 和嵌套层级透明度)
    out[#out+1] = draw_path(round_rect(x,y,w,h,radius), ui.background, calc_panel_alpha(level), ui.border_width*scale, 0, ui.border, ui.border_alpha)
    
    -- 玻璃顶部高光：仅当玻璃模糊着色器真正生效时才绘制。
    -- idle / 无视频 / vo 非 gpu-next / shader 未加载时，黑底下会多出一条白线。
    local glass_rim_active = ui.glass_top_highlight
        and o.glass_blur
        and menu_glass.loaded
        and not menu_glass.failed
        and current_vo == 'gpu-next'
        and video_track_present
    if glass_rim_active then
        out[#out+1] = draw_line(x+radius*0.72,y+0.8*scale,x+w-radius*0.72,y+0.8*scale, '#FFFFFF', ui.glass_highlight_alpha, math.max(0.7,0.8*scale))
    end

    local content_top = y + meta.top_pad + (meta.header_h or 0)
    local content_bottom = y + h - meta.bottom_pad
    local scroll_offset = meta.scroll_offset or 0

    local playlist_header = get_playlist_header(list, level)
    if meta.header_h and meta.header_h > 0 and playlist_header then
        local header_y = y + meta.top_pad + meta.header_h / 2
        local header_indent = o.playlist_header_indent_chars * o.font_size * scale
        local header_x = x + o.padding_x*scale + header_indent
        out[#out+1] = text_tag(header_x, header_y, playlist_header, o.text, o.font_size*scale, '4')
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
                    
                    row_out[#row_out+1]=draw_path(round_rect(sel_x,sel_y,sel_w,sel_h,hr), ui.hover, ui.hover_alpha,
                        (tonumber(ui.hover_border_width) or 0)*scale, 0, ui.hover_border)
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
                if meta.scrollable then right_edge = right_edge - meta.scrollbar_width - meta.scrollbar_gap end
                local arrow_center = nil
                local shortcut_right_x = nil
                local shortcut_right_gap = math.max(0, tonumber(o.shortcut_right_gap or 0)) * scale
                
                if playlist_header and shortcut ~= '' then
                    shortcut_right_gap = shortcut_right_gap + math.max(0, tonumber(o.playlist_shortcut_right_gap or 0)) * scale
                end
                if it.type == 'submenu' then
                    arrow_center = right_edge - (o.arrow_width * scale) / 2
                    local arrow_left = right_edge - o.arrow_width * scale
                    if shortcut ~= '' then shortcut_right_x = arrow_left - shortcut_right_gap end
                    right_edge = arrow_left - o.shortcut_gap * scale
                else
                    if shortcut ~= '' then shortcut_right_x = right_edge - shortcut_right_gap end
                end

                local display_shortcut = shortcut
                local shortcut_display_w = 0
                if shortcut ~= '' and shortcut_right_x then
                    local shortcut_maxw = math.max(1, shortcut_right_x - left_x - o.shortcut_gap * scale)
                    display_shortcut = truncate_text(shortcut, shortcut_maxw, scale)
                    shortcut_display_w = text_width(display_shortcut, scale)
                    right_edge = shortcut_right_x - shortcut_display_w - o.shortcut_gap * scale
                end

                local display_title=truncate_text(title,math.max(1,right_edge-left_x),scale)
                row_out[#row_out+1]=text_tag(left_x,text_y,display_title,c,fs,'4')
                if display_shortcut ~= '' then
                    row_out[#row_out+1]=text_tag(shortcut_right_x,text_y,display_shortcut,disabled and o.disabled_text or (ih and o.hover_shortcut or o.shortcut),fs,'6')
                end
                if it.type == 'submenu' then
                    local arrow_fs=o.arrow_font_size*scale
                    row_out[#row_out+1]=text_tag(arrow_center,text_y,o.arrow_char,ih and o.hover_arrow or o.submenu_arrow,arrow_fs,'5',nil,nil,ih and o.hover_arrow_alpha or o.arrow_alpha)
                end
            end
            if #row_out > 0 then
                for _, line in ipairs(row_out) do out[#out+1] = clip_tag .. line end
            end
        end
    end

    if meta.scrollable then
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
    return table.concat(out,'\n')
end

-- 更新 overlay 数据，但只有内容或画布尺寸真的变化时才提交。
-- 这能跳过重复 render() 生成相同 ASS 内容后的无效 overlay:update()。
local function set_overlay_data(data, ow, oh)
    local changed = overlay.data ~= data or overlay.res_x ~= ow or overlay.res_y ~= oh
    overlay.res_x = ow
    overlay.res_y = oh
    overlay.data = data
    return changed
end

local function clear()
    local ow,oh=get_osd()
    if ow and oh then
        current_ow,current_oh=ow,oh
    else
        ow,oh=REF_W,REF_H
    end
    local changed = set_overlay_data('', ow, oh)
    if menu_glass.path then menu_glass_update() end
    if changed then overlay:update() end
end

local render

local function prepare_playlist_scroll_for_open(level, item)
    if not item or type(item._playlist_current_menu_index) ~= 'number' or level <= 1 or type(item.submenu) ~= 'table' then return false end
    local ow, oh = get_osd()
    if not ow or not oh or ow <= 0 or oh <= 0 then return false end

    local _, _, layout, _, meta = measure(item.submenu, ow, oh, level)
    if not meta or not meta.scrollable then
        scroll_offsets[level] = 0
        return false
    end

    local target
    for _, g in ipairs(layout or {}) do
        if g.index == item._playlist_current_menu_index then target = g; break end
    end
    if not target then return false end

    local top = meta.top_pad + (meta.header_h or 0)
    local desired = target.y - top
    local offset = clamp(desired, 0, meta.max_scroll or 0)
    scroll_offsets[level] = offset
    return true
end

local function prepare_initial_playlist_scrolls(list, ow, oh, level)
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
                local row_h = BASE_ROW_HEIGHT * scale
                local pad_y = o.padding_y * scale
                local header_h = (type(it._playlist_header) == 'string' and it._playlist_header ~= '') and row_h or 0

                local desired_h = pad_y + header_h + pad_y
                for _, g in ipairs(layout or {}) do desired_h = desired_h + g.h end
                
                local max_h = panel_max_height(oh, scale)
                local max_scroll = math.max(0, desired_h - math.min(desired_h, max_h))

                if max_scroll > 0 then
                    local target_g
                    for _, g in ipairs(layout or {}) do
                        if g.index == it._playlist_current_menu_index then target_g = g; break end
                    end
                    if target_g then
                        local target_top = pad_y + header_h
                        scroll_offsets[child_level] = clamp(target_g.y - target_top, 0, max_scroll)
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
    if items_dirty then
        items_dirty=false
        if normalize_menu(root) == 0 then clear(); return end
    end

    local rw,rh,r_layout,r_scale,r_meta=measure(root,ow,oh,1)
    local margin=o.screen_margin*r_scale
    local x = anchor_x or (mx+2*r_scale)
    local y = anchor_y or (my+2*r_scale)

    if x+rw>ow-margin then x=(anchor_x and anchor_x-rw-2*r_scale) or (mx-rw-2*r_scale) end
    if y+rh>oh-margin then y=(anchor_y and anchor_y-rh-2*r_scale) or (my-rh-2*r_scale) end
    x=clamp(x,margin,ow-rw-margin)
    y=clamp(y,margin,oh-rh-margin)

    local ass={}
    ass[#ass+1]=draw_modal_mask(ow,oh)
    ass[#ass+1]=draw_menu(root,x,y,1,ow,oh,rw,rh,r_layout,r_scale,r_meta)

    for level=2,#open_path+1 do
        local parent=rects[level-1]
        local pitems=menu_at(level-1)
        local pidx=open_path[level-1]
        local child=pitems[pidx] and pitems[pidx].submenu or {}
        if parent and child then
            local cw,ch,c_layout,c_scale,c_meta=measure(child,ow,oh,level)
            local gap=o.submenu_gap*c_scale
            local cx=parent.x+parent.w+gap
            if cx+cw>ow-o.screen_margin*c_scale then cx=parent.x-cw-gap end

            local pg=nil
            for _,g in ipairs(parent.layout or {}) do if g.index==pidx then pg=g;break end end
            local cy=pg and (parent.y+pg.y-(parent.scroll_offset or 0)) or parent.y+o.padding_y*c_scale
            cy=clamp(cy,o.screen_margin*c_scale,oh-ch-o.screen_margin*c_scale)
            ass[#ass+1]=draw_menu(child,cx,cy,level,ow,oh,cw,ch,c_layout,c_scale,c_meta)
        end
    end

    local data = table.concat(ass,'\n')
    local overlay_changed = set_overlay_data(data, ow, oh)
    menu_glass_install()
    menu_glass_update()
    if overlay_changed then overlay:update() end
end

local saved_modernz_visibility = nil
local saved_osd_level = nil
local osd_restore_token = 0

local function set_osc_visibility(enable)
    local script_id = mp.get_script_name()
    
    if enable then
        if saved_modernz_visibility ~= nil then
            pcall(mp.commandv, 'script-message-to', 'modernz', 'osc-visibility', saved_modernz_visibility, 'yes')
            saved_modernz_visibility = nil
        end
        pcall(mp.commandv, 'script-message-to', 'uosc', 'disable-elements', script_id, '')
        pcall(mp.commandv, 'script-message', 'osc-visibility', 'auto')

        if saved_osd_level ~= nil then
            local level = saved_osd_level
            saved_osd_level = nil
            osd_restore_token = osd_restore_token + 1
            local token = osd_restore_token
            mp.add_timeout(0.05, function()
                if token == osd_restore_token and mp.get_property_native('osd-level') == 0 then
                    mp.set_property_native('osd-level', level)
                end
            end)
        end
        return
    end

    osd_restore_token = osd_restore_token + 1
    local mz = mp.get_property_native('user-data/osc/visibility')
    if mz ~= nil then
        saved_modernz_visibility = mz
        pcall(mp.commandv, 'script-message-to', 'modernz', 'osc-visibility', 'never', 'yes')
    end
    pcall(mp.commandv, 'script-message-to', 'uosc', 'disable-elements', script_id, 'timeline,controls')
    pcall(mp.commandv, 'script-message', 'osc-visibility', 'never')

    if saved_osd_level == nil then
        saved_osd_level = mp.get_property_native('osd-level')
        mp.set_property_native('osd-level', 0)
    end
end

local function remove_bindings()
    for n,_ in pairs(key_bindings) do pcall(mp.remove_key_binding,n) end
    key_bindings={}
end

local function cancel_hover_timer()
end

local function hide()
    if show_timer then show_timer:kill(); show_timer=nil end
    if geometry_timer then geometry_timer:kill(); geometry_timer=nil end
    cancel_hover_timer()
    if not visible then clear(); return end
    visible=false
    set_osc_visibility(true)
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
        if it._playlist_current_menu_index then prepare_playlist_scroll_for_open(selected_level, it) end
        render()
        return
    end
    local cmd=actual_cmd(it.cmd)
    hide()
    if not cmd or cmd == '' then return end

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
        ensure_visible(selected_level, selected_index)
        render()
    end,{repeatable=true})
    bind('DOWN','menu-down',function()
        selected_index=next_selectable(menu_at(selected_level),selected_index,1)
        ensure_visible(selected_level, selected_index)
        render()
    end,{repeatable=true})
    bind('RIGHT','menu-right',function()
        local it=menu_at(selected_level)[selected_index]
        if it and it.type=='submenu' and not state_has(it,'disabled') then
            open_path[selected_level]=selected_index
            selected_level=selected_level+1
            selected_index=first_selectable(it.submenu)
            if it._playlist_current_menu_index then prepare_playlist_scroll_for_open(selected_level, it) end
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
        if not l or not i then hide(); return end
        local it=menu_at(l)[i]
        if not it or it.type=='separator' or state_has(it,'disabled') then hide(); return end
        selected_level,selected_index=l,i
        activate_selected()
    end)
    bind('MBTN_RIGHT','menu-right-click',hide)
    bind('MBTN_MID','menu-middle-block',function() end)
    bind('MBTN_MID_DBL','menu-middle-dbl-block',function() end)
    bind('MBTN_LEFT_DBL','menu-left-dbl-block',function()
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
        ensure_visible(selected_level, selected_index)
        render()
    end)
end

local function clear_deeper_path(level)
    for k=#open_path, level+1, -1 do open_path[k]=nil end
end

local function on_mouse_move()
    if not visible then return end
    local x,y=get_mouse()
    local l,i=hit_test(x,y)
    if not l or not i then return end

    local list=menu_at(l)
    local it=list and list[i]
    if not it or it.type=='separator' or is_hidden(it) then return end

    local changed=(hover_level~=l or hover_index~=i)
    hover_level,hover_index=l,i
    selected_level,selected_index=l,i

    if open_path[l] ~= i then
        clear_deeper_path(l)
        open_path[l]=nil
    end

    local rendered = false
    if it.type=='submenu' and not state_has(it,'disabled') then
        open_path[l]=i
        if changed then rendered = schedule_hover_open(l,i) end
    else
        clear_deeper_path(l-1)
        open_path[l]=nil
        cancel_hover_timer()
    end

    if changed and not rendered then render() end
end

local function refresh_menu_snapshot()
    pcall(mp.commandv, 'script-message', 'menu-refresh-dynamic')
    local ok, data = pcall(mp.get_property_native, menu_prop)
    if ok and type(data) == 'table' then
        items = data
        normalize_menu(items)
        items_dirty = false
        return true
    end
    return false
end

local function open_hover_now(l, i)
    if not visible or not l or not i then return false end
    local list=menu_at(l)
    local it=list and list[i]
    if not it or it.type~='submenu' or state_has(it,'disabled') then
        clear_deeper_path(l-1)
        open_path[l]=nil
        render()
        return true
    end
    if o.click_to_show_submenus then return false end

    if it._playlist_total or it._playlist_current_menu_index then
        refresh_menu_snapshot()
        list=menu_at(l)
        it=list and list[i]
        if not it or it.type~='submenu' then return false end
    end

    open_path[l]=i
    for k=#open_path,l+1,-1 do open_path[k]=nil end
    selected_level=l+1
    selected_index=first_selectable(it.submenu)

    if it._playlist_current_menu_index then
        prepare_playlist_scroll_for_open(selected_level, it)
    end
    render()
    return true
end

schedule_hover_open = function(l, i)
    if o.click_to_show_submenus or not l or not i then return false end
    local list=menu_at(l)
    local it=list and list[i]
    if not it or it.type~='submenu' or state_has(it,'disabled') then return false end
    return open_hover_now(l, i)
end

local function show(attempt)
    attempt = attempt or 1
    pcall(mp.commandv,'script-message','menu-refresh-dynamic')

    if show_timer then show_timer:kill(); show_timer=nil end
    local delay = (attempt == 1) and 0.03 or 0.05
    show_timer = mp.add_timeout(delay, function()
        show_timer = nil
        refresh_menu_snapshot()

        local ready = type(items)=='table' and #items>0 and first_selectable(items) ~= nil
        if not ready then
            if attempt < 6 then show(attempt + 1)
            else msg.warn('menu data is empty') end
            return
        end

        local mx,my=get_mouse()
        anchor_x,anchor_y=(mx or 0)+2,(my or 0)+2
        visible=true
        set_osc_visibility(false)
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
        geometry_timer=nil
    end)
end

mp.register_script_message('show',show)
mp.register_script_message('hide',hide)
mp.register_script_message('geometry-debug',function()
    local ow,oh=get_osd()
    local x,y= get_mouse()
    local item_h = (ow and oh) and resolve_item_height(ow, oh) or WINDOW_ITEM_HEIGHT_1080
    local scale = (ow and oh) and ui_scale(ow, oh) or 1
    local font_h = o.font_size * scale * menu_font_scale_factor()
    msg.info(string.format('OSD=%s | canvas=OSD | mouse=%.1f,%.1f | overlay.res=%d,%d | item_h=%.1f | font=%.1f | scale=%.3f | fullscreen=%s',
        ow and oh and (ow..'x'..oh) or '0x0', x, y, overlay.res_x, overlay.res_y,
        item_h, font_h, scale, tostring(mp.get_property_native('fullscreen'))))
    mp.osd_message(string.format('OSD %s | item_h=%.0f | font=%.0f | scale=%.2f | mouse %.0f,%.0f',
        ow and oh and (ow..'x'..oh) or '0x0', item_h, font_h, scale, x, y), 2)
end)

mp.add_timeout(0,function()
    mp.commandv('script-message','menu-init',BACKEND_NAME)
end)

mp.observe_property(menu_prop,'native',function(_,v)
    if type(v)=='table' then
        items=v
        items_dirty=true
    else
        items={}
        items_dirty=false
    end
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

mp.observe_property('current-vo','string',function(_,v)
    current_vo = v
    if visible then
        menu_glass_install()
        menu_glass.sig = nil
        render()
    end
end)

mp.observe_property('current-tracks/video','native',function(_,v)
    video_track_present = v ~= nil
    if visible then render() end
end)

mp.observe_property('fullscreen','native',function()
    if not visible then return end
    local ow,oh = get_osd()
    if ow and oh then recompute_open_playlist_scrolls(ow,oh) end
    rects = {}
    render()
end)

mp.observe_property('playlist-playing-pos','number',function()
    if not visible then return end
    local ow,oh=get_osd()
    if not ow or not oh then return end
    refresh_menu_snapshot()
    recompute_open_playlist_scrolls(ow,oh)
    render()
end)

local function submit_async(args, cb, stdin_data)
    mp.command_native_async({
        name='subprocess',
        args=args,
        capture_stdout=true,
        capture_stderr=true,
        stdin_data=stdin_data,
        playback_only=false,
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
    if #parts == 0 then return 'All Files|*.*' end
    parts[#parts + 1] = 'All Files'
    parts[#parts + 1] = '*.*'
    return table.concat(parts, '|')
end

local function ps_single_quote(v)
    return "'" .. tostring(v or ''):gsub("'", "''") .. "'"
end

local open_windows_legacy

local function open_windows_primary(multi, folder, save, default_name, src)
    local was_ontop = mp.get_property_native("ontop")
    if was_ontop then mp.set_property_native("ontop", false) end

    -- 重写：使用 table.concat 逐行构建 PowerShell 脚本，彻底避免 Lua 长字符串拼接导致的换行丢失问题
    local script
    if folder then
        script = table.concat({
            '& {',
            '    Trap { Write-Error -ErrorRecord $_; Exit 1 }',
            '    Add-Type -AssemblyName System.Windows.Forms',
            '    $u8 = [System.Text.Encoding]::UTF8',
            '    $out = [Console]::OpenStandardOutput()',
            '    $fbd = New-Object -TypeName System.Windows.Forms.FolderBrowserDialog',
            '    $fbd.ShowNewFolderButton = $true',
            '    If ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {',
            '        $u8filename = $u8.GetBytes("$($fbd.SelectedPath)`n")',
            '        $out.Write($u8filename, 0, $u8filename.Length)',
            '    }',
            '}'
        }, '\n')
    elseif save then
        local name = tostring(default_name or 'file'):gsub('\\', '\\\\'):gsub('"', '\\"')
        script = table.concat({
            '& {',
            '    Trap { Write-Error -ErrorRecord $_; Exit 1 }',
            '    Add-Type -AssemblyName PresentationFramework',
            '    $u8 = [System.Text.Encoding]::UTF8',
            '    $out = [Console]::OpenStandardOutput()',
            '    $sfd = New-Object -TypeName Microsoft.Win32.SaveFileDialog',
            '    $sfd.FileName = "' .. name .. '"',
            '    If ($sfd.ShowDialog() -eq $true) {',
            '        $u8filename = $u8.GetBytes("$($sfd.FileName)`n")',
            '        $out.Write($u8filename, 0, $u8filename.Length)',
            '    }',
            '}'
        }, '\n')
    else
        local multi_line = multi and '$true' or '$false'
        script = table.concat({
            '& {',
            '    Trap { Write-Error -ErrorRecord $_; Exit 1 }',
            '    Add-Type -AssemblyName PresentationFramework',
            '    $u8 = [System.Text.Encoding]::UTF8',
            '    $out = [Console]::OpenStandardOutput()',
            '    $ofd = New-Object -TypeName Microsoft.Win32.OpenFileDialog',
            '    $ofd.Multiselect = ' .. multi_line,
            '    If ($ofd.ShowDialog() -eq $true) {',
            '        ForEach ($filename in $ofd.FileNames) {',
            '            $u8filename = $u8.GetBytes("$filename`n")',
            '            $out.Write($u8filename, 0, $u8filename.Length)',
            '        }',
            '    }',
            '}'
        }, '\n')
    end

    local ok_call, res = pcall(utils.subprocess, {
        args = {'powershell', '-NoProfile', '-Command', script},
        cancellable = false,
    })

    if was_ontop then mp.set_property_native("ontop", true) end

    if not ok_call then return false, tostring(res) end
    if not res or res.status ~= 0 then return false, (res and res.stderr) or ('subprocess exited with status ' .. tostring(res and res.status or 'unknown')) end

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
    local ok, err = open_windows_primary(multi, folder, save, default_name, src)
    if ok then return end
    msg.warn('primary Windows dialog failed: ' .. tostring(err))
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
    local osascript = '/usr/bin/osascript'
    if not utils.file_info(osascript) then osascript = 'osascript' end

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
    submit_async({osascript,'-e',code},function(out,err)
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
        local paths=split_lines((out or ''):gsub('%z','\n'))
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

local function windows_clipboard_get(src)
    local was_ontop = mp.get_property_native('ontop')
    if was_ontop then mp.set_property_native('ontop', false) end

    local ps = windows_ps_executable()
    if not ps then
        if was_ontop then mp.set_property_native('ontop', true) end
        mp.osd_message('找不到 PowerShell，无法读取剪贴板',3)
        return
    end

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

local function copy_path_platform()
    if package.config:sub(1, 1) == '\\' then return 'windows' end
    local p = mp.get_property('platform', 'unknown')
    if p == 'darwin' then return 'macos' end
    return 'linux'
end

local function copy_text_to_clipboard(text)
    if not text or text == '' then return false, 'No text to copy' end

    local p = copy_path_platform()
    local args
    local stdin = nil

    if p == 'windows' then
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

    if result and result.status == 0 then return true, nil end
    return false, result and (result.error or result.stderr) or 'Unknown error'
end

mp.register_script_message('clipboard/get',function(src)
    local p=platform_name()
    if p=='windows' then windows_clipboard_get(src); return end

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
mp.add_periodic_timer(0.04,function() if visible then on_mouse_move() end end)

msg.info('cross-platform menu backend v51 loaded as '..BACKEND_NAME)

local function reload_menu()
    msg.info('menu: reload_menu() called')
    load_options()
    modal_mask_cache.w = 0
    menu_glass.sig = nil
    if o.glass_enabled then menu_glass_install() end

    if visible then
        local ok, err = pcall(render)
        if not ok then msg.error('menu: reload render failed: ' .. tostring(err)) end
    end

    pcall(mp.commandv, 'script-message', 'menu-reloaded', BACKEND_NAME)
    return true
end

mp.register_script_message('reload-menu', reload_menu)
mp.register_script_message('reload', reload_menu)