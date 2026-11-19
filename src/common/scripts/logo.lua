local mp = require 'mp'
local assdraw = require 'mp.assdraw'
local opt = require 'mp.options'

local opts = {
    enabled = true,
    size = 1800,
    language = 'auto'
}

-- 读取 script-opts/logo.conf
opt.read_options(opts, 'logo')

-- 提取自 modernz-locale.json 的语言字典
local translations = {
    fr = "Déposez des fichiers ou des URL ici pour lire",
    de = "Dateien oder URLs hier ablegen, um sie abzuspielen",
    es = "Suelta archivos o URL aquí para reproducir",
    pl = "Upuść pliki lub adresy URL tutaj, aby odtworzyć",
    jp = "ここにファイルやURLをドロップして再生",
    zh = "将文件或 URL 拖放到此处播放",
    ["zh-tw"] = "將檔案或網址拖曳到這裡即可播放",
    ar = "اسحب الملفات أو الروابط هنا للتشغيل",
    ru = "Перетащите файлы или URL сюда для воспроизведения",
    is = "Dragðu skrár eða vefslóðir hingað til að spila",
    dk = "Træk filer eller URL'er hertil for at afspille",
}

local osd = mp.create_osd_overlay("ass-events")

-- 获取当前应该使用的语言文字
local function get_idle_text()
    local lang = opts.language
    
    -- 如果设置为 auto，则尝试读取 mpv 当前的系统语言
    if lang == "auto" then
        -- mpv 的 language 选项通常返回类似于 "zh-CN,zh,en" 的列表
        local sys_lang = mp.get_property("options/language", "en")
        local lang_list = {}
        for l in sys_lang:gmatch("[^,]+") do
            table.insert(lang_list, l:lower())
        end
        
        -- 按优先级匹配
        for _, l in ipairs(lang_list) do
            if l:find("^zh%-tw") or l:find("^zh%-hk") then
                return translations["zh-TW"]
            elseif l:find("^zh") then
                return translations["zh"]
            elseif l:find("^jp") or l:find("^ja") then
                return translations["jp"]
            elseif translations[l] then
                return translations[l]
            end
        end
    else
        -- 如果手动指定了语言
        lang = lang:lower()
        if translations[lang] then
            return translations[lang]
        end
    end
    
    -- 默认回退到英语
    return "Drop files or URLs to play here"
end

-- 与 mpv osc.lua 保持一致
local function set_osd(res_x, res_y, text, z)
    if osd.res_x == res_x and
       osd.res_y == res_y and
       osd.data == text then
        return
    end

    osd.res_x = res_x
    osd.res_y = res_y
    osd.data = text
    osd.z = z
    osd:update()
end

local function wipe_osd()
    set_osd(osd.res_x, osd.res_y, "", -1000)
end

-- 贝塞尔圆形路径
local function circle(cx, cy, r)
    local k = r * 0.5522847498

    return string.format(
        "m %.2f %.2f " ..
        "b %.2f %.2f %.2f %.2f %.2f %.2f " ..
        "b %.2f %.2f %.2f %.2f %.2f %.2f " ..
        "b %.2f %.2f %.2f %.2f %.2f %.2f " ..
        "b %.2f %.2f %.2f %.2f %.2f %.2f c",

        cx + r, cy,

        cx + r, cy + k,
        cx + k, cy + r,
        cx, cy + r,

        cx - k, cy + r,
        cx - r, cy + k,
        cx - r, cy,

        cx - r, cy - k,
        cx - k, cy - r,
        cx, cy - r,

        cx + k, cy - r,
        cx + r, cy - k,
        cx + r, cy
    )
end

-- 绘制一个 ASS 矢量图层
local function add_shape(ass, prefix, path, color)
    ass:new_event()
    ass:append(
        prefix ..
        "{\\c&H" .. color .. "&\\p6}" ..
        path ..
        "{\\p0}"
    )
end

-- Logo 主体
local function render_logo()
    if not opts.enabled then
        wipe_osd()
        return
    end

    if not mp.get_property_bool("idle-active", false) then
        wipe_osd()
        return
    end

    local dimensions = mp.get_property_native("osd-dimensions")

    if not dimensions or
       not dimensions.w or
       not dimensions.h then
        return
    end

    local aspect = dimensions.aspect

    if not aspect or aspect <= 0 then
        aspect = dimensions.w / dimensions.h
    end

    if aspect <= 0 then
        return
    end

    local display_h = 325
    local display_w = display_h * aspect

    -- 与 osc.lua 原版 Logo 尺寸及居中计算一致
    local logo_size = 1800 / 32

    local icon_x = (display_w - logo_size) / 2
    local icon_y = (display_h - logo_size) / 2 - 10

    local prefix = string.format(
        "{\\rDefault\\an7\\1a&H00&\\bord0\\shad0\\pos(%f,%f)}",
        icon_x,
        icon_y
    )

    local ass = assdraw.ass_new()

    -- 坐标中心：900, 900
    -- 原图颜色经过 ASS BGR 顺序转换

    -- 1. 外层紫色圆环
    add_shape(
        ass, prefix,
        circle(900, 900, 828),
        "F7648B"
    )

    -- 2. 深黑紫色边缘
    add_shape(
        ass, prefix,
        circle(900, 900, 762),
        "200610"
    )

    -- 3. 唱片主体
    add_shape(
        ass, prefix,
        circle(900, 900, 745),
        "461527"
    )

    -- 4. 中心圆形深色边框
    add_shape(
        ass, prefix,
        circle(900, 900, 430),
        "200610"
    )

    -- 5. 中心浅紫色圆形
    add_shape(
        ass, prefix,
        circle(900, 900, 390),
        "F7C1D4"
    )

    -- 6. 播放按钮外框
    local triangle_outer =
        "m 735 700 " ..
        "b 735 650 765 630 810 655 " ..
        "l 1130 840 " ..
        "b 1180 870 1180 930 1130 960 " ..
        "l 810 1145 " ..
        "b 765 1170 735 1150 735 1100 c"

    add_shape(
        ass, prefix,
        triangle_outer,
        "200610"
    )

    -- 7. 播放按钮内部
    local triangle_inner =
        "m 775 735 " ..
        "b 775 715 785 710 805 720 " ..
        "l 1090 885 " ..
        "b 1110 895 1110 905 1090 915 " ..
        "l 805 1080 " ..
        "b 785 1090 775 1085 775 1065 c"

    add_shape(
        ass, prefix,
        triangle_inner,
        "F7648B"
    )

    -- 8. 左上角高光
    local highlight =
        "m 340 470 " .. -- 起点向内收缩 (原 300 450)
        "b 340 440 350 410 370 385 " ..
        "b 420 320 500 260 580 230 " ..
        "b 615 215 640 220 650 235 " ..
        "b 660 250 655 275 625 295 " ..
        "b 560 335 480 395 435 455 " ..
        "b 415 480 390 505 365 505 " ..
        "b 345 505 340 490 340 470 c"

    add_shape(
        ass, prefix,
        highlight,
        "F986A8"
    )

    local text_y = icon_y + logo_size + 30
    ass:new_event()
    ass:append(
        string.format("{\\rDefault\\an5\\pos(%f,%f)\\fs22\\c&HFFFFFF&\\bord0\\shad0}", display_w / 2, text_y) ..
        get_idle_text()
    )

    set_osd(
        display_w,
        display_h,
        ass.text,
        -1000
    )
end

-- 清理
local function render_wipe()
    wipe_osd()
end

-- 状态更新
local function update()
    render_logo()
end

-- 空闲状态
mp.observe_property(
    "idle-active",
    "bool",
    update
)

-- 窗口尺寸变化
mp.observe_property(
    "osd-dimensions",
    "native",
    update
)

-- 播放状态变化
mp.register_event("file-loaded", render_wipe)
mp.register_event("end-file", update)

-- 手动开关
mp.add_key_binding(
    "Ctrl+l",
    "toggle-logo",
    function()
        opts.enabled = not opts.enabled
        update()
    end
)

-- 脚本退出
mp.register_event("shutdown", render_wipe)

mp.msg.info("Custom Logo loaded")
update()