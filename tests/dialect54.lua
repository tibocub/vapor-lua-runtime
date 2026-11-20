--! dialect 5.4
assert(vapor.dialect == "5.4")
assert(unpack == nil and setfenv == nil and loadstring == nil)
assert(tostring(10 / 2) == "5.0")
assert(7 // 2 == 3 and (6 & 3) == 2)
