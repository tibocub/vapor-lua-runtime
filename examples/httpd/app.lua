-- A tiny notes service on std.httpd: a one-page UI, GET /api/info, GET/POST /api/notes, DELETE /api/notes/ID. In memory, no dependencies.
local M = {}

local PAGE = [[<!doctype html><meta charset=utf-8><title>vlr notes</title>
<style>body{font:16px system-ui;max-width:36em;margin:2em auto;padding:0 1em}li{margin:.3em 0}button{margin-left:.5em}</style>
<h1>vlr notes</h1><form id=f><input id=t size=30 maxlength=200 autofocus> <button>add</button></form><ul id=l></ul><p id=i></p>
<script>
async function load(){const n=await (await fetch('/api/notes')).json();l.innerHTML='';for(const x of n){const li=document.createElement('li');li.textContent=x.text;
const b=document.createElement('button');b.textContent='x';b.onclick=async()=>{await fetch('/api/notes/'+x.id,{method:'DELETE'});load()};li.append(b);l.append(li)}
const i=await (await fetch('/api/info')).json();document.getElementById('i').textContent=i.runtime+' on '+i.platform}
f.onsubmit=async e=>{e.preventDefault();if(!t.value)return;await fetch('/api/notes',{method:'POST',body:t.value});t.value='';load()};load()
</script>]]

local function jstr(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    return ({['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t'})[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end

-- opts.max_notes (default 100), opts.max_note_len (default 200)
function M.new(opts)
  opts = opts or {}
  local max_notes, max_len = opts.max_notes or 100, opts.max_note_len or 200
  local notes, nextid, started = {}, 1, vapor.now()
  local JSON = {["Content-Type"] = "application/json"}

  return function(req, res)
    local p, m = req.path, req.method
    if p == "/" then
      if m ~= "GET" and m ~= "HEAD" then return 405, nil, {Allow = "GET, HEAD"} end
      return 200, PAGE, {["Content-Type"] = "text/html; charset=utf-8", ["Content-Security-Policy"] = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'"}
    elseif p == "/api/info" then
      return 200, ('{"runtime":%s,"platform":%s,"uptime_s":%d,"notes":%d,"lua_kb":%d}'):format(
        jstr("vlr " .. vapor.version), jstr(vapor.platform), (vapor.now() - started) // 1000, #notes, math.floor(collectgarbage("count"))), JSON
    elseif p == "/api/notes" then
      if m == "GET" then
        local out = {}
        for i, n in ipairs(notes) do out[i] = ('{"id":%d,"text":%s}'):format(n.id, jstr(n.text)) end
        return 200, "[" .. table.concat(out, ",") .. "]", JSON
      elseif m == "POST" then
        local text = req.body
        if #text == 0 or #text > max_len or text:find("%z") then return 400, "note must be 1.." .. max_len .. " bytes of text\n" end
        if #notes >= max_notes then return 507, "too many notes\n" end
        local n = {id = nextid, text = text}
        nextid = nextid + 1
        notes[#notes + 1] = n
        return 201, ('{"id":%d}'):format(n.id), {["Content-Type"] = "application/json", Location = "/api/notes/" .. n.id}
      end
      return 405, nil, {Allow = "GET, POST"}
    end
    local id = p:match("^/api/notes/(%d+)$")
    if id then
      if m ~= "DELETE" then return 405, nil, {Allow = "DELETE"} end
      id = tonumber(id)
      for i, n in ipairs(notes) do
        if n.id == id then table.remove(notes, i); return 204 end
      end
      return 404
    end
    return 404
  end
end

return M
