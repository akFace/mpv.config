----------------------------------------------------------------
----------------- 切换script-opts配置文件功能------------------------
---------------------------------------------------------------
-- 使用前需要手动做的事
-- 在 portable_config 下手动创建 switch-opts 目录，放入你的源 .conf 文件（比如 config1.conf、config2.conf）。

-- script-opts 目录是 mpv 本来就有的，不用管。

-- switch-opts-backup.json 会在首次启动 mpv 时自动生成。

-- 行为说明
-- 首次启动：把 script-opts 里所有 .conf 内容序列化后写入 switch-opts-backup.json。之后每次启动检测到该文件存在即跳过。
-- 绑定快捷键：
-- 切换配置：key script-message switch-opts config1.conf/xxx.conf，把 switch-opts/config1.conf 重名名 xxx.conf 并覆盖到 script-opts/xxx.conf。

-- 恢复默认：key script-message switch-opts default，从 switch-opts-backup.json 反序列化后写回所有 .conf。
-----------------------------------------------------

local mp = require("mp")
local utils = require("mp.utils")
------------------------------------------------------------
-- 基本设置
------------------------------------------------------------
local TAG = "[switch-opts] "
------------------------------------------------------------
-- 获取 mpv config directory（只用 ~~）
------------------------------------------------------------
local function normalize_path(path)
    if type(path) ~= "string" then
        return nil
    end
    path = path:gsub("[\r\n]+$", "")
    path = path:gsub("[/\\]+$", "")
    if path == "" then
        return nil
    end
    return path
end

local function get_config_dir()
    local ok, result = pcall(
        mp.command_native,
        {"expand-path", "~~/"}
    )
    if not ok or type(result) ~= "string" or result == "" then
        return nil
    end
    return normalize_path(result)
end

local config_dir = get_config_dir()
if not config_dir then
    mp.msg.error(TAG .. "无法确定 mpv config directory。")
    return
end
------------------------------------------------------------
-- 目录与文件
------------------------------------------------------------
local script_opts_dir = utils.join_path(config_dir, "script-opts")
local switch_opts_dir = utils.join_path(config_dir, "switch-opts")
local backup_file = utils.join_path(config_dir, "switch-opts-backup.json")
------------------------------------------------------------
-- 日志（仅保留 error）
------------------------------------------------------------
local function error_log(message)
    mp.msg.error(TAG .. tostring(message))
end
------------------------------------------------------------
-- 判断文件是否存在
------------------------------------------------------------
local function file_exists(path)
    local info = utils.file_info(path)
    return info ~= nil and info.is_file == true
end
------------------------------------------------------------
-- 判断目录是否存在
------------------------------------------------------------
local function directory_exists(path)
    local info = utils.file_info(path)
    return info ~= nil and info.is_dir == true
end
------------------------------------------------------------
-- 读取文件
------------------------------------------------------------
local function read_file(path)
    local file, err = io.open(path, "rb")
    if not file then
        return nil, err
    end
    local data = file:read("*a")
    file:close()
    if data == nil then
        return nil, "无法读取文件"
    end
    return data
end
------------------------------------------------------------
-- 写入文件（原子写入）
-- 先写临时文件，成功后替换目标文件。Windows 上 os.rename
-- 不能覆盖已存在文件，需要先 remove。
------------------------------------------------------------
local function write_file(path, data)
    local tmp = path .. ".tmp"
    local file, err = io.open(tmp, "wb")
    if not file then
        return false, err
    end
    local ok, write_err = file:write(data)
    file:close()
    if not ok then
        os.remove(tmp)
        return false, write_err
    end
    if package.config:sub(1,1) == "\\" then
        os.remove(path)
    end
    local rename_ok, rename_err = os.rename(tmp, path)
    if not rename_ok then
        os.remove(tmp)
        return false, rename_err
    end
    return true
end
------------------------------------------------------------
-- 检查 .conf 文件名
------------------------------------------------------------
local function valid_conf_filename(name)
    if not name or name == "" then
        return false
    end
    if not name:lower():match("%.conf$") then
        return false
    end
    if name:find("/", 1, true) then
        return false
    end
    if name:find("\\", 1, true) then
        return false
    end
    if name:find("%.%.", 1, true) then
        return false
    end
    return true
end
------------------------------------------------------------
-- 获取目录中的所有 .conf 文件
------------------------------------------------------------
local function get_conf_files(directory)
    local files = utils.readdir(directory, "files")
    if not files then
        return {}
    end
    local result = {}
    for _, filename in ipairs(files) do
        if valid_conf_filename(filename) then
            table.insert(result, filename)
        end
    end
    table.sort(result)
    return result
end
------------------------------------------------------------
-- 备份序列化 / 反序列化
-- 格式：[名字长度]:[名字][内容长度]:[内容] 依次拼接
-- 二进制安全，不依赖换行符分隔。
------------------------------------------------------------
local function serialize(backup_table)
    local parts = {}
    for name, content in pairs(backup_table) do
        table.insert(parts,
            tostring(#name) .. ":" .. name ..
            tostring(#content) .. ":" .. content)
    end
    return table.concat(parts)
end

local function deserialize(data)
    local result = {}
    local pos = 1
    while pos <= #data do
        local colon1 = data:find(":", pos, true)
        if not colon1 then break end
        local name_len = tonumber(data:sub(pos, colon1 - 1))
        if not name_len then break end
        local name = data:sub(colon1 + 1, colon1 + name_len)
        local pos2 = colon1 + name_len + 1
        local colon2 = data:find(":", pos2, true)
        if not colon2 then break end
        local content_len = tonumber(data:sub(pos2, colon2 - 1))
        if not content_len then break end
        local content = data:sub(colon2 + 1, colon2 + content_len)
        result[name] = content
        pos = colon2 + content_len + 1
    end
    return result
end
------------------------------------------------------------
-- 首次备份
------------------------------------------------------------
local function create_initial_backup()
    if file_exists(backup_file) then
        return true
    end
    if not directory_exists(script_opts_dir) then
        error_log("script-opts 目录不存在：" .. script_opts_dir)
        return false
    end
    local files = get_conf_files(script_opts_dir)
    local backup_table = {}
    for _, filename in ipairs(files) do
        local source = utils.join_path(script_opts_dir, filename)
        local data, err = read_file(source)
        if data == nil then
            error_log("读取默认配置失败：" .. source .. " : " .. tostring(err))
            return false
        end
        backup_table[filename] = data
    end
    local ok, err = write_file(backup_file, serialize(backup_table))
    if not ok then
        error_log("写入备份失败：" .. backup_file .. " : " .. tostring(err))
        return false
    end
    return true
end
------------------------------------------------------------
-- 解析 mapping
------------------------------------------------------------
local function parse_mapping(argument)
    if not argument or argument == "" then
        return nil, nil
    end
    local separator = argument:find("/", 1, true)
    if not separator then
        return nil, nil
    end
    if argument:find("/", separator + 1, true) then
        return nil, nil
    end
    local source = argument:sub(1, separator - 1)
    local target = argument:sub(separator + 1)
    if not valid_conf_filename(source) then
        return nil, nil
    end
    if not valid_conf_filename(target) then
        return nil, nil
    end
    return source, target
end
------------------------------------------------------------
-- 验证所有 mapping
------------------------------------------------------------
local function validate_mappings(arguments)
    local mappings = {}
    local used_targets = {}
    for _, argument in ipairs(arguments) do
        local source, target = parse_mapping(argument)
        if not source then
            return nil,
                "无效参数：" .. tostring(argument)
                .. "\n正确格式：source.conf/target.conf"
        end
        local source_path = utils.join_path(switch_opts_dir, source)
        if not file_exists(source_path) then
            return nil, "switch-opts 中不存在：" .. source
        end
        local target_key = target:lower()
        if used_targets[target_key] then
            return nil, "重复的目标文件：" .. target
        end
        used_targets[target_key] = true
        table.insert(mappings, {
                source = source,
                target = target,
                source_path = source_path,
                target_path = utils.join_path(script_opts_dir, target)
            })
    end
    if #mappings == 0 then
        return nil, "没有指定任何配置。"
    end
    return mappings
end
------------------------------------------------------------
-- Reload 相关；reload‑menu 为第三方 mpv‑menu 脚本消息，非 mpv 内置
------------------------------------------------------------
local function reload_all_scripts()
    pcall(function()
        mp.commandv('script-message-to', 'menu', 'reload-menu')
    end)
    return true
end
------------------------------------------------------------
-- 恢复默认配置
------------------------------------------------------------
local function restore_default()
    if not file_exists(backup_file) then
        error_log("没有找到首次启动备份：" .. backup_file)
        mp.osd_message("switch-opts\nNo data", 4)
        return
    end
    local data, err = read_file(backup_file)
    if data == nil then
        error_log("读取备份失败：" .. backup_file .. " : " .. tostring(err))
        mp.osd_message("switch-opts\nNo data", 4)
        return
    end
    local backup_table = deserialize(data)
    local count = 0
    for filename, content in pairs(backup_table) do
        local destination = utils.join_path(script_opts_dir, filename)
        local ok, werr = write_file(destination, content)
        if not ok then
            error_log("恢复失败：" .. destination .. " : " .. tostring(werr))
            return
        end
        count = count + 1
    end
    if count == 0 then
        mp.osd_message("switch-opts\nNo data", 4)
        return
    end
    reload_all_scripts()
end
------------------------------------------------------------
-- 切换配置
------------------------------------------------------------
local function switch_configs(arguments)
    if #arguments == 0 then
        mp.osd_message("switch-opts\n没有指定配置", 3)
        return
    end
    if #arguments == 1 and arguments[1]:lower() == "default" then
        restore_default()
        return
    end
    for _, argument in ipairs(arguments) do
        if argument:lower() == "default" then
            mp.osd_message("switch-opts\ndefault 不能与其他配置一起使用", 4)
            return
        end
    end
    local mappings, validation_error = validate_mappings(arguments)
    if not mappings then
        error_log(validation_error)
        mp.osd_message("switch-opts\n" .. validation_error, 4)
        return
    end
    for _, item in ipairs(mappings) do
        local data, err = read_file(item.source_path)
        if data == nil then
            error_log("读取失败：" .. item.source_path .. " : " .. tostring(err))
            return
        end
        item.data = data
    end
    for _, item in ipairs(mappings) do
        local ok, err = write_file(item.target_path, item.data)
        if not ok then
            error_log("写入失败：" .. item.target_path .. " : " .. tostring(err))
            return
        end
    end
    reload_all_scripts()
    local lines = { "switch-opts"}
    for _, item in ipairs(mappings) do
        table.insert(lines, item.source .. " → " .. item.target)
    end
    mp.osd_message(table.concat(lines, "\n"), 3)
end
------------------------------------------------------------
-- 注册 script-message
------------------------------------------------------------
mp.register_script_message("switch-opts", function(...)
    local arguments = { ... }
    switch_configs(arguments)
end)
------------------------------------------------------------
-- 启动初始化：不创建任何目录，只做首次备份
------------------------------------------------------------
mp.add_timeout(0, function()
    if not directory_exists(script_opts_dir) then
        error_log("script-opts 目录不存在：" .. script_opts_dir)
        return
    end
    create_initial_backup()
end)