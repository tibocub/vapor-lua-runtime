-- socket.url: LuaSocket's URL parsing/building (RFC 3986 subset, same API, pure Lua).
local string, table, base = string, table, _G
local M = {_VERSION = "URL 1.0.3"}

function M.escape(s)
  return (string.gsub(s, "([^A-Za-z0-9_])", function(c) return string.format("%%%02x", string.byte(c)) end))
end

local function make_set(t)
  local s = {}
  for _, v in base.ipairs(t) do s[v] = 1 end
  return s
end

local segment_set = make_set{"-", "_", ".", "!", "~", "*", "'", "(", ")", ":", "@", "&", "=", "+", "$", ","}

local function protect_segment(s)
  return string.gsub(s, "([^A-Za-z0-9_])", function(c)
    if segment_set[c] then return c else return string.format("%%%02X", string.byte(c)) end
  end)
end

function M.unescape(s)
  return (string.gsub(s, "%%(%x%x)", function(hex) return string.char(base.tonumber(hex, 16)) end))
end

local function absolute_path(base_path, relative_path)
  if string.sub(relative_path, 1, 1) == "/" then return relative_path end
  base_path = string.gsub(base_path, "[^/]*$", "")
  local path = base_path .. relative_path
  path = string.gsub(path, "([^/]*%./)", function(s) if s ~= "./" then return s end end)
  path = string.gsub(path, "/%.$", "/")
  local reduced
  while reduced ~= path do
    reduced = path
    path = string.gsub(reduced, "([^/]*/%.%./)", function(s) if s ~= "../../" then return "" end end)
  end
  path = string.gsub(reduced, "([^/]*/%.%.)$", function(s) if s ~= "../.." then return "" end end)
  return path
end

function M.parse(url, default)
  local parsed = {}
  for i, v in base.pairs(default or parsed) do parsed[i] = v end
  if not url or url == "" then return nil, "invalid url" end
  url = string.gsub(url, "#(.*)$", function(f) parsed.fragment = f; return "" end)
  url = string.gsub(url, "^([%w][%w%+%-%.]*)%:", function(s) parsed.scheme = s; return "" end)
  url = string.gsub(url, "^//([^/]*)", function(n) parsed.authority = n; return "" end)
  url = string.gsub(url, "%?(.*)", function(q) parsed.query = q; return "" end)
  url = string.gsub(url, "%;(.*)", function(p) parsed.params = p; return "" end)
  if url ~= "" then parsed.path = url end
  local authority = parsed.authority
  if not authority then return parsed end
  authority = string.gsub(authority, "^([^@]*)@", function(u) parsed.userinfo = u; return "" end)
  authority = string.gsub(authority, ":([^:%]]*)$", function(p) parsed.port = p; return "" end)
  if authority ~= "" then parsed.host = string.match(authority, "^%[(.+)%]$") or authority end
  local userinfo = parsed.userinfo
  if not userinfo then return parsed end
  userinfo = string.gsub(userinfo, ":([^:]*)$", function(p) parsed.password = p; return "" end)
  parsed.user = userinfo
  return parsed
end

function M.build(parsed)
  local url = parsed.path or ""
  if parsed.params then url = url .. ";" .. parsed.params end
  if parsed.query then url = url .. "?" .. parsed.query end
  local authority = parsed.authority
  if parsed.host then
    authority = parsed.host
    if string.find(authority, ":", 1, true) then authority = "[" .. authority .. "]" end
    if parsed.port then authority = authority .. ":" .. base.tostring(parsed.port) end
    local userinfo = parsed.userinfo
    if parsed.user then
      userinfo = parsed.user
      if parsed.password then userinfo = userinfo .. ":" .. parsed.password end
    end
    if userinfo then authority = userinfo .. "@" .. authority end
  end
  if authority then url = "//" .. authority .. url end
  if parsed.scheme then url = parsed.scheme .. ":" .. url end
  if parsed.fragment then url = url .. "#" .. parsed.fragment end
  return url
end

function M.absolute(base_url, relative_url)
  local base_parsed
  if base.type(base_url) == "table" then
    base_parsed = base_url
    base_url = M.build(base_parsed)
  else
    base_parsed = M.parse(base_url)
  end
  local result
  local relative_parsed = M.parse(relative_url)
  if not base_parsed then result = relative_url
  elseif not relative_parsed then result = base_url
  elseif relative_parsed.scheme then result = relative_url
  else
    relative_parsed.scheme = base_parsed.scheme
    if not relative_parsed.authority then
      relative_parsed.authority = base_parsed.authority
      if not relative_parsed.path then
        relative_parsed.path = base_parsed.path
        if not relative_parsed.params then
          relative_parsed.params = base_parsed.params
          if not relative_parsed.query then relative_parsed.query = base_parsed.query end
        end
      else
        relative_parsed.path = absolute_path(base_parsed.path or "", relative_parsed.path)
      end
    end
    result = M.build(relative_parsed)
  end
  return result
end

function M.parse_path(path)
  local parsed = {}
  path = path or ""
  string.gsub(path, "([^/]+)", function(s) table.insert(parsed, s) end)
  for i = 1, #parsed do parsed[i] = M.unescape(parsed[i]) end
  if string.sub(path, 1, 1) == "/" then parsed.is_absolute = 1 end
  if string.sub(path, -1, -1) == "/" then parsed.is_directory = 1 end
  return parsed
end

function M.build_path(parsed, unsafe)
  local path = ""
  local n = #parsed
  if unsafe then
    for i = 1, n - 1 do path = path .. parsed[i]; path = path .. "/" end
    if n > 0 then
      path = path .. parsed[n]
      if parsed.is_directory then path = path .. "/" end
    end
  else
    for i = 1, n - 1 do path = path .. protect_segment(parsed[i]); path = path .. "/" end
    if n > 0 then
      path = path .. protect_segment(parsed[n])
      if parsed.is_directory then path = path .. "/" end
    end
  end
  if parsed.is_absolute then path = "/" .. path end
  return path
end

return M
