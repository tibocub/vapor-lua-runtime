-- vapor.stream: one file-like object over any non-blocking byte source (sockets now; pipes, files, the console later).
-- A backend provides ops: read(max) -> data | nil,"again" | nil,"eof" | nil,err ; write(data) -> n | nil,"again" | nil,err ;
-- wait(mode, timeout) -> true | nil,"timeout" (mode "r" or "w") ; close(). Methods are used from tasks and block only the task.
--   s:read(fmt)  fmt: number = that many bytes, "l" a line without the newline, "L" with it, "a" everything; leading "*" accepted (5.1)
--   s:readsome(max) at least one byte as soon as any arrives (streaming), nil at end        s:write(...)   s:lines()   s:chunks(max)
--   s:settimeout(seconds|nil)   s:close()   s:on(event, fn): "data" (chunk), "end", "error" (msg), "close" -- Node-style, a task reads for you
--   stream.pipe(src, dst): copies until src ends, with the backpressure of write
local vapor = vapor
local M = {}
local Stream = {}
Stream.__index = Stream

function M.wrap(ops, extra)
  local s = setmetatable({ops = ops, buf = "", timeout = nil, closed = false}, Stream)
  if extra then for k, v in pairs(extra) do s[k] = v end end
  return s
end

function Stream:settimeout(t) self.timeout = t; return self end
-- limits for untrusted peers (servers): s:setdeadline(ms) = an absolute vapor.now() time after which any wait fails with "timeout" (nil clears it, so one
-- slow trickle cannot outlive it however often a byte arrives); s:setmaxline(n) = a line longer than n bytes fails with "line too long" instead of growing the buffer
function Stream:setdeadline(at) self.deadline = at; return self end
function Stream:setmaxline(n) self.maxline = n; return self end

-- more bytes into the buffer: true, or nil,"eof" / nil,"timeout" / nil,err
local function fill(self)
  while true do
    if self.closed then return nil, "closed" end
    local d, e = self.ops.read(4096)
    if d then self.buf = self.buf .. d; return true end
    if e ~= "again" then return nil, e end
    local t = self.timeout
    if self.deadline then
      local left = (self.deadline - vapor.now()) / 1000
      if left <= 0 then return nil, "timeout" end
      if t == nil or left < t then t = left end
    end
    local ok, werr = self.ops.wait("r", t)
    if not ok then return nil, werr end
  end
end

function Stream:read(fmt)
  fmt = fmt == nil and "l" or fmt
  if type(fmt) == "string" then fmt = fmt:gsub("^%*", "") end
  if type(fmt) == "number" then
    while #self.buf < fmt do
      local ok, e = fill(self)
      if not ok then
        if e == "eof" and #self.buf > 0 then break end
        return nil, e
      end
    end
    local out = self.buf:sub(1, fmt)
    self.buf = self.buf:sub(fmt + 1)
    return out
  elseif fmt == "l" or fmt == "L" then
    while true do
      local i = self.buf:find("\n", 1, true)
      if i then
        if self.maxline and i - 1 > self.maxline then return nil, "line too long" end
        local line = self.buf:sub(1, fmt == "L" and i or i - 1)
        self.buf = self.buf:sub(i + 1)
        return line
      end
      if self.maxline and #self.buf > self.maxline then return nil, "line too long" end
      local ok, e = fill(self)
      if not ok then
        if e == "eof" and #self.buf > 0 then local rest = self.buf; self.buf = ""; return rest end
        return nil, e
      end
    end
  elseif fmt == "a" then
    while true do
      local ok, e = fill(self)
      if not ok then
        if e == "eof" then local all = self.buf; self.buf = ""; return all end
        return nil, e
      end
    end
  end
  error("bad read format " .. tostring(fmt), 2)
end

function Stream:readsome(max)
  if #self.buf == 0 then
    local ok, e = fill(self)
    if not ok then return nil, e end
  end
  max = max or #self.buf
  local out = self.buf:sub(1, max)
  self.buf = self.buf:sub(max + 1)
  return out
end

function Stream:write(...)
  local data = table.concat({...})
  local sent = 0
  while sent < #data do
    if self.closed then return nil, "closed" end
    local n, e = self.ops.write(data:sub(sent + 1))
    if n then
      sent = sent + n
    elseif e == "again" then
      local ok, werr = self.ops.wait("w", self.timeout)
      if not ok then return nil, werr, sent end
    else
      return nil, e, sent
    end
  end
  return self
end

function Stream:lines(fmt)
  return function() return self:read(fmt or "l") end
end

function Stream:chunks(max)
  return function() return self:readsome(max or 4096) end
end

function Stream:close()
  if self.closed then return true end
  self.closed = true
  self.ops.close()
  if self.handlers and self.handlers.close then self.handlers.close() end
  return true
end

-- Node-style events on top of the same stream: the first on() starts a task that reads until the end
function Stream:on(event, fn)
  local h = self.handlers
  if not h then
    h = {}
    self.handlers = h
    vapor.spawn(function()
      while not self.closed do
        local d, e = self:readsome(4096)
        if d then
          if h.data then h.data(d) end
        else
          if e == "eof" or e == "closed" then if h["end"] then h["end"]() end
          elseif h.error then h.error(e) end
          break
        end
      end
      self:close()
    end)
  end
  h[event] = fn
  return self
end

function M.pipe(src, dst)
  for chunk in src:chunks() do
    local ok, e = dst:write(chunk)
    if not ok then return nil, e end
  end
  return true
end

return M
