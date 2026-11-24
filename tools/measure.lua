local vlr = require("vlr")
-- Measurements for small targets: vlr measure.lua mem | speed | sched | compile | depth
-- Prints "name value" lines; sizes in bytes unless noted. One section per run (the RP2040 console wedges on long runs).
local what = arg[1] or "mem"
local function kb() collectgarbage(); collectgarbage(); return collectgarbage("count") end
local function out(k, v) print(k, type(v) == "number" and string.format("%.1f", v) or v) end

if what == "mem" then
  out("lua_heap_kb_empty", kb())
  local b = kb(); require("lfs");   out("lfs_kb", kb() - b)
  b = kb(); require("lpeg");        out("lpeg_kb", kb() - b)
  b = kb(); require("cjson");       out("cjson_kb", kb() - b)
  b = kb(); local t = {}
  for i = 1, 100 do t[i] = coroutine.create(function() end) end
  out("coroutine_bytes", (kb() - b) * 1024 / 100)
  t = nil; collectgarbage() -- free them: the next measurement must not run on top of 88 KB of idle coroutines
  b = kb()
  for i = 1, 50 do vlr.spawn(function() vlr.sleep(0.5) end) end
  vlr.sleep(0.05) -- let them all park
  out("parked_task_bytes", (kb() - b) * 1024 / 50)
  b = kb(); local tt = {}
  for i = 1, 1000 do tt[i] = i end
  out("table_1000_ints_bytes", (kb() - b) * 1024)

elseif what == "speed" then
  local function time(name, f) local t = os.clock(); f(); out(name .. "_s", os.clock() - t) end
  time("fib23", function() local function fib(n) if n < 2 then return n end return fib(n - 1) + fib(n - 2) end fib(23) end)
  time("intloop_300k", function() local x = 0 for i = 1, 300000 do x = x + i % 7 end end)
  time("sin_20k", function() local x = 0 for i = 1, 20000 do x = x + math.sin(i) end end)
  time("string_fmt_1k", function() local t = {} for i = 1, 1000 do t[#t + 1] = string.format("%d:%s", i, "x") end table.concat(t) end)
  time("sort_1000", function() local t = {} for i = 1, 1000 do t[i] = (i * 7919) % 2003 end table.sort(t) end)
  time("table_insert_500", function() local t = {} for i = 1, 500 do t[#t + 1] = {i} end end)

elseif what == "sched" then
  -- cost of the scheduler itself
  local t = os.clock(); local n = 2000
  vlr.spawn(function() for i = 1, n do vlr.sleep(0) end end)
  vlr.spawn(function() for i = 1, n do vlr.sleep(0) end end)
  vlr.sleep(0)
  local t0 = vlr.now()
  for i = 1, 20 do vlr.sleep(0.01) end
  local dt = vlr.now() - t0
  out("sleep_10ms_x20_total_ms", dt)
  out("sleep_10ms_avg_overshoot_ms", (dt - 200) / 20)

elseif what == "compile" then
  -- largest script that still compiles: n lines of `x=1`; (heap peak while parsing)
  for _, kbytes in ipairs{10, 20, 40, 80, 120} do
    local src = string.rep("x=1\n", kbytes * 256)
    local before = collectgarbage("count")
    local f, err = load(src)
    out("compile_" .. kbytes .. "KB", f and "ok" or tostring(err))
    src, f = nil, nil
    collectgarbage()
    if not f and false then break end
  end

elseif what == "depth" then
  local d = 0
  local function r() d = d + 1; local ok = pcall(r); end
  pcall(r)
  out("pcall_depth_reached", d)
  local d2 = 0
  local function rr() d2 = d2 + 1; return 1 + rr() end
  local ok, e = pcall(rr)
  out("lua_recursion_depth", d2)
  out("lua_recursion_err", tostring(e):sub(1, 40))
end
