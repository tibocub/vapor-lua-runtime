-- Lua 5.1 compatibility on the 5.4 engine (loaded by default, skipped with --dialect=5.4).
-- Number printing (5.0 -> "5") is done in C (patches/lua-dotzero.patch).
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
  if i then debug.upvaluejoin(fn, i, function() return t end, 1) end
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
