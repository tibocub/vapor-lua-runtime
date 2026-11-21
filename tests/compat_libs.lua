-- 5.1-era library support found by running real rocks (docs/libtest.md): module()/package.seeall, math.log10 & friends, float arguments, bit, bit32, cjson.safe
assert(vapor.dialect == "5.1")

-- float arguments are truncated like in 5.1; non-numbers still fail
assert(("abcdef"):sub(1.5, 3.9) == "abc" and string.rep("a", 2.9) == "aa" and string.format("%d", 3.9) == "3")
assert(not pcall(string.rep, "a", "x") and not pcall(string.rep, "a", 0 / 0))

assert(math.log10(1000) == 3 and math.ldexp(1, 4) == 16 and select(2, math.frexp(8)) == 4 and math.frexp(8) == 0.5)

-- module() as a rock uses it: loaded through require, globals defined in the chunk land in the module table
package.preload["old.style"] = function(...)
  local name = ...
  local chunk = assert(loadstring([[
    module("old.style", package.seeall)
    function hello() return "hi " .. tostring(_NAME) .. " " .. type(string) end   -- string is visible through package.seeall
    value = 42
  ]]))
  chunk()
  return package.loaded["old.style"]
end
local m = require("old.style")
assert(m.hello() == "hi old.style table" and m.value == 42 and m._NAME == "old.style" and m._PACKAGE == "old.", "module()")
assert(old.style == m, "dotted module names nest in the globals")
assert(rawget(_G, "value") == nil and rawget(_G, "hello") == nil, "module globals do not leak")

-- bit (BitOp)
local bit = require("bit")
assert(bit.band(0xFF00, 0x0FF0) == 0x0F00 and bit.bor(1, 2, 4) == 7 and bit.bxor(5, 1) == 4 and bit.bnot(0) == -1)
assert(bit.lshift(1, 31) == -2147483648 and bit.rshift(-1, 28) == 15 and bit.arshift(-8, 1) == -4 and bit.arshift(0x40000000, 30) == 1)
assert(bit.rol(1, 31) == -2147483648 and bit.ror(1, 1) == -2147483648 and bit.bswap(0x12345678) == 0x78563412 and bit.tobit(0xFFFFFFFF) == -1)
assert(bit.tohex(255) == "000000ff" and bit.tohex(255, 2) == "ff" and bit.tohex(255, -4) == "00FF" and bit.tobit(2 ^ 32 + 5) == 5)

-- bit32 (5.2)
local b32 = require("bit32")
assert(b32.band(0xF0, 0x3C) == 0x30 and b32.bor(1, 2) == 3 and b32.bxor(3, 1) == 2 and b32.bnot(0) == 0xFFFFFFFF and b32.btest(6, 3))
assert(b32.lshift(1, 31) == 0x80000000 and b32.lshift(1, 32) == 0 and b32.rshift(0x80000000, 31) == 1 and b32.rshift(1, -3) == 8)
assert(b32.arshift(0x80000000, 4) == 0xF8000000 and b32.arshift(0x7FFFFFFF, 4) == 0x07FFFFFF)
assert(b32.lrotate(1, 33) == 2 and b32.rrotate(1, 1) == 0x80000000 and b32.extract(0xABCD, 4, 8) == 0xBC and b32.replace(0, 0xF, 4, 4) == 0xF0)
assert(not pcall(b32.extract, 1, 30, 4), "extract out of range")

-- cjson.safe returns nil, err instead of raising
if package.preload["cjson.safe"] then
  local safe = require("cjson.safe")
  local v, err = safe.decode("[1,")
  assert(v == nil and err, "cjson.safe.decode")
  assert(safe.encode({1, 2}) == "[1,2]")
end
print("ok")
