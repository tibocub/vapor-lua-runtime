-- tasks, sleep ordering, timeouts
local order = {}
vapor.spawn(function() vapor.sleep(0.06); order[#order + 1] = "b" end)
vapor.spawn(function() vapor.sleep(0.02); order[#order + 1] = "a" end)
local t0 = vapor.now()
vapor.sleep(0.1)
assert(table.concat(order) == "ab", table.concat(order))
local dt = vapor.now() - t0
assert(dt >= 95 and dt < 400, dt)

-- fd 0 is /dev/null in the runner? no: just test a timeout on a pipe-less fd via vapor.wait directly
local r = vapor.wait({}, 10)
assert(type(r) == "table" and #r == 0)
