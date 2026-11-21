-- native console records (Windows) -> events, through vaporUI's pure translator (no console needed)
local term = require("vapor.term")
local function rec(t) return term.record(t)[1] end
local function is(got, want)
  assert(got, "no event, wanted " .. want[1] .. "," .. tostring(want[2]))
  for i, w in ipairs(want) do assert(got[i] == w, string.format("field %d: %s vs %s", i, tostring(got[i]), tostring(w))) end
end
local LCTRL, LALT, SHIFT = 0x8, 0x2, 0x10
is(rec{vk = 0x41, scan = 0x1E, uc = 1, unshifted = 97, ctrl = LCTRL}, {"key", "a", 4})            -- Ctrl+A (record carries the control char)
is(rec{vk = 0x41, scan = 0x1E, uc = 97, unshifted = 97, ctrl = LALT}, {"key", "a", 2})            -- Alt+a
is(rec{vk = 0x41, scan = 0x1E, uc = 1, unshifted = 97, ctrl = LCTRL + SHIFT}, {"key", "a", 5})    -- Ctrl+Shift+A
is(rec{vk = 0x41, scan = 0x1E, uc = 97, unshifted = 97}, {"char", "a"})                           -- plain typing is text
is(rec{vk = 0x41, scan = 0x1E, uc = 65, unshifted = 97, ctrl = SHIFT}, {"char", "A"})
is(rec{vk = 0x25, scan = 0x4B, ctrl = 0x100 + LCTRL}, {"key", "left", 4})                         -- Ctrl+Left (enhanced key)
is(rec{vk = 0x74, scan = 0x3F}, {"key", "f5", 0})
assert(#term.record{vk = 0x11, scan = 0x1D, ctrl = LCTRL} == 0, "a modifier alone is no event")     -- Ctrl pressed alone
is(rec{kind = 2, buttons = 1, prev_buttons = 0, x = 4, y = 2, level = 1}, {"mouse", "press", 1, 5, 3}) -- left click, 1-based cells
is(rec{kind = 2, buttons = 0, flags = 1, x = 4, y = 2, level = 2}, {"mouse", "move", 0, 5, 3})        -- hover needs level 2
assert(#term.record{kind = 2, buttons = 0, flags = 1, x = 4, y = 2, level = 1} == 0, "no hover at level 1")
print("ok")
