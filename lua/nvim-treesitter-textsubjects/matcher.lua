local Range = require('nvim-treesitter-textsubjects.range').Range

local M = {}

local function is_language_supported(lang, seen)
    if not lang then
        return false
    end

    local lang_ok, _ = vim.treesitter.language.add(lang)
    if not lang_ok then
        return false
    end

    if
        #vim.treesitter.query.get_files(lang, 'textsubjects-smart') > 0
        or #vim.treesitter.query.get_files(lang, 'textsubjects-container-outer') > 0
        or #vim.treesitter.query.get_files(lang, 'textsubjects-container-inner') > 0
    then
        return true
    end

    if seen[lang] then
        return false
    end
    seen[lang] = true

    local query = vim.treesitter.query.get(lang, 'injections')
    if query then
        for _, capture in ipairs(query.info.captures) do
            if capture == 'language' or is_language_supported(capture, seen) then
                return true
            end
        end

        for _, info in ipairs(query.info.patterns) do
            -- we're looking for #set injection.language <whatever>
            if info[1][1] == 'set!' and info[1][2] == 'injection.language' then
                if is_language_supported(info[1][3], seen) then
                    return true
                end
            end
        end
    end

    return false
end

---@param bufnr number
---@return boolean
function M.is_supported(bufnr)
    local lang = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)
    return is_language_supported(lang, {})
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
---@param query_group string
---@return textsubjects.Match[]
function M.get_matches(bufnr, capture_name, query_group)
    capture_name = capture_name:sub(2) -- drop leading '@'

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
        local query = vim.treesitter.query.get(tree_lang, query_group)
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

return M
