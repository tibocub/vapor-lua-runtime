-- what a package manager asks the runtime: who are you, where, which modules are already built in
assert(type(vapor.version) == "string" and vapor.version:match("^%d+%.%d+%.%d+"))
assert(({linux = 1, windows = 1, nuttx = 1, wasm = 1, macos = 1, posix = 1})[vapor.platform], vapor.platform)
assert(type(vapor.builtin) == "table")
for name in pairs(vapor.builtin) do assert(package.preload[name], name .. " listed but not in package.preload") end
for name in pairs(package.preload) do assert(vapor.builtin[name], name .. " preloaded but not listed") end
assert(vapor.builtin.lfs and vapor.builtin.lpeg and vapor.builtin.cjson)
