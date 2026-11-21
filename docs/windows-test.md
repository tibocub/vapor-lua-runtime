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

---

# Results so far (Windows 10 19045, 2026-11-21, one machine: MSYS2 mingw64 gcc 15.2, French AZERTY keyboard)

Kept here so the Linux workstation has everything. Raw files: `reports/windows-20261121-1531.txt` (full report), `reports/keys-conhost-fr-driven.txt`.

## Automated: all pass
`sh tests/win/report.sh` from the MinGW64 shell: build, `tests/run.sh` (every test, normal and `--step`, including net, record, keys, identity, modules,
manifest, fs, exec, fd), the ConPTY suite (`tests/win32/run.sh`) and the https check. Everything is `ok` except the two items below.

## How the console tests work (so they can be extended)
- `tests/win32/conpty.c` runs vlr.exe inside a **ConPTY** (a real Windows pseudo console), types VT bytes and prints what the program wrote. Steps on
  stdin: `send TEXT` (`\e \r \x03` escapes), `wait MS`, `resize COLS ROWS`. Beware shell quoting when writing steps (`printf` eats `\r`: use a heredoc).
  It clears an inherited "ignore Ctrl+C" flag (Git Bash children have it) and gives the child null std handles (else a redirected stdin leaks in).
- ConPTY only carries VT bytes: it cannot type real keys or the mouse. For real keystrokes use **`win_drive`** (`vaporUI/tests/win_drive.c`): it opens a real
  console window and types with `SendInput` by scan code, so the keyboard layout does the translation (`win_drive 0000040C vlr.exe tests/keys.lua 2 out.txt < chords.txt`).
  It refuses to type when its window loses the foreground. Do not touch the keyboard while it runs. `AttachConsole` to the new window can be refused;
  it then still types but cannot read the screen (use the program's own log file, as `tests/keys.lua` has).
- Kill stray `vlr.exe` / `input-handling.exe` windows before rebuilding: a running exe makes the link fail with "Permission denied".

## Bugs found on real Windows and fixed
- A console resize (or focus or key-up) left a record in the input that made `vlr_wait` report "readable" while `ReadFile` blocked: the program hung after any resize.
- `print("é")` showed mojibake on a console (now the output code page is UTF-8 for the process, restored at exit).
- The build needed an `sh` on PATH (GNU make from Chocolatey runs recipes through cmd.exe otherwise): add `C:\Program Files\Git\usr\bin` and
  `E:\MSYS64\mingw64\bin` to the user PATH, or use the MinGW64 shell. A running PowerShell keeps the PATH it started with: open a new window.
- `modules.conf` listed `vaporUI/src/vtraw.c` (Linux console only); the Windows build failed when the vaporUI checkout lacked it. A source can now be
  written `posix:path` (`tools/modsrc.sh`): built only for the posix hosts. `tests/win/report.sh` now aborts when the build fails instead of testing a stale `vlr.exe`.

## Keyboard on a real console (conhost window = what cmd.exe and PowerShell use, French layout, 135 chords typed with win_drive)
Native key records reach vaporUI's translator and the results equal vaporUI's own (`vaporUI/docs/input.md`, "Windows: what was checked..."). Works: Ctrl+letter and
Ctrl+Shift+letter, Ctrl/Alt/Ctrl+Alt/Ctrl+Shift on the number row accents, Alt+Shift+& (`key,&,3,1,30`), `é è à ç ù € @` as text, dead keys compose
(`^e` = ê), arrows/Home/Delete/Backspace/Tab/Enter/F-keys with every modifier mix, scan codes.

Known quirks, not fixed (shared with vaporUI):
- AltGr + a dead key (AltGr+é = `~`): extra `Ctrl-Alt-...` event whose character is `2` or `é` depending on the window; Ctrl+Alt+è gives `7`.
- Ctrl+^ and Alt+^ come out as `[` (dead key has no character, US base used).
- Ctrl+Shift+à (Ctrl+Shift+0) never arrives (Windows or the console).
- The unshifted character comes from the foreground window's layout: wrong when the console is not focused.
- Through a ConPTY fed by a VT-only terminal: Ctrl+é sent as kitty/modifyOtherKeys is dropped by ConPTY, Ctrl+Space (byte 0) reads as `Ctrl-à`.

## Open: https on a fresh Windows can fail with "unknown issuer"
`vlr_system_roots` reads the ROOT store (72 certificates here). Windows installs most roots **on demand** the first time its own chain engine needs them,
so a site whose root was never used on this machine (example.com: SSL.com TLS ECC Root CA 2022) fails in vlr until something else triggers the fetch; after
a PowerShell `X509Chain.Build` for that site the store had 73 roots and vlr succeeded. google.com, github.com, wikipedia.org worked from the start; an expired
certificate is refused correctly. The report's https step can therefore print `FAIL certificate is not trusted (unknown issuer)` once on a clean machine.
Workaround: `certutil -generateSSTFromWU %TEMP%\roots.sst` then `certutil -addstore -f Root %TEMP%\roots.sst` (installs the whole Microsoft root list), or visit the
site with any Windows app first. Real fix to do: validate through the OS (`CertGetCertificateChain`) or also load the AuthRoot store, instead of a static PEM.

## Not tested (needs a person, or software this machine lacks)
- **Mouse** (hover, click, drag, wheel) in `vapor.input({mouse=2})`: no tool here injects mouse events into a real console.
- **Windows Terminal and Ghostty** (not installed). Windows Terminal binds Ctrl+Shift+letters, Alt+Shift+-/+/D, Ctrl+Alt+digit, Alt+arrows, Ctrl+Tab, Alt+Enter, F11 and
  Ctrl+=/- by default (from its documentation): a missing Ctrl/Alt combo there is the terminal's binding, not vlr.
- Alt+Enter, Alt+Space, Alt+Tab, Alt+F4, Ctrl+Esc (belong to Windows/the console), classic PowerShell 5 / pwsh windows (only cmd was run through the whole list; they share the console host).
- This machine's `../vaporUI` remote is SSH (`git@github.com:...`) and has no key: `git pull` there fails; pull with `git pull --ff-only https://github.com/tibocub/vaporUI main`.
