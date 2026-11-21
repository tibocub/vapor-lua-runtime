# VLR - The Vapor Lua Runtime (looking for a name that sucks less)

A middle-ground between PICO-8 and the JVM.

VLR aims to provide general-purpose programming like Python and NodeJS, without
the hundred of MBs of ram usage per process.


Notable features:
- defaults to Lua 5.1 with optional 5.4 dialect compatibility where required
- cross-platform (Linux/Win/Mac/BSD/WASM)
- a core + standard lib under the form of many modules (like bare)
- [vpm](https://github.com/tibocub/vpm), a Lua package manager compatible with
luarocks, tailored specifically for VLR and vaporOS
- can bundle Lua libs written in C in the runtime's binary


## Why is Lua 5.1 the default ?

As we aim for the best compatiblity for the Lua ecosystem, 5.1 stays the most
widely targetted version by libraries.

LuaJIT also only supports 5.1, which mean the optional JIT activation on targets
that supports it depends on the program being written in the 5.1 dialect.

However, VLR is actually built on Lua 5.4 so it's possible to activate 5.4 where
needed to get gotos, bitwise operators, etc.


## Why bundle a library in the runtime ?

It doesn't really make sense in linux because if you want a native lib you can
just download and compile it. But on embed targets, you can't and in most cases
dynamic linking isn't an option so it produces large binaries.

The bundled libraries are detected by vpm so it's possible to resolve the dependencies
of a lua program or librarie that depends on a bundled library correctly.

This means it make it possible to pre-compile native lua libraries in the
runtime for targets that can't compile C code while still being able to
install, update and manage pure-Lua libraries and programs dynamically.


