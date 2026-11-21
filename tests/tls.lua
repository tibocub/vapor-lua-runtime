-- TLS client against local openssl servers (started by tests/tls/run.sh)
local tls = require("vapor.tls")
local dir, good, other = os.getenv("TLS_DIR"), tonumber(os.getenv("TLS_GOOD")), tonumber(os.getenv("TLS_OTHER"))
if not dir then print("skip tls.lua (run tests/tls/run.sh)"); return end
local function slurp(p) local f = assert(io.open(dir .. "/" .. p, "rb")); local s = f:read("*a"); f:close(); return s end

-- 1. a verified connection: the server answers GET with its status page
local s, err = tls.connect("localhost", good, {ca = slurp("good.crt"), timeout = 5})
assert(s, err)
assert(s:write("GET / HTTP/1.0\r\n\r\n"))
local head = s:read("l")
assert(head and head:find("HTTP/1.0 200", 1, true), tostring(head))
local rest = s:read("a")
assert(rest and #rest > 100, "body")
s:close()

-- 2. the certificate is for another name: refused
local s2, err2 = tls.connect("localhost", other, {ca = slurp("other.crt"), timeout = 5})
assert(not s2 and err2 and err2:find("host name", 1, true), tostring(err2))

-- 3. a certificate that is not in the trusted set: refused
local s3, err3 = tls.connect("localhost", good, {ca = slurp("other.crt"), timeout = 5})
assert(not s3 and err3 and err3:find("trusted", 1, true), tostring(err3))

-- 4. nothing listens: a plain connection error, not a hang
local s4, err4 = tls.connect("localhost", 1, {ca = slurp("good.crt"), timeout = 2})
assert(not s4 and err4)
print("ok")
