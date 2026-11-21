-- std.http: an HTTP/1.1 client over vapor.net (and vapor.tls for https). One request per connection ("Connection: close"): simple and enough for
-- vpm and scripts; keep-alive pools are a later step.
--   http.request{url=, method="GET", headers={}, body=string|nil, timeout=30, redirects=5, sink=function(chunk), ca=, cafile=}
--     -> {status=200, reason="OK", headers={["content-type"]=...} (lower-case names), body=string | nil when a sink took it, url=final url}  or  nil, err
--   http.get(url [, opts])   http.post(url, body [, opts])
-- Bodies: Content-Length, chunked and read-until-close are handled; redirects (301 302 303 307 308) are followed, 301-303 turn POST into GET. A sink gets the
-- body in pieces as it arrives (downloads without holding the file in memory). Response headers that repeat are joined with ", ".
-- shortcut: no compressed bodies (no Accept-Encoding sent), no proxies, no cookies, no keep-alive; upgrade when a real app needs one.
local M = {}

local function parse_url(url)
  local scheme, rest = url:match("^(%a[%w+.-]*)://(.*)$")
  if not scheme then return nil, "not an absolute URL: " .. url end
  scheme = scheme:lower()
  if scheme ~= "http" and scheme ~= "https" then return nil, "unsupported scheme " .. scheme end
  local authority, path = rest:match("^([^/?#]*)(.*)$")
  path = path:gsub("#.*$", "")
  if path == "" or path:sub(1, 1) == "?" then path = "/" .. path end
  authority = authority:gsub("^.*@", "") -- user info is not sent
  local host, port = authority:match("^%[(.-)%]:?(%d*)$") -- [v6]:port
  if not host then host, port = authority:match("^(.-):?(%d*)$") end
  if host == "" then return nil, "no host in " .. url end
  return {scheme = scheme, host = host, port = tonumber(port) or (scheme == "https" and 443 or 80), path = path, authority = authority}
end

local function resolve(base, loc)
  if loc:match("^%a[%w+.-]*://") then return loc end
  local u = parse_url(base)
  local origin = u.scheme .. "://" .. u.authority
  if loc:sub(1, 2) == "//" then return u.scheme .. ":" .. loc end
  if loc:sub(1, 1) == "/" then return origin .. loc end
  local dir = u.path:gsub("[?].*$", ""):match("^(.*/)") or "/"
  return origin .. dir .. loc
end

local function read_headers(s)
  local line, err = s:read("l")
  if not line then return nil, err or "connection closed" end
  line = line:gsub("\r$", "")
  local status, reason = line:match("^HTTP/%d%.%d (%d%d%d) ?(.*)$")
  if not status then return nil, "bad status line: " .. line end
  local headers = {}
  while true do
    local h, herr = s:read("l")
    if not h then return nil, herr or "connection closed in headers" end
    h = h:gsub("\r$", "")
    if h == "" then break end
    local k, v = h:match("^([^:]+):%s*(.-)%s*$")
    if k then
      k = k:lower()
      headers[k] = headers[k] and (headers[k] .. ", " .. v) or v
    end
  end
  return tonumber(status), reason, headers
end

local function read_body(s, headers, method, status, put)
  if method == "HEAD" or status == 204 or status == 304 or (status >= 100 and status < 200) then return true end
  local te = headers["transfer-encoding"]
  if te and te:lower():find("chunked", 1, true) then
    while true do
      local sizeline, err = s:read("l")
      if not sizeline then return nil, err or "connection closed in a chunked body" end
      local size = tonumber(sizeline:match("^%s*(%x+)"), 16)
      if not size then return nil, "bad chunk size: " .. sizeline end
      if size == 0 then
        repeat local t = s:read("l") until t == nil or t:gsub("\r$", "") == "" -- trailers
        return true
      end
      local left = size
      while left > 0 do
        local d, derr = s:readsome(math.min(left, 16384))
        if not d then return nil, derr or "connection closed in a chunk" end
        put(d)
        left = left - #d
      end
      s:read(2) -- CRLF after the chunk
    end
  end
  local len = tonumber(headers["content-length"])
  if len then
    local left = len
    while left > 0 do
      local d, err = s:readsome(math.min(left, 16384))
      if not d then return nil, err == "eof" and "connection closed before the whole body arrived" or err end
      put(d)
      left = left - #d
    end
    return true
  end
  while true do -- until the server closes
    local d, err = s:readsome(16384)
    if not d then
      if err == "eof" then return true end
      return nil, err
    end
    put(d)
  end
end

function M.request(o)
  local method = (o.method or "GET"):upper()
  local url = o.url
  local redirects = o.redirects or 5
  local body = o.body
  for _ = 0, redirects do
    local u, perr = parse_url(url)
    if not u then return nil, perr end
    local s, err
    local opts = {timeout = o.timeout or 30, ca = o.ca, cafile = o.cafile}
    if u.scheme == "https" then
      s, err = require("vapor.tls").connect(u.host, u.port, opts)
    else
      s, err = require("vapor.net").connect(u.host, u.port, opts.timeout)
    end
    if not s then return nil, err end
    s:settimeout(opts.timeout)
    local headers = {["Host"] = u.authority, ["User-Agent"] = "vlr", ["Accept"] = "*/*", ["Connection"] = "close"}
    for k, v in pairs(o.headers or {}) do headers[k] = v end
    if body then headers["Content-Length"] = tostring(#body) end
    local out = {method .. " " .. u.path .. " HTTP/1.1"}
    for k, v in pairs(headers) do out[#out + 1] = k .. ": " .. v end
    out[#out + 1] = ""
    out[#out + 1] = body or ""
    local ok, werr = s:write(table.concat(out, "\r\n"))
    if not ok then s:close(); return nil, werr end

    local status, reason, rh = read_headers(s)
    if not status then s:close(); return nil, reason end
    local loc = rh.location
    if loc and (status == 301 or status == 302 or status == 303 or status == 307 or status == 308) then
      s:close()
      url = resolve(url, loc)
      if status <= 303 and method ~= "GET" and method ~= "HEAD" then method, body = "GET", nil end
    else
      local parts = {}
      local put = o.sink or function(d) parts[#parts + 1] = d end
      local bok, berr = read_body(s, rh, method, status, put)
      s:close()
      if not bok then return nil, berr end
      return {status = status, reason = reason, headers = rh, body = (not o.sink) and table.concat(parts) or nil, url = url}
    end
  end
  return nil, "too many redirects"
end

function M.get(url, opts)
  opts = opts or {}
  opts.url = url
  return M.request(opts)
end

function M.post(url, body, opts)
  opts = opts or {}
  opts.url, opts.method, opts.body = url, "POST", body
  return M.request(opts)
end

return M
