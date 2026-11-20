-- vlr scheduler: cooperative tasks over vapor.wait (one poll primitive) with timers and an event queue.
-- No threads, no callbacks. Everything blocks "inside" a task; the loop in vapor.run does the one real wait.
local vapor = vapor
local now, cwait = vapor.now, vapor.wait
local create, resume, yield, running = coroutine.create, coroutine.resume, coroutine.yield, coroutine.running
local unpack = table.unpack

local ready = {}    -- queue of {co, args...}
local timers = {}   -- {at=ms, fn=function}; shortcut: linear scan, upgrade to a heap past ~100 timers
local fdw = {}      -- fd -> array of tokens (a token is {co=...})
local pullers = {}  -- tokens waiting in vapor.pull
local evq = {}      -- events nobody pulled yet
local waiting = setmetatable({}, {__mode = "k"}) -- co -> the token it is blocked on
local failed = false
local live = 0     -- tasks not yet finished: the loop ends when this reaches 0
local inputmode    -- true while vapor.input() owns the console (events)

local function step(co, ...)
  local ok, err = resume(co, ...)
  if not ok then
    io.stderr:write(debug.traceback(co, tostring(err)), "\n")
    failed = true
  end
  if coroutine.status(co) == "dead" then live = live - 1 end
end

local function wake(tok, ...)
  if waiting[tok.co] ~= tok then return end -- already woken (timeout vs event race)
  waiting[tok.co] = nil
  ready[#ready + 1] = {tok.co, ...}
end

local function block(tok, timeout)
  waiting[tok.co] = tok
  if timeout then
    timers[#timers + 1] = {at = now() + math.floor(timeout * 1000), fn = function() wake(tok, nil, "timeout") end}
  end
  return yield()
end

local function me()
  local co, ismain = running()
  assert(not ismain, "vapor: call this from a task (vapor.spawn / the main script)")
  return {co = co}
end

function vapor.spawn(fn, ...)
  local co = create(fn)
  live = live + 1
  ready[#ready + 1] = {co, ...}
  return co
end

function vapor.sleep(seconds)
  local tok = me()
  waiting[tok.co] = tok
  timers[#timers + 1] = {at = now() + math.floor(seconds * 1000), fn = function() wake(tok) end}
  yield()
end

-- wait until fd is readable: returns fd, or nil,"timeout"
function vapor.wait_fd(fd, timeout)
  local tok = me()
  local l = fdw[fd]
  if not l then l = {}; fdw[fd] = l end
  l[#l + 1] = tok
  return block(tok, timeout)
end

function vapor.push(name, ...)
  for i, tok in ipairs(pullers) do
    if waiting[tok.co] == tok then
      table.remove(pullers, i)
      return wake(tok, name, ...)
    end
  end
  evq[#evq + 1] = {name, ...}
end

-- next event (name, ...) or nil,"timeout"
function vapor.pull(timeout)
  if #evq > 0 then return unpack(table.remove(evq, 1)) end
  local tok = me()
  pullers[#pullers + 1] = tok
  return block(tok, timeout)
end

local timerid = 0
function vapor.timer(seconds)
  timerid = timerid + 1
  local id = timerid
  timers[#timers + 1] = {at = now() + math.floor(seconds * 1000), fn = function() vapor.push("timer", id) end}
  return id
end

-- ---- input events: keys, chars, mouse, resize (terminal consoles; a web page pushes the same events itself) ----
-- vapor.input(true | {mouse = 0|1|2}) puts the console in raw mode and starts delivering events to vapor.pull:
--   "char", text            "key", name, mods (1 shift, 2 alt, 4 ctrl)      "mouse", action, button, x, y, mods
--   "resize", cols, rows    "quit" when the input ends. Coordinates are 1-based. vapor.input(false) restores the console.
-- While on, the console belongs to the events: do not also read it with io.read / vapor.wait_fd(0).
local lastc, lastr, guard

local function feed(list) for _, e in ipairs(list) do vapor.push(unpack(e)) end end

local function pump()
  local bytes = vapor.console_read(256)
  if bytes == nil then vapor.input(false); vapor.push("quit"); return end
  if #bytes > 0 then feed(vapor.decode(bytes)) end
  if vapor.decode_pending() then -- a lone ESC (or the start of a sequence): wait a moment for the rest
    timers[#timers + 1] = {at = now() + 25, fn = function() if vapor.decode_pending() then feed(vapor.decode_flush()) end end}
  end
end

local function poll_size() -- shortcut: polled every 250 ms (no SIGWINCH in the platform interface); upgrade with a size-change handle
  if not inputmode then return end
  local c, r = vapor.console_size()
  if c and (c ~= lastc or r ~= lastr) then
    vapor.push("resize", c, r) -- also when the size was unknown at start and just became known
    lastc, lastr = c, r
  end
  timers[#timers + 1] = {at = now() + 250, fn = poll_size}
end

function vapor.input(opts)
  if opts then
    local mouse = type(opts) == "table" and opts.mouse or 0
    if not inputmode then
      vapor.console_raw(true)
      guard = setmetatable({}, {__gc = function() vapor.input(false) end}) -- restore the console even on os.exit
      inputmode = true
      lastc, lastr = vapor.console_size()
      timers[#timers + 1] = {at = now() + 250, fn = poll_size}
    end
    io.stdout:write(mouse >= 2 and "\27[?1003h\27[?1006h" or mouse == 1 and "\27[?1002h\27[?1000h\27[?1006h" or "")
    io.stdout:flush()
  elseif inputmode then
    inputmode = false
    io.stdout:write("\27[?1006l\27[?1003l\27[?1002l\27[?1000l")
    io.stdout:flush()
    vapor.console_raw(false)
  end
end

vapor.size = vapor.console_size

local function pending_fds()
  local list = {}
  for fd, l in pairs(fdw) do
    local keep = {}
    for _, tok in ipairs(l) do if waiting[tok.co] == tok then keep[#keep + 1] = tok end end
    if #keep == 0 then fdw[fd] = nil else fdw[fd] = keep; list[#list + 1] = fd end
  end
  return list
end

local function drain()
  while #ready > 0 do
    local q = ready
    ready = {}
    for i = 1, #q do step(unpack(q[i])) end
  end
end

local function deadline() -- ms until the earliest timer, or nil
  if #timers == 0 then return nil end
  local first = timers[1].at
  for i = 2, #timers do if timers[i].at < first then first = timers[i].at end end
  return math.max(0, first - now())
end

-- One turn of the loop, for a host that owns the main loop (browser, GUI toolkit): runs ready tasks, waits at most
-- max_ms (nil = until the next timer/fd), wakes what is due, runs ready tasks again.
-- Returns nil when nothing is left to do, else ms until the next timer (-1 if only waiting on fds).
function vapor.step(max_ms)
  drain()
  local fds = pending_fds()
  if inputmode then fds[#fds + 1] = 0 end
  if live == 0 or (#timers == 0 and #fds == 0) then return nil end -- nothing left, or nothing can ever wake a task
  local timeout = deadline()
  if max_ms and (not timeout or max_ms < timeout) then timeout = max_ms end
  for _, fd in ipairs(cwait(fds, timeout) or {}) do
    if fd == 0 and inputmode then pump()
    else
      local l = fdw[fd]
      fdw[fd] = nil
      for _, tok in ipairs(l or {}) do wake(tok, fd) end
    end
  end
  local t, due, keep = now(), {}, {}
  for _, e in ipairs(timers) do if e.at <= t then due[#due + 1] = e else keep[#keep + 1] = e end end
  timers = keep
  table.sort(due, function(a, b) return a.at < b.at end)
  for _, e in ipairs(due) do e.fn() end
  drain()
  if live == 0 or (#timers == 0 and #pending_fds() == 0 and not inputmode) then return nil end
  return deadline() or -1
end

function vapor.run()
  while vapor.step() do end
end

function vapor.failed() return failed end
