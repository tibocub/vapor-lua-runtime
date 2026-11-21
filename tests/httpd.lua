-- std.httpd: normal requests, keep-alive, and the hostile cases (smuggling, oversize, slow clients, injection, traversal, connection limit)
if not vapor.caps.net then return end
local net, http, httpd = require("vapor.net"), require("std.http"), require("std.httpd")

local errors = {}
local srv = assert(httpd.listen{
  port = 0, header_timeout = 0.4, idle_timeout = 0.6, max_body = 1000, max_header = 300, max_conns = 4, on_error = function(e) errors[#errors + 1] = e end,
  handler = function(req, res)
    if req.path == "/hello" then return "hello " .. (req.query.name or "world")
    elseif req.path == "/echo" then return 201, req.method .. ":" .. req.body, {["X-Seen"] = req.headers["x-test"] or "-"}
    elseif req.path == "/boom" then error("secret internal detail")
    elseif req.path == "/inject" then res:header("X-A", "x\r\nSet-Cookie: pwned=1"); return "no"
    elseif req.path == "/send" then res:status(202):header("X-Mode", "send"):send("sent")
    elseif req.path == "/slow" then vapor.sleep(0.5); return "slow"
    elseif req.path == "/who" then return req.remote.address
    end
    return 404
  end,
})
local port = srv:port()
assert(port and port > 0)

-- raw exchange: send bytes, read until the server closes (or the idle wait ends); returns everything received
local function raw(bytes, wait)
  local c = assert(net.connect("127.0.0.1", port, 5))
  c:write(bytes)
  c:settimeout(wait or 2)
  local got = c:read("a") or ""
  c:close()
  return got
end
local function status(r) return tonumber(r:match("^HTTP/1%.1 (%d+)")) end

-- through the client library
local r = assert(http.get("http://127.0.0.1:" .. port .. "/hello?name=l%C3%A9o+x"))
assert(r.status == 200 and r.body == "hello léo x", r.body)
r = assert(http.post("http://127.0.0.1:" .. port .. "/echo", "data", {headers = {["X-Test"] = "1"}}))
assert(r.status == 201 and r.body == "POST:data" and r.headers["x-seen"] == "1", r.body)
r = assert(http.get("http://127.0.0.1:" .. port .. "/nope"))
assert(r.status == 404 and r.body:match("^404 Not Found"))
r = assert(http.get("http://127.0.0.1:" .. port .. "/send"))
assert(r.status == 202 and r.body == "sent" and r.headers["x-mode"] == "send")
r = assert(http.get("http://127.0.0.1:" .. port .. "/who"))
assert(r.body == "127.0.0.1")

-- keep-alive: two requests on one connection, then Connection: close ends it
do
  local c = assert(net.connect("127.0.0.1", port, 5))
  c:write("GET /hello HTTP/1.1\r\nHost: x\r\n\r\nGET /hello?name=2 HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
  c:settimeout(2)
  local all = c:read("a")
  assert(select(2, all:gsub("HTTP/1%.1 200 OK", "")) == 2 and all:find("hello 2", 1, true), all)
  assert(all:find("Connection: keep%-alive") and all:find("Connection: close"))
  c:close()
end

-- HEAD: headers with the length, no body
local head = raw("HEAD /hello HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
assert(status(head) == 200 and head:find("Content%-Length: 11") and head:sub(-4) == "\r\n\r\n", head)

-- the handler's error never reaches the client
local boom = raw("GET /boom HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
assert(status(boom) == 500 and not boom:find("secret"), boom)
assert(#errors == 1 and tostring(errors[1]):find("secret"), "error reported to on_error")

-- header injection through res:header is refused (500), nothing leaks into the response
local inj = raw("GET /inject HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
assert(status(inj) == 500 and not inj:find("pwned"), inj)

-- malformed and hostile requests: each gets the right status and the connection is closed
local function expect(code, bytes, what)
  local resp = raw(bytes)
  assert(status(resp) == code, what .. ": wanted " .. code .. ", got " .. tostring(status(resp)) .. "\n" .. resp)
end
expect(400, "GET /hello HTTP/1.1\r\n\r\n", "HTTP/1.1 without Host")
expect(400, "garbage\r\n\r\n", "bad request line")
expect(400, "GET http://evil.example/ HTTP/1.1\r\nHost: x\r\n\r\n", "absolute-form target")
expect(400, "GET /a\0b HTTP/1.1\r\nHost: x\r\n\r\n", "NUL in target")
expect(400, "GET /hello HTTP/1.1\r\nHost: x\r\nBad Header: 1\r\n\r\n", "space in header name")
expect(400, "GET /hello HTTP/1.1\r\nHost: x\r\nX: a\1b\r\n\r\n", "control character in a value")
expect(400, "POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 4\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n", "Content-Length with Transfer-Encoding")
expect(400, "POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 4\r\nContent-Length: 5\r\n\r\nabcd", "conflicting Content-Length")
expect(400, "POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: -1\r\n\r\n", "negative Content-Length")
expect(501, "POST /echo HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n", "chunked request body")
expect(413, "POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 1001\r\n\r\n", "body over max_body")
expect(414, "GET /" .. string.rep("a", 400) .. " HTTP/1.1\r\nHost: x\r\n\r\n", "request line over max_header")
expect(431, "GET /hello HTTP/1.1\r\nHost: x\r\nX: " .. string.rep("a", 400) .. "\r\n\r\n", "header line over max_header")
do
  local many = {}
  for i = 1, 120 do many[i] = "X" .. i .. ": 1\r\n" end
  expect(431, "GET /hello HTTP/1.1\r\nHost: x\r\n" .. table.concat(many) .. "\r\n", "too many headers")
end
-- duplicate identical Content-Length values are fine
expect(201, "POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 2\r\nContent-Length: 2\r\nConnection: close\r\n\r\nab", "identical Content-Length")
-- HTTP/1.0 closes by default
assert(raw("GET /hello HTTP/1.0\r\n\r\n"):find("Connection: close"))

-- a client that dribbles the header is cut off by the total header deadline, however often a byte arrives
do
  local c = assert(net.connect("127.0.0.1", port, 5))
  local t0 = vapor.now()
  c:write("GET /hello HTTP/1.1\r\n")
  for _ = 1, 20 do
    vapor.sleep(0.1)
    if not c:write("X-A: 1\r\n") then break end
  end
  c:settimeout(2)
  local resp = c:read("a") or ""
  c:close()
  assert(status(resp) == 408 or resp == "", "slow header: " .. resp)
  assert(vapor.now() - t0 < 1500, "dribbling did not extend the deadline")
end

-- an idle keep-alive connection is closed after idle_timeout, and a body that never arrives times out
do
  local c = assert(net.connect("127.0.0.1", port, 5))
  c:write("GET /hello HTTP/1.1\r\nHost: x\r\n\r\n")
  c:settimeout(3)
  assert(c:read("l"):find("200"))
  local t0 = vapor.now()
  local rest = c:read("a") -- headers + body come, then the server closes at idle_timeout (0.6 s)
  assert(rest and vapor.now() - t0 < 2000, "idle connection was closed")
  c:close()
end

-- connection limit: with 4 held connections, the 5th gets 503
do
  local held = {}
  for i = 1, 4 do held[i] = assert(net.connect("127.0.0.1", port, 5)); held[i]:write("GET /slow HTTP/1.1\r\nHost: x\r\n\r\n") end
  vapor.sleep(0.15)
  local over = raw("GET /hello HTTP/1.1\r\nHost: x\r\n\r\n")
  assert(status(over) == 503, "over the connection limit: " .. over)
  for _, h in ipairs(held) do h:close() end
end

-- static files: served, directories get index.html, traversal refused
do
  local dir = "httpd-test-www-" .. os.time()
  local mk = vapor.fs and vapor.fs.mkdir
  if mk then
    assert(vapor.fs.mkdir(dir))
    local f = assert(io.open(dir .. "/index.html", "w")); f:write("<h1>hi</h1>"); f:close()
    f = assert(io.open(dir .. "/a.txt", "w")); f:write("text"); f:close()
    local s2 = assert(httpd.listen{port = 0, handler = httpd.static(dir)})
    local base = "http://127.0.0.1:" .. s2:port()
    local a = assert(http.get(base .. "/"))
    assert(a.status == 200 and a.body == "<h1>hi</h1>" and a.headers["content-type"]:find("text/html"))
    assert(assert(http.get(base .. "/a.txt")).body == "text")
    assert(assert(http.get(base .. "/missing")).status == 404)
    local c = assert(net.connect("127.0.0.1", s2:port(), 5))
    c:write("GET /%2e%2e/etc/passwd HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
    c:settimeout(2)
    assert(status(c:read("a")) == 403, "encoded traversal refused")
    c:close()
    s2:close()
    os.remove(dir .. "/index.html"); os.remove(dir .. "/a.txt"); vapor.fs.rmdir(dir)
  end
end

-- the example app (examples/httpd), end to end
do
  package.path = "examples/httpd/?.lua;" .. package.path
  local app = require("app")
  local s3 = assert(httpd.listen{port = 0, handler = app.new{max_notes = 2}})
  local base = "http://127.0.0.1:" .. s3:port()
  local page = assert(http.get(base .. "/"))
  assert(page.status == 200 and page.body:find("vlr notes") and page.headers["content-security-policy"])
  local info = assert(http.get(base .. "/api/info"))
  assert(info.body:find('"platform":"' .. vapor.platform .. '"', 1, true), info.body)
  assert(assert(http.get(base .. "/api/notes")).body == "[]")
  local c1 = assert(http.post(base .. "/api/notes", 'say "hi"\nnow'))
  assert(c1.status == 201 and c1.body == '{"id":1}' and c1.headers.location == "/api/notes/1")
  assert(assert(http.post(base .. "/api/notes", "two")).status == 201)
  assert(assert(http.post(base .. "/api/notes", "three")).status == 507, "note limit")
  assert(assert(http.post(base .. "/api/notes", "")).status == 400, "empty note")
  assert(assert(http.get(base .. "/api/notes")).body == '[{"id":1,"text":"say \\"hi\\"\\nnow"},{"id":2,"text":"two"}]')
  assert(assert(http.request{url = base .. "/api/notes/1", method = "DELETE"}).status == 204)
  assert(assert(http.request{url = base .. "/api/notes/1", method = "DELETE"}).status == 404)
  assert(assert(http.request{url = base .. "/api/notes", method = "DELETE"}).status == 405)
  s3:close()
end

srv:close()
vapor.sleep(0.05)
local ok = net.connect("127.0.0.1", port, 1)
assert(not ok, "closed server refuses connections")
print("ok")
