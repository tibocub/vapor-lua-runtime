-- std.http against a small server in the same process: content-length, chunked, until-close, redirects (relative and POST->GET), POST body, sink, errors
if not vapor.caps.net then return end
local net, http = require("vapor.net"), require("std.http")
local srv = assert(net.listen("127.0.0.1", 0))
local base = "http://127.0.0.1:" .. srv:port()

local routes = {
  ["/plain"] = function(c) c:write("HTTP/1.1 200 OK\r\nContent-Length: 5\r\nX-Dup: a\r\nX-Dup: b\r\n\r\nhello") end,
  ["/chunked"] = function(c) c:write("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n") end,
  ["/close"] = function(c) c:write("HTTP/1.1 200 OK\r\n\r\nuntil close") end,
  ["/redir"] = function(c) c:write("HTTP/1.1 302 Found\r\nLocation: /plain\r\nContent-Length: 0\r\n\r\n") end,
  ["/big"] = function(c) c:write("HTTP/1.1 200 OK\r\nContent-Length: 200000\r\n\r\n", string.rep("z", 200000)) end,
  ["/missing"] = function(c) c:write("HTTP/1.1 404 Not Found\r\nContent-Length: 2\r\n\r\nno") end,
  ["/loop"] = function(c) c:write("HTTP/1.1 302 Found\r\nLocation: /loop\r\nContent-Length: 0\r\n\r\n") end,
  ["/short"] = function(c) c:write("HTTP/1.1 200 OK\r\nContent-Length: 50\r\n\r\nonly a little") end,
}
local last_post
vapor.spawn(function()
  while true do
    local c = srv:accept()
    if not c then return end
    local req = c:read("l")
    local method, path = req:match("^(%u+) (%S+)")
    local len = 0
    while true do
      local h = c:read("l"):gsub("\r$", "")
      if h == "" then break end
      len = tonumber(h:match("^[Cc]ontent%-[Ll]ength: (%d+)")) or len
    end
    if method == "POST" then
      last_post = c:read(len)
      c:write("HTTP/1.1 303 See Other\r\nLocation: /plain\r\nContent-Length: 0\r\n\r\n")
    else
      (routes[path] or routes["/missing"])(c)
    end
    c:close()
  end
end)

local r = assert(http.get(base .. "/plain"))
assert(r.status == 200 and r.body == "hello" and r.headers["x-dup"] == "a, b")
assert(assert(http.get(base .. "/chunked")).body == "hello world")
assert(assert(http.get(base .. "/close")).body == "until close")
local rd = assert(http.get(base .. "/redir"))
assert(rd.body == "hello" and rd.url == base .. "/plain")
local p = assert(http.post(base .. "/submit", "a=1&b=2"))   -- 303 turns the POST into a GET
assert(last_post == "a=1&b=2" and p.body == "hello")
assert(http.get(base .. "/nothing").status == 404)
local n = 0
local s = assert(http.get(base .. "/big", {sink = function(d) n = n + #d end}))
assert(n == 200000 and s.body == nil)
local _, e1 = http.get(base .. "/loop", {redirects = 3}); assert(e1 and e1:find("redirects"), tostring(e1))
local _, e2 = http.get(base .. "/short", {timeout = 2}); assert(e2, "a short body is an error")
local _, e3 = http.get("ftp://x/"); assert(e3)
srv:close()
print("ok")
