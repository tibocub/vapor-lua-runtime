local vlr = require("vlr")
-- the REPL logic, fed from a list of lines
local repl = require("vlr.repl")
local lines = {"1 + 2", "x = 5", "x * 2", "for i = 1, 2 do", "  io.write(i, ' ')", "end", "error('boom')", "1 +", "= bad", "print('hi')"}
local i, out = 0, {}
repl(function() i = i + 1; return lines[i] end, function(s) out[#out + 1] = s end)
local text = table.concat(out)
assert(text:find("3\n", 1, true), text)
assert(text:find("10\n", 1, true), text)
assert(text:find("boom", 1, true), text)
assert(select(2, text:gsub("\n", "\n")) >= 5, text)
print("ok")
