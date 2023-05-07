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

-- editor.tabspaces: defines how the TAB key should be handled.
--      n:integer :: number of spaces to insert when the TAB key 
--			is pressed
--                   	(according to cursor position)
--                   	eg.:  editor.tabspaces = 4
--      or false  :: insert a TAB char (0x09) when the TAB key is pressed
--                   	eg.:  editor.tabspaces = false

--~ editor.tabspaces = 8
editor.tabspaces = false

-- Extension API 
-- ple extensions can use functions and parameters in 
-- global table 'eapi'

local e = editor.actions

-- RUN A SHELL COMMAND
-- Add a new action "line_shell" which takes the current line,
-- passes it as a command to the shell and inserts the result
-- after the current line.


local function sh(cmd)
	local f, r, err, succ, status, exit
	f, err = io.popen(cmd, "r")
	if not f then return "popen error: " .. tostring(err) end
	r, err = f:read("a")
	succ, exit, status = f:close()
	if not r then return "popen read error: " .. tostring(err) end
	if exit == 'signal' then 
		return "process killed with signal: " .. tostring(status) 
	end
	return r
end


local function line_shell()
	-- the shell command is the content of the current line
	local cmd = e.getline()  -- get the current line
	-- make sure we also capture stderr...
	cmd = cmd .. " 2>&1 "
	-- execute the shell command
	local r = sh(cmd)
	
	e.goend()   -- go to end of line
	e.nl()      -- insert a newline at the cursor
	e.insert(r)  -- insert the shell command output
	e.insert('\n---\n') -- and a separator line
end

-- bind the line_shell function to ^X^M (or ^X-return)
editor.bindings_ctlx[13] = line_shell


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
editor.bindings_ctlx[101] = edit_file_at_cursor -- ^Xe


-- RUN LUA BUFFER
-- Run the complete buffer as a Lua program.
-- The program is run by a Lua subprocess
-- The subprocess standard output is inserted  at the end
-- of the buffer in a multi-line comment.

function e.eval_lua_buffer()
	local msg = editor.msg
	-- msg(m) can be used to diplay a short message (a string)
	-- at the last line of the terminal
	local strf = string.format
	
	-- get buffer content as a string
	local s = e.gettext() 
	
	-- pass buffer content to Lua as stdin; redirect stderr to stdout
	local luacmd = strf("lua 2>&1 << EOT\n%s\nEOT", s)
	local r = sh(luacmd)
	
--~ 	-- insert result in a Lua comment at end of buffer
--~ 	e.goeot()	                  -- go to end of text
--~ 	e.nl() 	                          -- insert a newline
--~ 	e.insert(strf("--[[\n%s\n]]", r)) -- insert result

 	-- insert result at the end of buffer *OUT*
	e.newbuffer("*OUT*")
	e.goeot()	               -- go to end of text
	e.nl() 	                       -- insert a newline
	e.insert(strf("===\n%s\n", r)) -- insert result
	return
end --eval_lua_buffer

-- bind function to ^Xl  (string.byte"l" == 108)
editor.bindings_ctlx[108] = e.eval_lua_buffer -- ^Xl


-- ERROR HANDLING:
-- the default error handler is the function editor.error_handler(). 
-- It is defined in ple.lua. 
-- When an error occurs, it is called with one argument that is 
-- the Lua stack traceback.
-- It can be redefined here, e.g.:
-- editor.error_handler = function(tb) editor.msg("ERROR!!!") end
-- or set to nil. In that case, on error the editor exits immediately.
-- editor.error_handler = nil

-- test error in key bindings
local function testerr()
	error("some key binding error...")
end
editor.bindings_ctlx[116] = testerr -- ^Xt



------------------------------------------------------------------------
-- append some text to the initial message displayed when entering
-- the editor
editor.initmsg = editor.initmsg .. " - Sample ple_init.lua loaded. "
