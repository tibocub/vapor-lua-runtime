-- Lua 5.1 compatibility on the 5.4 engine (loaded by default, skipped with --dialect=5.4).
-- Number printing (5.0 -> "5") is done in C (patches/lua-dotzero.patch).
local upvaluejoin = debug.upvaluejoin -- the public name is removed at the end of this file
unpack = table.unpack
function loadstring(s, name) return load(s, name) end
function table.getn(t) return #t end
function table.maxn(t)
  local n = 0
  for k in pairs(t) do if type(k) == "number" and k > n then n = k end end
  return n
end
function math.pow(a, b) return a ^ b end
math.mod = math.fmod
math.log10 = function(x) return math.log(x, 10) end
math.ldexp = function(m, e) return m * 2.0 ^ e end
math.cosh = function(x) return (math.exp(x) + math.exp(-x)) / 2 end
math.sinh = function(x) return (math.exp(x) - math.exp(-x)) / 2 end
math.tanh = function(x) local a, b = math.exp(x), math.exp(-x); return (a - b) / (a + b) end
function math.frexp(x)
  if x == 0 or x ~= x or x == math.huge or x == -math.huge then return x, 0 end
  local e = math.floor(math.log(math.abs(x), 2)) + 1
  local m = x / 2.0 ^ e
  if math.abs(m) >= 1 then m, e = m / 2, e + 1 elseif math.abs(m) < 0.5 then m, e = m * 2, e - 1 end
  return m, e
end

local function envindex(f)
  for i = 1, 255 do
    local name = debug.getupvalue(f, i)
    if name == nil then return nil end
    if name == "_ENV" then return i end
  end
end

-- f is a function, or a stack level (1 = the caller)
local function resolve(f)
  if type(f) == "number" then
    local info = debug.getinfo(f + 2, "f") -- +1 for this helper, +1 for getfenv/setfenv itself
    return info and info.func
  end
  return f
end

function getfenv(f)
  if f == 0 then return _G end
  f = resolve(f == nil and 1 or f)
  local i = f and envindex(f)
  if i then return (select(2, debug.getupvalue(f, i))) end
  return _G -- shortcut: a function without _ENV uses no globals; C functions report _G, upgrade if a rock cares
end

function setfenv(f, t)
  local fn = resolve(f)
  local i = fn and envindex(fn)
  if i then upvaluejoin(fn, i, function() return t end, 1) end
  return fn
end

-- 5.1 os.execute returns the exit status (a number), not true/"exit"/code
local execute = os.execute
function os.execute(cmd)
  if cmd == nil then return execute() and 1 or 0 end
  local ok, _, code = execute(cmd)
  if ok then return 0 end
  return code or -1
end

-- 5.1 module(name, ...): the module table is the global (dotted names nest), the caller's environment becomes it, package.loaded gets it;
-- extra arguments are functions applied to it (package.seeall). Many older rocks are written this way.
function package.seeall(m) return setmetatable(m, {__index = _G}) end

function module(name, ...)
  local mod = package.loaded[name]
  if type(mod) ~= "table" then
    local t = _G
    for part in name:gmatch("[^.]+") do
      if t[part] == nil then t[part] = {} end
      t = t[part]
    end
    if type(t) ~= "table" then error("name conflict for module '" .. name .. "'", 2) end
    mod = t
    package.loaded[name] = mod
  end
  if mod._NAME == nil then
    mod._NAME, mod._M, mod._PACKAGE = name, mod, name:match("^(.*%.)[^.]*$") or ""
  end
  setfenv(2, mod)
  for _, f in ipairs({...}) do f(mod) end
end

-- what a stock 5.1 reports and has (LUA_COMPAT included): code that tests _VERSION or feature-detects must take its 5.1 path
_VERSION = "Lua 5.1"
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
package.loaders = package.searchers
debug.getfenv, debug.setfenv = function(f) return getfenv(f) end, function(f, t) return setfenv(f, t) end
-- the 5.2+ names that 5.1 and LuaJIT lack are removed, so `if utf8 then` / `if math.type then` choose the 5.1 branch
-- (kept: table.unpack, which 5.2-compat LuaJIT builds have too, and package.searchers, which require itself reads)
utf8, warn, rawlen = nil, nil, nil
string.pack, string.unpack, string.packsize = nil, nil, nil
table.move, table.pack = nil, nil
math.type, math.tointeger, math.ult, math.maxinteger, math.mininteger = nil, nil, nil, nil, nil
coroutine.close, coroutine.isyieldable = nil, nil
debug.upvalueid, debug.upvaluejoin, debug.getuservalue, debug.setuservalue, debug.setcstacklimit = nil, nil, nil, nil, nil

