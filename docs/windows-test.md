# Testing vlr on real Windows

Everything below was only run under wine so far; what wine cannot show is marked **(real console)**.

## Build
MSYS2 (mingw64 shell, `pacman -S make mingw-w64-x86_64-gcc`), from the repo root. The sibling checkouts of lfs, lpeg and lua-cjson are
expected next to the repo (`EXT`, default `..`):

    make TARGET=win32 CC=gcc          # vlr.exe, static, with lfs + lpeg + cjson
    make TARGET=win32 CC=gcc MODULES=lfs

(The Makefile defaults `CC` to the cross compiler `x86_64-w64-mingw32-gcc`; inside MSYS2 pass `CC=gcc`.)

## Automated suite
    VLR=./vlr.exe sh tests/run.sh        # Git Bash or the MSYS2 shell

Expected: every line `ok`; under wine the whole suite passed. Things to look at on real Windows: `fs.lua` (paths, UTF-8 names, `rmdir`),
`exec*.lua` (`os.execute` through `cmd.exe`: status codes), `fd.lua` (stdin handle 0 as console, pipe and file).

## Manual checks (real console)
In Windows Terminal AND in classic conhost (cmd.exe window):

1. `vlr.exe tests/pty/events.lua` : press letters, arrows, Ctrl+Right, F-keys, click and scroll the mouse, resize the window, type `q`.
   Each should print one `EV ...` line (`char,a`, `key,up,0`, `key,right,4`, `mouse,press,1,x,y,0`, `resize,cols,rows`). Report which ones are missing.
2. After `q` the console must be back to normal (echo on, line editing, no mouse reporting).
3. `echo hello | vlr.exe -e` is not supported; instead check `echo print(io.read("l")) > t.lua & echo hi | vlr.exe t.lua` prints `hi`.
4. Non-ASCII: a script that prints `"é€"` and one that reads a file named `é.txt` via `vapor.fs.list`.
5. Ctrl+C inside `vapor.input(true)` arrives as `key,c,4` (the app decides), outside it ends the program.
