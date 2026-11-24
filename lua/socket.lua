-- socket: a LuaSocket-compatible subset over vapor.net, so pure-Lua rocks written for luasocket run unmodified (std.socket is the same module).
--   socket.tcp() -> master; m:connect(host, port) -> 1 | nil, err; m:bind(host, port); m:listen(backlog) -> server (m itself); server:accept() -> client
--   client:send(data [, i [, j]]) -> last byte sent | nil, err, lastsent; client:receive(pattern, prefix) pattern "*l" (default) "*L" "*a" or a byte count
--   timeouts: client:settimeout(seconds | nil [, mode]); on a timeout receive/send give nil, "timeout" (and the partial data); errors are "closed", "timeout", ...
--   client:getpeername() / getsockname(); close(); shutdown(); setoption(...) (accepted, ignored); getfd()
--   socket.udp() -> setpeername/sendto/receive/receivefrom/settimeout/close; socket.select(recvt, sendt, timeout) -> readable, writable, err
--   socket.gettime() (seconds, float), socket.sleep(s), socket.dns.toip(name), socket.dns.gethostname(), socket._VERSION, socket.skip, socket.try/newtry/protect
-- Not done (shortcuts): socket.select polls every 5 ms instead of waiting on all handles at once; dns.toip only resolves through connect-time lookup (returns the
-- name if it already is an address); ltn12, mime, socket.url and socket.http are in vlr (socket_*.lua, ltn12.lua, mime.lua); smtp/ftp/headers are not.
local vapor = vapor
local net = require("vapor.net")
local raw = require("vapor.netraw")
local M = {_VERSION = "vlr socket (LuaSocket 3.0 subset)"}

local function clean(fmt) return type(fmt) == "string" and (fmt:gsub("^%*", "")) or fmt end

local Client = {}
Client.__index = Client
Client.__tostring = function(o) return ("tcp{client}: %p"):format(o) end
local Server = {}
Server.__index = Server
Server.__tostring = function(o) return ("tcp{server}: %p"):format(o) end
local Master = {}
Master.__index = Master
Master.__tostring = function(o) return ("tcp{master}: %p"):format(o) end

local function wrapclient(stream)
  return setmetatable({s = stream, timeout = nil}, Client)
end

function M.tcp()
  return setmetatable({timeout = nil}, Master)
end

function Master:settimeout(t) self.timeout = t; return 1 end
function Master:setoption() return 1 end
function Master:close() if self.server then self.server:close() end return 1 end
function Master:bind(host, port)
  local srv, err = net.listen(host == "*" and "0.0.0.0" or host, port or 0)
  if not srv then return nil, err end
  self.server = srv
  return 1
end
function Master:listen() if not self.server then return nil, "not bound" end
  return setmetatable({server = self.server, timeout = self.timeout}, Server) end
-- timeout 0 is LuaSocket's non-blocking mode: connect returns nil, "timeout" while the connection is in progress and 1 once it is up
-- (the caller waits with socket.select and calls connect again), as copas and other event loops expect. It never yields.
local function numeric(host) return host:match("^%d+%.%d+%.%d+%.%d+$") or host:find(":", 1, true) end
local function connect_nb(self, host, port)
  if not self.h then
    local addr = host
    if not numeric(host) then
      self.rh = self.rh or raw.resolve_start(host)
      if self.rh then
        local a, e = raw.resolve_result(self.rh)
        if not a then
          if e == "again" then return nil, "timeout" end
          self.rh = nil
          return nil, e
        end
        addr, self.rh = a, nil
      end
    end
    local h, err = raw.connect(addr, port)
    if not h then return nil, err end
    self.h, self.peer = h, {host, port}
  end
  if not raw.ready(self.h, true) then return nil, "timeout" end
  local st, serr = raw.status(self.h)
  if not st then raw.close(self.h); self.h = nil; return nil, serr end
  local s = net.wrap(self.h, self.peer[1], self.peer[2])
  s:settimeout(0)
  setmetatable(self, Client)
  self.s, self.h, self.peer, self.master = s, nil, nil, nil
  return 1
end

function Master:connect(host, port)
  if self.timeout == 0 then return connect_nb(self, host, port) end
  local s, err = net.connect(host, port, self.timeout)
  if not s then return nil, err == "timeout" and "timeout" or err end
  s:settimeout(self.timeout)
  setmetatable(self, Client)
  self.s = s
  self.master = nil
  return 1
end

function Server:accept()
  local s, err = self.server:accept(self.timeout)
  if not s then return nil, err end
  local c = wrapclient(s)
  c.timeout = self.timeout
  s:settimeout(self.timeout)
  return c
end
function Server:settimeout(t) self.timeout = t; return 1 end
function Server:close() return self.server:close() and 1 end
function Server:getsockname() return "0.0.0.0", self.server:port() end
function Server:setoption() return 1 end
function Server:getfd() return self.server.handle end

function Client:settimeout(t) self.timeout = t; if self.s then self.s:settimeout(t) end return 1 end
function Client:setoption() return 1 end
function Client:getfd() return self.s and self.s.handle or -1 end
function Client:getpeername() local p = self.s and self.s.peer; if p then return p[1], p[2] end return nil, "not connected" end
function Client:getsockname() if not self.s then return nil, "not connected" end local a, p = raw.name(self.s.handle); return a, p end
function Client:close() if self.s then self.s:close() end return 1 end
function Client:shutdown() return 1 end

function Client:send(data, i, j)
  if not self.s then return nil, "closed" end
  if i or j then data = data:sub(i or 1, j) end
  local ok, err, sent = self.s:write(data)
  if not ok then return nil, err == "eof" and "closed" or err, (i or 1) - 1 + (sent or 0) end
  return (i or 1) - 1 + #data
end

function Client:receive(pattern, prefix)
  local s = self.s
  if not s then return nil, "closed" end
  pattern = clean(pattern or "l")
  local out, err
  if pattern == "l" then out, err = s:read("l"); if out then out = out:gsub("\r", "") end  -- LuaSocket drops every CR in line mode
  elseif pattern == "L" then out, err = s:read("L")
  elseif pattern == "a" then out, err = s:read("a"); if out == "" and not err then out, err = nil, "closed" end
  elseif type(pattern) == "number" then out, err = s:read(pattern)
  else error("bad argument #1 to 'receive' (invalid receive pattern)", 2) end
  if out then return (prefix or "") .. out end
  if err == "eof" then err = "closed" end
  local partial = s.buf
  s.buf = ""
  return nil, err, partial ~= "" and (prefix or "") .. partial or (prefix and prefix or "")
end

function M.bind(host, port, backlog)
  local m = M.tcp()
  local ok, err = m:bind(host, port)
  if not ok then return nil, err end
  return m:listen(backlog)
end

-- UDP
local Udp = {}
Udp.__index = Udp
Udp.__tostring = function(o) return ("udp{unconnected}: %p"):format(o) end
function M.udp()
  local u, err = net.udp("0.0.0.0", 0)
  if not u then return nil, err end
  return setmetatable({u = u}, Udp)
end
function Udp:settimeout(t) self.timeout = t; return 1 end
function Udp:setpeername(host, port) self.peer = {host, port}; return 1 end
function Udp:setsockname(host, port) return 1 end
function Udp:sendto(data, host, port)
  local n, err = self.u:sendto(data, host, port)
  if not n then return nil, err end
  return n
end
function Udp:send(data) if not self.peer then return nil, "no peer" end return self:sendto(data, self.peer[1], self.peer[2]) end
function Udp:receivefrom(size)
  local d, addr, port = self.u:recvfrom(self.timeout)
  if not d then return nil, addr end
  return size and d:sub(1, size) or d, addr, port
end
function Udp:receive(size) local d, a = self:receivefrom(size); return d, a end
function Udp:getsockname() return "0.0.0.0", self.u:port() end
function Udp:close() self.u:close(); return 1 end
function Udp:getfd() return self.u.handle end

-- select: readable when buffered bytes exist or the handle polls readable (wait_fd with a zero timeout)
local function readable(obj)
  local s = obj.s
  if s and s.buf ~= "" then return true end
  local h = obj.getfd and obj:getfd()
  if not h or h < 0 then return false end
  return vapor.wait_fd(h, 0) ~= nil
end
local function writable(obj)
  local h = obj.getfd and obj:getfd()
  if not h or h < 0 then return false end
  return vapor.wait_fd(h, 0, "w") ~= nil
end
function M.select(recvt, sendt, timeout)
  local deadline = timeout and (M.gettime() + timeout)
  while true do
    local r, w = {}, {}
    for _, o in ipairs(recvt or {}) do if readable(o) then r[#r + 1] = o; r[o] = o end end
    for _, o in ipairs(sendt or {}) do if writable(o) then w[#w + 1] = o; w[o] = o end end
    if #r > 0 or #w > 0 then return r, w end
    if deadline and M.gettime() >= deadline then return r, w, "timeout" end
    vapor.sleep(0.005)
  end
end

function M.gettime() return vapor.now and vapor.now() / 1000 or os.time() end
function M.sleep(s) vapor.sleep(s) end
M.skip = function(n, ...) return select(n + 1, ...) end
M.try = function(...) local v = ... if v then return ... end error({select(2, ...)}) end
function M.newtry(f) return function(...) local v = ... if v then return ... end if f then f() end error({(select(2, ...))}, 2) end end
function M.protect(f)
  return function(...)
    local r = {pcall(f, ...)}
    if r[1] then return table.unpack(r, 2) end
    if type(r[2]) == "table" then return nil, r[2][1] end
    error(r[2], 0)
  end
end

M.dns = {
  toip = function(name) return name end,
  gethostname = function() return "localhost" end,
}
return M
