local vlr = require("vlr")
-- tasks, sleep ordering, timeouts
local order = {}
vlr.spawn(function() vlr.sleep(0.06); order[#order + 1] = "b" end)
vlr.spawn(function() vlr.sleep(0.02); order[#order + 1] = "a" end)
local t0 = vlr.now()
vlr.sleep(0.1)
assert(table.concat(order) == "ab", table.concat(order))
local dt = vlr.now() - t0
assert(dt >= 95 and dt < 400, dt)

-- fd 0 is /dev/null in the runner? no: just test a timeout on a pipe-less fd via vlr.wait directly
local r = vlr.wait({}, 10)
assert(type(r) == "table" and #r == 0)
