local matcher = require('nvim-treesitter-textsubjects.matcher')

local M = {}

---@alias textsubjects.Range integer[] -- { start_row, start_col, end_row, end_col }

---@class textsubjects.Selection
---@field changedtick number The buffer's changedtick when the selection was made
---@field range textsubjects.Range The actual selected range (after mode normalization and whitespace extension)
---@field raw_range textsubjects.Range The original Tree-sitter range before expansion
---@field mode string The selection mode ('v', 'V', or '<C-v>')

---@type table<number, textsubjects.Selection[]>
local prev_selections = {}

--- Returns the last selection for the given buffer if it matches the current changedtick.
--- @param bufnr number
--- @return textsubjects.Selection?
local function get_last_selection(bufnr)
    local selections = prev_selections[bufnr]
    if not selections or #selections == 0 then
        return nil
    end

    local last = selections[#selections]
    if last.changedtick ~= vim.api.nvim_buf_get_changedtick(bufnr) then
        return nil
    end

    return last
end

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

--- expand_to_visual_selection extends the selection to select any surrounding
--- whitespace as part of the text object. It heuristically determines if the
--- selection should be line-wise (V) or character-wise (v). If the selection
--- encompasses the entire content of its start and end lines, it switches to
--- line-wise mode and attempts to include a surrounding blank line (preferring
--- the one below). Otherwise, it stays in character-wise mode and includes
--- surrounding whitespace on the same lines. It returns the adjusted range and
--- the chosen visual mode.
local function expand_to_visual_selection(range)
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
        start_col = 0
        if end_row + 1 < vim.fn.line('$') and start_row > 0 then
            if string.match(vim.fn.getline(end_row + 2), '^%s*$', 1) then
                -- we either have a blank line below AND above OR just below,
                -- in either case we want extend to the line below
                end_row = end_row + 1
            elseif string.match(vim.fn.getline(start_row), '^%s*$', 1) then
                -- we have a blank line above AND NOT below, we extend to the line above
                start_row = start_row - 1
            end
        end
        end_col = #vim.fn.getline(end_row + 1)
    else
        sel_mode = 'v'
        end_col = end_col + endline_whitespace_len
        if endline_whitespace_len == 0 and startline_whitespace_len ~= startline_len then
            start_col = start_col - startline_whitespace_len
        end
    end

    return { start_row, start_col, end_row, end_col }, sel_mode
end

--- Converts current visual selection or point into a canonical 0-based,
--- end-exclusive range. It handles mode-specific coordinate normalization
--- (e.g. V mode full lines).
local function normalize_selection(sel_start, sel_end)
    local _, start_row, start_col = unpack(sel_start)
    local _, end_row, end_col = unpack(sel_end)

    if vim.fn.visualmode() == 'V' then
        start_col = 1
        end_col = #vim.fn.getline(end_row)
    elseif vim.o.selection == 'exclusive' and end_col ~= vim.v.maxcol then
        end_col = end_col - 1
    end

    local line_len = #vim.fn.getline(end_row)
    if end_col > line_len then
        end_col = line_len
    end

    return { start_row - 1, math.max(start_col - 1, 0), end_row - 1, end_col }
end

--- Selects the given canonical range in the buffer using the specified visual
--- mode. It handles the translation from internal coordinates to Vim's
--- inclusive/exclusive cursor positions.
local function update_selection(range, selection_mode)
    local start_row, start_col, end_row, end_col = unpack(range)
    selection_mode = selection_mode or 'v'

    local mode = vim.api.nvim_get_mode()
    if mode.mode ~= selection_mode then
        selection_mode = vim.api.nvim_replace_termcodes(selection_mode, true, true, true)
        vim.cmd.normal({ selection_mode, bang = true })
    end

    if end_col > 0 and (selection_mode ~= 'v' or vim.o.selection ~= 'exclusive') then
        end_col = end_col - 1
    end

    -- Select from end to start so that we end up with the cursor at the
    -- beginning of selection.
    -- Note: nvim_win_set_cursor uses 1-based rows and 0-based columns.
    vim.api.nvim_win_set_cursor(0, { end_row + 1, end_col })
    vim.cmd('normal! o')
    vim.api.nvim_win_set_cursor(0, { start_row + 1, start_col })
end

--- Finds the smallest range from the query that strictly surrounds the given range.
--- @param bufnr number
--- @param query string
--- @param current_range textsubjects.Range
--- @return textsubjects.Range?
local function find_best_range(bufnr, query, current_range)
    local best
    local ranges = matcher.get_ranges(bufnr, '@range', query)
    for _, range in ipairs(ranges) do
        -- match must cover an exclusively bigger range than the current selection
        if does_surround(range, current_range) then
            if not best or does_surround(best, range) then
                best = range
            end
        end
    end
    return best
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
    local last_selection = get_last_selection(bufnr)
    local raw_sel = sel
    if last_selection and (is_equal(sel, last_selection.range) or is_equal(sel, last_selection.raw_range)) then
        raw_sel = last_selection.raw_range
    end

    local best = find_best_range(bufnr, query, raw_sel)
    if best then
        local new_best, sel_mode = expand_to_visual_selection(best)
        update_selection(new_best, sel_mode)

        local last = get_last_selection(bufnr)
        if not last then
            prev_selections[bufnr] = {}
        end
        table.insert(
            prev_selections[bufnr],
            ---@type textsubjects.Selection
            {
                changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
                range = new_best,
                raw_range = best,
                mode = sel_mode,
            }
        )
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
    local sel = normalize_selection(sel_start, sel_end)

    local last = get_last_selection(bufnr)
    if last and is_equal(sel, last.range) then
        -- If current selection matches the last one, discard it and go
        -- to the previous one.
        table.remove(prev_selections[bufnr])
        last = get_last_selection(bufnr)
    end

    if not last then
        -- If the last selection is invalid (e.g. changedtick mismatch), the
        -- entire history for this buffer is invalid.
        prev_selections[bufnr] = nil
        vim.cmd('normal! v')
        return
    end

    update_selection(last.range, last.mode)
end

return M
