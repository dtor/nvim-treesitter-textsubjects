local matcher = require('nvim-treesitter-textsubjects.matcher')

local M = {}

-- array of { changedtick = number, selection: number, mode: string }
-- TODO: we could use extmarks with each selection to avoid using buf
-- changedtick, it would be a lot smarter and more accurate, but it'd be pretty
-- hard to implement
local prev_selections = {}

--- @return boolean: true iff the range @a is equal to the range @b
local function is_equal(a, b)
    return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
end

--- @return boolean: true iff the range @a strictly surrounds the range @b. @a == @b => false.
local function does_surround(a, b)
    local a_start_row, a_start_col, a_end_row, a_end_col = a[1], a[2], a[3], a[4]
    local b_start_row, b_start_col, b_end_row, b_end_col = b[1], b[2], b[3], b[4]

    if a_start_row > b_start_row or a_start_row == b_start_row and a_start_col > b_start_col then
        return false
    end
    if a_end_row < b_end_row or a_end_row == b_end_row and a_end_col < b_end_col then
        return false
    end
    return a_start_row < b_start_row or a_start_col < b_start_col or a_end_row > b_end_row or a_end_col > b_end_col
end

--- extend_range_with_whitespace extends the selection to select any surrounding whitespace as part of the text object
local function extend_range_with_whitespace(range)
    local start_row, start_col, end_row, end_col = unpack(range)

    -- everything before the selection on the same lines as the start of the range
    local startline = string.sub(vim.fn.getline(start_row + 1), 1, start_col)
    local startline_len = #startline
    local startline_whitespace_len = #string.match(startline, '(%s*)$', 1)

    -- everything after the selection on the same lines as the end of the range
    local endline = string.sub(vim.fn.getline(end_row + 1), end_col + 1, -1)
    local endline_len = #endline
    local endline_whitespace_len = #string.match(endline, '^(%s*)', 1)

    local sel_mode
    if startline_whitespace_len == startline_len and endline_whitespace_len == endline_len then
        -- the text objects is the only thing on the lines in the range so we
        -- should use visual line mode
        sel_mode = 'V'
        if end_row + 1 < vim.fn.line('$') and start_row > 0 then
            if string.match(vim.fn.getline(end_row + 2), '^%s*$', 1) then
                -- we either have a blank line below AND above OR just below,
                -- in either case we want extend to the line below
                end_col = math.max(#vim.fn.getline(end_row + 2), 1)
                end_row = end_row + 1
            elseif string.match(vim.fn.getline(start_row), '^%s*$', 1) then
                -- we have a blank line above AND NOT below, we extend to the line above
                start_col = math.max(#vim.fn.getline(start_row), 1)
                start_row = start_row - 1
            end
        end
    else
        sel_mode = 'v'
        end_col = end_col + endline_whitespace_len
        if endline_whitespace_len == 0 and startline_whitespace_len ~= startline_len then
            start_col = start_col - startline_whitespace_len
        end
    end

    return { start_row, start_col, end_row, end_col }, sel_mode
end

local function normalize_selection(sel_start, sel_end)
    local _, sel_start_row, sel_start_col = unpack(sel_start)
    local start_max_cols = #vim.fn.getline(sel_start_row)
    -- visual line mode results in getpos("'>") returning a massive number so
    -- we have to set it to the true end col
    if start_max_cols < sel_start_col then
        sel_start_col = start_max_cols
    end
    -- tree-sitter uses zero-indexed rows
    sel_start_row = sel_start_row - 1
    -- tree-sitter uses zero-indexed cols for the start
    sel_start_col = sel_start_col - 1

    local _, sel_end_row, sel_end_col = unpack(sel_end)
    local end_max_cols = #vim.fn.getline(sel_end_row)
    -- visual line mode results in getpos("'>") returning a massive number so
    -- we have to set it to the true end col
    if end_max_cols < sel_end_col then
        sel_end_col = end_max_cols
    end
    -- tree-sitter uses zero-indexed rows
    sel_end_row = sel_end_row - 1

    return { sel_start_row, sel_start_col, sel_end_row, sel_end_col }
end

local function update_selection(bufnr, range, selection_mode)
    local start_row, start_col, end_row, end_col = unpack(range)
    selection_mode = selection_mode or 'v'

    local mode = vim.api.nvim_get_mode()
    if mode.mode ~= selection_mode then
        selection_mode = vim.api.nvim_replace_termcodes(selection_mode, true, true, true)
        vim.cmd.normal({ selection_mode, bang = true })
    end

    if end_col == 0 then
        end_row = end_row - 1
        local line = vim.api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, true)[1]
        if line then
            end_col = #line + 1
        else
            end_col = 1
        end
    end

    local end_col_offset = 1
    if selection_mode == 'v' and vim.o.selection == 'exclusive' then
        end_col_offset = 0
    end
    end_col = end_col - end_col_offset

    -- Select from end to start so that we end up with the cursor at the
    -- beginning of selection.
    vim.api.nvim_win_set_cursor(0, { end_row + 1, end_col })
    vim.cmd('normal! o')
    vim.api.nvim_win_set_cursor(0, { start_row + 1, start_col })
end

---@param query string
---@param restore_visual boolean
---@param sel_start table
---@param sel_end table
function M.select(query, restore_visual, sel_start, sel_end)
    local bufnr = vim.api.nvim_get_current_buf()
    local lang = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)
    if not lang then
        return
    end

    local sel = normalize_selection(sel_start, sel_end)
    local best
    local ranges = matcher.get_ranges(bufnr, '@range', query)
    for _, range in ipairs(ranges) do
        local match_start_row, match_start_col, match_end_row, match_end_col = unpack(range)
        local match = { match_start_row, match_start_col, match_end_row, match_end_col }

        -- match must cover an exclusively bigger range than the current selection
        if does_surround(match, sel) then
            if not best or does_surround(best, match) then
                best = match
            end
        end
    end

    if best then
        local new_best, sel_mode = extend_range_with_whitespace(best)
        update_selection(bufnr, new_best, sel_mode)
        local selections = prev_selections[bufnr]
        if selections == nil or not does_surround(new_best, selections[#selections][1]) then
            prev_selections[bufnr] = {
                {
                    changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
                    new_best,
                    sel_mode,
                },
            }
        else
            table.insert(selections, {
                changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
                new_best,
                sel_mode,
            })
        end
    else
        if restore_visual then
            vim.cmd('normal! gv')
        end
    end
end

---@param sel_start table
---@param sel_end table
function M.prev_select(sel_start, sel_end)
    local bufnr = vim.api.nvim_get_current_buf()
    local selections = prev_selections[bufnr]
    local sel = normalize_selection(sel_start, sel_end)
    if #vim.fn.getline(sel[1] + 1) == 0 then
        sel[2] = 1
    end
    if #vim.fn.getline(sel[3] + 1) == 0 then
        sel[4] = 1
    end
    local changedtick = vim.api.nvim_buf_get_changedtick(bufnr)

    -- TODO: this could use extmarks
    -- We are removing any previous selections which have a different
    -- changedtick because that means the text is *probably* different and the
    -- selection range *may* now be invalid
    while selections ~= nil and selections[#selections].changedtick ~= changedtick do
        table.remove(selections)
        if #selections == 0 then
            selections = nil
        end
    end

    if selections == nil then
        prev_selections[bufnr] = nil
        vim.cmd('normal! v')
        return
    end

    local head = selections[#selections][1]
    if is_equal(sel, head) or does_surround(sel, head) then
        table.remove(selections)
        if #selections == 0 then
            prev_selections[bufnr] = nil
            vim.cmd('normal! v')
            return
        end
    end

    local new_sel, sel_mode = unpack(selections[#selections])
    update_selection(bufnr, new_sel, sel_mode)
end

return M
