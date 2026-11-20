# vlr host build (POSIX). Other targets bring their own build and backend; the shared source list is sources.mk.
include sources.mk
CC      ?= cc
CFLAGS  ?= -O2
CFLAGS  += -std=c99 -Wall -Iinclude -Ithird_party/lua
EXT     ?= ..
LUASRC   = $(addprefix third_party/lua/,$(VLR_LUA_SRC))

# modules.conf: sources (and -D flags) after the first two columns
MODTOK  := $(shell awk '!/^[#]/ && NF>2 {for(i=3;i<=NF;i++) print $$i}' modules.conf | sed 's#@EXT@#$(EXT)#')
MODSRC   = $(filter-out -%,$(MODTOK))
MODFLAGS = $(filter -%,$(MODTOK))
MODOBJ   = $(MODSRC:.c=.o)

OBJ      = $(LUASRC:.c=.o) $(VLR_CORE_SRC:.c=.o) $(VLR_MAIN_SRC:.c=.o) src/platform_posix.o \
           $(addprefix build/,$(addsuffix .o,$(VLR_LUA_EMBED))) build/vlr_modules.o $(MODOBJ)

vlr: $(OBJ)
	$(CC) $(LDFLAGS) -o $@ $(OBJ) -lm

third_party/lua/%.o: CFLAGS += -DLUA_USE_POSIX
$(MODOBJ): CFLAGS := $(filter-out -std=c99,$(CFLAGS)) -D_GNU_SOURCE -w $(MODFLAGS)
src/platform_posix.o: CFLAGS := $(filter-out -std=c99,$(CFLAGS))

build/embed: tools/embed.c
	@mkdir -p build
	$(CC) -o $@ $<
build/mkmodules: tools/mkmodules.c
	@mkdir -p build
	$(CC) -o $@ $<
build/vlr_modules.c: modules.conf build/mkmodules
	build/mkmodules modules.conf > $@
build/%.c: lua/%.lua build/embed
	build/embed $* $< > $@

test: vlr
	sh tests/run.sh

check: vlr
	sh tools/check.sh

clean:
	rm -rf vlr build src/*.o third_party/lua/*.o $(MODOBJ)
.PHONY: test check clean
