-- terminal input decoder (vapor.decode): chars, keys, modifiers, mouse, split sequences
local function ev(s) return vapor.decode(s) end
local function same(got, want)
  assert(#got == #want, "count " .. #got .. " vs " .. #want)
  for i, w in ipairs(want) do
    for j = 1, #w do assert(got[i][j] == w[j], string.format("event %d field %d: %s vs %s", i, j, tostring(got[i][j]), tostring(w[j]))) end
  end
end

same(ev("ab"), {{"char", "a"}, {"char", "b"}})
same(ev("h\xc3\xa9"), {{"char", "h"}, {"char", "\xc3\xa9"}})          -- UTF-8
same(ev("\xe2\x82\xac"), {{"char", "\xe2\x82\xac"}})
same(ev("\r\t\x7f"), {{"key", "enter", 0}, {"key", "tab", 0}, {"key", "backspace", 0}})
same(ev("\x03"), {{"key", "c", 4}})                                  -- Ctrl+C
same(ev("\27[A\27[B\27[C\27[D"), {{"key", "up", 0}, {"key", "down", 0}, {"key", "right", 0}, {"key", "left", 0}})
same(ev("\27[1;5C"), {{"key", "right", 4}})                          -- Ctrl+Right
same(ev("\27[1;2A"), {{"key", "up", 1}})                             -- Shift+Up
same(ev("\27[3~\27[5~\27[6~\27[2~"), {{"key", "delete", 0}, {"key", "pageup", 0}, {"key", "pagedown", 0}, {"key", "insert", 0}})
same(ev("\27OP\27[15~\27[24~"), {{"key", "f1", 0}, {"key", "f5", 0}, {"key", "f12", 0}})
same(ev("\27[Z"), {{"key", "tab", 1}})                               -- Shift+Tab
same(ev("\27x"), {{"key", "x", 2}})                                  -- Alt+x

-- SGR mouse: 1-based coordinates
same(ev("\27[<0;10;5M"), {{"mouse", "press", 1, 10, 5, 0}})
same(ev("\27[<0;10;5m"), {{"mouse", "release", 1, 10, 5, 0}})
same(ev("\27[<2;3;4M"), {{"mouse", "press", 3, 3, 4, 0}})           -- right button
same(ev("\27[<32;7;8M"), {{"mouse", "drag", 1, 7, 8, 0}})
same(ev("\27[<35;7;8M"), {{"mouse", "move", 0, 7, 8, 0}})
same(ev("\27[<64;1;1M\27[<65;1;1M"), {{"mouse", "scroll_up", 0, 1, 1, 0}, {"mouse", "scroll_down", 0, 1, 1, 0}})
same(ev("\27[<16;2;2M"), {{"mouse", "press", 1, 2, 2, 4}})           -- Ctrl+click

-- a sequence split across reads
same(ev("\27["), {})
same(ev("1;5"), {})
same(ev("A"), {{"key", "up", 4}})
same(ev("\xe2\x82"), {})
same(ev("\xac"), {{"char", "\xe2\x82\xac"}})

-- a lone ESC only comes out of the flush
same(ev("\27"), {})
assert(vapor.decode_pending() == true)
same(vapor.decode_flush(), {{"key", "escape", 0}})
assert(vapor.decode_pending() == false)

-- garbage must not wedge the decoder
same(ev("\27[999999999999;1;1;1;1;1;1Z"), {{"key", "tab", 1}})
same(ev("\xff\x80ok"), {{"char", "o"}, {"char", "k"}})
