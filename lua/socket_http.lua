-- socket.http: LuaSocket's HTTP/1.1 client API over socket.tcp (http:// only, like the original; use std.http for https).
-- request(url [, body]) -> body, code, headers, status      request{url=, method=, headers=, source=, sink=, step=, redirect=, create=, user=, password=, ...} -> 1, code, headers, status
-- Shortcuts: no proxy, no keep-alive (Connection: close), the step argument is accepted and ignored.
local socket = require("socket")
local url = require("socket.url")
local ltn12 = require("ltn12")
local mime = require("mime")
local M = {TIMEOUT = 60, PORT = 80, USERAGENT = "vlr socket.http", _VERSION = "HTTP 1.0 (vlr)"}

local function lower_headers(h)
  local t = {}
  for k, v in pairs(h or {}) do t[k:lower()] = v end
  return t
end

local function readheaders(c)
  local h = {}
  while true do
    local line, err = c:receive("*l")
    if not line then return nil, err end
    if line == "" then return h end
    local k, v = line:match("^([^:%s]+):%s*(.-)%s*$")
    if k then k = k:lower(); h[k] = h[k] and (h[k] .. ", " .. v) or v end
  end
end

local function readbody(c, headers, method, code, sink)
  if method == "HEAD" or code == 204 or code == 304 or (code >= 100 and code < 200) then return 1 end
  local function put(chunk) if chunk and chunk ~= "" then local ok, err = sink(chunk); if not ok then return nil, err end end return true end
  local te = (headers["transfer-encoding"] or ""):lower()
  if te:find("chunked", 1, true) then
    while true do
      local line, err = c:receive("*l")
      if not line then return nil, err end
      local n = tonumber(line:match("^%s*(%x+)"), 16)
      if not n then return nil, "invalid chunk size" end
      if n == 0 then
        while true do local l = c:receive("*l"); if not l or l == "" then break end end
        return 1
      end
      local data, derr = c:receive(n)
      if not data then return nil, derr end
      local ok, serr = put(data); if not ok then return nil, serr end
      c:receive("*l")
    end
  end
  local len = tonumber(headers["content-length"])
  if len then
    while len > 0 do
      local data, err, partial = c:receive(math.min(len, 8192))
      data = data or partial
      if not data or data == "" then return nil, err or "closed" end
      len = len - #data
      local ok, serr = put(data); if not ok then return nil, serr end
    end
    return 1
  end
  while true do   -- until the server closes
    local data, err, partial = c:receive(8192)
    data = data or partial
    if data and data ~= "" then local ok, serr = put(data); if not ok then return nil, serr end end
    if not data or data == "" then break end
  end
  return 1
end

local function trequest(req, redirects)
  local u = url.parse(req.url, {host = "", port = M.PORT, path = "/", scheme = "http"})
  if u.scheme ~= "http" then return nil, "unsupported scheme '" .. tostring(u.scheme) .. "'" end
  if u.host == "" then return nil, "invalid host '" .. tostring(u.host) .. "'" end
  local method = (req.method or "GET"):upper()
  local sink = req.sink or ltn12.sink.null()
  local c = (req.create or socket.tcp)()
  c:settimeout(req.timeout or M.TIMEOUT)
  local ok, err = c:connect(req.host or u.host, tonumber(req.port or u.port))
  if not ok then c:close(); return nil, err end
  local headers = {host = u.host .. (tonumber(u.port) ~= 80 and (":" .. u.port) or ""), ["user-agent"] = M.USERAGENT, connection = "close"}
  local user, pass = req.user or u.user, req.password or u.password
  if user then
    local a, rest = mime.b64(user .. ":" .. (pass or ""))
    headers.authorization = "Basic " .. a .. (mime.b64(nil, rest) or "")
  end
  for k, v in pairs(req.headers or {}) do headers[k:lower()] = v end
  local body
  if req.source then
    local parts = {}
    while true do local chunk, err2 = req.source(); if not chunk then if err2 then c:close(); return nil, err2 end break end parts[#parts + 1] = chunk end
    body = table.concat(parts)
    headers["content-length"] = headers["content-length"] or #body
  elseif method == "POST" or method == "PUT" then headers["content-length"] = headers["content-length"] or 0 end
  local lines = {("%s %s HTTP/1.1"):format(method, (u.path or "/") .. (u.params and (";" .. u.params) or "") .. (u.query and ("?" .. u.query) or ""))}
  for k, v in pairs(headers) do lines[#lines + 1] = k .. ": " .. tostring(v) end
  ok, err = c:send(table.concat(lines, "\r\n") .. "\r\n\r\n" .. (body or ""))
  if not ok then c:close(); return nil, err end

  local status, serr = c:receive("*l")
  if not status then c:close(); return nil, serr end
  local code = tonumber(status:match("^HTTP/%d%.%d%s+(%d%d%d)"))
  if not code then c:close(); return nil, "invalid status line" end
  local rh, herr = readheaders(c)
  if not rh then c:close(); return nil, herr end
  local rcode = code
  if (code == 301 or code == 302 or code == 303 or code == 307 or code == 308) and rh.location and (req.redirect ~= false) and (method == "GET" or method == "HEAD")
     and redirects < 5 then
    c:close()
    local nreq = {}
    for k, v in pairs(req) do nreq[k] = v end
    nreq.url = url.absolute(req.url, rh.location); nreq.host, nreq.port = nil, nil
    if type(req.redirect) == "function" then nreq.url = req.redirect(req.url, nreq.url, code) or nreq.url end
    return trequest(nreq, redirects + 1)
  end
  local ok2, berr = readbody(c, rh, method, code, sink)
  c:close()
  sink(nil)
  if not ok2 then return nil, berr end
  return 1, rcode, rh, status
end

function M.request(a, b)
  if type(a) == "string" then
    local t = {}
    local req = {url = a, sink = ltn12.sink.table(t)}
    if b then req.source = ltn12.source.string(b); req.method = "POST"
      req.headers = {["content-length"] = #b, ["content-type"] = "application/x-www-form-urlencoded"} end
    local r, code, headers, status = trequest(req, 0)
    return r and table.concat(t) or nil, code, headers, status
  end
  return trequest(a, 0)
end

return M
