-- lfs (the official LuaFileSystem API, bundled) covers what plain Lua lacks for the file system
local lfs = require("lfs")
local d = (os.getenv("TMPDIR") or ".") .. "/vlr-fs-test-" .. os.time()
assert(lfs.mkdir(d))
assert(lfs.attributes(d, "mode") == "directory")
local f = assert(io.open(d .. "/x.txt", "w")); f:write("hello"); f:close()
local l = {}
for n in lfs.dir(d) do if n ~= "." and n ~= ".." then l[#l + 1] = n end end
assert(#l == 1 and l[1] == "x.txt")
local st = lfs.attributes(d .. "/x.txt")
assert(st.mode == "file" and st.size == 5)
assert(lfs.attributes(d .. "/missing") == nil)
assert(os.remove(d .. "/x.txt"))
assert(lfs.rmdir(d))
assert(lfs.attributes(d) == nil)
