-- vlr.repl: an interactive prompt (vlr with no script, or vlr -i). Reads whole lines in the console's own line mode (so the terminal edits
-- them); waits cooperatively, so timers and tasks keep running while it sits at the prompt.
-- repl([read [, write]]): read(prompt) -> line or nil at end of input; write(text). Defaults: the console. Returns when input ends.
-- shortcut: no history or completion of its own (the terminal's line editing only); NuttX gets a readline hook, upgrade then.
local vlr = require("vlr")

local function default_read(prompt)
  io.stdout:write(prompt); io.stdout:flush()
  if vlr.wait_fd then vlr.wait_fd(0) end
  return io.read("l")
end
local function default_write(s) io.stdout:write(s); io.stdout:flush() end

local function show(write, ok, ...)
  if not ok then write(tostring((...)) .. "\n"); return end
  local n = select("#", ...)
  if n == 0 then return end
  local t = {}
  for i = 1, n do t[i] = tostring((select(i, ...))) end
  write(table.concat(t, "\t") .. "\n")
end

return function(read, write)
  read, write = read or default_read, write or default_write
  local env = _G
  local pending = ""
  while true do
    local line = read(pending == "" and "> " or ">> ")
    if line == nil then write("\n"); return end
    local src = pending == "" and line or pending .. "\n" .. line
    local fn, err = load("return " .. src, "=stdin", "t", env) -- an expression prints its values
    if not fn then fn, err = load(src, "=stdin", "t", env) end
    if fn then
      pending = ""
      show(write, pcall(fn))
    elseif err:find("<eof>", 1, true) then
      pending = src -- unfinished statement: keep reading
    else
      pending = ""
      write(err .. "\n")
    end
  end
end
