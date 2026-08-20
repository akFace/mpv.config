-- github-release-checker.lua
-- 自动检查 akFace/mpv.config 的 GitHub 最新 Release
--
-- 安装：将本文件放到 mpv/scripts/ 目录
-- 默认快捷键：Ctrl+Alt+U

local mp = require 'mp'
local utils = require 'mp.utils'

local REPO = "akFace/mpv.config"
local API_URL = "https://api.github.com/repos/" .. REPO .. "/releases/latest"

local open_cmd_args = nil
local pending_open = false   -- 防止重复延迟打开

local function osd(text, duration)
    mp.osd_message(text, duration or 4)
end

local function trim(s)
    return (s or ""):match("^%s*(.-)%s*$")
end

local function normalize_version(v)
    if not v then return nil end
    v = trim(v)
    v = v:gsub("^v", "")
    return v
end

-- 版本比较函数（提取所有数字段）
local function compare_version(a, b)
    a = normalize_version(a)
    b = normalize_version(b)
    if not a or not b then return nil end

    local function parse_version(v)
        local nums = {}
        for num in v:gmatch("%d+") do
            table.insert(nums, tonumber(num))
        end
        return nums
    end

    local pa, pb = parse_version(a), parse_version(b)
    local maxn = math.max(#pa, #pb)
    for i = 1, maxn do
        local na = pa[i] or 0
        local nb = pb[i] or 0
        if na < nb then return -1 end
        if na > nb then return 1 end
    end
    return 0
end

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

local function get_current_version()
    local mpv_conf = mp.find_config_file("mpv.conf")
    if not mpv_conf then return nil end
    local config_dir = mpv_conf:match("^(.*)[/\\]")
    if not config_dir then return nil end
    local version = read_file(config_dir .. "/config-version")
    if not version then return nil end
    version = version:match("^%s*(.-)%s*$")
    return version ~= "" and version or nil
end

-- 多平台获取最新版本（依次尝试 curl / wget / PowerShell）
local function get_latest_release()
    local is_windows = package.config:sub(1,1) == "\\"
    local candidates = {}

    if is_windows then
        table.insert(candidates, {"curl", "-sL", "--max-time", "10", API_URL})
        table.insert(candidates, {
            "powershell", "-Command",
            "Invoke-RestMethod -Uri '" .. API_URL .. "' -UserAgent 'mpv-checker' | ConvertTo-Json -Compress"
        })
    else
        table.insert(candidates, {"curl", "-sL", "--max-time", "10", API_URL})
        table.insert(candidates, {"wget", "-qO-", "--timeout=10", API_URL})
    end

    for _, cmd in ipairs(candidates) do
        local res = mp.command_native({
            name = "subprocess",
            args = cmd,
            capture_stdout = true,
            capture_stderr = true,
            playback_only = false,
        })
        if res and res.status == 0 and res.stdout then
            local tag = res.stdout:match([["tag_name"%s*:%s*"([^"]+)"]])
            if tag then
                return tag
            end
        end
    end
    return nil
end

-- 初始化打开浏览器的命令（跨平台）
local function init_open_cmd()
    if open_cmd_args then return end

    local is_windows = package.config:sub(1,1) == "\\"
    if is_windows then
        open_cmd_args = { "cmd", "/c", "start", "" }
        return
    end

    local res = mp.command_native({
        name = "subprocess",
        args = { "uname", "-s" },
        capture_stdout = true,
        playback_only = false,
    })

    if res and res.status == 0 then
        local osname = res.stdout:gsub("%s+", "")
        if osname == "Darwin" then
            open_cmd_args = { "open" }
        else
            open_cmd_args = { "xdg-open" }
        end
    else
        open_cmd_args = { "xdg-open" }
    end
end

local function open_url(url)
    init_open_cmd()
    local args = {}
    for _, v in ipairs(open_cmd_args) do table.insert(args, v) end
    table.insert(args, url)
    mp.command_native({
        name = "subprocess",
        args = args,
        playback_only = false,
    })
end

local function check_update()
    mp.msg.info("正在检查 akFace/mpv.config 更新……")
    osd("正在检查 akFace/mpv.config 更新……", 2)

    local latest = get_latest_release()
    if not latest then
        osd("检查更新失败：无法获取最新版本", 5)
        mp.msg.error("无法从 GitHub 返回内容中找到 tag_name")
        return
    end
    mp.msg.info("GitHub 最新版本：" .. latest)

    local current = get_current_version()
    if not current then
        osd("无法读取 config-version", 5)
        return
    end
    mp.msg.info("本地 config-version：" .. current)

    local cmp = compare_version(current, latest)
    if cmp == nil then
        osd("版本比较失败\n当前：" .. current .. "\n最新：" .. latest, 5)
        return
    end

    if cmp < 0 then
        -- 显示提示，延迟 4 秒后打开浏览器（防止重复触发）
        osd("发现新版本！\n当前：" .. current .. "\n最新：" .. latest .. "\n即将打开 Release 页面…", 5)
        if not pending_open then
            pending_open = true
            mp.add_timeout(4, function()
                open_url("https://github.com/akFace/mpv.config/releases")
                pending_open = false
            end)
        end
    elseif cmp == 0 then
        osd("已是最新版本：" .. latest, 4)
    else
        osd("当前版本：" .. current .. "\nGitHub 最新版本：" .. latest, 5)
    end
end

mp.register_script_message("check-config-update", check_update)
mp.add_key_binding("Ctrl+Alt+u", "check-config-update", check_update)

mp.msg.info("GitHub Release Checker loaded: " .. REPO)