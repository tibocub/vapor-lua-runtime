-- std.httpd: an HTTP/1.1 server for vlr, written for untrusted clients. Experimental.
--   local httpd = require("std.httpd")
--   local srv = assert(httpd.listen{port = 8080, handler = function(req, res) return "hello" end})
--   vapor.run()                        -- the server is tasks; srv:close() stops accepting
-- req:  method, target (as sent), path (decoded, query removed), query (table of decoded values; repeated keys keep the last), headers (lowercase names),
--       version ("1.0" | "1.1"), remote (address, port), body (string; read before the handler runs, so at most max_body bytes)
-- The handler answers by returning body | status, body | status, body, headers | status, body, headers, or by res:status(n), res:header(k, v), res:send(body).
-- Errors in the handler become "500 internal error" (the message goes to srv.on_error, never to the client).
-- Limits (all configurable): max_header 16 KB per header line, max_headers 100, max_body 1 MB, header_timeout 10 s for the whole header block,
-- body_timeout 30 s, idle_timeout 5 s between requests, max_requests 100 per connection, max_conns 64 (more get "503" and are closed).
-- Rejected with 400/411/413/414/431/501 and the connection closed: bad request lines, both Content-Length and Transfer-Encoding (request smuggling),
-- conflicting Content-Length values, a missing Host on HTTP/1.1, control characters in headers, request bodies that are chunked (not supported).
-- Shortcuts: no TLS here yet (put it behind a TLS terminator, or wrap with vapor.tls in a later version), no request-body streaming, no chunked
-- request bodies, no HTTP/2, Connection: close is sent when the client asks or a limit is reached.
local vapor = vapor
local net = require("vapor.net")
local M = {}

local REASONS = {
  [100] = "Continue", [200] = "OK", [201] = "Created", [204] = "No Content", [206] = "Partial Content", [301] = "Moved Permanently", [302] = "Found",
  [304] = "Not Modified", [400] = "Bad Request", [401] = "Unauthorized", [403] = "Forbidden", [404] = "Not Found", [405] = "Method Not Allowed",
  [408] = "Request Timeout", [411] = "Length Required", [413] = "Payload Too Large", [414] = "URI Too Long", [415] = "Unsupported Media Type",
  [431] = "Request Header Fields Too Large", [500] = "Internal Server Error", [501] = "Not Implemented", [503] = "Service Unavailable",
}

local function url_decode(s, plus)
  if plus then s = s:gsub("%+", " ") end
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end
M.url_decode = url_decode

local function parse_query(q)
  local t = {}
  for pair in q:gmatch("[^&]+") do
    local k, v = pair:match("^([^=]*)=?(.*)$")
    t[url_decode(k, true)] = url_decode(v, true)
  end
  return t
end

local Res = {}
Res.__index = Res

local function bad_header(k, v) return k:find("[^%w!#$%%&'*+%-.^_`|~]") or k == "" or v:find("[%z\1-\8\10-\31\127]") end

function Res:status(n) self.code = n; return self end

-- header names and values with CR, LF or other control characters would split the response (header injection): refused
function Res:header(k, v)
  v = tostring(v)
  if bad_header(k, v) then error("invalid header", 2) end
  self.headers[#self.headers + 1] = {k, v}
  return self
end

function Res:send(body, code)
  if self.sent then return self end
  if code then self.code = code end
  self.body = body or ""
  self.sent = true
  return self
end

local function serialize(res, req, keep)
  local code = res.code
  local body = res.body or ""
  local nobody = req.method == "HEAD" or code == 204 or code == 304 or (code >= 100 and code < 200)
  local out = {("HTTP/1.1 %d %s\r\n"):format(code, REASONS[code] or "Status")}
  local has = {}
  for _, h in ipairs(res.headers) do
    out[#out + 1] = h[1] .. ": " .. h[2] .. "\r\n"
    has[h[1]:lower()] = true
  end
  if not has.date then out[#out + 1] = "Date: " .. os.date("!%a, %d %b %Y %H:%M:%S GMT") .. "\r\n" end
  if not has.server then out[#out + 1] = "Server: vlr\r\n" end
  if not has["content-type"] and #body > 0 then out[#out + 1] = "Content-Type: text/plain; charset=utf-8\r\n" end
  if not (code == 204 or code == 304 or code < 200) then out[#out + 1] = "Content-Length: " .. #body .. "\r\n" end
  out[#out + 1] = keep and "Connection: keep-alive\r\n\r\n" or "Connection: close\r\n\r\n"
  if not nobody then out[#out + 1] = body end
  return table.concat(out)
end

-- lingering close (RFC 9112 9.6): after an error answer, read what the client already sent before closing. Closing a socket with unread data makes
-- some stacks (Windows) reset the connection, which throws the answer away before the client has read it. Bounded: 250 ms and 64 KB.
local function drain(s)
  s:setdeadline(vapor.now() + 250)
  s:settimeout(0.05)
  local left = 65536
  while left > 0 do
    local d = s:readsome(8192)
    if not d then break end
    left = left - #d
  end
end

local function respond_error(s, code, req)
  local body = code .. " " .. (REASONS[code] or "") .. "\n"
  local res = setmetatable({code = code, headers = {}, body = body}, Res)
  s:write(serialize(res, req or {method = "GET"}, false))
  pcall(drain, s)
end

-- reads one request; returns req, or nil,code (answer with that error and close) or nil,nil (client gone / idle timeout: close quietly)
local function read_request(s, o)
  s:setdeadline(vapor.now() + math.floor(o.header_timeout * 1000))
  s:setmaxline(o.max_header)
  local line, err
  repeat
    line, err = s:read("l") -- tolerate leading blank lines (RFC 9112 2.2)
    if line then line = line:gsub("\r$", "") end
  until line ~= ""
  if not line then
    if err == "line too long" then return nil, 414 end
    return nil, nil
  end
  local method, target, version = line:match("^(%u+) (%S+) HTTP/(1%.[01])$")
  if not method or #method > 16 then return nil, 400 end
  if target:sub(1, 1) ~= "/" and target ~= "*" then return nil, 400 end -- origin-form only: no proxy requests
  if target:find("[%z\1-\31\127]") then return nil, 400 end
  local headers, count = {}, 0
  while true do
    local h, herr = s:read("l")
    if not h then return nil, herr == "line too long" and 431 or (herr == "timeout" and 408 or nil) end
    h = h:gsub("\r$", "")
    if h == "" then break end
    count = count + 1
    if count > o.max_headers then return nil, 431 end
    local k, v = h:match("^([^:%s]+):[ \t]*(.-)[ \t]*$")
    if not k or k:find("[^%w!#$%%&'*+%-.^_`|~]") or v:find("[%z\1-\8\10-\31\127]") then return nil, 400 end
    k = k:lower()
    if k == "content-length" and headers[k] and headers[k] ~= v then return nil, 400 end
    headers[k] = (headers[k] and k ~= "content-length") and (headers[k] .. ", " .. v) or v
  end
  if version == "1.1" and not headers.host then return nil, 400 end
  if headers["transfer-encoding"] then
    if headers["content-length"] then return nil, 400 end -- both: the classic smuggling setup
    return nil, 501
  end
  local body = ""
  local cl = headers["content-length"]
  if cl then
    if not cl:match("^%d+$") or #cl > 12 then return nil, 400 end
    cl = tonumber(cl)
    if cl > o.max_body then return nil, 413 end
    if cl > 0 then
      if headers.expect and headers.expect:lower() == "100-continue" then s:write("HTTP/1.1 100 Continue\r\n\r\n") end
      s:setdeadline(vapor.now() + math.floor(o.body_timeout * 1000))
      local b, berr = s:read(cl)
      if not b or #b < cl then return nil, berr == "timeout" and 408 or nil end
      body = b
    end
  end
  local path, query = target:match("^([^?]*)%??(.*)$")
  local req = {method = method, target = target, version = version, headers = headers, body = body,
               path = url_decode(path), query = parse_query(query)}
  if req.path:find("%z") then return nil, 400 end
  return req
end

local function handle(srv, s, remote_addr, remote_port)
  local o = srv.opts
  for n = 1, o.max_requests do
    local req, code = read_request(s, o)
    if not req then
      if code then pcall(respond_error, s, code) end
      return
    end
    req.remote = {address = remote_addr, port = remote_port}
    local res = setmetatable({code = 200, headers = {}}, Res)
    local ok, a, b, c, d = pcall(o.handler, req, res)
    if not ok then
      if srv.on_error then pcall(srv.on_error, a, req) end
      res = setmetatable({code = 500, headers = {}, body = "500 Internal Server Error\n", sent = true}, Res)
    elseif not res.sent then
      -- the handler's return values: body | status, body | status, body, headers
      local code2, body, hdrs = 200, nil, nil
      if type(a) == "number" then code2, body, hdrs = a, b, c else body, hdrs = a, b end
      if type(hdrs) == "table" then
        for k, v in pairs(hdrs) do
          local okh = pcall(res.header, res, k, v)
          if not okh then code2, body = 500, "500 Internal Server Error\n" end
        end
      end
      res.code = code2
      res.body = body ~= nil and tostring(body) or (code2 == 200 and "" or (code2 .. " " .. (REASONS[code2] or "") .. "\n"))
      res.sent = true
    end
    local conn = (req.headers.connection or ""):lower()
    local keep = req.version == "1.1" and not conn:find("close", 1, true) or (req.version == "1.0" and conn:find("keep-alive", 1, true) ~= nil)
    if n == o.max_requests or not srv.listener then keep = false end
    s:setdeadline(vapor.now() + math.floor(o.body_timeout * 1000))
    local wok = s:write(serialize(res, req, keep))
    if not wok or not keep then return end
    s:setdeadline(nil)
    s:settimeout(o.idle_timeout) -- the next request must start within idle_timeout; read_request then applies the header deadline
  end
end

local Server = {}
Server.__index = Server

function Server:port() return self.listener and self.listener:port() end

function Server:close()
  if self.listener then
    local l = self.listener
    self.listener = nil
    l:close()
  end
  return true
end

function M.listen(o)
  assert(type(o) == "table" and type(o.handler) == "function", "httpd.listen{handler = function(req, res) ... end}")
  local opts = {
    handler = o.handler, max_header = o.max_header or 16384, max_headers = o.max_headers or 100, max_body = o.max_body or 1048576,
    header_timeout = o.header_timeout or 10, body_timeout = o.body_timeout or 30, idle_timeout = o.idle_timeout or 5,
    max_requests = o.max_requests or 100, max_conns = o.max_conns or 64,
  }
  local listener, err = net.listen(o.host or "127.0.0.1", o.port or 8080, o.backlog or 128)
  if not listener then return nil, err end
  local srv = setmetatable({opts = opts, listener = listener, conns = 0, on_error = o.on_error}, Server)
  vapor.spawn(function()
    while srv.listener do
      local c, aerr = srv.listener:accept()
      if not c then
        if aerr == "closed" or not srv.listener then break end
        vapor.sleep(0.05) -- a transient accept error (descriptor limit): do not spin
      elseif srv.conns >= opts.max_conns then
        pcall(respond_error, c, 503)
        c:close()
      else
        srv.conns = srv.conns + 1
        c:settimeout(opts.idle_timeout)
        vapor.spawn(function()
          pcall(handle, srv, c, c.peer[1], c.peer[2])
          pcall(c.close, c)
          srv.conns = srv.conns - 1
        end)
      end
    end
  end)
  return srv
end

-- a handler that serves files below root (GET/HEAD): no "..", no backslashes or NUL, directories get index.html. Symbolic links are followed (shortcut: keep root free of links you do not trust)
local TYPES = {html = "text/html; charset=utf-8", htm = "text/html; charset=utf-8", css = "text/css", js = "text/javascript", json = "application/json",
  txt = "text/plain; charset=utf-8", png = "image/png", jpg = "image/jpeg", jpeg = "image/jpeg", gif = "image/gif", svg = "image/svg+xml", wasm = "application/wasm",
  lua = "text/plain; charset=utf-8", ico = "image/x-icon", md = "text/plain; charset=utf-8"}

function M.static(root)
  root = root:gsub("[/\\]+$", "")
  return function(req, res)
    if req.method ~= "GET" and req.method ~= "HEAD" then return 405, nil, {Allow = "GET, HEAD"} end
    local p = req.path
    if p:find("\\", 1, true) or p:find("%z") then return 400 end
    for seg in p:gmatch("[^/]+") do if seg == ".." then return 403 end end
    if p:sub(-1) == "/" then p = p .. "index.html" end
    local f = io.open(root .. p, "rb")
    if not f then return 404 end
    local data = f:read("a")
    f:close()
    if not data then return 404 end -- a directory
    local ext = p:match("%.(%w+)$")
    return 200, data, {["Content-Type"] = TYPES[ext and ext:lower()] or "application/octet-stream"}
  end
end

return M
