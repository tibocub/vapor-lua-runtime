-- vapor.net: TCP and UDP for tasks. Connections are streams (see vapor.stream); nothing blocks the process, only the calling task.
--   local c = net.connect("example.org", 80, timeout)       c:write("..."); c:read("l"); c:close()
--   local srv = net.listen("127.0.0.1", 8080); local c = srv:accept(); ... ; srv:port(); srv:close()
--   local u = net.udp("127.0.0.1", 0); u:sendto("hi", host, port); local data, addr, port = u:recvfrom(timeout); u:port()
-- Name resolution blocks the whole process while it runs (shortcut: a resolver handle in the platform would be exact).
local vapor = vapor
local raw = require("vapor.netraw")
local stream = require("vapor.stream")
local M = {}

local function socket_ops(h)
  return {
    read = function(max) return raw.recv(h, max) end,
    write = function(data) return raw.send(h, data) end,
    wait = function(mode, timeout) return vapor.wait_fd(h, timeout, mode) end,
    close = function() raw.close(h) end,
  }
end

local function wrap(h, host, port)
  return stream.wrap(socket_ops(h), {handle = h, peer = {host, port}})
end

function M.connect(host, port, timeout)
  local h, err = raw.connect(host, port)
  if not h then return nil, err end
  local ok, werr = vapor.wait_fd(h, timeout, "w")
  if not ok then raw.close(h); return nil, werr end
  local st, serr = raw.status(h)
  if not st then raw.close(h); return nil, serr end
  return wrap(h, host, port)
end

local Server = {}
Server.__index = Server

function M.listen(host, port, backlog)
  local h, err = raw.listen(host, port, backlog)
  if not h then return nil, err end
  return setmetatable({handle = h}, Server)
end

function Server:accept(timeout)
  while true do
    local h, addr, port = raw.accept(self.handle)
    if h then return wrap(h, addr, port) end
    if addr ~= "again" then return nil, addr end
    local ok, e = vapor.wait_fd(self.handle, timeout)
    if not ok then return nil, e end
  end
end

function Server:port() local _, p = raw.name(self.handle); return p end
function Server:close() raw.close(self.handle); return true end

local Udp = {}
Udp.__index = Udp

function M.udp(host, port)
  local h, err = raw.udp(host, port)
  if not h then return nil, err end
  return setmetatable({handle = h}, Udp)
end

function Udp:sendto(data, host, port)
  while true do
    local n, e = raw.sendto(self.handle, host, port, data)
    if n then return n end
    if e ~= "again" then return nil, e end
    local ok, werr = vapor.wait_fd(self.handle, nil, "w")
    if not ok then return nil, werr end
  end
end

function Udp:recvfrom(timeout)
  while true do
    local data, addr, port = raw.recvfrom(self.handle)
    if data then return data, addr, port end
    if addr ~= "again" then return nil, addr end
    local ok, e = vapor.wait_fd(self.handle, timeout)
    if not ok then return nil, e end
  end
end

function Udp:port() local _, p = raw.name(self.handle); return p end
function Udp:close() raw.close(self.handle); return true end

return M
