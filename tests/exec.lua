local vlr = require("vlr")
-- os.execute through the platform shell (skipped where there is none, e.g. wasm)
if not vlr.caps.exec then return end
assert(os.execute("exit 3") == 3)
assert(os.execute("exit 0") == 0)
assert(os.execute() ~= 0)
