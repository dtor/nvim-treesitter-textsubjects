local queries = require('nvim-treesitter.query')

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
        queries.has_query_files(lang, 'textsubjects-smart')
        or queries.has_query_files(lang, 'textsubjects-container-outer')
        or queries.has_query_files(lang, 'textsubjects-container-inner')
    then
        return true
    end

    if seen[lang] then
        return false
    end
    seen[lang] = true

    if queries.has_query_files(lang, 'injections') then
        local query = queries.get_query(lang, 'injections')
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

return M
