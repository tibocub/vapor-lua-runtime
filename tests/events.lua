-- event queue: push before pull, pull timeout, timer events, ordering
vapor.push("a", 1, 2)
local n, x, y = vapor.pull(1)
assert(n == "a" and x == 1 and y == 2)

local ev, why = vapor.pull(0.03)
assert(ev == nil and why == "timeout")

local id = vapor.timer(0.03)
local n2, got = vapor.pull(1)
assert(n2 == "timer" and got == id)

-- a task pulling while another pushes
vapor.spawn(function() vapor.sleep(0.02); vapor.push("hello", "world") end)
local a, b = vapor.pull(1)
assert(a == "hello" and b == "world")
