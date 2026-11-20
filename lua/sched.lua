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

local function step(co, ...)
  local ok, err = resume(co, ...)
  if not ok then
    io.stderr:write(debug.traceback(co, tostring(err)), "\n")
    failed = true
  end
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

local function pending_fds()
  local list = {}
  for fd, l in pairs(fdw) do
    local keep = {}
    for _, tok in ipairs(l) do if waiting[tok.co] == tok then keep[#keep + 1] = tok end end
    if #keep == 0 then fdw[fd] = nil else fdw[fd] = keep; list[#list + 1] = fd end
  end
  return list
end

function vapor.run()
  while true do
    while #ready > 0 do
      local q = ready
      ready = {}
      for i = 1, #q do step(unpack(q[i])) end
    end
    local fds = pending_fds()
    if #timers == 0 and #fds == 0 then break end -- nothing can ever wake a task
    local timeout
    if #timers > 0 then
      local first = timers[1].at
      for i = 2, #timers do if timers[i].at < first then first = timers[i].at end end
      timeout = math.max(0, first - now())
    end
    for _, fd in ipairs(cwait(fds, timeout) or {}) do
      local l = fdw[fd]
      fdw[fd] = nil
      for _, tok in ipairs(l or {}) do wake(tok, fd) end
    end
    local t, due, keep = now(), {}, {}
    for _, e in ipairs(timers) do if e.at <= t then due[#due + 1] = e else keep[#keep + 1] = e end end
    timers = keep
    table.sort(due, function(a, b) return a.at < b.at end)
    for _, e in ipairs(due) do e.fn() end
  end
end

-- runs fn as the first task, then everything it started; exit code 1 if any task raised
function vapor.main(fn, ...)
  vapor.spawn(fn, ...)
  vapor.run()
  return failed and 1 or 0
end
