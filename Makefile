# vlr host build (POSIX). Other targets bring their own build and backend; the shared source list is sources.mk.
include sources.mk
CC      ?= cc
CFLAGS  ?= -O2
CFLAGS  += -std=c99 -Wall -Iinclude -Ithird_party/lua
EXT     ?= ..
LUASRC   = $(addprefix third_party/lua/,$(VLR_LUA_SRC))

# modules.conf: sources (and -D flags) after the first two columns
MODULES ?=
GEN     ?= build
MODTOK  := $(shell sh tools/modsrc.sh modules.conf $(EXT) $(MODULES))
MODSRC   = $(filter-out -%,$(MODTOK))
MODFLAGS = $(filter -%,$(MODTOK))

TARGET  ?= posix
RUN     ?=
OBJDIR   = build/$(TARGET)
ifeq ($(TARGET),win32)
CC       = x86_64-w64-mingw32-gcc
EXE      = .exe
PLATSRC  = src/platform_win32.c
LUADEF   =
LIBS     = -static
else ifneq ($(filter wasm web,$(TARGET)),)
# needs `source ~/Code/emsdk/emsdk_env.sh`; this build is for Node (NODERAWFS), the browser build is later
CC       = emcc
EXE      = .js
RUN      = node
PLATSRC  = src/platform_wasm.c src/platform_posix.c
LUADEF   = -DLUA_USE_POSIX
ifeq ($(TARGET),web)
# browser (and Node, for the test harness): an ES module factory createVlr(); files live in MEMFS (web/vlr-glue.js)
OUT      = web/vlr.js
LIBS     = -sENVIRONMENT=web,node -sMODULARIZE=1 -sEXPORT_ES6=1 -sEXPORT_NAME=createVlr -sINVOKE_RUN=0 \
           -sEXPORTED_RUNTIME_METHODS=FS,callMain,ccall -sALLOW_MEMORY_GROWTH=1 -sEXIT_RUNTIME=0 -sFORCE_FILESYSTEM=1
else
LIBS     = -sNODERAWFS=1 -sENVIRONMENT=node -sALLOW_MEMORY_GROWTH=1 -sEXIT_RUNTIME=1
endif
else
EXE      =
PLATSRC  = src/platform_posix.c
LUADEF   = -DLUA_USE_POSIX
LIBS     = -lm
ifneq ($(DYNAMIC),)
# optional: require() can also load .so modules (package.cpath); the executable exports the Lua API for them
LUADEF  += -DLUA_USE_DLOPEN
LIBS    += -ldl -Wl,-E
CFLAGS  += -DVLR_DLOPEN=1
endif
endif

SRCS     = $(LUASRC) $(VLR_CORE_SRC) $(VLR_MAIN_SRC) $(PLATSRC) $(MODSRC) \
           $(addprefix $(GEN)/,$(addsuffix .c,$(VLR_LUA_EMBED))) $(GEN)/vlr_modules.c
OBJ      = $(addprefix $(OBJDIR)/,$(notdir $(SRCS:.c=.o)))
VPATH    = src third_party/lua $(sort $(dir $(MODSRC)))

OUT     ?= vlr$(EXE)

$(OUT): $(OBJ)
	@mkdir -p $(dir $(OUT))
	$(CC) $(LDFLAGS) -o $@ $(OBJ) $(LIBS)

$(OBJDIR)/%.o: %.c
	@mkdir -p $(OBJDIR)
	$(CC) $(CFLAGS) -c -o $@ $<

$(OBJDIR)/vlr.o: CFLAGS += $(LUADEF) # vlr_lua_system must encode the status the way this Lua build decodes it

$(OBJDIR)/%.o: $(GEN)/%.c
	@mkdir -p $(OBJDIR)
	$(CC) $(CFLAGS) -c -o $@ $<

$(addprefix $(OBJDIR)/,$(notdir $(LUASRC:.c=.o))): CFLAGS += $(LUADEF) -include vlr_lua.h
# third-party module sources are built as their authors expect (no -std, warnings off); our own (./...) keep the strict flags
$(addprefix $(OBJDIR)/,$(notdir $(filter-out ./%,$(MODSRC:.c=.o)))): CFLAGS := $(filter-out -std=c99,$(CFLAGS)) -D_GNU_SOURCE -w $(MODFLAGS)
$(OBJDIR)/platform_posix.o: CFLAGS := $(filter-out -std=c99,$(CFLAGS))
ifneq ($(filter wasm web,$(TARGET)),)
$(OBJDIR)/platform_posix.o: CFLAGS += -DVLR_POSIX_NO_WAIT
endif

build/embed: tools/embed.c
	@mkdir -p build
	$(CC) -o $@ $<
build/mkmodules: tools/mkmodules.c
	@mkdir -p build
	$(CC) -o $@ $<
# the module list is an input too: a stamp that changes when MODULES does regenerates the registry
build/modules.stamp: FORCE
	@mkdir -p build
	@echo '$(MODULES)' | cmp -s - $@ || echo '$(MODULES)' > $@
FORCE:
$(GEN)/vlr_modules.c: modules.conf build/mkmodules build/modules.stamp
	@mkdir -p $(GEN)
	build/mkmodules modules.conf $(MODULES) > $@
$(GEN)/%.c: lua/%.lua build/embed
	@mkdir -p $(GEN)
	build/embed $* $< > $@

# generated C (embedded Lua, module registry) only; for builds driven by another build system
gen: $(addprefix $(GEN)/,$(addsuffix .c,$(VLR_LUA_EMBED))) $(GEN)/vlr_modules.c

test: $(OUT)
	VLR="$(RUN) ./vlr$(EXE)" sh tests/run.sh

check: vlr
	sh tools/check.sh

clean:
	rm -rf vlr vlr.exe vlr.js vlr.wasm build
.PHONY: test check clean gen
