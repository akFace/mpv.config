-- merge-input.lua
-- 将 custom-input.conf 的内容合并到 input.conf，重复键由后者覆盖前者。
-- `_` 行按内容去重：完全相同的行不重复追加，内容不同的才追加。
-- 调用：
--   script-message merge-inputs               （带备份）
--   script-message merge-inputs-nobackup      （不备份）

local mp = require 'mp'
local msg = require 'mp.msg'
local utils = require 'mp.utils'

local MAIN_INPUT = "~~/input.conf"
local EXTRA_INPUT = "~~/custom-input.conf"
local BACKUP_SUFFIX = ".bak"

-- ===== 语言检测 =====

local function detect_language()
    for _, var in ipairs({"LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG"}) do
        local v = os.getenv(var)
        if v and v ~= "" then
            local first = v:match("^([^:]+)") or v
            if first:lower():match("^zh") then return "zh" end
            if first:lower():match("^en") then return "en" end
        end
    end

    local mpv_lang = mp.get_property("language") or ""
    if mpv_lang:lower():match("^zh") then return "zh" end

    local platform = mp.get_property("platform") or ""
    if platform == "windows" then
        local r = utils.subprocess({
            args = {"powershell", "-NoProfile", "-Command", "(Get-Culture).Name"},
            cancellable = false,
            capture_stdout = true,
            capture_stderr = false,
        })
        if r and r.status == 0 and r.stdout then
            local out = r.stdout:lower()
            if out:match("^zh") then return "zh" end
            if out:match("^en") then return "en" end
        end
    end

    return "en"
end

-- ===== i18n 字符串表 =====

local LANG = detect_language()

local STR = {
    en = {
        merge_failed_read_main   = "Merge failed: cannot read input.conf (%s)",
        merge_failed_read_extra  = "Merge failed: cannot read custom-input.conf (%s)",
        merge_failed_write_main  = "Merge failed: cannot write input.conf (%s)",
        merge_done               = "Merge done: %d key(s) overwritten, %d key(s) added. Backup saved as %s",
        merge_done_no_backup     = "Merge done: %d key(s) overwritten, %d key(s) added.",
        overwritten_keys         = "Overwritten keys: ",
        added_keys               = "Added keys: ",
        script_loaded            = "merge-input.lua loaded. Press Ctrl+Shift+M to merge custom-input.conf into input.conf",
    },
    zh = {
        merge_failed_read_main   = "合并失败：无法读取 input.conf (%s)",
        merge_failed_read_extra  = "合并失败：无法读取 custom-input.conf (%s)",
        merge_failed_write_main  = "合并失败：无法写入 input.conf (%s)",
        merge_done               = "合并完成：覆盖 %d 个键，新增 %d 个键。备份已保存为 %s",
        merge_done_no_backup     = "合并完成：覆盖 %d 个键，新增 %d 个键。",
        overwritten_keys         = "覆盖的键：",
        added_keys               = "新增的键：",
        script_loaded            = "merge-input.lua 已加载，按 Ctrl+Shift+M 合并 custom-input.conf 到 input.conf",
    },
}

local function T(key, ...)
    local lang_table = STR[LANG] or STR.en
    local template = lang_table[key] or STR.en[key] or key
    if select("#", ...) > 0 then
        return string.format(template, ...)
    end
    return template
end

-- ===== 工具函数 =====

local function read_file(path)
    local f, err = io.open(path, "r")
    if not f then return nil, err end
    local content = f:read("*a")
    f:close()
    return content
end

local function write_file(path, content)
    local f, err = io.open(path, "w")
    if not f then return false, err end
    f:write(content)
    f:close()
    return true
end

local function parse_key(line)
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed == "" then return nil end
    if trimmed:sub(1, 1) == "#" then return nil end
    local key = trimmed:match("^(%S+)")
    if not key then return nil end
    return key
end

local function is_binding_line(line)
    return parse_key(line) ~= nil
end

-- 把一行规范化（去首尾空白），用于内容比较
local function normalize_line(line)
    return (line:match("^%s*(.-)%s*$")) or ""
end

-- ===== 主逻辑 =====

local function merge_inputs(skip_backup)
    local main_path  = mp.command_native({"expand-path", MAIN_INPUT})
    local extra_path = mp.command_native({"expand-path", EXTRA_INPUT})

    local main_content, err1 = read_file(main_path)
    if not main_content then
        mp.osd_message(T("merge_failed_read_main", tostring(err1)), 3)
        return
    end

    local extra_content, err2 = read_file(extra_path)
    if not extra_content then
        mp.osd_message(T("merge_failed_read_extra", tostring(err2)), 3)
        return
    end

    if not skip_backup then
        write_file(main_path .. BACKUP_SUFFIX, main_content)
    end

    local function split_lines(text)
        local lines = {}
        text = text:gsub("\r\n", "\n")
        for line in (text .. "\n"):gmatch("(.-)\n") do
            lines[#lines + 1] = line
        end
        if lines[#lines] == "" then lines[#lines] = nil end
        return lines
    end

    local main_lines  = split_lines(main_content)
    local extra_lines = split_lines(extra_content)

    -- 解析 custom-input.conf
    --   extra_blocks     普通键：key -> block
    --   extra_underscore `_` 键：有序的 block 列表
    --   order            普通键第一次出现的顺序
    local extra_blocks     = {}
    local extra_underscore = {}
    local order = {}
    local current_key   = nil
    local current_block = nil

    for _, line in ipairs(extra_lines) do
        local key = parse_key(line)
        if key then
            current_key = key
            current_block = { lines = { line } }
            if key == "_" then
                extra_underscore[#extra_underscore + 1] = current_block
            else
                if not extra_blocks[key] then
                    order[#order + 1] = key
                end
                extra_blocks[key] = current_block
            end
        elseif current_key then
            current_block.lines[#current_block.lines + 1] = line
        end
    end

    -- 收集主文件里已有的普通键，以及 `_` 行的完整内容集合
    local main_key_lines = {}
    local main_underscore_set = {}
    local i = 1
    while i <= #main_lines do
        local key = parse_key(main_lines[i])
        if key then
            if key == "_" then
                main_underscore_set[normalize_line(main_lines[i])] = true
            else
                main_key_lines[key] = true
            end
            local j = i + 1
            while j <= #main_lines and not is_binding_line(main_lines[j]) do
                j = j + 1
            end
            i = j
        else
            i = i + 1
        end
    end

    local result = {}
    local replaced_keys = {}
    local added_keys = {}
    local added_underscore = {}

    -- 1) 复制主文件；普通键被 custom 覆盖；`_` 行原样保留
    i = 1
    while i <= #main_lines do
        local key = parse_key(main_lines[i])
        if key and key ~= "_" and extra_blocks[key] then
            for _, l in ipairs(extra_blocks[key].lines) do
                result[#result + 1] = l
            end
            replaced_keys[#replaced_keys + 1] = key
            local j = i + 1
            while j <= #main_lines and not is_binding_line(main_lines[j]) do
                j = j + 1
            end
            i = j
        else
            result[#result + 1] = main_lines[i]
            i = i + 1
        end
    end

    -- 2) 追加 custom 里主文件没有的普通键
    for _, key in ipairs(order) do
        if not main_key_lines[key] then
            for _, l in ipairs(extra_blocks[key].lines) do
                result[#result + 1] = l
            end
            added_keys[#added_keys + 1] = key
        end
    end

    -- 3) 追加 custom 里的 `_` 块：按内容去重
    for _, block in ipairs(extra_underscore) do
        local first_line = normalize_line(block.lines[1] or "")
        if not main_underscore_set[first_line] then
            for _, l in ipairs(block.lines) do
                result[#result + 1] = l
            end
            added_underscore[#added_underscore + 1] = first_line
            -- 更新集合，避免 custom 内部自身重复
            main_underscore_set[first_line] = true
        end
    end

    local new_content = table.concat(result, "\n") .. "\n"
    local ok, werr = write_file(main_path, new_content)
    if not ok then
        mp.osd_message(T("merge_failed_write_main", tostring(werr)), 3)
        return
    end

    mp.commandv("load-input-conf", main_path)

    local done_text
    if skip_backup then
        done_text = T("merge_done_no_backup", #replaced_keys, #added_keys)
    else
        done_text = T("merge_done", #replaced_keys, #added_keys, BACKUP_SUFFIX)
    end
    mp.osd_message(done_text, 4)
    msg.info(done_text)
    if #replaced_keys > 0 then
        msg.info(T("overwritten_keys") .. table.concat(replaced_keys, ", "))
    end
    if #added_keys > 0 then
        msg.info(T("added_keys") .. table.concat(added_keys, ", "))
    end
    if #added_underscore > 0 then
        msg.info("Added _ blocks: " .. #added_underscore)
    end
end

-- ===== 注册消息和快捷键 =====

mp.register_script_message("merge-inputs", function()
    merge_inputs(false)
end)

mp.register_script_message("merge-inputs-nobackup", function()
    merge_inputs(true)
end)

msg.info(T("script_loaded"))