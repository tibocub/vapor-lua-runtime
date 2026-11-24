local vlr = require("vlr")
-- the LuaSocket-compatible subset: code written for luasocket runs unchanged
if not vlr.caps.net then return end
local socket = require("socket")

local server = assert(socket.bind and socket.bind("127.0.0.1", 0) or (function()
  local m = socket.tcp(); assert(m:bind("127.0.0.1", 0)); return m:listen(5)
end)())
local _, port = server:getsockname()
assert(port and port > 0)

vlr.spawn(function()
  local c = assert(server:accept())
  c:settimeout(5)
  assert(c:send("hello\r\nworld\n"))
  assert(c:receive(4) == "ping")
  assert(c:send("0123456789"))
  vlr.sleep(0.2)        -- let the client time out once
  assert(c:send("tail"))
  c:close()
end)

local c = socket.tcp()
c:settimeout(5)
assert(c:connect("127.0.0.1", port) == 1)
assert(c:receive() == "hello")             -- "*l" drops the newline and any CR, like luasocket
assert(c:receive("*l") == "world")
assert(c:send("ping") == 4)
assert(c:receive(10) == "0123456789")
c:settimeout(0.05)
local d, err, partial = c:receive("*l")        -- nothing arrives for a while
assert(d == nil and err == "timeout" and partial == "", tostring(err))
c:settimeout(5)
assert(c:receive("*a") == "tail")           -- until the peer closes
local e, err2 = c:receive(1)
assert(e == nil and err2 == "closed", tostring(err2))
c:close()

-- select: a ready reader and the timeout case
local srv2 = socket.tcp(); assert(srv2:bind("127.0.0.1", 0)); local s2 = srv2:listen(5)
local _, p2 = s2:getsockname()
local cl = socket.tcp(); assert(cl:connect("127.0.0.1", p2))
local r, w, serr = socket.select({cl}, nil, 0.05)
assert(#r == 0 and serr == "timeout")
local acc = assert(s2:accept()); acc:send("x")
r = socket.select({cl}, nil, 2)
assert(#r == 1 and r[1] == cl)
assert(cl:receive(1) == "x")
local _, w2 = socket.select(nil, {cl}, 1)
assert(#w2 == 1)

-- udp
local u1, u2 = socket.udp(), socket.udp()
u1:settimeout(2)
local _, p1 = u1:getsockname()
u2:sendto("dgram", "127.0.0.1", p1)
local data, from = u1:receivefrom()
assert(data == "dgram" and from == "127.0.0.1", tostring(data) .. tostring(from))

-- protect / try
local f = socket.protect(function() socket.try(nil, "boom") end)
local nilv, msg = f()
assert(nilv == nil and msg == "boom")
assert(type(socket.gettime()) == "number")
print("ok")
