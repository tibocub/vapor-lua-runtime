--! dialect 5.4
-- the 5.4 dialect keeps Lua 5.4's strictness: no float truncation, no module(), no bit32 global
assert(not pcall(string.rep, "a", 2.5))
assert(module == nil and rawget(_G, "math").log10 == nil)
print("ok")
