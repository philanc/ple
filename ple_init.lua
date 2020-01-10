
-- a sample PLE configuration / extension file
------------------------------------------------------------------------
-- The configuration file is looked for in sequence at the 
-- following locations:
--	- the file which pathname is in the environment variable PLE_INIT
--	- ./ple_init.lua
--	- ~/config/ple/ple_init.lua
--
--The first file found, if any, is loaded. 
------------------------------------------------------------------------


-- Let's add a new action "newline_shell" which takes the current line,
-- passes it as a command to the shell and inserts the result at the cursor.

local e = editor.actions

function e.newline_shell(b)
	-- the function will be called with the current buffer as
	-- the first argument. So b is the current buffer.
	--
	-- get the current line and the cursor column j
	local line, j = b:getline() 
	-- the shell command is the content of the line up to the cursor
	local cmd = line:sub(1, j)
	-- make sure we also get stderr...
	cmd = cmd .. " 2>&1 "
	-- execute the shell command
	local fh, err = io.popen(cmd)
	if not fh then
		editor.msg("newline_shell error: " .. err)
		return
	end
	local ll = {} -- read lines into ll
	for l in fh:lines() do
		table.insert(ll, l)
	end
	fh:close()
	-- insert a newline at the cursor
	e.nl(b)
	-- insert the list of lines at the cursor (if the list is not empty)
	if #ll > 0 then b:bufins(ll) end
	-- insert another newline
	e.nl(b)
end	

	
-- bind 'newline_shell' to ESC-Return (esc-^M)
editor.bindings[27][13] = e.newline_shell


-- edit file at cursor
function e.edit_file_at_cursor(b)
	local line, j = b:getline()
	-- (FIXME) assume the line contains only the filename
	local fname = line
	e.findfile(b, fname)
end
-- bind function
editor.bindings[27][101] = e.edit_file_at_cursor -- ESC-e


-- eval buffer as a Lua chunk (in the editor environment)
function e.eval_lua_buffer(b)
	local msg = editor.msg
	local strf = string.format
	local txt = b:gettext()
	local r, s, fn, errm
	fn, errm = load(txt, "buffer", "t") -- chunkname=buffer, mode=text only
	if not fn then 
		msg(errm)
	else
		pr, r, errm = pcall(fn)
		if not pr then msg(strf("lua error: %s", r)); return end
		if not r then msg(strf("nil: %s", errm)); return end
		if r == true then msg(strf("ok. %s", errm or "")); return end
		-- display r in *LUA* buffer
		local lb = e.newbuffer(b, "*LUA*") -- the Lua buffer
		lb:settext(r)
		editor.fullredisplay(lb)
		return
	end
end
-- bind function
editor.bindings[27][108] = e.eval_lua_buffer -- ESC-l
	



------------------------------------------------------------------------
-- append some text to the initial message displayed when entering
-- the editor
editor.initmsg = editor.initmsg .. " - Sample ple_init.lua loaded. "
