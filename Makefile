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
else ifeq ($(TARGET),wasm)
# needs `source ~/Code/emsdk/emsdk_env.sh`; this build is for Node (NODERAWFS), the browser build is later
CC       = emcc
EXE      = .js
RUN      = node
PLATSRC  = src/platform_wasm.c src/platform_posix.c
LUADEF   = -DLUA_USE_POSIX
LIBS     = -sNODERAWFS=1 -sENVIRONMENT=node -sALLOW_MEMORY_GROWTH=1 -sEXIT_RUNTIME=1
else
EXE      =
PLATSRC  = src/platform_posix.c
LUADEF   = -DLUA_USE_POSIX
LIBS     = -lm
endif

SRCS     = $(LUASRC) $(VLR_CORE_SRC) $(VLR_MAIN_SRC) $(PLATSRC) $(MODSRC) \
           $(addprefix $(GEN)/,$(addsuffix .c,$(VLR_LUA_EMBED))) $(GEN)/vlr_modules.c
OBJ      = $(addprefix $(OBJDIR)/,$(notdir $(SRCS:.c=.o)))
VPATH    = src third_party/lua $(sort $(dir $(MODSRC)))

vlr$(EXE): $(OBJ)
	$(CC) $(LDFLAGS) -o $@ $(OBJ) $(LIBS)

$(OBJDIR)/%.o: %.c
	@mkdir -p $(OBJDIR)
	$(CC) $(CFLAGS) -c -o $@ $<

$(OBJDIR)/%.o: $(GEN)/%.c
	@mkdir -p $(OBJDIR)
	$(CC) $(CFLAGS) -c -o $@ $<

$(addprefix $(OBJDIR)/,$(notdir $(LUASRC:.c=.o))): CFLAGS += $(LUADEF)
$(addprefix $(OBJDIR)/,$(notdir $(MODSRC:.c=.o))): CFLAGS := $(filter-out -std=c99,$(CFLAGS)) -D_GNU_SOURCE -w $(MODFLAGS)
$(OBJDIR)/platform_posix.o: CFLAGS := $(filter-out -std=c99,$(CFLAGS))
ifeq ($(TARGET),wasm)
$(OBJDIR)/platform_posix.o: CFLAGS += -DVLR_POSIX_NO_WAIT
endif

build/embed: tools/embed.c
	@mkdir -p build
	$(CC) -o $@ $<
build/mkmodules: tools/mkmodules.c
	@mkdir -p build
	$(CC) -o $@ $<
$(GEN)/vlr_modules.c: modules.conf build/mkmodules
	@mkdir -p $(GEN)
	build/mkmodules modules.conf $(MODULES) > $@
$(GEN)/%.c: lua/%.lua build/embed
	@mkdir -p $(GEN)
	build/embed $* $< > $@

# generated C (embedded Lua, module registry) only; for builds driven by another build system
gen: $(addprefix $(GEN)/,$(addsuffix .c,$(VLR_LUA_EMBED))) $(GEN)/vlr_modules.c

test: vlr$(EXE)
	VLR="$(RUN) ./vlr$(EXE)" sh tests/run.sh

check: vlr
	sh tools/check.sh

clean:
	rm -rf vlr vlr.exe vlr.js vlr.wasm build
.PHONY: test check clean gen
