local M = {}

local namespace_unique_id = vim.api.nvim_create_namespace "YellowHighlighter"
local db_path = vim.fn.stdpath "data" .. "/highlighter_marks.json"

local function load_db()
	local f = io.open(db_path, "r")
	if not f then
		return {}
	end
	local content = f:read "*a"
	f:close()
	if content == "" then
		return {}
	end
	local ok, data = pcall(vim.fn.json_decode, content)
	return ok and data or {}
end

local function save_db(db)
	local f = io.open(db_path, "w")
	if f then
		f:write(vim.fn.json_encode(db))
		f:close()
	end
end

local function load_buffer_marks(bufnr)
	local filepath = vim.api.nvim_buf_get_name(bufnr)
	if filepath == "" then
		return
	end

	local db = load_db()
	local marks = db[filepath] or {}

	vim.api.nvim_buf_clear_namespace(bufnr, namespace_unique_id, 0, -1)
	for _, pos in ipairs(marks) do
		pcall(
			vim.api.nvim_buf_set_extmark,
			bufnr,
			namespace_unique_id,
			pos[1],
			pos[2],
			{
				end_row = pos[3],
				end_col = pos[4],
				hl_group = "CustomYellowHighlight",
			}
		)
	end
end

local function save_buffer_marks(bufnr)
	local filepath = vim.api.nvim_buf_get_name(bufnr)
	if filepath == "" then
		return
	end

	local db = load_db()

	-- get all marks in this buffer
	local marks = vim.api.nvim_buf_get_extmarks(
		bufnr,
		namespace_unique_id,
		0,
		-1,
		{ details = true }
	)

	if #marks == 0 then
		db[filepath] = nil
	else
		db[filepath] = {}
		for _, mark in ipairs(marks) do
			local details = mark[4]

			if details then
				table.insert(db[filepath], {
					mark[2], -- start_row
					mark[3], -- start_col
					details.end_row,
					details.end_col,
				})
			end
		end
	end
	save_db(db)
end

local function trim_whitespace(bufnr, sr, sc, er, ec)
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

	-- clamp exclusive end to the actual line length so an oversized or stale ec
	local er_len = len_of(er)
	if ec > er_len then
		ec = er_len
	end

	local lr, lc
	if ec > 0 then
		lr, lc = er, ec - 1
	else
		lr = er - 1
		lc = len_of(lr) - 1
	end

	-- empty or inverted region.
	if lr < sr or (lr == sr and lc < sc) then
		return nil
	end

	-- advance start past leading whitespace.
	while true do
		if sr > lr or (sr == lr and sc > lc) then
			return nil
		end
		local b = byte_at(sr, sc)
		if b == nil then -- past end of line: next line, col 0
			sr = sr + 1
			sc = 0
		elseif b == " " or b == "\t" then
			sc = sc + 1
		else
			break
		end
	end

	-- retreat end past trailing whitespace (operate on inclusive lr, lc).
	while true do
		if lr < sr or (lr == sr and lc < sc) then
			return nil
		end
		local b = byte_at(lr, lc)
		if b == nil then -- before start of line / empty line: prev line end
			lr = lr - 1
			lc = len_of(lr) - 1
		elseif b == " " or b == "\t" then
			lc = lc - 1
		else
			break
		end
	end

	-- inclusive last char (lr, lc) -> exclusive end (lr, lc + 1).
	return sr, sc, lr, lc + 1
end

local function toggle_highlight(bufnr, start_row, start_col, end_row, end_col)
	-- details = true so we know exactly where existing marks end
	local existing_marks = vim.api.nvim_buf_get_extmarks(
		bufnr,
		namespace_unique_id,
		{ start_row, start_col },
		{ end_row, end_col },
		{ overlap = true, details = true }
	)

	if #existing_marks > 0 then
		-- subtract mode (eraser): carve out the toggled region from each overlapping mark
		for _, mark in ipairs(existing_marks) do
			local m_id = mark[1]
			local m_s_row = mark[2]
			local m_s_col = mark[3]
			local details = mark[4]

			if details then
				local m_e_row = details.end_row
				local m_e_col = details.end_col

				vim.api.nvim_buf_del_extmark(bufnr, namespace_unique_id, m_id)

				-- 2. leftover mark before the erased section (trimmed: no dangling edge ws)
				if
					m_s_row < start_row
					or (m_s_row == start_row and m_s_col < start_col)
				then
					local tsr, tsc, ter, tec = trim_whitespace(
						bufnr,
						m_s_row,
						m_s_col,
						start_row,
						start_col
					)
					if tsr then
						vim.api.nvim_buf_set_extmark(
							bufnr,
							namespace_unique_id,
							tsr,
							tsc,
							{
								end_row = ter,
								end_col = tec,
								hl_group = "CustomYellowHighlight",
							}
						)
					end
				end

				-- 3. leftover mark after the erased section (trimmed: no dangling edge ws)
				if
					m_e_row > end_row
					or (m_e_row == end_row and m_e_col > end_col)
				then
					local tsr, tsc, ter, tec = trim_whitespace(
						bufnr,
						end_row,
						end_col,
						m_e_row,
						m_e_col
					)
					if tsr then
						vim.api.nvim_buf_set_extmark(
							bufnr,
							namespace_unique_id,
							tsr,
							tsc,
							{
								end_row = ter,
								end_col = tec,
								hl_group = "CustomYellowHighlight",
							}
						)
					end
				end
			end
		end
	else
		-- add mode: shrink-wrap to drop leading/trailing whitespace.
		local tsr, tsc, ter, tec =
			trim_whitespace(bufnr, start_row, start_col, end_row, end_col)
		if not tsr then
			return -- selection was entirely whitespace; nothing to highlight
		end
		start_row, start_col, end_row, end_col = tsr, tsc, ter, tec
		vim.api.nvim_buf_set_extmark(
			bufnr,
			namespace_unique_id,
			start_row,
			start_col,
			{
				end_row = end_row,
				end_col = end_col,
				hl_group = "CustomYellowHighlight",
			}
		)
	end

	save_buffer_marks(bufnr)
end

_G.__yellow_highlighter_op = function(motion_type)
	local bufnr = vim.api.nvim_get_current_buf()
	local start_mark = vim.api.nvim_buf_get_mark(bufnr, "[")
	local end_mark = vim.api.nvim_buf_get_mark(bufnr, "]")

	local start_row = start_mark[1] - 1
	local start_col = start_mark[2]
	local end_row = end_mark[1] - 1
	local end_col = end_mark[2]

	local lines = vim.api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, false)
	local line_len = lines[1] and string.len(lines[1]) or 0

	if motion_type == "line" then
		end_col = line_len
	else
		end_col = math.min(end_col + 1, line_len)
	end

	toggle_highlight(bufnr, start_row, start_col, end_row, end_col)
end

function M.setup()
	vim.api.nvim_set_hl(
		0,
		"CustomYellowHighlight",
		{ bg = "#FDE047", fg = "#000000", bold = true }
	)

	local augroup =
		vim.api.nvim_create_augroup("YellowHighlighterAuto", { clear = true })

	vim.api.nvim_create_autocmd({ "BufReadPost" }, {
		group = augroup,
		callback = function(args)
			load_buffer_marks(args.buf)
		end,
	})

	vim.api.nvim_create_autocmd({ "BufWritePost" }, {
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
		local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
		vim.api.nvim_feedkeys(esc, "x", false)

		vim.schedule(function()
			local bufnr = vim.api.nvim_get_current_buf()
			local start_pos = vim.api.nvim_buf_get_mark(bufnr, "<")
			local end_pos = vim.api.nvim_buf_get_mark(bufnr, ">")

			local start_row = start_pos[1] - 1
			local start_col = start_pos[2]
			local end_row = end_pos[1] - 1
			local end_col = end_pos[2] + 1

			local lines =
				vim.api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, false)
			local line_len = lines[1] and string.len(lines[1]) or 0
			end_col = math.min(end_col, line_len)

			toggle_highlight(bufnr, start_row, start_col, end_row, end_col)
		end)
	end, { desc = "Toggle visual highlight" })

	vim.keymap.set("n", "gH", function()
		local bufnr = vim.api.nvim_get_current_buf()
		vim.api.nvim_buf_clear_namespace(bufnr, namespace_unique_id, 0, -1)
		save_buffer_marks(bufnr)
		vim.notify("Highlights cleared", vim.log.levels.INFO)
	end, { desc = "Clear all yellow highlights" })
end

M._trim_whitespace = trim_whitespace

return M
