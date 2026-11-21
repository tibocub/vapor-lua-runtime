-- run by tests/pty/run.py inside a pseudo terminal: prints every event as one line until "q" is typed
-- usage: events.lua [mouse level 0|1|2]  (1 = clicks and drags, 2 = also hover; the pty test uses 1)
vapor.input({mouse = tonumber(arg and arg[1]) or 1})
while true do
  local ev = {vapor.pull(5)}
  if ev[1] == nil then print("timeout"); break end
  print("EV " .. table.concat(ev, ","))
  if ev[1] == "char" and ev[2] == "q" then break end
end
vapor.input(false)
print("DONE")
