
buffer = require 'buffer'

b = buffer.new {'123'}
assert(#b.ll == 1 and b.ll[1] == '123')


-- bufins and undo/redo

b:setcur(1, 2)
b:bufins{"abc", "def"}
assert(b.ll[1] == '1abc' and b.ll[2] == 'def23')
b:undo()
assert(#b.ll == 1 and b.ll[1] == '123')

b = buffer.new {'123'}
b:setcur(1, 4)
b:bufins{"abc", "def", ""}
assert(#b.ll == 3 and b.ll[1] == '123abc')
assert(b.ll[2] == 'def' and b.ll[3] == '')
b:undo()
assert(#b.ll == 1 and b.ll[1] == '123')
b:redo()
assert(#b.ll == 3 and b.ll[1] == '123abc')
assert(b.ll[2] == 'def' and b.ll[3] == '')

-- bufdel
b = buffer.new{"abc", "", "def"}
b:setcur(1,2)
b:bufdel(3,2)
assert(#b.ll == 1 and b.ll[1] == 'aef')
b:undo()
assert(b.ll[1] == 'abc' and b.ll[2] == '' and b.ll[3] == 'def')

