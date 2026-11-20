-- run by tests/pty/run.py inside a pseudo terminal: prints every event as one line until "q" is typed
vapor.input({mouse = 1})
while true do
  local ev = {vapor.pull(5)}
  if ev[1] == nil then print("timeout"); break end
  print("EV " .. table.concat(ev, ","))
  if ev[1] == "char" and ev[2] == "q" then break end
end
vapor.input(false)
print("DONE")
