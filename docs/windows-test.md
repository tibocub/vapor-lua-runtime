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

---

# Round 2: keyboard and mouse diagnostics (needs a human at the keyboard)

Background: in the first report everything automated passed, but by hand in real windows: mouse hover was never reported, drag only worked in Ghostty
(not in cmd or PowerShell), Ctrl+key combinations did nothing, and multi-modifier combos felt clunky. Changes made for it (rebuild first: `git pull`, then
`sh tests/win/report.sh` or just `make TARGET=win32 CC=gcc`):
- Hover needs mouse level 2 (`events.lua` used level 1, drag only). `tests/pty/events.lua` now takes the level as its argument.
- On Windows a console in quick-edit mode (the default) swallows clicks and drags for text selection. Mouse level 2 now turns quick-edit off and enables mouse input.
- A modifier key pressed alone (Shift, Ctrl, Alt) is no longer treated as "input is ready" (it made the program wait inside ReadFile and feel laggy).

Run the diagnostic **once in each terminal you have** (Windows Terminal with PowerShell, Windows Terminal with cmd, classic cmd.exe window, classic PowerShell
window, Ghostty). In the MinGW64 shell or directly in that terminal from the repo folder:

    ./vlr.exe tests/keys.lua 2 reports/keys-<terminal-name>.txt

(`<terminal-name>` e.g. `wt-powershell`, `cmd`, `ghostty`.) Each key press prints the raw bytes received and how vlr decoded them, and is saved to the file.
Press these one at a time, waiting for the line to appear, then `q` to quit:

1. `a`, `Shift+a`, `Alt+a`, `Ctrl+a`, `Ctrl+b`, `Ctrl+z`
2. `Left`, `Shift+Left`, `Alt+Left`, `Ctrl+Left`, `Ctrl+Shift+Left`, `Ctrl+Alt+Left`
3. `Home`, `Ctrl+Home`, `Delete`, `Ctrl+Delete`, `Backspace`, `Ctrl+Backspace`, `Tab`, `Shift+Tab`, `Ctrl+Enter`
4. `F5`, `Shift+F5`, `Ctrl+F5`
5. Mouse: move over the window without clicking (hover), left click, right click, hold and drag, scroll wheel up and down.

Note for each terminal whether a key produced **no line at all** (the terminal or Windows ate it) or a line with `(no event)` (bytes arrived but vlr does not
decode them; send me those bytes). Then:

    git add reports && git commit -m "Windows key diagnostics" && git push

and reply with which terminals you ran and anything odd (lag, a frozen window, characters echoed on screen).

## Round 3: the Windows console now delivers native records (retest, needs a human)
vlr no longer asks the Windows console for VT escape bytes. It reads key and mouse records (virtual key, scan code, modifier state, character) and
vaporUI's translator turns them into events; this is the path vaporUI tested with real keystrokes. Please `git pull`, rebuild (`sh tests/win/report.sh` does it), then:
1. Send back the new report (`reports/windows-*.txt`; all lines must still be `ok`, including the ConPTY suite: those tests type into a pseudo console).
2. Repeat the Round 2 key list with `./vlr.exe tests/keys.lua 2 reports/keys-<terminal>.txt` (lines now read `native record -> key,left,4`). A key that gives
   **no line** is dropped by the console, the terminal or the translator: say which keys. Pay attention to Ctrl+letter, Ctrl+arrows, Ctrl+Shift combos,
   Alt+letter, mouse hover/drag in cmd, PowerShell, Windows Terminal.
3. Reply with what changed compared to Round 2.
