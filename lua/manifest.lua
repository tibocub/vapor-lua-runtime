-- vapor.manifest: an app is a folder with manifest.lua (plain data) and its entry script; `vlr <folder>` checks the manifest
-- against this runtime and runs the entry. Optional module "vapor.manifest".
--   return {name = "editor", version = "0.1.0", entry = "main.lua",           -- entry defaults to main.lua
--           needs = {vlr = "0.2", dialect = "5.4", caps = {"tty"}, modules = {"vapor.input", "lpeg"}}}
-- Modules are found built in (vapor.builtin) or as Lua files in <folder>/lua_modules and <folder>.
local vapor = vapor
local M = {}

local function vnum(s)
  local a, b, c = tostring(s):match("^(%d+)%.?(%d*)%.?(%d*)")
  return {tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0}
end

local function atleast(have, want)
  have, want = vnum(have), vnum(want)
  for i = 1, 3 do if have[i] ~= want[i] then return have[i] > want[i] end end
  return true
end

function M.load(dir)
  local f, err = loadfile(dir .. "/manifest.lua", "t", {}) -- no functions available to a manifest: it is data
  if not f then return nil, err end
  local ok, m = pcall(f)
  if not ok then return nil, m end
  if type(m) ~= "table" then return nil, dir .. "/manifest.lua must return a table" end
  return m
end

function M.path(dir) return dir .. "/lua_modules/?.lua;" .. dir .. "/lua_modules/?/init.lua;" .. dir .. "/?.lua;" .. dir .. "/?/init.lua" end

-- what keeps this app from running here: a list of sentences, empty when it can run
function M.check(m, dir)
  local bad, needs = {}, m.needs or {}
  if type(m.name) ~= "string" then bad[#bad + 1] = "manifest has no name" end
  if needs.vlr and not atleast(vapor.version, needs.vlr) then bad[#bad + 1] = "needs vlr " .. needs.vlr .. " or newer (this is " .. vapor.version .. ")" end
  if needs.dialect and needs.dialect ~= vapor.dialect then bad[#bad + 1] = "needs the " .. needs.dialect .. " dialect (run vlr --dialect=" .. needs.dialect .. ")" end
  for _, c in ipairs(needs.caps or {}) do
    if not vapor.caps[c] then bad[#bad + 1] = "needs capability " .. c .. " (not available on " .. vapor.platform .. ")" end
  end
  for _, name in ipairs(needs.modules or {}) do
    if not vapor.builtin[name] and not (dir and package.searchpath(name, M.path(dir))) and not package.loaded[name] then
      bad[#bad + 1] = "needs module " .. name .. " (neither built in nor in lua_modules)"
    end
  end
  return bad
end

function M.main(dir, ...)
  local m, err = M.load(dir)
  if not m then io.stderr:write("vlr: ", tostring(err), "\n"); os.exit(1) end
  local bad = M.check(m, dir)
  if #bad > 0 then
    io.stderr:write("vlr: ", tostring(m.name), " cannot run here:\n")
    for _, b in ipairs(bad) do io.stderr:write("  ", b, "\n") end
    os.exit(1)
  end
  package.path = M.path(dir) .. ";" .. package.path
  local entry = dir .. "/" .. (m.entry or "main.lua")
  local f, lerr = loadfile(entry)
  if not f then io.stderr:write("vlr: ", tostring(lerr), "\n"); os.exit(1) end
  arg = {[0] = entry, ...}
  return f(...)
end

return M
