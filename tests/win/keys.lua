-- Diagnostic for terminal input: shows the raw bytes the console delivers and what vlr decodes them to, and logs them to a file.
-- usage:  vlr tests/win/keys.lua [mouse level 0|1|2] [logfile]      (q quits; default log reports/keys-last.txt)
-- Mouse level 2 reports hover too. Press the combinations you want to check, one at a time.
local term = require("vapor.term")
local mouse = tonumber(arg[1]) or 2
local logname = arg[2] or "reports/keys-last.txt"
local log = io.open(logname, "w")
local function out(s) io.stdout:write(s, "\r\n"); io.stdout:flush(); if log then log:write(s, "\n"); log:flush() end end

out("keys: platform=" .. vapor.platform .. " native=" .. tostring(term.native()) .. " mouse level=" .. mouse .. " (hover needs 2)  (q quits)")
vapor.input({mouse = mouse}) -- sets raw mode and the mouse reporting; we read the bytes ourselves below
vapor._source(0, nil)        -- ...so take the console back from the event pump (a key that produces no event prints nothing at all)
local d = require("vapor.term")
local quit = false
while not quit do
  local ok = vapor.wait_fd(0, 30)
  if not ok then out("(30 s without input, ending)"); break end
  if term.native() then -- Windows: native console records, already translated into events (the bytes path does not exist there)
    local evs = {}
    for _, e in ipairs(term.console_events()) do evs[#evs + 1] = table.concat(e, ","); if e[1] == "char" and e[2] == "q" then quit = true end end
    if #evs > 0 then out("native record -> " .. table.concat(evs, " | ")) end
    goto continue
  end
  local bytes = term.console_read(256)
  if bytes == nil then break end
  if #bytes > 0 then
    local hex = {}
    for i = 1, #bytes do hex[i] = string.format("%02x", bytes:byte(i)) end
    local evs = {}
    for _, e in ipairs(d.decode(bytes)) do evs[#evs + 1] = table.concat(e, ",") end
    out("bytes " .. table.concat(hex, " ") .. "   ->  " .. (#evs > 0 and table.concat(evs, " | ") or "(no event)"))
    if bytes == "q" then quit = true end
  end
  ::continue::
end
vapor.input(false)
if log then log:close() end
print("log written to " .. logname)
