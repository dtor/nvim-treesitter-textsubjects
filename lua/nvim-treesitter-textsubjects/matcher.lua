local Range = require('nvim-treesitter-textsubjects.range').Range
local Position = require('nvim-treesitter-textsubjects.range').Position

local M = {}

---@param name string
---@return string
local function get_full_query_name(name)
    return 'textsubjects-' .. name:gsub('^textsubjects%-', '')
end

local function is_language_supported(lang, query_names, seen)
    if not lang then
        return false
    end

    local lang_ok, _ = vim.treesitter.language.add(lang)
    if not lang_ok then
        return false
    end

    for _, query_name in ipairs(query_names) do
        if #vim.treesitter.query.get_files(lang, get_full_query_name(query_name)) > 0 then
            return true
        end
    end

    if seen[lang] then
        return false
    end
    seen[lang] = true

    local query = vim.treesitter.query.get(lang, 'injections')
    if query then
        for _, capture in ipairs(query.info.captures) do
            if capture == 'language' or is_language_supported(capture, query_names, seen) then
                return true
            end
        end

        for _, info in ipairs(query.info.patterns) do
            -- we're looking for #set injection.language <whatever>
            if info[1][1] == 'set!' and info[1][2] == 'injection.language' then
                if is_language_supported(info[1][3], query_names, seen) then
                    return true
                end
            end
        end
    end

    return false
end

---@param bufnr number
---@param query_names string[]
---@return boolean
function M.is_supported(bufnr, query_names)
    local lang = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)
    return lang ~= nil and is_language_supported(lang, query_names, {})
end

---@class (exact) textsubjects.Match
---@field range textsubjects.Range The primary target range
---@field extended? textsubjects.Range The optional boundary range (for gap detection)

---@param match table<integer, TSNode[]>
---@param captures string[]
---@param target_capture string
---@return textsubjects.Match?
local function match_to_obj(match, captures, target_capture)
    ---@type textsubjects.Range?
    local range
    ---@type textsubjects.Range?
    local extended_range

    for id, nodes in pairs(match) do
        local capture_name = captures[id]
        local first_node = nodes[1]
        local last_node = nodes[#nodes]

        if capture_name == target_capture then
            range = Range.from_nodes(first_node, last_node)
        elseif capture_name == target_capture .. '.extended' then
            if #nodes ~= 2 then
                error('Invalid extended capture: wrong number of nodes' .. #nodes)
            end
            extended_range = Range.from_nodes_inner(first_node, last_node)
        end
    end

    if range then
        if extended_range and range:equals(extended_range) then
            extended_range = nil
        end

        return ---@type textsubjects.Match
        {
            range = range,
            extended = extended_range,
        }
    end
end

---Returns list of match objects from nodes matching given capture name and query
---@param bufnr integer
---@param capture_name string
---@param query_name string
---@return textsubjects.Match[]
function M.get_matches(bufnr, capture_name, query_name)
    capture_name = capture_name:sub(2) -- drop leading '@'
    query_name = get_full_query_name(query_name)

    local lang = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)
    if not lang then
        return {}
    end

    local parser = vim.treesitter.get_parser(bufnr, lang, { error = false })
    if not parser then
        return {}
    end

    parser:parse(true)

    local matches = {}
    parser:for_each_tree(function(tstree, language_tree)
        local tree_lang = language_tree:lang()
        local query = vim.treesitter.query.get(tree_lang, query_name)
        if query then
            for _, match, _ in query:iter_matches(tstree:root(), bufnr) do
                local match_obj = match_to_obj(match, query.captures, capture_name)
                if match_obj then
                    table.insert(matches, match_obj)
                end
            end
        end
    end)
    return matches
end

---Prints matches for a given query suffix for debugging
---@param query_name string
function M.print_matches(query_name)
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor = Position.from_vim(vim.fn.getpos('.'))

    local lang = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)
    if not lang then
        print('No treesitter support for filetype ' .. vim.bo[bufnr].filetype)
        return
    end

    query_name = query_name == '' and 'smart' or query_name
    if not M.is_supported(bufnr, { query_name }) then
        print("Query '" .. query_name .. "' does not exist for language '" .. lang .. "'")
        return
    end

    print('Cursor: ' .. cursor.row .. ', ' .. cursor.col)
    print('Query: ' .. query_name)

    local matches = M.get_matches(bufnr, '@range', query_name)
    if #matches > 0 then
        for _, m in ipairs(matches) do
            local line = '  Match: ' .. m.range:to_string()

            if m.extended then
                line = line .. ' EXT: ' .. m.extended:to_string()
            end

            -- Use the outermost range (extended if available, otherwise primary) for cursor matching
            local match_range = m.extended or m.range
            if match_range.start_pos:le(cursor) and cursor:lt(match_range.end_pos) then
                line = line .. ' *'
            end

            print(line)
        end
    else
        print('No matches')
    end
end

return M
