# vlr host build (POSIX). Other targets bring their own build and backend.
CC      ?= cc
CFLAGS  ?= -O2
CFLAGS  += -std=c99 -Wall -Iinclude -Ithird_party/lua
LUASRC   = $(filter-out third_party/lua/lua.c third_party/lua/luac.c,$(wildcard third_party/lua/*.c))
OBJ      = $(LUASRC:.c=.o) src/vlr.o src/main.o src/platform_posix.o build/compat.o build/sched.o

vlr: $(OBJ)
	$(CC) -o $@ $(OBJ) -lm

third_party/lua/%.o: CFLAGS += -DLUA_USE_POSIX
src/platform_posix.o: CFLAGS := $(filter-out -std=c99,$(CFLAGS))

build/embed: tools/embed.c
	@mkdir -p build
	$(CC) -o $@ $<
build/%.c: lua/%.lua build/embed
	build/embed $* $< > $@

test: vlr
	sh tests/run.sh

clean:
	rm -rf vlr build src/*.o third_party/lua/*.o
.PHONY: test clean
