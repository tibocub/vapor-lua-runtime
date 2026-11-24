-- ltn12, mime, socket.url and socket.http (LuaSocket's companion modules)
local ltn12, mime, url = require("ltn12"), require("mime"), require("socket.url")

-- ltn12
local t = {}
assert(ltn12.pump.all(ltn12.source.string(("x"):rep(5000)), (ltn12.sink.table(t))) and #t == 3 and table.concat(t) == ("x"):rep(5000))
local up = function(c) return c and c:upper() or nil end
t = {}
ltn12.pump.all(ltn12.source.chain(ltn12.source.string("abc"), up), (ltn12.sink.table(t)))
assert(table.concat(t) == "ABC")
t = {}
ltn12.pump.all(ltn12.source.cat(ltn12.source.string("a"), ltn12.source.string("b")), ltn12.sink.chain(up, (ltn12.sink.table(t))))
assert(table.concat(t) == "AB")
local _, err = ltn12.pump.all(ltn12.source.error("boom"), ltn12.sink.null())
assert(err == "boom")

-- mime
local function b64(s) local a, r = mime.b64(s); return a .. (mime.b64(nil, r) or "") end
assert(b64("") == "" and b64("f") == "Zg==" and b64("fo") == "Zm8=" and b64("foo") == "Zm9v" and b64("foobar") == "Zm9vYmFy")
assert(mime.unb64("Zm9vYmFy") == "foobar" and mime.unb64("Zm8=") == "fo" and mime.unb64("Zg==") == "f")
local all = {}
for i = 0, 255 do all[#all + 1] = string.char(i) end
all = table.concat(all)
assert(mime.unb64(b64(all)) == all, "binary round trip")
t = {}
ltn12.pump.all(ltn12.source.chain(ltn12.source.string(("hello world"):rep(50)), mime.encode("base64"), mime.wrap(60)), (ltn12.sink.table(t)))
local enc = table.concat(t)
assert(enc:find("\r\n", 1, true) and not enc:find("[^%w%+/=\r\n]"))
t = {}
ltn12.pump.all(ltn12.source.chain(ltn12.source.string(enc), mime.decode("base64")), (ltn12.sink.table(t)))
assert(table.concat(t) == ("hello world"):rep(50), "encode/wrap/decode through ltn12")
assert(mime.qp("a=b\200") == "a=3Db=C8" and mime.unqp("a=3Db=C8") == "a=b\200")
t = {}
ltn12.pump.all(ltn12.source.chain(ltn12.source.string("a\nb\r\nc\rd"), mime.normalize("\n")), (ltn12.sink.table(t)))
assert(table.concat(t) == "a\nb\nc\nd", table.concat(t))

-- socket.url (examples from RFC 3986 / the LuaSocket manual)
local p = url.parse("http://user:pw@www.example.com:8080/a/b;p?q=1#frag")
assert(p.scheme == "http" and p.host == "www.example.com" and p.port == "8080" and p.user == "user" and p.password == "pw" and p.path == "/a/b" and p.params == "p" and p.query == "q=1" and p.fragment == "frag")
assert(url.build(p) == "http://user:pw@www.example.com:8080/a/b;p?q=1#frag")
assert(url.absolute("http://a/b/c/d;p?q", "g") == "http://a/b/c/g" and url.absolute("http://a/b/c/d;p?q", "../g") == "http://a/b/g")
assert(url.absolute("http://a/b/c/d;p?q", "//g") == "http://g" and url.absolute("http://a/b/c/d;p?q", "?y") == "http://a/b/c/d;p?y")
assert(url.escape("a b/é") == "a%20b%2f%c3%a9" and url.unescape("a%20b") == "a b")
local pp = url.parse_path("/a/b%20c/d/")
assert(pp[1] == "a" and pp[2] == "b c" and pp.is_absolute and pp.is_directory and url.build_path(pp) == "/a/b%20c/d/")
assert(url.parse("") == nil)

-- socket.http against a tiny server written with plain sockets (one task per connection)
if vapor.caps.net then
  local http, socket = require("socket.http"), require("socket")
  local function handler(req)
    if req.path == "/r" then return 302, "", {Location = "/hello"}
    elseif req.path == "/hello" then return 200, "hello " .. (req.query:match("name=(%w+)") or "world")
    elseif req.path == "/echo" then return 200, req.method .. ":" .. req.body .. ":" .. (req.headers.authorization or "-")
    elseif req.path == "/big" then return 200, ("z"):rep(100000) end
    return 404, ""
  end
  local listener = assert(socket.bind("127.0.0.1", 0))
  local srv = {port = function() return select(2, listener:getsockname()) end}
  vapor.spawn(function()
    while true do
      local c = listener:accept()
      if not c then break end
      vapor.spawn(function()
        local line = c:receive("*l")
        local method, target = line:match("^(%u+) (%S+)")
        local path, query = target:match("^([^?]*)%??(.*)$")
        local headers = {}
        for l in function() local x = c:receive("*l"); if x ~= "" then return x end end do
          local k, v = l:match("^([^:]+):%s*(.*)$"); headers[k:lower()] = v
        end
        local body = headers["content-length"] and c:receive(tonumber(headers["content-length"])) or ""
        local code, text, extra = handler{method = method, path = path, query = query, headers = headers, body = body}
        local out = {("HTTP/1.1 %d X\r\nContent-Length: %d\r\nConnection: close\r\n"):format(code, #text)}
        for k, v in pairs(extra or {}) do out[#out + 1] = k .. ": " .. v .. "\r\n" end
        c:send(table.concat(out) .. "\r\n" .. text)
        c:close()
      end)
    end
  end)
local base = "http://127.0.0.1:" .. srv:port()
  local body, code, headers, status = http.request(base .. "/hello?name=lua")
  assert(body == "hello lua" and code == 200 and headers["content-length"] == "9" and status:find("200"), tostring(body) .. tostring(code))
  assert(http.request(base .. "/r") == "hello world", "redirect followed")
  assert(http.request(base .. "/echo", "data=1") == "POST:data=1:-", "string body posts")
  assert(#http.request(base .. "/big") == 100000)
  local t2 = {}
  local r, c2 = http.request{url = base .. "/echo", method = "PUT", source = ltn12.source.string("xyz"), sink = (ltn12.sink.table(t2)), user = "u", password = "p"}
  assert(r == 1 and c2 == 200 and table.concat(t2) == "PUT:xyz:Basic dTpw", table.concat(t2))
  local _, c3 = http.request(base .. "/missing")
  assert(c3 == 404)
  assert(select(2, http.request("https://example.org/")) == "unsupported scheme 'https'")
  assert(select(2, http.request("http://127.0.0.1:1/")) ~= nil, "connection refused is an error")
  listener:close()
end
print("ok")
