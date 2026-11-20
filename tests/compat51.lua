-- default dialect: 5.1 behaviour on the 5.4 engine
assert(vapor.dialect == "5.1")
assert(unpack({1, 2, 3}) == 1 and select("#", unpack({1, 2, 3})) == 3)
assert(loadstring("return 1 + 1")() == 2)
assert(table.getn({1, 2}) == 2 and math.pow(2, 3) == 8)
assert(tostring(10 / 2) == "5" and tostring(1.5) == "1.5" and (10 / 2) .. "" == "5")

local function f() return x end
setfenv(f, {x = 42})
assert(f() == 42)
assert(getfenv(f).x == 42)

local env = {tostring = tostring}
local g = loadstring("y = 7; return y")
setfenv(g, env)
assert(g() == 7 and env.y == 7 and rawget(_G, "y") == nil)

-- stack-level form: setfenv(1, t) changes the caller
local function h()
  setfenv(1, {z = "level1"})
  return z
end
assert(h() == "level1")
