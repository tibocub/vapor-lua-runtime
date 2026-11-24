-- "bit": the LuaJIT/BitOp API on integers (results are signed 32-bit, like BitOp), for 5.1-era code that does `require("bit")`.
local M = {}
local function n(x)
  if x ~= math.floor(x) then x = math.floor(x + 0.5) end
  return x
end
local function s32(x) x = x & 0xFFFFFFFF; if x >= 0x80000000 then x = x - 0x100000000 end; return x end
M.tobit = function(x) return s32(n(x)) end
M.bnot = function(x) return s32(~n(x)) end
M.band = function(x, ...) x = n(x); for i = 1, select("#", ...) do x = x & n((select(i, ...))) end; return s32(x) end
M.bor = function(x, ...) x = n(x); for i = 1, select("#", ...) do x = x | n((select(i, ...))) end; return s32(x) end
M.bxor = function(x, ...) x = n(x); for i = 1, select("#", ...) do x = x ~ n((select(i, ...))) end; return s32(x) end
M.lshift = function(x, k) return s32((n(x) & 0xFFFFFFFF) << (n(k) & 31)) end
M.rshift = function(x, k) return s32((n(x) & 0xFFFFFFFF) >> (n(k) & 31)) end
M.arshift = function(x, k)
  x, k = s32(n(x)), n(k) & 31
  return s32(x >> k | (x < 0 and ~(0xFFFFFFFF >> k) or 0)) -- Lua's >> is logical on the 64-bit value: fill the top with the sign
end
M.rol = function(x, k) x, k = n(x) & 0xFFFFFFFF, n(k) & 31; return s32((x << k) | (x >> (32 - k))) end
M.ror = function(x, k) x, k = n(x) & 0xFFFFFFFF, n(k) & 31; return s32((x >> k) | (x << (32 - k))) end
M.bswap = function(x)
  x = n(x) & 0xFFFFFFFF
  return s32(((x & 0xFF) << 24) | ((x & 0xFF00) << 8) | ((x >> 8) & 0xFF00) | (x >> 24))
end
M.tohex = function(x, w)
  w = w and n(w) or 8
  local upper = w < 0
  if upper then w = -w end
  if w > 8 then w = 8 end
  local s = string.format(upper and "%08X" or "%08x", n(x) & 0xFFFFFFFF)
  return s:sub(9 - w)
end
return M
