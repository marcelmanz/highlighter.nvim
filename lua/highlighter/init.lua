local M = {}

local namespace = vim.api.nvim_create_namespace "YellowHighlighter"
local db_path = vim.fn.stdpath "data" .. "/highlighter_marks.json"
local HL_GROUP = "CustomYellowHighlight"

local function is_before(first_row, first_col, second_row, second_col)
	return first_row < second_row
		or (first_row == second_row and first_col < second_col)
end

local function line_len(bufnr, row)
	local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
	return line and #line or 0
end

local function load_db()
	local file = io.open(db_path, "r")
	if not file then
		return {}
	end
	local content = file:read "*a"
	file:close()
	if content == "" then
		return {}
	end
	local ok, data = pcall(vim.fn.json_decode, content)
	return ok and data or {}
end

local function save_db(db)
	local file = io.open(db_path, "w")
	if file then
		file:write(vim.fn.json_encode(db))
		file:close()
	end
end

local function buf_path(bufnr)
	local path = vim.api.nvim_buf_get_name(bufnr)
	return path ~= "" and path or nil
end

local function set_mark(bufnr, start_row, start_col, end_row, end_col)
	vim.api.nvim_buf_set_extmark(bufnr, namespace, start_row, start_col, {
		end_row = end_row,
		end_col = end_col,
		hl_group = HL_GROUP,
	})
end

-- trim leading/trailing whitespace from a (0-indexed, end_col-exclusive) region.
-- returns nil for empty / inverted / whitespace-only regions.
local function trim_whitespace(bufnr, start_row, start_col, end_row, end_col)
	local cur_row, cur_line = -1, nil
	local function line_of(row)
		if row ~= cur_row then
			cur_row = row
			cur_line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
		end
		return cur_line
	end
	local function byte_at(row, col)
		local line = line_of(row)
		if not line or col < 0 or col >= #line then
			return nil
		end
		return line:sub(col + 1, col + 1)
	end
	local function len_of(row)
		local line = line_of(row)
		return line and #line or 0
	end

	-- clamp past-EOL end_col to the real line length
	end_col = math.min(end_col, len_of(end_row))

	-- exclusive end (end_row, end_col) -> inclusive last char (last_row, last_col)
	local last_row, last_col
	if end_col > 0 then
		last_row, last_col = end_row, end_col - 1
	else
		last_row = end_row - 1
		last_col = len_of(last_row) - 1
	end

	if is_before(last_row, last_col, start_row, start_col) then
		return nil
	end

	-- advance start past leading whitespace
	while true do
		if is_before(last_row, last_col, start_row, start_col) then
			return nil
		end
		local byte = byte_at(start_row, start_col)
		if byte == nil then -- past EOL: wrap to next line
			start_row, start_col = start_row + 1, 0
		elseif byte == " " or byte == "\t" then
			start_col = start_col + 1
		else
			break
		end
	end

	-- retreat end past trailing whitespace
	while true do
		if is_before(last_row, last_col, start_row, start_col) then
			return nil
		end
		local byte = byte_at(last_row, last_col)
		if byte == nil then -- before BOL / empty line: end of previous line
			last_row = last_row - 1
			last_col = len_of(last_row) - 1
		elseif byte == " " or byte == "\t" then
			last_col = last_col - 1
		else
			break
		end
	end

	-- inclusive (last_row, last_col) -> exclusive end_col
	return start_row, start_col, last_row, last_col + 1
end

local function set_trimmed_mark(bufnr, start_row, start_col, end_row, end_col)
	local trim_start_row, trim_start_col, trim_end_row, trim_end_col =
		trim_whitespace(bufnr, start_row, start_col, end_row, end_col)
	if trim_start_row then
		set_mark(
			bufnr,
			trim_start_row,
			trim_start_col,
			trim_end_row,
			trim_end_col
		)
	end
end

local function load_buffer_marks(bufnr)
	local path = buf_path(bufnr)
	if not path then
		return
	end
	vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
	for _, coords in ipairs(load_db()[path] or {}) do
		pcall(set_mark, bufnr, coords[1], coords[2], coords[3], coords[4])
	end
end

local function save_buffer_marks(bufnr)
	local path = buf_path(bufnr)
	if not path then
		return
	end
	local db = load_db()
	local marks = vim.api.nvim_buf_get_extmarks(
		bufnr,
		namespace,
		0,
		-1,
		{ details = true }
	)
	if #marks == 0 then
		db[path] = nil
	else
		local serialized = {}
		for _, mark in ipairs(marks) do
			local details = mark[4]
			if details then
				table.insert(
					serialized,
					{ mark[2], mark[3], details.end_row, details.end_col }
				)
			end
		end
		db[path] = serialized
	end
	save_db(db)
end

-- erase overlapping marks, keeping any non-whitespace leftover on either side;
-- otherwise add a trimmed highlight for the whole region.
local function toggle_highlight(bufnr, start_row, start_col, end_row, end_col)
	local existing = vim.api.nvim_buf_get_extmarks(
		bufnr,
		namespace,
		{ start_row, start_col },
		{ end_row, end_col },
		{ overlap = true, details = true }
	)

	if #existing == 0 then
		set_trimmed_mark(bufnr, start_row, start_col, end_row, end_col)
	else
		for _, mark in ipairs(existing) do
			local details = mark[4]
			if details then
				local mark_start_row, mark_start_col = mark[2], mark[3]
				local mark_end_row, mark_end_col =
					details.end_row, details.end_col
				vim.api.nvim_buf_del_extmark(bufnr, namespace, mark[1])
				if
					is_before(
						mark_start_row,
						mark_start_col,
						start_row,
						start_col
					)
				then
					set_trimmed_mark(
						bufnr,
						mark_start_row,
						mark_start_col,
						start_row,
						start_col
					)
				end
				if is_before(end_row, end_col, mark_end_row, mark_end_col) then
					set_trimmed_mark(
						bufnr,
						end_row,
						end_col,
						mark_end_row,
						mark_end_col
					)
				end
			end
		end
	end

	save_buffer_marks(bufnr)
end

-- convert 1-indexed nvim marks to a 0-indexed, end_col-exclusive region.
-- line_mode spans the whole last line (linewise motions).
local function region_from_marks(bufnr, start_mark, end_mark, line_mode)
	local start_row, start_col = start_mark[1] - 1, start_mark[2]
	local end_row = end_mark[1] - 1
	local end_line_len = line_len(bufnr, end_row)
	local end_col = line_mode and end_line_len
		or math.min(end_mark[2] + 1, end_line_len)
	return start_row, start_col, end_row, end_col
end

_G.__yellow_highlighter_op = function(motion_type)
	local bufnr = vim.api.nvim_get_current_buf()
	local start_row, start_col, end_row, end_col = region_from_marks(
		bufnr,
		vim.api.nvim_buf_get_mark(bufnr, "["),
		vim.api.nvim_buf_get_mark(bufnr, "]"),
		motion_type == "line"
	)
	toggle_highlight(bufnr, start_row, start_col, end_row, end_col)
end

function M.setup()
	vim.api.nvim_set_hl(
		0,
		HL_GROUP,
		{ bg = "#FDE047", fg = "#000000", bold = true }
	)

	local augroup =
		vim.api.nvim_create_augroup("YellowHighlighterAuto", { clear = true })

	vim.api.nvim_create_autocmd("BufReadPost", {
		group = augroup,
		callback = function(args)
			load_buffer_marks(args.buf)
		end,
	})

	vim.api.nvim_create_autocmd("BufWritePost", {
		group = augroup,
		callback = function(args)
			save_buffer_marks(args.buf)
		end,
	})

	vim.keymap.set("n", "gh", function()
		vim.go.operatorfunc = "v:lua.__yellow_highlighter_op"
		return "g@"
	end, { expr = true, desc = "Toggle highlight using a motion (e.g., ghiw)" })

	vim.keymap.set("x", "gh", function()
		vim.api.nvim_feedkeys(
			vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
			"x",
			false
		)
		vim.schedule(function()
			local bufnr = vim.api.nvim_get_current_buf()
			local start_row, start_col, end_row, end_col = region_from_marks(
				bufnr,
				vim.api.nvim_buf_get_mark(bufnr, "<"),
				vim.api.nvim_buf_get_mark(bufnr, ">"),
				false
			)
			toggle_highlight(bufnr, start_row, start_col, end_row, end_col)
		end)
	end, { desc = "Toggle visual highlight" })

	vim.keymap.set("n", "gH", function()
		local bufnr = vim.api.nvim_get_current_buf()
		vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
		save_buffer_marks(bufnr)
		vim.notify("Highlights cleared", vim.log.levels.INFO)
	end, { desc = "Clear all yellow highlights" })
end

M._trim_whitespace = trim_whitespace

return M
