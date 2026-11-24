-- merge-input.lua
-- 将 custom-input.conf 的内容合并到 input.conf，重复键由后者覆盖前者。
-- `_` 行按内容去重：完全相同的行不重复追加，内容不同的才追加。
-- 使用 `#rm_menu: 菜单路径` 删除匹配的菜单项，`*` 可匹配任意字符。
-- 例如：`_ ignore #rm_menu: 工具 > mpvnet 功能 > *`
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
        merge_done               = "Merge done: %d key(s) overwritten, %d key(s) added, %d menu item(s) changed, %d menu item(s) removed. Backup saved as %s",
        merge_done_no_backup     = "Merge done: %d key(s) overwritten, %d key(s) added, %d menu item(s) changed, %d menu item(s) removed.",
        overwritten_keys         = "Overwritten keys: ",
        added_keys               = "Added keys: ",
        changed_menus            = "Changed menu items: ",
        script_loaded            = "merge-input.lua loaded. Press Ctrl+Shift+M to merge custom-input.conf into input.conf",
    },
    zh = {
        merge_failed_read_main   = "合并失败：无法读取 input.conf (%s)",
        merge_failed_read_extra  = "合并失败：无法读取 custom-input.conf (%s)",
        merge_failed_write_main  = "合并失败：无法写入 input.conf (%s)",
        merge_done               = "合并完成：覆盖 %d 个键，新增 %d 个键，变更 %d 个菜单项，移除 %d 个菜单项。备份已保存为 %s",
        merge_done_no_backup     = "合并完成：覆盖 %d 个键，新增 %d 个键，变更 %d 个菜单项，移除 %d 个菜单项。",
        overwritten_keys         = "覆盖的键：",
        added_keys               = "新增的键：",
        changed_menus            = "变更的菜单项：",
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

local function is_menu_separator(line)
    local trimmed = normalize_line(line)
    if trimmed == "" then
        return false
    end

    local menu_path = trimmed:match("#menu:%s*(.-)%s*$")
    if menu_path then
        menu_path = menu_path:gsub("%s*#@.*$", "")
        menu_path = normalize_line(menu_path)
        return menu_path:sub(-1) == "-"
    end

    return false
end

local function get_menu_path(lines, ignore_separator_lines)
    for _, line in ipairs(lines) do
        if ignore_separator_lines and is_menu_separator(line) then
            -- 自定义文件中的分隔线不作为菜单项参与匹配
        else
            local path = line:match("#menu:%s*(.-)%s*$")
            if path then
                path = path:gsub("%s*#@.*$", "")
                return normalize_line(path)
            end
        end
    end
    return nil
end

local function wildcard_match(value, pattern)
    if not pattern:find("*", 1, true) then
        return value == pattern
    end

    local parts = {}
    local start = 1
    while true do
        local star = pattern:find("*", start, true)
        if not star then
            parts[#parts + 1] = pattern:sub(start)
            break
        end
        parts[#parts + 1] = pattern:sub(start, star - 1)
        start = star + 1
    end

    local position = 1
    local first_part = 1
    if pattern:sub(1, 1) ~= "*" then
        local first = parts[1]
        if value:sub(1, #first) ~= first then
            return false
        end
        position = #first + 1
        first_part = 2
    end

    local last_part = #parts
    for i = first_part, last_part do
        local part = parts[i]
        if part ~= "" then
            if i == last_part and pattern:sub(-1) ~= "*" then
                local suffix_start = #value - #part + 1
                if suffix_start < position or value:sub(suffix_start) ~= part then
                    return false
                end
            else
                local found = value:find(part, position, true)
                if not found then
                    return false
                end
                position = found + #part
            end
        end
    end
    return true
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

    local function parse_custom_blocks(lines)
        local extra_blocks = {}
        local extra_sequence = {}
        local extra_key_slot = {}
        local menu_removals = {}
        local current_key = nil
        local current_block = nil

        for _, line in ipairs(lines) do
            local remove_path = line:match("#rm_menu:%s*(.-)%s*$")
            if remove_path ~= nil then
                remove_path = normalize_line(remove_path:gsub("%s*#@.*$", ""))
                if remove_path ~= "" then
                    menu_removals[remove_path] = true
                end
                current_key = nil
                current_block = nil
            else
                local key = parse_key(line)
                if key then
                    current_key = key
                    current_block = { lines = { line } }
                    if key == "_" then
                        extra_sequence[#extra_sequence + 1] = current_block
                    else
                        if extra_blocks[key] then
                            extra_sequence[extra_key_slot[key]] = current_block
                        else
                            extra_key_slot[key] = #extra_sequence + 1
                            extra_sequence[#extra_sequence + 1] = current_block
                        end
                        extra_blocks[key] = current_block
                    end
                elseif current_key then
                    current_block.lines[#current_block.lines + 1] = line
                end
            end
        end

        return extra_blocks, extra_sequence, menu_removals
    end

    -- 解析 custom-input.conf
    --   extra_blocks   普通键：key -> 最新 block
    --   extra_sequence 按原始出现顺序保存所有 block
    local extra_blocks, extra_sequence, menu_removals = parse_custom_blocks(extra_lines)

    local function is_removed_menu_block(lines)
        local path = get_menu_path(lines)
        if path then
            for pattern in pairs(menu_removals) do
                if wildcard_match(path, pattern) then
                    return true
                end
            end
        end
        return false
    end

    local function get_block(lines, start_index, end_index)
        local block = {}
        for k = start_index, end_index do
            block[#block + 1] = lines[k]
        end
        return block
    end

    local function append_lines(block, output)
        for _, line in ipairs(block) do
            output[#output + 1] = line
        end
    end

    local function same_block_content(a, b)
        if not a or not b or #a ~= #b then
            return false
        end
        for i = 1, #a do
            if a[i] ~= b[i] then
                return false
            end
        end
        return true
    end

    local function append_commented_block(block, output)
        if #block == 0 then return end
        output[#output + 1] = "# " .. block[1]
        for i = 2, #block do
            output[#output + 1] = block[i]
        end
    end

    -- 按优先级处理：
    -- 1. 删除规则
    -- 2. 完整内容相同：直接保留主文件原内容
    -- 3. 同菜单路径：替换旧菜单项
    -- 4. 同键覆盖：替换旧键绑定
    -- 5. 追加新增项
    local function find_same_content_custom_block(block)
        local block_lines = block.lines or block
        for _, custom_block in ipairs(extra_sequence) do
            if custom_block ~= block and same_block_content(block_lines, custom_block.lines) then
                return custom_block
            end
        end
        return nil
    end

    local function find_matching_custom_menu(block)
        local menu_path = get_menu_path(block.lines or block)
        if not menu_path then
            return nil
        end

        for _, custom_block in ipairs(extra_sequence) do
            if custom_block ~= block then
                local custom_path = get_menu_path(custom_block.lines, true)
                if custom_path and custom_path == menu_path then
                    return custom_block
                end
            end
        end

        return nil
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
    local changed_menus = 0
    local removed_menus = 0
    local placed_custom = {}

    -- 1) 复制主文件；优先级：删除规则 -> 完整内容相同 -> 菜单路径替换 -> 同键覆盖 -> `_` 原样保留
    i = 1
    while i <= #main_lines do
        local key = parse_key(main_lines[i])
        if key then
            local j = i + 1
            while j <= #main_lines and not is_binding_line(main_lines[j]) do
                j = j + 1
            end
            local block = get_block(main_lines, i, j - 1)
            local main_menu_path = get_menu_path(block)
            local same_content_match = find_same_content_custom_block({ lines = block })
            local custom_menu_match = main_menu_path and find_matching_custom_menu({ lines = block })

            if is_removed_menu_block(block) then
                -- 1. 删除规则：主文件中的旧菜单项被注释掉并计数
                append_commented_block(block, result)
                removed_menus = removed_menus + 1
            elseif same_content_match then
                -- 2. 完整内容相同：不执行替换，保留主文件原内容
                append_lines(block, result)
                placed_custom[same_content_match] = true
            elseif custom_menu_match then
                -- 3. 菜单路径匹配：用 custom 的菜单项替换旧菜单块
                if is_removed_menu_block(custom_menu_match.lines) then
                    append_commented_block(block, result)
                    removed_menus = removed_menus + 1
                else
                    append_lines(custom_menu_match.lines, result)
                    placed_custom[custom_menu_match] = true
                    changed_menus = changed_menus + 1
                end
            elseif key ~= "_" and extra_blocks[key] then
                -- 4. 同键覆盖：普通按键被 custom 的新定义覆盖
                if is_removed_menu_block(extra_blocks[key].lines) then
                    append_commented_block(block, result)
                    removed_menus = removed_menus + 1
                else
                    if main_key_lines[key] and main_menu_path ~= nil then
                        append_commented_block(block, result)
                    end
                    replaced_keys[#replaced_keys + 1] = key
                end
            else
                -- 5. 其他情况保留原块；`_` 行原样保留，不重复追加
                append_lines(block, result)
            end
            i = j
        else
            result[#result + 1] = main_lines[i]
            i = i + 1
        end
    end

    -- 2) 按 custom 文件中的原始顺序追加块：
    --    自定义菜单项不受 #rm_menu 规则影响（它们不会被移除），
    --    仅主文件中的旧菜单项会在第 1 步被删除。
    for _, block in ipairs(extra_sequence) do
        if placed_custom[block] then
            -- 已在主文件中按位置替换或覆盖，避免重复追加
        else
            local first_line = block.lines[1] or ""
            local key = parse_key(first_line)

            if key == "_" then
                local normalized = normalize_line(first_line)
                if not main_underscore_set[normalized] then
                    append_lines(block.lines, result)
                    added_underscore[#added_underscore + 1] = normalized
                    main_underscore_set[normalized] = true
                    if get_menu_path(block.lines) then
                        changed_menus = changed_menus + 1
                    end
                end
            elseif key then
                append_lines(block.lines, result)
                if get_menu_path(block.lines) then
                    changed_menus = changed_menus + 1
                elseif not main_key_lines[key] then
                    added_keys[#added_keys + 1] = key
                end
            end
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
        done_text = T("merge_done_no_backup", #replaced_keys, #added_keys, changed_menus, removed_menus)
    else
        done_text = T("merge_done", #replaced_keys, #added_keys, changed_menus, removed_menus, BACKUP_SUFFIX)
    end
    mp.osd_message(done_text, 4)
    msg.info(done_text)
    if #replaced_keys > 0 then
        msg.info(T("overwritten_keys") .. table.concat(replaced_keys, ", "))
    end
    if #added_keys > 0 then
        msg.info(T("added_keys") .. table.concat(added_keys, ", "))
    end
    if changed_menus > 0 then
        msg.info(T("changed_menus") .. tostring(changed_menus))
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
