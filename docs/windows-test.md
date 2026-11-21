# Windows test instructions (written for an LLM or a person on the Windows PC)

Goal: build vlr on real Windows, run every automated check, and send the results back as a file in the repo. Do **not** change source
files unless a step below says so; if something fails, the report is the deliverable, not a fix. (If you do fix something, say exactly what and why in
the report and commit it separately.)

## 0. What you need
Windows 10 or newer and **MSYS2** (https://www.msys2.org). Open the **"MSYS2 MinGW 64-bit"** shell (not "MSYS2 MSYS", not PowerShell, not Git Bash). Install:

    pacman -S --needed make git curl tar mingw-w64-x86_64-gcc

Get the repo up to date (the user pushes from the Linux side):

    git clone https://github.com/tibocub/vapor-lua-runtime   # first time
    cd vapor-lua-runtime && git pull                          # later times

If you see lots of `No such file or directory` or `\r: command not found` lines, the checkout got Windows line endings. Fix once:

    git config core.autocrlf false
    git rm --cached -r -q . && git reset --hard      # re-checks out every file with LF (repo has a .gitattributes for it)

## 1. Run the one command
From the repo root, in the MinGW64 shell:

    sh tests/win/report.sh

It clones the three native-module sources next to the repo (pinned versions), builds `vlr.exe`, runs `tests/run.sh` and the ConPTY console suite
(`tests/win32/run.sh`), prints everything, and writes it to `reports/windows-<date>.txt`. It waits for Enter at the end, so the window does not
vanish. If it stops early with `MISSING TOOL` or `ABORT`, fix that (the message says how) and run it again.

## 2. Send the result back
    git add reports
    git commit -m "Windows report"
    git push

Then reply with: the report file name, the `SUMMARY` line, and the full text of every line that starts with `FAIL` (and the few lines after it).

## 3. What the checks cover (for reference)
- `tests/run.sh`: every `tests/*.lua` in normal and `--step` mode, app folders, `os.exit`; includes `tests/net.lua` (Winsock loopback: TCP, UDP, large
  transfer, timeouts), `fs.lua` (paths, `rmdir`), `exec*.lua` (`os.execute` through `cmd.exe`), `fd.lua`.
- `tests/win32/run.sh`: vlr.exe inside a real Windows pseudo console (keys, Ctrl+Right, ESC, resize, console restored, pipe stdin, UTF-8, Ctrl+C).
- Not automatable: the **mouse** in `vapor.input({mouse=1})`. If a human is at the machine: run `./vlr.exe tests/pty/events.lua` in Windows Terminal and in a
  classic cmd.exe window, click and scroll, resize, then type `q`; note which `EV mouse,...` lines appear. Put the answer in the reply.

## Manual notes from earlier rounds
- Found and fixed earlier on real Windows: a console resize left a record that made `vlr_wait` report "readable" while `ReadFile` blocked; `print("é")` showed
  mojibake on a console (output code page is now UTF-8 for the process).
- Known open: with a console and a socket waited on together, polling is in 10 ms slices (sockets alone wait exactly).
