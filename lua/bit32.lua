-- "bit32": the Lua 5.2 library on integers (results are unsigned 32-bit), for 5.1/5.2-era code that does `require("bit32")`.
local M = {}
local function u(x)
  if math.type(x) == "float" then x = math.floor(x) end
  return x & 0xFFFFFFFF
end
M.bnot = function(x) return ~u(x) & 0xFFFFFFFF end
M.band = function(...) local r = 0xFFFFFFFF; for i = 1, select("#", ...) do r = r & u((select(i, ...))) end; return r end
M.bor = function(...) local r = 0; for i = 1, select("#", ...) do r = r | u((select(i, ...))) end; return r end
M.bxor = function(...) local r = 0; for i = 1, select("#", ...) do r = r ~ u((select(i, ...))) end; return r end
M.btest = function(...) return M.band(...) ~= 0 end
M.lshift = function(x, k)
  x, k = u(x), math.floor(k)
  if k < 0 then return M.rshift(x, -k) end
  if k >= 32 then return 0 end
  return (x << k) & 0xFFFFFFFF
end
M.rshift = function(x, k)
  x, k = u(x), math.floor(k)
  if k < 0 then return M.lshift(x, -k) end
  if k >= 32 then return 0 end
  return x >> k
end
M.arshift = function(x, k)
  x, k = u(x), math.floor(k)
  if k < 0 then return M.lshift(x, -k) end
  if k >= 32 then return x >= 0x80000000 and 0xFFFFFFFF or 0 end
  local r = x >> k
  if x >= 0x80000000 then r = r | (0xFFFFFFFF << (32 - k) & 0xFFFFFFFF) end
  return r
end
M.lrotate = function(x, k) x, k = u(x), math.floor(k) % 32; return ((x << k) | (x >> (32 - k))) & 0xFFFFFFFF end
M.rrotate = function(x, k) return M.lrotate(x, -math.floor(k)) end
M.extract = function(x, field, width)
  width = width or 1
  if field < 0 or width < 1 or field + width > 32 then error("trying to access non-existent bits", 2) end
  return (u(x) >> field) & ((1 << width) - 1)
end
M.replace = function(x, v, field, width)
  width = width or 1
  if field < 0 or width < 1 or field + width > 32 then error("trying to access non-existent bits", 2) end
  local mask = ((1 << width) - 1) << field
  return (u(x) & ~mask & 0xFFFFFFFF) | ((u(v) << field) & mask)
end
return M
