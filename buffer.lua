-- Copyright (c) 2021  Phil Leblanc  -- License: MIT (see LICENSE file)

------------------------------------------------------------------------
--[[  buffer.lua - this is a component of  ple, the 'pure Lua editor'.

211213  home :: cj==1  consistent w/ ci ...and lua arrays

This module defines a buffer object.

A buffer contains 
  - a text, as a list of lines. Lines are UTF8-encoded.
  - a cursor that points to a location in the text.
	the cursor is implemented as 2 numbers: ci, cj
	ci is a line index (starting at 1)
	cj is an UTF8 character position in the line 
		(not a byte offset)
  - a "mark" that points to the beginning or the end of the current 
    selection. The selection is the text between the cursor and the mark.
  - operations to give access to the text, the cursor and the selection
  - support undoing operations performed on the text

]]

-- some local definitions (used by the module term and/or by the editor

local strf = string.format
local byte, char, rep = string.byte, string.char, string.rep

local utf8 = require("utf8")
local ulen = utf8.len
local uchar = utf8.char
local uoff = utf8.offset

local function lines(s)
	-- split s into a list of lines
	lt = {}
	s = s .. "\n"
	for l in string.gmatch(s, "(.-)\r?\n") do table.insert(lt, l) end
	return lt
end


------------------------------------------------------------------------
-- BUFFER AND CURSOR MANIPULATION
--
-- 		use these functions instead of direct buf.ll manipulation.
-- 		This will make it easier to change or enrich the
-- 		representation later. (eg. syntax coloring, undo/redo, ...)

buffer = {}; buffer.__index = buffer -- this is the buffer class

-- (note: 'b' is a buffer object in all functions below)


function buffer.new(ll)
	-- create and initialize a new buffer object
	-- ll is a list of lines (lines should not contain newline bytes)
	local b = {
	  ll=ll,	-- list of text lines
	  ci=1, cj=1,	-- text cursor (line ci, offset cj)
	  unsaved=false,-- true if content has changed since last save
	  chgd=true,	-- true if buffer has changed since last display
			--    (content, cursor or mark changes)
	  ual = {},	-- undo action list
	  ualtop = 0,	-- current top of the undo list 
			--    (~= #ual !! see undo)
	-- XXX li, hs should move to a window object
	  li=1,		-- index in ll of the line at the top of the box
	  hs=0,		-- horizontal scroll (number of columns)

	}
	setmetatable(b, buffer)
	return b
end--new

-- various predicates and accessors

-- these functions assume that the TEXT IS VALID UTF8 
-- (no invalid byte sequence)

-- test if cursor is at end / beginning of  line  (eol, bol)
function buffer.ateol(b) return b.cj > ulen(b.ll[b.ci]) end
function buffer.atbol(b) return b.cj <= 1 end
-- test if cursor is at  first or last line of text
function buffer.atfirst(b) return (b.ci <= 1) end
function buffer.atlast(b) return (b.ci >= #b.ll) end
-- test if cursor is at  end or beginning of  text (eot, bot)
function buffer.ateot(b) return b:atlast() and b:ateol() end
function buffer.atbot(b) return b:atfirst() and b:atbol() end

function buffer.beforecur(b, di, dj)
	-- return true if point (di, dj) is before the cursor 
	-- in the text
	return ((di < b.ci) or (di == b.ci and dj < b.cj))
end

function buffer.markbeforecur(b)
	-- return true if the mark is defined and is before the 
	-- cursor in the text
	return b.si and b:beforecur(b.si, b.sj)
end

function buffer.getcur(b) return b.ci, b.cj end -- get the cursor
function buffer.getsel(b) return b.si, b.sj end -- get the mark

function buffer.curcode(b)
	-- return code of utf8 char at cursor
	local s = b.ll[b.ci]
	if b:ateol() then return nil end
	return utf8.codepoint(s, uoff(s, b.cj))
end

function buffer.curch(b)
	-- return utf8 char at cursor
	local u = buffer.curcode(b)
	return u and uchar(u)
end

function buffer.eol(b)
	-- return coord of current end of line
	local ci = b.ci
	return ci, ulen(b.ll[ci])
end

function buffer.eot(b)
	-- return coord of buffer end of text
	local ci = #b.ll
	return ci, ulen(b.ll[ci])+1
end

function buffer.getline(b, i)
	-- return current line. if i is provided, return line i
	return b.ll[i or b.ci]
end

function buffer.getlines(b, di, dj)
	-- return the text between the cursor and point (di, dj) as
	-- a list of lines. this assumes that (di, dj) is after the cursor.
	local s
	local ci, cj = b:getcur()
	if di == ci then
		s = b.ll[ci]
		return { s:sub(uoff(s,cj), uoff(s,dj)-1) }
	end
	local sl = {}
	for i = ci, di do
		local l = b.ll[i]
		if i == ci then l = l:sub(uoff(l,cj)) end
		if i == di then l = l:sub(1, uoff(l,dj)-1) end
		table.insert(sl, l)
	end
	return sl
end--getlines

function buffer.gettext(b)
	return table.concat(b.ll, '\n')
end

--- cursor movement

-- MAX: used to indicate the last line or the end of line
buffer.MAX = math.maxinteger 

--~ function buffer.setcurj(b, j) -- set cursor on the current line
--~ 	local ci = b:getcur()
--~ 	local ln = ulen(b.ll[ci])
--~ 	if not j or j > ln then j = ln end
--~ 	if j < 1 then j = 1 end
--~ 	b.cj = j
--~ 	return j
--~ end

function buffer.setcur(b, i, j) 
	-- set cursor absolute
	-- if i or j are nil/false the corresponding cursor coordinate
	-- is not modified.
	-- if i or j are not positive or too large they are adjusted 
	-- respectively to the first or last line, and to the bol/eol
	-- position.
	if i then
		if i > #b.ll then 
			b.ci = #b.ll
		elseif i < 1 then
			b.ci = 1
		else
			b.ci = i
		end
	end
	if j then
		local eol = ulen(b.ll[b.ci]) + 1
		if j > eol then 
			b.cj = eol
		elseif j < 1 then
			b.cj = 1
		else
			b.cj = j
		end
	end
	return true
end

function buffer.movecur(b, di, dj)
	-- move cursor relative to the current position
	-- di, dj can be positive or negative for upward/downward
	-- or forward/backward movement, or zero for no movement.
	return buffer.setcur(b, b.ci + di, b.cj + dj)
end

--- text modification at cursor

-- all modifications should be performed by the following functions:
--   bufins(strlist)
--	insert list of string at cursor. if strlist is a string, it is
--	equivalent to a list with only one element
--	if buffer contains one line "abc" and cursor is between b and c
--	(ie screen cursor is on 'c') then
--	bufins{"xx"}  changes the buffer line to "abxxc"
--	bufins{"xx", "yy"}  now the buffer has two lines: "abxx", "yyc"
--	bufins{"", ""}  inserts a newline:   "ab", "c"
--
--   bufdel(di, dj)
--	delete all characters between the cursor and point (di, dj)
--	(bufdel assumes that di, dj is after the cursor)
--	if the buffer is  ("abxx", "yyc") and the cursor is just after 'b',
--	bufdel(2,2) changes the buffer to ("abc")


local ualpush -- defined further down with all undo functions

function buffer.bufins(b, sl, no_undo)
	-- if no_undo is true, don't record the modification
	local slc = {} -- dont push directly sl. make a copy.
	if type(sl) == "string" then
		if not ulen(sl) then return nil, "invalid UTF8 sequence" end
		slc[1] = sl
	elseif #sl == 0 then 
		return true -- insert an empty list: nothing to do
	else
		for i = 1, #sl do 
			if not ulen(sl[i]) then return nil, "invalid UTF8 sequence" end
			slc[i] = sl[i] 
		end
	end
	if not no_undo then ualpush(b, 'ins', slc) end
	local ci, cj = b:getcur()
	local l = b.ll[ci]
	local l1 = l:sub(1,uoff(l,cj)-1)
	local l2 = l:sub(uoff(l,cj))
	local s1 = nil
	if type(sl) == "string" then	s1 = sl
	elseif #sl == 1 then  s1 = sl[1]
	end
	if s1 then -- insert s1 in current line
		b.ll[ci] = l1 .. s1 .. l2
		b:setcur(ci, cj + ulen(s1))
	else -- several lines in sl
		b.ll[ci] = l1 .. sl[1]
		ci = ci + 1
		for i = 2, #sl-1 do
			table.insert(b.ll, ci, sl[i])
			ci = ci + 1
		end
		local last = sl[#sl]
		cj = ulen(last) + 1
		table.insert(b.ll, ci, last .. l2)
		b:setcur(ci, cj)
	end
	b.chgd = true
	b.unsaved = true
	return true
end--bufins

function buffer.bufdel(b, di, dj, no_undo)
	-- if no_undo is true, don't record the modification
	assert(not b:beforecur(di, dj), "point must be after cursor")
	if not no_undo then ualpush(b, 'del', b:getlines(di, dj)) end
	local ci, cj = b:getcur()
	local l1, l2 = b.ll[ci], b.ll[di]
	l1 = l1:sub(1, uoff(l1, cj) - 1)
--~ print('l1', l1)
--~ print('l2', l2)
--~ print('uoff #l2 dj', #l2, dj)
	l2 = l2:sub(uoff(l2, dj))
	if di == ci then -- delete in current line at cursor
		b.ll[ci] = l1 .. l2
	else -- delete several lines
		local ci1 = ci + 1
		for i = ci1, di do
			-- the next line to remove is always the line at ci+1
			table.remove(b.ll, ci1)
		end
		b.ll[ci] = l1 .. l2
	end
	b.chgd = true
	b.unsaved = true
	return true
end--bufdel

function buffer.settext(b, txt)
	-- replace the buffer text
	-- !! it cannot be undone and it clears the undo stack !!
	-- the cursor and display are reinitialized at the top
	-- of the new text.
	buffer.undo_clearall(b)
	if not ulen(txt) then return nil, "invalid UTF8 sequence" end
	b.ll = lines(txt)
	b.chgd = true
	b.unsaved = true
	b.ci = 1 -- line index
	b.cj = 1 -- cursor offset
	return true
end--settext

------------------------------------------------------------------------
-- undo functions

function ualpush(b, op, sl)
	-- push enough context to be able to undo a core operation (ins, del)
	-- sl is always a list of lines
	local top = #b.ual
	if top > b.ualtop then -- remove the remaining redo actions
		for i = top, b.ualtop+1, -1 do table.remove(b.ual, i) end
		assert(#b.ual == b.ualtop)
	end
	local last = b.ual[top]

	-- in the future, try to merge successive insch()

	sl.op, sl.ci, sl.cj = op, b.ci, b.cj
	table.insert(b.ual, sl)
	b.ualtop = b.ualtop + 1
	return
end

function buffer.op_undo(b, sl)
--~ he.pp(sl)
	b:setcur(sl.ci, sl.cj)
	if sl.op == "del" then
		return b:bufins(sl, true)
	elseif sl.op == "ins" then
		if #sl == 1 then -- Insertion was limited to part of a single line
			return b:bufdel(sl.ci, sl.cj+ulen(sl[1]), true)
		else -- Insertion spanned multiple lines
			return b:bufdel(sl.ci+#sl-1, ulen(sl[#sl])+1, true)
		end
	else
		return nil, "unknown op"
	end
end

function buffer.op_redo(b, sl)
	b:setcur(sl.ci, sl.cj)
	if sl.op == "ins" then
		return b:bufins(sl, true)
	elseif sl.op == "del" then
		return b:bufdel(sl.ci+#sl-1, sl.cj+ulen(sl[#sl]), true)
	else
		return nil, "unknown op"
	end
end

function buffer.undo_clearall(b)
	b.ual = {}
	b.ualtop = 0
end

function buffer.undo(b)
	if b.ualtop == 0 then return nil, "nothing to undo" end
	b:op_undo(b.ual[b.ualtop])
	b.ualtop = b.ualtop - 1
	return true
end--undo

function buffer.redo(b)
	if b.ualtop == #b.ual then return nil, "nothing to redo!" end
	b.ualtop = b.ualtop + 1
	b:op_redo(b.ual[b.ualtop])
	return true
end--redo

------------------------------------------------------------------------
-- to be removed later (or not?)

buffer.MAX = 0xffffffff

function buffer.setcurj(b, cj)
	return b:setcur(nil, cj)
end

------------------------------------------------------------------------
return buffer

