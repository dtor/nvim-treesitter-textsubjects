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

---Returns list of ranges from nodes matching given capture name and query
---@param bufnr integer
---@param capture_name string
---@param query_group string
---@return textsubjects.Range[]
function M.get_ranges(bufnr, capture_name, query_group)
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

    local ranges = {}
    parser:for_each_tree(function(tstree, language_tree)
        local tree_lang = language_tree:lang()
        local query = vim.treesitter.query.get(tree_lang, query_group)
        if query then
            for _, match, _ in query:iter_matches(tstree:root(), bufnr) do
                for id, nodes in pairs(match) do
                    if query.captures[id] == capture_name then
                        local first_node = nodes[1]
                        local last_node = nodes[#nodes]

                        table.insert(ranges, Range.from_nodes(first_node, last_node))
                    end
                end
            end
        end
    end)
    return ranges
end

return M
