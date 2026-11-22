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
TARGET  ?= posix
# the target's half of a module (@PLAT@ in modules.conf): sockets are posix or win32; wasm has none
VLR_PLAT ?= $(if $(filter win32,$(TARGET)),win32,$(if $(filter wasm web,$(TARGET)),none,posix))
# CONF_EXTRA=file...: more module lines (what `vpm bundle` writes) appended to modules.conf for this build; @VLR@ is pinned to this checkout
CONF    := modules.conf
ifneq ($(CONF_EXTRA),)
CONF    := $(GEN)/modules.all
$(shell mkdir -p $(GEN) && sed 's#@VLR@#$(CURDIR)#g' modules.conf $(CONF_EXTRA) > $(CONF).tmp && { cmp -s $(CONF).tmp $(CONF) && rm $(CONF).tmp || mv $(CONF).tmp $(CONF); })
endif
uniq = $(if $(1),$(firstword $(1)) $(call uniq,$(filter-out $(firstword $(1)),$(1))))
MODTOK  := $(shell VLR_PLAT=$(VLR_PLAT) sh tools/modsrc.sh $(CONF) $(EXT) $(MODULES))
MODSRC   = $(call uniq,$(filter-out -%,$(MODTOK)))
MODFLAGS = $(filter -%,$(MODTOK))

RUN     ?=
OBJDIR   = build/$(TARGET)
ifeq ($(TARGET),win32)
CC       = x86_64-w64-mingw32-gcc
EXE      = .exe
PLATSRC  = src/platform_win32.c
LUADEF   =
LIBS     = -static -lws2_32 -lbcrypt -lcrypt32
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
LIBS     = -lm -lpthread
ifeq ($(STATIC),)
# desktop default: require() can also load .so modules (package.cpath) that vpm builds from C rocks; the executable exports the Lua API for them. make STATIC=1 for a fully static binary
LUADEF  += -DLUA_USE_DLOPEN
ifeq ($(shell uname -s),Darwin)
LIBS    += -ldl -Wl,-export_dynamic
else
LIBS    += -ldl -Wl,-E
endif
CFLAGS  += -DVLR_DLOPEN=1
endif
endif

SRCS     = $(LUASRC) $(VLR_CORE_SRC) $(VLR_MAIN_SRC) $(PLATSRC) \
           $(addprefix $(GEN)/,$(addsuffix .c,$(VLR_LUA_EMBED))) $(GEN)/vlr_modules.c
# module sources get object names from their whole path: two modules may both have a util.c (or a lutf8lib.c like Lua's own)
MODOBJ   = $(foreach s,$(MODSRC),$(OBJDIR)/m_$(subst /,_,$(s:.c=.o)))
OBJ      = $(addprefix $(OBJDIR)/,$(notdir $(SRCS:.c=.o))) $(MODOBJ)
VPATH    = src third_party/lua

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
# THIRDFLAGS: extra flags for third-party module sources only (tools/check.sh: sanitizer exceptions)
define modrule
$(OBJDIR)/m_$(subst /,_,$(1:.c=.o)): $(1)
	@mkdir -p $(OBJDIR)
	$(CC) $(if $(filter ./%,$(1)),$(CFLAGS),$(filter-out -std=c99,$(CFLAGS)) -D_GNU_SOURCE -w $(THIRDFLAGS)) $(MODFLAGS) -c -o $$@ $$<
endef
$(foreach s,$(MODSRC),$(eval $(call modrule,$(s))))
$(OBJDIR)/platform_posix.o: CFLAGS := $(filter-out -std=c99,$(CFLAGS))
ifneq ($(filter wasm web,$(TARGET)),)
$(OBJDIR)/platform_posix.o: CFLAGS += -DVLR_POSIX_NO_WAIT
endif

# generators run on the build machine, whatever the target compiler is (emcc, mingw cross)
HOSTCC ?= cc
build/embed: tools/embed.c
	@mkdir -p build
	$(HOSTCC) -o $@ $<
build/mkmodules: tools/mkmodules.c
	@mkdir -p build
	$(HOSTCC) -o $@ $<
# the module list is an input too: a stamp that changes when MODULES does regenerates the registry
build/modules.stamp: FORCE
	@mkdir -p build
	@echo '$(MODULES)' | cmp -s - $@ || echo '$(MODULES)' > $@
FORCE:
$(GEN)/vlr_modules.c: $(CONF) build/mkmodules build/modules.stamp $(wildcard lua/*.lua)
	@mkdir -p $(GEN)
	VLR_EXT=$(EXT) build/mkmodules $(CONF) $(MODULES) > $@
$(GEN)/%.c: lua/%.lua build/embed
	@mkdir -p $(GEN)
	build/embed $* $< > $@

# lua/luaheaders.lua is generated from third_party/lua/*.h (committed; tests/luaheaders.lua fails when it is stale)
headers: vlr
	./vlr tools/mkheaders.lua

# generated C (embedded Lua, module registry) only; for builds driven by another build system
gen: $(addprefix $(GEN)/,$(addsuffix .c,$(VLR_LUA_EMBED))) $(GEN)/vlr_modules.c

test: $(OUT)
	VLR="$(strip $(RUN) ./vlr$(EXE))" sh tests/run.sh

check: vlr
	sh tools/check.sh

clean:
	rm -rf vlr vlr.exe vlr.js vlr.wasm build
.PHONY: test check clean gen
