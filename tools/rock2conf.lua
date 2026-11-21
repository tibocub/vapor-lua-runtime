-- rock2conf.lua ROCKSPEC SRCDIR : prints modules.conf lines for the modules of a builtin-type rockspec.
-- Run with vlr itself:  ./vlr tools/rock2conf.lua ../luafilesystem/luafilesystem-scm-1.rockspec ../luafilesystem
-- SRCDIR is the unpacked source, expected next to the other checkouts (it becomes @EXT@/<its folder name>).
-- C modules become `name luaopen_x sources -Ddefines`; Lua files become `name lua:path`. Rocks that need a build step
-- (type make/cmake/...) or an external library (`libraries`) are refused: write those lines by hand.
local spec, srcdir = arg[1], arg[2]
if not spec or not srcdir then io.stderr:write("usage: rock2conf.lua ROCKSPEC SRCDIR\n"); os.exit(2) end

local env = {}
local f, err = loadfile(spec, "t", env)
if not f then io.stderr:write(err, "\n"); os.exit(1) end
assert(pcall(f))
local build = env.build or {}
if (build.type or "builtin") ~= "builtin" then
  io.stderr:write("rock2conf: build type '", tostring(build.type), "' is not supported (builtin only); write the modules.conf line by hand\n")
  os.exit(1)
end

local base = "@EXT@/" .. srcdir:gsub("/+$", ""):match("([^/]+)$")
local names = {}
for name in pairs(build.modules or {}) do names[#names + 1] = name end
table.sort(names)
for _, name in ipairs(names) do
  local m = build.modules[name]
  if type(m) == "string" then m = {sources = {m}} end
  if type(m.sources) == "string" then m.sources = {m.sources} end
  local first = m.sources[1]
  if #m.sources == 1 and first:match("%.lua$") then
    print(name .. " lua:" .. base .. "/" .. first)
  else
    if m.libraries or m.libdirs then
      io.stderr:write("rock2conf: ", name, " links external libraries (", table.concat(m.libraries or {}, ","), "); not supported\n"); os.exit(1)
    end
    local sym = "luaopen_" .. name:gsub("^.*%-", ""):gsub("%.", "_")
    local parts = {name, sym}
    -- a symbol of Lua's own libraries (utf8, string...) cannot be linked twice: rename the rock's one at compile time
    local stdlib = {base = 1, coroutine = 1, table = 1, io = 1, os = 1, string = 1, utf8 = 1, math = 1, debug = 1, package = 1}
    local clash = stdlib[sym:sub(9)] and ("luaopen_rock_" .. name:gsub("%W", "_"))
    if clash then parts[2] = clash end
    for _, s in ipairs(m.sources) do parts[#parts + 1] = base .. "/" .. s end
    if clash then parts[#parts + 1] = "-D" .. sym .. "=" .. clash end
    for _, d in ipairs(m.defines or {}) do parts[#parts + 1] = "-D" .. d end
    for _, d in ipairs(m.incdirs or {}) do parts[#parts + 1] = "-I" .. base .. "/" .. d end
    print(table.concat(parts, " "))
  end
end
-- install.lua (pure Lua files the rock also installs, like cjson.util) are not modules of the build table
local extra = build.install and build.install.lua or {}
for name, file in pairs(extra) do io.stderr:write("rock2conf: note: install.lua ", name, " = ", file, " (add it as `", name, " lua:", base, "/", file, "` if needed)\n") end
