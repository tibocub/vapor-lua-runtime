-- ssl.https: LuaSec's https client (same API as socket.http), on ssl and socket.http.
--   https.request(url [, body]) -> body, code, headers, status      https.request{url=, method=, headers=, source=, sink=, redirect=, cafile=, ...} -> 1, code, headers, status
-- a redirect to plain http fails safe: the same TLS socket is used, so the handshake with port 80 fails.
local socket = require("socket")
local ssl = require("ssl")
local http = require("socket.http")
local ltn12 = require("ltn12")
local M = {PORT = 443, _VERSION = "0.1 (vlr)"}

local function create(cfg)
  return function()
    local sock = socket.tcp()
    local conn = {}
    function conn.settimeout(_, t) return sock:settimeout(t) end
    function conn.connect(_, host, port)
      local ok, err = sock:connect(host, port)
      if not ok then return nil, err end
      local w, werr = ssl.wrap(sock, cfg)
      if not w then return nil, werr end
      w:sni(host)
      ok, err = w:dohandshake()
      if not ok then return nil, err end
      conn.w = w
      return 1
    end
    return setmetatable(conn, {__index = function(t, k)
      local o = rawget(t, "w") or sock
      local f = o[k]
      if type(f) == "function" then return function(_, ...) return f(o, ...) end end
    end})
  end
end

function M.request(reqt, body)
  if type(reqt) == "string" then
    local t = {}
    local r, code, headers, status = M.request{url = reqt, source = body and ltn12.source.string(body), method = body and "POST" or "GET",
      headers = body and {["content-length"] = #body, ["content-type"] = "application/x-www-form-urlencoded"} or nil, sink = ltn12.sink.table(t)}
    return r and table.concat(t) or nil, code, headers, status
  end
  local cfg = {mode = "client", protocol = reqt.protocol or "any", verify = reqt.verify or "peer", cafile = reqt.cafile, capath = reqt.capath}
  if not tostring(reqt.url):match("^https:") then return nil, "unsupported scheme (ssl.https needs an https URL)" end
  local nreqt = {}
  for k, v in pairs(reqt) do nreqt[k] = v end
  nreqt.create = create(cfg)
  return http.request(nreqt)
end

return setmetatable(M, {__call = function(_, ...) return M.request(...) end})
