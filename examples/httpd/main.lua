-- Run: vlr examples/httpd/main.lua [port [host]]   (default 127.0.0.1:8080; open http://127.0.0.1:8080/ ). Ctrl+C stops it.
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
package.path = here .. "/?.lua;" .. package.path
local httpd = require("std.httpd")
local app = require("app")

local port, host = tonumber(arg[1]) or 8080, arg[2] or "127.0.0.1"
local srv, err = httpd.listen{
  host = host, port = port, handler = app.new(),
  on_error = function(e, req) io.stderr:write(("error handling %s %s: %s\n"):format(req.method, req.target, tostring(e))) end,
}
if not srv then io.stderr:write("cannot listen on ", host, ":", port, ": ", tostring(err), "\n"); os.exit(1) end
print(("vlr notes on http://%s:%d/ (Ctrl+C stops)"):format(host, srv:port()))
vapor.run()
