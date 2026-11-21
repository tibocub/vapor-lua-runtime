# Linux console (real TTY) keyboard test: for the human at the machine

vlr puts a real Linux virtual console (Ctrl+Alt+F3, not a terminal emulator or ssh) into raw keycode mode (K_MEDIUMRAW) and translates the keys with the
kernel's own keymap, so Ctrl/Alt/Shift combinations that the console normally loses (Ctrl+é, Alt+Shift+é, Ctrl+&...) arrive intact. Terminal emulators
and ssh keep the escape-byte decoder. `VLR_RAW_KEYS=0` turns the raw mode off.

1. Switch to a text console (Ctrl+Alt+F3), log in, `cd` to the vlr checkout and build (`make`).
2. `./vlr tests/keys.lua 2 /tmp/keys-tty.txt`. The first line must say `native=true`. Press: letters, Shift+letters, Ctrl+letters, Alt+letters,
   Ctrl+Alt, AltGr combinations, accents and dead keys (`^` then `e`), arrows with Ctrl/Shift/Alt, F1..F12, Home/End/Delete/Backspace/Tab/Enter, Ctrl+Space,
   then `q`. Each line shows the decoded event (`native record -> key,a,4,a,4`: name, modifiers, US base key, scancode).
3. Safety checks (important, the keyboard mode belongs to the console): (a) after `q`, the shell must type normally and Ctrl+C must work; (b) run
   `./vlr tests/keys.lua` again and kill it from another console with `kill -9 <pid>`: the keyboard must still work afterwards (a guard process restores it);
   (c) press Ctrl+Alt+F4 while it runs: the console must switch, and back again with Ctrl+Alt+F3.
4. If the keyboard stays broken: from another console or ssh run `kbd_mode -u` (or `kbd_mode -a`), then tell me what was running.
5. Reply with `/tmp/keys-tty.txt`, your keyboard layout (`localectl status`), and anything wrong.
