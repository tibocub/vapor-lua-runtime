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

-- ---- hooks for optional modules (input, net, ...): timers and handle sources, without touching scheduler internals ----
local sources = {} -- fd -> function called from the loop when the handle is readable (a persistent wait, unlike vapor.wait_fd)

function vapor._after(ms, fn) timers[#timers + 1] = {at = now() + ms, fn = fn} end

function vapor._source(fd, fn) sources[fd] = fn end

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
  for fd in pairs(sources) do fds[#fds + 1] = fd end
  if live == 0 or (#timers == 0 and #fds == 0) then return nil end -- nothing left, or nothing can ever wake a task
  local timeout = deadline()
  if max_ms and (not timeout or max_ms < timeout) then timeout = max_ms end
  for _, fd in ipairs(cwait(fds, timeout) or {}) do
    local src, l = sources[fd], fdw[fd]
    fdw[fd] = nil
    if src then src(fd) end
    for _, tok in ipairs(l or {}) do wake(tok, fd) end
  end
  local t, due, keep = now(), {}, {}
  for _, e in ipairs(timers) do if e.at <= t then due[#due + 1] = e else keep[#keep + 1] = e end end
  timers = keep
  table.sort(due, function(a, b) return a.at < b.at end)
  for _, e in ipairs(due) do e.fn() end
  drain()
  if live == 0 or (#timers == 0 and #pending_fds() == 0 and next(sources) == nil) then return nil end
  return deadline() or -1
end

function vapor.run()
  while vapor.step() do end
end

function vapor.failed() return failed end

-- Optional modules appear lazily: vapor.fs is the module "vapor.fs" (loaded on first access); a build without it gives nil.
-- Only registered (compiled-in) modules count, so a typo never searches the file system. `alias` keeps older stable names.
local alias = {size = {"term", "console_size"}}
setmetatable(vapor, {__index = function(t, k)
  local a = alias[k]
  local name = "vapor." .. (a and a[1] or k)
  if type(k) ~= "string" or not package.preload[name] then return nil end
  local v = require(name)
  if a then v = v[a[2]] end
  rawset(t, k, v)
  return v
end})
