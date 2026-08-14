-- open-in-browser.lua
-- 一个通过 script-message 在浏览器中打开自定义网址的 mpv 插件

local utils = require("mp.utils")

-- 核心功能：在系统默认浏览器中打开 URL
local function open_url(url)
    if not url or url == "" then
        mp.msg.warn("没有提供要打开的 URL")
        return
    end

    -- 构建系统命令
    local command
    if package.config:sub(1,1) == "\\" then
        -- Windows
        command = { "cmd", "/c", "start", url }
    elseif package.config:sub(1,1) == "/" then
        -- macOS / Linux
        local uname = mp.get_property("platform", "unknown")
        if uname == "darwin" then
            command = { "open", url }
        else
            -- Linux: 优先使用 xdg-open，这是最通用的方式
            command = { "xdg-open", url }
        end
    end

    if not command then
        mp.msg.error("不支持的操作系统")
        return
    end

    -- 执行命令
    local result = utils.subprocess({ args = command, playback_only = false })
    if result.status == 0 then
        mp.msg.log("info", "成功在浏览器中打开: " .. url)
    else
        mp.msg.error("打开失败: " .. (result.error or "未知错误"))
    end
end

-- 注册 script-message 命令
-- 在 input.conf 中可以用: script-message open-browser "你的网址"
mp.register_script_message("open-browser-link", open_url)