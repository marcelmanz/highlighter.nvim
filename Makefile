.PHONY: test format check

test:
	nvim --headless --noplugin -u NORC -c "luafile test/trim_spec.lua" -c "qa!"

format:
	stylua lua/ test/

check:
	stylua --check lua/ test/
