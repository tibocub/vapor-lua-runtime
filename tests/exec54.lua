--! dialect 5.4
local vlr = require("vlr")
if not vlr.caps.exec then return end
local ok, how, code = os.execute("exit 3")
assert(ok == nil and how == "exit" and code == 3)
assert(os.execute("exit 0") == true)
assert(os.execute() == true)
