# Real terminal path (posix only): keys, mouse and resize through a pty into vapor.pull, and the tty restored on exit.
import fcntl, os, pty, select, struct, sys, termios, time

vlr = os.environ.get("VLR", "./vlr")
pid, fd = pty.fork()
if pid == 0:
    os.execv(vlr, [vlr, "tests/pty/events.lua"])
buf = b""

def pump(t):
    global buf
    end = time.time() + t
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try: buf += os.read(fd, 4096)
            except OSError: return

def send(b, wait=0.2):
    os.write(fd, b); pump(wait)

pump(0.5)
send(b"a")
send(b"\x1b[A")                    # Up
send(b"\x1b[1;5C")                 # Ctrl+Right
send(b"\x1b[<0;12;3M")             # mouse press
send(b"\x1b")                      # lone ESC: comes out after the 25 ms timeout
pump(0.3)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))   # resize
pump(0.7)
send(b"q", 0.5)
pump(0.5)
_, status = os.waitpid(pid, 0)
out = buf.decode("utf-8", "replace")
want = ["EV char,a", "EV key,up,0", "EV key,right,4", "EV mouse,press,1,12,3,0", "EV key,escape,0", "EV resize,100,30",
        "EV char,q", "DONE"]
missing = [w for w in want if w not in out]
if missing or os.waitstatus_to_exitcode(status) != 0:
    print("FAIL pty events; missing", missing, "status", status); print(out); sys.exit(1)
print("ok   tests/pty events (keys, mouse, escape, resize)")
