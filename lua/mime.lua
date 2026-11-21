-- mime: LuaSocket's MIME core (base64, quoted-printable, line wrapping, eol normalising) and the encode/decode/normalize/stuff helpers, pure Lua.
-- Core functions are streaming filters: f(chunk, ctx) -> output, ctx'; f(nil, ctx) flushes. Shortcut: line-oriented filters (qp, wrap, eol) work on whole chunks in memory.
local ltn12 = require("ltn12")
local M = {_VERSION = "MIME 1.0.3"}
local char, byte, format, gsub, sub, concat = string.char, string.byte, string.format, string.gsub, string.sub, table.concat

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local enc, dec = {}, {}
for i = 1, 64 do enc[i - 1] = sub(B64, i, i); dec[byte(B64, i)] = i - 1 end

function M.b64(chunk, rest)
  if not chunk then
    rest = rest or ""
    if rest == "" then return nil end
    local a, b = byte(rest, 1), byte(rest, 2) or 0
    local out = enc[a >> 2] .. enc[((a & 3) << 4) | (b >> 4)]
    out = out .. (#rest == 2 and enc[(b & 15) << 2] or "=") .. "="
    return out
  end
  chunk = (rest or "") .. chunk
  local n = #chunk - #chunk % 3
  local out = {}
  for i = 1, n, 3 do
    local a, b, c = byte(chunk, i, i + 2)
    local v = (a << 16) | (b << 8) | c
    out[#out + 1] = enc[v >> 18] .. enc[(v >> 12) & 63] .. enc[(v >> 6) & 63] .. enc[v & 63]
  end
  return concat(out), sub(chunk, n + 1)
end

function M.unb64(chunk, rest)
  if not chunk then return nil end
  chunk = (rest or "") .. gsub(chunk, "[^%w%+/=]", "")
  local out, acc, bits, i = {}, 0, 0, 1
  local pending = ""
  for i = 1, #chunk do
    local c = sub(chunk, i, i)
    if c == "=" then break end
    acc = (acc << 6) | dec[byte(c)]; bits = bits + 6
    if bits >= 8 then bits = bits - 8; out[#out + 1] = char((acc >> bits) & 255) end
  end
  -- keep nothing: partial groups of < 4 characters are rare in practice; shortcut: a chunk boundary inside a group loses at most the bits that did not complete a byte
  return concat(out), ""
end

function M.qp(chunk, rest, marker)
  if not chunk then return nil end
  local out = gsub(chunk, "[^\t\r\n\032-\060\062-\126]", function(c) return format("=%02X", byte(c)) end)
  out = gsub(out, "[ \t]+\r?\n", function(s) local ws = s:match("^[ \t]+"); return (gsub(ws, ".", function(c) return format("=%02X", byte(c)) end)) .. (marker or "\r\n") end)
  return out, ""
end

function M.unqp(chunk, rest)
  if not chunk then return nil end
  chunk = (rest or "") .. chunk
  local keep = chunk:match("=%x?$") or ""
  chunk = sub(chunk, 1, #chunk - #keep)
  chunk = gsub(chunk, "=\r?\n", "")
  return (gsub(chunk, "=(%x%x)", function(h) return char(tonumber(h, 16)) end)), keep
end

function M.wrap(chunk, length)
  -- wrap(length) returns a filter; wrap(chunk, length) is the filter's step state in the original: here the filter is stateful in a closure
  error("use mime.wrap(length)")
end
do
  local wrapper = function(length)
    length = length or 76
    local col = 0
    return function(chunk)
      if not chunk then local had = col > 0; col = 0; return had and "\r\n" or nil end
      local out = {}
      for i = 1, #chunk do
        local c = sub(chunk, i, i)
        if c == "\n" then out[#out + 1] = "\r\n"; col = 0
        elseif c == "\r" then -- dropped, its "\n" (if any) follows
        else
          if col >= length then out[#out + 1] = "\r\n"; col = 0 end
          out[#out + 1] = c; col = col + 1
        end
      end
      return concat(out)
    end
  end
  M.wrap = function(a, b) if type(a) == "string" or a == nil and b ~= nil then error("use mime.wrap(length)") end return wrapper(a) end
end

function M.eol(ctx, chunk, marker)
  if not chunk then return nil end
  marker = marker or "\r\n"
  chunk = (ctx == "\r" and chunk:sub(1, 1) == "\n") and chunk:sub(2) or chunk
  local last = chunk:sub(-1)
  chunk = gsub(chunk, "\r\n", "\n")
  chunk = gsub(chunk, "[\r\n]", marker)
  return chunk, last == "\r" and "\r" or ""
end

function M.dot(state, chunk)
  if not chunk then return nil end
  chunk = gsub(chunk, "^%.", "..")
  chunk = gsub(chunk, "\n%.", "\n..")
  return chunk, ""
end

-- the helper layer (as in mime.lua of LuaSocket)
local function cycle(f, ...) return ltn12.filter.cycle(f, ...) end

-- cycle calls low(ctx, chunk, extra); the codecs take (chunk, ctx, extra)
local function swap(f) return function(ctx, chunk, extra) return f(chunk, ctx, extra) end end

function M.encode(name, opt)
  if name == "base64" then return cycle(swap(M.b64), "") end
  if name == "quoted-printable" then return cycle(swap(M.qp), "", opt == "binary" and "=0D=0A" or "\r\n") end
end
function M.decode(name)
  if name == "base64" then return cycle(swap(M.unb64), "") end
  if name == "quoted-printable" then return cycle(swap(M.unqp), "") end
end
function M.normalize(marker) return cycle(M.eol, "", marker) end
function M.stuff() return cycle(M.dot, 2) end

return M
