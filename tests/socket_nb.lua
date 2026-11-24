-- LuaSocket's non-blocking mode (settimeout(0)), which event loops such as copas rely on: nothing blocks or yields, "timeout" says "try later"
if not require("vlr").caps.net then return end -- wasm, boards without a network stack
local socket = require("socket")
assert(tostring(socket.tcp()):find("^tcp{master}"), "copas tells TCP from UDP by tostring")
assert(tostring(socket.udp()):find("^udp"), tostring(socket.udp()))

local server = assert(socket.bind("127.0.0.1", 0))
local _, port = server:getsockname()
server:settimeout(0)
local nothing, e0 = server:accept()
assert(nothing == nil and e0 == "timeout", "accept with nothing waiting: " .. tostring(e0))

-- connect in non-blocking mode: "timeout" until the connection is up, then 1
local c = socket.tcp()
c:settimeout(0)
local ok, err = c:connect("127.0.0.1", port)
local tries = 0
while not ok do
  assert(err == "timeout", tostring(err))
  tries = tries + 1; assert(tries < 1000, "connect never completed")
  socket.select(nil, {c}, 1)
  ok, err = c:connect("127.0.0.1", port)
end
assert(tostring(c):find("^tcp{client}"))

local a
for _ = 1, 200 do a = server:accept(); if a then break end socket.select({server}, nil, 0.05) end
assert(a, "accepted")
a:settimeout(0)
local d, e1 = a:receive(1)
assert(d == nil and e1 == "timeout", "receive with no data: " .. tostring(e1))
assert(c:send("hi\n"))
assert(socket.select({a}, nil, 2)[1] == a)
assert(a:receive("*l") == "hi")
c:close(); a:close(); server:close()
print("ok")
