-- vapor.input: keys, chars, mouse and resize events from the console (module "vapor.input", needs "vapor.term").
-- vapor.input(true | {mouse = 0|1|2}) puts the console in raw mode and delivers events to vapor.pull:
--   "char", text            "key", name, mods (1 shift, 2 alt, 4 ctrl)      "mouse", action, button, x, y, mods
--   "resize", cols, rows    "quit" when the input ends. Coordinates are 1-based. vapor.input(false) restores the console.
-- While on, the console belongs to the events: do not also read it with io.read / vapor.wait_fd(0).
local vapor = vapor
local term = require("vapor.term")
local on, lastc, lastr, guard, rawlevel

local function feed(list) for _, e in ipairs(list) do vapor.push(table.unpack(e)) end end

local input

local function pump()
  local bytes = term.console_read(256)
  if bytes == nil then input(false); vapor.push("quit"); return end
  if #bytes > 0 then feed(term.decode(bytes)) end
  if term.decode_pending() then -- a lone ESC (or the start of a sequence): wait a moment for the rest
    vapor._after(25, function() if term.decode_pending() then feed(term.decode_flush()) end end)
  end
end

local function poll_size() -- shortcut: polled every 250 ms (no SIGWINCH in the platform interface); upgrade with a size-change handle
  if not on then return end
  local c, r = term.console_size()
  if c and (c ~= lastc or r ~= lastr) then
    vapor.push("resize", c, r) -- also when the size was unknown at start and just became known
    lastc, lastr = c, r
  end
  vapor._after(250, poll_size)
end

function input(opts)
  if opts then
    local mouse = type(opts) == "table" and opts.mouse or 0
    local level = mouse > 0 and 2 or 1
    if on and level ~= rawlevel then term.console_raw(level); rawlevel = level end
    if not on then
      term.console_raw(level)
      rawlevel = level
      guard = setmetatable({}, {__gc = function() input(false) end}) -- restore the console even on os.exit
      on = true
      lastc, lastr = term.console_size()
      vapor._source(0, pump)
      vapor._after(250, poll_size)
    end
    io.stdout:write(mouse >= 2 and "\27[?1003h\27[?1006h" or mouse == 1 and "\27[?1002h\27[?1000h\27[?1006h" or "")
    io.stdout:flush()
  elseif on then
    on = false
    vapor._source(0, nil)
    io.stdout:write("\27[?1006l\27[?1003l\27[?1002l\27[?1000l")
    io.stdout:flush()
    term.console_raw(false)
  end
end

return input
