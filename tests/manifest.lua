-- app manifests: check against this runtime, no code runs from a manifest
local mf = require("vapor.manifest")
local dir = (arg[0]:match("^(.*)/[^/]*$") or ".") .. "/app"
local good = assert(mf.load(dir .. "/good"))
assert(good.name == "good")
assert(#mf.check(good, dir .. "/good") == 0, table.concat(mf.check(good, dir .. "/good"), "; "))
local bad = assert(mf.load(dir .. "/bad"))
local problems = table.concat(mf.check(bad, dir .. "/bad"), "\n")
for _, want in ipairs{"needs vlr 99.0", "capability gfx", "module nosuch"} do assert(problems:find(want, 1, true), want .. " in: " .. problems) end
assert(not mf.load(dir .. "/missing"))
