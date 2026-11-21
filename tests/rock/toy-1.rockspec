package = "toy"
version = "1-1"
source = {url = "none"}
build = {
  type = "builtin",
  modules = {
    ["toy.core"] = {sources = {"src/core.c", "src/aux.c"}, defines = {"TOY_FAST", "LEVEL=2"}, incdirs = {"src"}},
    ["toy-v2.single"] = "src/single.c",
    ["utf8"] = "src/u.c",
    ["toy.util"] = "lua/util.lua",
  },
}
