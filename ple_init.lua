
-- a sample PLE configuration / extension file
------------------------------------------------------------------------
-- The configuration file is looked for in sequence at the
-- following locations:
--	- the file which pathname is in the environment variable PLE_INIT
--	- ./ple_init.lua
--	- ~/.config/ple/ple_init.lua
--
--The first file found, if any, is loaded.
------------------------------------------------------------------------

local strf = string.format

-- Configuration

-- Configuration variables and editor extension API are available
-- through the 'editor' global object.

-- eapi.tabspaces: defines how the TAB key should be handled.
--      n:integer :: number of spaces to insert when the TAB key 
--			is pressed
--                   	(according to cursor position)
--                   	eg.:  editor.tabspaces = 4
--      or false  :: insert a TAB char (0x09) when the TAB key is pressed
--                   	eg.:  editor.tabspaces = false

--~ eapi.tabspaces = 8
eapi.tabspaces = false

-- Extension API 
-- ple extensions can use functions and parameters in 
-- global table 'eapi'

local e = eapi.actions

-- SHELL command
-- Add a new action "line_shell" which takes the current line,
-- passes it as a command to the shell and inserts the result
-- after the current line.


local function line_shell()
	-- the function will be called with the current buffer as
	-- the first argument. So here, b is the current buffer.
	--
	-- get the current line
	local line = e.getline()
	-- the shell command is the content of the line
	local cmd = line
	-- make sure we also get stderr...
	cmd = cmd .. " 2>&1 "
	-- execute the shell command
	local fh, err = io.popen(cmd)
	if not fh then
		eapi.msg("newline_shell error: " .. err)
		return
	end
	local ll = {} -- read lines into ll
	for l in fh:lines() do
		table.insert(ll, l)
	end
	fh:close()
	-- go to end of line
	-- (DO NOT forget the buffer parameter for all e.* functions)
	e.goend()
	-- insert a newline at the cursor
	e.nl()
	-- insert the list of lines at the cursor
	-- e.insert() can be called with either a list of lines or a string
	-- that may contain newlines ('\n') characters
	-- lines should NOT contain '\n' characters
	e.insert(ll)
	-- insert another newline and a separator line
	e.nl()
	e.insert('---\n')
		-- the previous line is equivalent to
		-- e.insert('---'); e.nl()
end

-- bind the line_shell function to ^X^M (or ^X-return)
eapi.bindings_ctlx[13] = line_shell


-- EDIT FILE AT CURSOR
-- assume the current line contains a filename.
-- get the filename and open the file in a new buffer
--
local function edit_file_at_cursor()
	local line = e.getline()
	-- (FIXME) assume the line contains only the filename
	local fname = line
	e.findfile(fname)
end

-- bind function to ^Xe (string.byte"e" == 101)
eapi.bindings_ctlx[101] = edit_file_at_cursor -- ^Xe


-- EVAL LUA BUFFER
-- eval buffer as a Lua chunk
-- 	Beware! the chunk is evaluated **in the editor environment**
--	which can be a way to shoot oneself in the foot!
-- chunk evaluation result is inserted  at the end
-- of the buffer in a multi-line comment.

function e.eval_lua_buffer(b)
	local msg = eapi.msg
		-- msg(m) can be used to diplay a short message (a string)
		-- at the last line of the terminal
	local strf = string.format

	-- get the number of lines in the buffer
	-- getcur() returns the cursor position (line and column indexes)
	-- and the number of lines in the buffer.
	local ci, cj, ln = e.getcur() -- ci, cj are ignored here.
	-- get content of the buffer
	local t = {}
	for i = 1, ln do
		table.insert(t, e.getline(i))
	end
	-- txt is the content of the buffer as a string
	local txt = table.concat(t, "\n")
	-- eval txt as a Lua chunk **in the editor environment**
	local r, s, fn, errmsg, result
	fn, errmsg = load(txt, "buffer", "t") -- load the Lua chunk
	if not fn then
		result = strf("load error: %s", errmsg)
	else
		pr, r, errm = pcall(fn)
		if not pr then
			result = strf("lua error: %s", r)
		elseif not r then
			result = strf("return: %s, %s", r, errmsg)
		else
			result = r
		end
	end
	-- insert result in a comment at end of buffer
	e.goeot()	-- go to end of buffer
	e.nl() 	-- insert a newline
	--insert result
	e.insert(strf("--[[\n%s\n]]", tostring(result)))
	return
end --eval_lua_buffer

-- bind function to ^Xl  (string.byte"l" == 108)
eapi.bindings_ctlx[108] = e.eval_lua_buffer -- ^Xl




------------------------------------------------------------------------
-- append some text to the initial message displayed when entering
-- the editor
eapi.initmsg = eapi.initmsg .. " - eapi/Sample ple_init.lua loaded. "
