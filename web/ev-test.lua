vapor.input(true)
while true do
  local ev = {vapor.pull(3)}
  if ev[1] == nil then print("timeout") break end
  print("EV " .. table.concat(ev, ","))
  if ev[1] == "char" and ev[2] == "q" then break end
end
