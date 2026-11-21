-- vapor.net over loopback: tcp echo, read formats, timeouts, refused connection, udp, Node-style events, pipe
if not vapor.caps.net then return end -- wasm, boards without a network stack
local net, stream = require("vapor.net"), require("vapor.stream")

local srv = assert(net.listen("127.0.0.1", 0))
local port = srv:port()
assert(port and port > 0)

-- server task: echoes lines until the client closes, then says goodbye on a second connection
vapor.spawn(function()
  local c = assert(srv:accept(5))
  while true do
    local line = c:read("l")
    if not line then break end
    c:write("echo:", line, "\n")
  end
  c:close()
  local c2 = assert(srv:accept(5))
  c2:write("a few bytes then ", string.rep("x", 100000)) -- larger than a socket buffer: write must wait for the reader
  c2:close()
end)

local c = assert(net.connect("127.0.0.1", port, 5))
c:write("hello\nworld\n")
assert(c:read("l") == "echo:hello")
assert(c:read("L") == "echo:world\n")
c:settimeout(0.1)
local none, e = c:read("l")   -- nothing more is coming: times out instead of hanging
assert(none == nil and e == "timeout", tostring(e))
c:settimeout(5)
c:close()

-- second connection: big transfer, byte counts, "a" and EOF
local c2 = assert(net.connect("127.0.0.1", port, 5))
assert(c2:read(17) == "a few bytes then ")
local rest = c2:read("a")
assert(#rest == 100000 and rest:sub(1, 3) == "xxx")
assert(c2:read("l") == nil)
c2:close()
srv:close()

-- refused: nothing listens on a port we just closed
local bad, err = net.connect("127.0.0.1", port, 5)
assert(bad == nil and type(err) == "string", "connect to a closed port must fail")

-- UDP
local u1, u2 = assert(net.udp("127.0.0.1", 0)), assert(net.udp("127.0.0.1", 0))
assert(u1:sendto("ping", "127.0.0.1", u2:port()) == 4)
local data, addr, p = assert(u2:recvfrom(5))
assert(data == "ping" and addr == "127.0.0.1" and p == u1:port())
local nothing, werr = u1:recvfrom(0.05)
assert(nothing == nil and werr == "timeout")
u1:close(); u2:close()

-- Node-style events and pipe over a second server
local srv2 = assert(net.listen("127.0.0.1", 0))
local got, ended = {}, false
vapor.spawn(function()
  local s = assert(srv2:accept(5))
  s:write("abc"); vapor.sleep(0.05); s:write("def")
  s:close()
end)
local cc = assert(net.connect("127.0.0.1", srv2:port(), 5))
cc:on("data", function(d) got[#got + 1] = d end):on("end", function() ended = true end)
for _ = 1, 100 do if ended then break end vapor.sleep(0.02) end
assert(ended and table.concat(got) == "abcdef", table.concat(got))
srv2:close()

-- pipe: copies one stream into another with write backpressure
local srv3 = assert(net.listen("127.0.0.1", 0))
local sink = {}
vapor.spawn(function()
  local s = assert(srv3:accept(5))
  s:write("pipe me"); s:close()
end)
local src = assert(net.connect("127.0.0.1", srv3:port(), 5))
local out = stream.wrap({read = function() return nil, "eof" end, write = function(d) sink[#sink + 1] = d; return #d end,
                         wait = function() return true end, close = function() end})
assert(stream.pipe(src, out))
assert(table.concat(sink) == "pipe me")
srv3:close()

-- closing a handle wakes the tasks waiting on it (on Windows a closed socket in a poll set never wakes by itself)
do
  local s2 = assert(net.listen("127.0.0.1", 0))
  local woke
  vapor.spawn(function() local c, e = s2:accept(); woke = e or "accepted" end)
  vapor.sleep(0.05)
  s2:close()
  vapor.sleep(0.05)
  assert(woke == "closed", tostring(woke))
end

-- name resolution does not stop other tasks: a ticking task keeps running while "localhost" and an unknown name resolve
do
  local ticks, stop = 0, false
  vapor.spawn(function() while not stop do vapor.sleep(0.01); ticks = ticks + 1 end end)
  local a = assert(net.resolve("localhost", 5))
  assert(a == "127.0.0.1" or a == "::1", a)
  local bad, err = net.resolve("no-such-host.invalid", 10)
  assert(bad == nil and err, "an unknown name is an error")
  assert(net.resolve("127.0.0.1") == "127.0.0.1")
  vapor.sleep(0.05)
  assert(ticks > 0, "the other task kept running")
  stop = true
  vapor.sleep(0.05)
end
