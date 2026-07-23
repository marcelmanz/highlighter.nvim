package.path = "lua/?.lua;lua/?/init.lua;" .. package.path
local hl = require("highlighter")
hl.setup()
local trim = hl._trim_whitespace
local function mkbuf(lines)
	local b = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
	return b
end

local fails = 0
local function check(name, got, want)
	local n = #got
	if want == nil then
		if n ~= 0 then
			fails = fails + 1
		end
		return
	end
	if n ~= 4 or got[1] ~= want[1] or got[2] ~= want[2] or got[3] ~= want[3] or got[4] ~= want[4] then
		fails = fails + 1
		print(
			("FAIL %s: got %s want %d,%d,%d,%d"):format(
				name,
				n == 4 and ("%d,%d,%d,%d"):format(got[1], got[2], got[3], got[4]) or "nil",
				want[1],
				want[2],
				want[3],
				want[4]
			)
		)
	end
end

check("ec past EOL single", { trim(mkbuf({ "foo" }), 0, 0, 0, 5) }, { 0, 0, 0, 3 })
check("ec past EOL multi", { trim(mkbuf({ "foo", "bar" }), 0, 0, 0, 9) }, { 0, 0, 0, 3 })
check("zerowidth row0", { trim(mkbuf({ "foo", "bar" }), 0, 0, 0, 0) }, nil)
check("ec0 to prev line", { trim(mkbuf({ "foo", "bar" }), 0, 0, 1, 0) }, { 0, 0, 0, 3 })
check("ec0 skips empty", { trim(mkbuf({ "foo", "", "bar" }), 0, 0, 2, 0) }, { 0, 0, 0, 3 })
check("ec0 empty above -> nil", { trim(mkbuf({ "", "bar" }), 0, 0, 1, 0) }, nil)
check("leading indent", { trim(mkbuf({ "    foo" }), 0, 0, 0, 7) }, { 0, 4, 0, 7 })
check("trailing ws", { trim(mkbuf({ "foo   " }), 0, 0, 0, 6) }, { 0, 0, 0, 3 })
check("both edges", { trim(mkbuf({ "   foo   " }), 0, 0, 0, 9) }, { 0, 3, 0, 6 })
check("internal ws kept", { trim(mkbuf({ "foo bar baz" }), 0, 0, 0, 11) }, { 0, 0, 0, 11 })
check("tabs", { trim(mkbuf({ "\t\tfoo\t" }), 0, 0, 0, 6) }, { 0, 2, 0, 5 })
check("all ws -> nil", { trim(mkbuf({ "    " }), 0, 0, 0, 4) }, nil)
check("blank lines -> nil", { trim(mkbuf({ "", "", "" }), 0, 0, 2, 0) }, nil)
check("empty buf -> nil", { trim(mkbuf({ "" }), 0, 0, 0, 0) }, nil)
check("inverted -> nil", { trim(mkbuf({ "foo" }), 0, 3, 0, 0) }, nil)
check("mb trailing", { trim(mkbuf({ "fél" }), 0, 0, 0, 4) }, { 0, 0, 0, 4 })
check("mb leading", { trim(mkbuf({ "él" }), 0, 0, 0, 3) }, { 0, 0, 0, 3 })
check("mid blank kept", { trim(mkbuf({ "foo", "", "bar" }), 0, 0, 2, 3) }, { 0, 0, 2, 3 })
check("ideo space kept", { trim(mkbuf({ "\u{3000}x" }), 0, 0, 0, 4) }, { 0, 0, 0, 4 })

if fails > 0 then
	print(("FAIL: %d test(s)"):format(fails))
	vim.cmd("cq 1")
else
	print("PASS: all trim tests")
end
