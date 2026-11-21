-- vapor.tls: TLS client over a vapor.net stream. The certificate chain and the host name are always verified (there is no way to skip that).
--   tls.connect(host, port, opts) -> stream (like vapor.net.connect), or nil, err
--   tls.wrap(sock, host, opts)    -> stream over an already connected socket stream
--   opts.ca = PEM text or anchors | opts.cafile = path of a PEM bundle | opts.timeout   (default: $VLR_CA_FILE, $SSL_CERT_FILE, then the system bundle)
--   tls.anchors(pem) -> trust anchors to reuse for many connections
-- The engine (vapor.tlsraw) does no I/O; this file moves its bytes, so waiting stays in the scheduler. The stream is the one from vapor.stream.
-- shortcut: a peer that closes the transport without close_notify reads as end of data (truncation is not told apart). Where the system has no bundle file the roots come from
-- the Windows certificate store (ROOT store) plus the built-in Mozilla list (vapor.cacerts, tools/mkcacerts.sh), read once per process.
local raw = require("vapor.tlsraw")
local stream = require("vapor.stream")
local M = {}

M.anchors = raw.anchors

local default_files = {"/etc/ssl/certs/ca-certificates.crt", "/etc/pki/tls/certs/ca-bundle.crt", "/etc/ssl/ca-bundle.pem",
                       "/etc/ssl/cert.pem", "/usr/local/share/certs/ca-root-nss.crt"}
local cache = {}

local function slurp(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function load_anchors(opts)
  local ca = opts.ca
  if type(ca) == "userdata" then return ca end
  local key = ca or opts.cafile
  if not key then
    local candidates = {}
    for _, p in ipairs({os.getenv("VLR_CA_FILE") or "", os.getenv("SSL_CERT_FILE") or ""}) do candidates[#candidates + 1] = p end
    for _, p in ipairs(default_files) do candidates[#candidates + 1] = p end
    for _, p in ipairs(candidates) do
      if p ~= "" and slurp(p) then key = p; break end
    end
  end
  if not key and not ca then
    -- no bundle file: the system's certificate store (Windows) plus the built-in Mozilla roots (vapor.cacerts, if this build has them). Windows keeps only some roots
    -- in its store and fetches the others when a chain needs them, so the store alone is not enough for a client that does not build chains through the OS.
    if not cache.system then
      local parts = {}
      local sys = raw.system_roots()
      if sys then parts[#parts + 1] = sys end
      local ok, builtin = pcall(require, "vapor.cacerts")
      if ok then parts[#parts + 1] = builtin end
      if #parts > 0 then
        local a, err = raw.anchors(table.concat(parts, "\n"))
        if not a then return nil, err end
        cache.system = a
      end
    end
    if cache.system then return cache.system end
  end
  if not key then return nil, "no trusted certificates: pass opts.ca (PEM text) or opts.cafile, or set VLR_CA_FILE" end
  if cache[key] then return cache[key] end
  local pem = ca or slurp(key)
  if not pem then return nil, "cannot read " .. key end
  local a, err = raw.anchors(pem)
  if not a then return nil, err end
  cache[key] = a
  return a
end

function M.wrap(sock, host, opts)
  opts = opts or {}
  local anchors, aerr = load_anchors(opts)
  if not anchors then return nil, aerr end
  local e, err = raw.client(anchors, host)
  if not e then return nil, err end
  local s
  local pending = "" -- bytes read from the socket the engine has not taken yet

  local function send_records()
    while e:state() & 2 ~= 0 do
      local d = e:take()
      if not d then break end
      local ok, werr = sock:write(d)
      if not ok then return nil, werr end
    end
    return true
  end

  -- read more records from the peer into the engine
  local function feed()
    if pending == "" then
      sock:settimeout(s and s.timeout or opts.timeout)
      local d, rerr = sock:readsome(4096)
      if not d then return nil, rerr end
      pending = d
    end
    local n = e:put(pending)
    pending = pending:sub(n + 1)
    return true
  end

  local function dead()
    local code, text = e:error()
    if code then return nil, text end
    return nil, "eof"
  end

  local ops = {}
  function ops.read(max)
    while true do
      local ok, werr = send_records()
      if not ok then return nil, werr end
      local st = e:state()
      if st & 16 ~= 0 then return e:recv() end
      if st & 1 ~= 0 then return dead() end
      local fok, ferr = feed()
      if not fok then
        if ferr == "eof" then return nil, "eof" end
        return nil, ferr
      end
    end
  end
  function ops.write(data)
    local left = data
    while left ~= "" do
      local ok, werr = send_records()
      if not ok then return nil, werr end
      local st = e:state()
      if st & 1 ~= 0 then return dead() end
      if st & 8 ~= 0 then
        local n = e:send(left)
        left = left:sub(n + 1)
      else
        local fok, ferr = feed()
        if not fok then return nil, ferr end
      end
    end
    e:flush()
    local ok, werr = send_records()
    if not ok then return nil, werr end
    return #data
  end
  function ops.wait() return true end -- reads and writes above wait on the socket themselves
  function ops.close()
    e:close()
    pcall(send_records)
    sock:close()
  end
  s = stream.wrap(ops)
  s.timeout = opts.timeout

  -- handshake: run the engine until it can take application data (or failed)
  while true do
    local ok, werr = send_records()
    if not ok then sock:close(); return nil, werr end
    local st = e:state()
    if st & 1 ~= 0 then local _, derr = dead(); sock:close(); return nil, derr end
    if st & 8 ~= 0 then break end
    local fok, ferr = feed()
    if not fok then sock:close(); return nil, ferr == "eof" and "connection closed during the TLS handshake" or ferr end
  end
  return s
end

function M.connect(host, port, opts)
  opts = opts or {}
  local sock, err = require("vapor.net").connect(host, port, opts.timeout)
  if not sock then return nil, err end
  return M.wrap(sock, host, opts)
end

return M
