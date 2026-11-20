# Source list shared by every build (host Makefile, NuttX app Makefile, emscripten). A target adds its backend
# (src/platform_<target>.c) and flags. VLR_ROOT is the repo root. Generated files (build/*.c) come from the rules
# in the host Makefile / the target's equivalent: embed tool for lua/*.lua, mkmodules for modules.conf.
VLR_ROOT      ?= .
VLR_CORE_SRC   = src/vlr.c src/vtinput.c
VLR_MAIN_SRC   = src/main.c
VLR_LUA_EMBED  = compat sched
VLR_LUA_SRC    = $(filter-out lua.c luac.c,$(notdir $(wildcard $(VLR_ROOT)/third_party/lua/*.c)))
VLR_INCLUDES   = include third_party/lua
