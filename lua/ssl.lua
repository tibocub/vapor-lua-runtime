-- ssl: the LuaSec API subset a client needs, over vlr.tls (BearSSL). Code written for LuaSec runs unchanged:
--   local conn = ssl.wrap(sock, {mode = "client", protocol = "any", verify = "peer", cafile = "/path/ca.pem"})
--   conn:sni(host); assert(conn:dohandshake()); conn:send(...); conn:receive(...); conn:close()
-- Differences from LuaSec (shortcuts): the certificate chain and host name are ALWAYS verified, whatever `verify` says (there is no way to turn it off);
-- the host name checked is the one given to :sni(host), which must be called before :dohandshake(); client mode only; no client certificates,
-- `protocol`, `options`, `ciphers` and `capath` are accepted and ignored (BearSSL picks TLS 1.0-1.2 suites); no :getpeercertificate().
local tls = require("vlr.tls")
local M = {_VERSION = "0.1 (vlr, LuaSec client subset)"}

local Conn = {}
-- everything not defined here (settimeout, getfd, send/receive, close...) goes to the underlying socket, which holds the TLS stream after the handshake
Conn.__index = function(t, k)
  local v = Conn[k]
  if v ~= nil then return v end
  local f = t.sock[k]
  if type(f) == "function" then return function(_, ...) return f(t.sock, ...) end end
end

Conn.__tostring = function(o) return ("SSL{client}: %p"):format(o) end -- copas tells TLS from plain sockets by this prefix

function M.wrap(sock, params)
  params = params or {}
  if params.mode and params.mode ~= "client" then return nil, "ssl server mode is not supported" end
  return setmetatable({sock = sock, params = params}, Conn)
end

function Conn:sni(host) self.host = host; return true end

function Conn:dohandshake()
  if not self.host then return nil, "call conn:sni(host) before conn:dohandshake() (vlr checks the host name)" end
  local sock = self.sock
  local stream, err = tls.wrap(sock.s, self.host, {cafile = self.params.cafile, timeout = sock.timeout})
  if not stream then return nil, err end
  sock.s = stream
  return true
end

return M
