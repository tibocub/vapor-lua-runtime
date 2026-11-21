/* The Linux console (a real VT, not a terminal emulator) in raw keycode mode: the kernel's keymap loses information (Ctrl+e-acute, Alt+Shift+e-acute...),
   so the keyboard is put in K_MEDIUMRAW, which reports which physical key went down or up, and vaporUI's pure src/vtraw.c translates it with the kernel's
   own keymap. Everywhere else (terminal emulators, ssh, other OSes) this file does nothing and the byte decoder is used.
   Safety, because the mode belongs to the console and outlives us if we die without restoring it: restored at exit and on fatal signals, a small guard
   process restores it if we are killed outright, Ctrl+Alt+F<n> switches console like the kernel did. VLR_RAW_KEYS=0 turns it off.
   Ported from vaporUI's src/platform/posix.c (the reference). shortcut: no CapsLock/NumLock LEDs, no compose key. */
#include "term_vt.h"

#if defined(__linux__)
#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>
#include <fcntl.h>

#include <linux/kd.h>
#include <linux/keyboard.h>
#include <linux/vt.h>

#include "vlr_platform.h"
#include "vtraw.h"

#define TTY 0
static VuiVtRaw *raw;
static long saved_mode;
static int guard_pipe = -1, atexit_set;
static pid_t guard_pid;
static struct termios saved_termios;

static void restore_mode(void)
{
    if (raw != NULL) ioctl(TTY, KDSKBMODE, saved_mode);
}

static void fatal(int sig)
{
    signal(sig, SIG_DFL);
    restore_mode();
    raise(sig);
}

static int load_keymap(VuiVtRaw *r)
{
    struct kbdiacrsuc *diacr = calloc(1, sizeof(*diacr));
    int chars = 0, t, k;

    for (t = 0; t < VUI_VT_TABLES; t++) {
        for (k = 0; k < VUI_VT_KEYS; k++) {
            struct kbentry ent;

            memset(&ent, 0, sizeof ent);
            ent.kb_table = (unsigned char)t;
            ent.kb_index = (unsigned char)k;
            if (ioctl(TTY, KDGKBENT, &ent) != 0) { free(diacr); return -1; }
            r->map[t][k] = vui_vtraw_entry(ent.kb_value);
            chars += t == 0 && (r->map[t][k].type == VT_CHAR || r->map[t][k].type == VT_LETTER);
        }
    }
    r->accents = 0;
    if (diacr != NULL && ioctl(TTY, KDGKBDIACRUC, diacr) == 0) {
        unsigned int i;

        for (i = 0; i < diacr->kb_cnt && i < VUI_VT_DIACR; i++) {
            r->accent[i].diacr = diacr->kbdiacruc[i].diacr;
            r->accent[i].base = diacr->kbdiacruc[i].base;
            r->accent[i].result = diacr->kbdiacruc[i].result;
            r->accents = i + 1;
        }
    }
    free(diacr);
    return chars >= 20 ? 0 : -1; /* a map with no letters is not a keymap we understand */
}

void vlr_vt_stop(void)
{
    if (raw == NULL) return;
    restore_mode();
    free(raw);
    raw = NULL;
    if (guard_pipe >= 0) { /* tell the guard we are done: it exits */
        close(guard_pipe);
        guard_pipe = -1;
        waitpid(guard_pid, NULL, 0);
    }
}

int vlr_vt_start(void)
{
    static const int sigs[] = {SIGTERM, SIGHUP, SIGINT, SIGQUIT, SIGSEGV, SIGABRT, SIGBUS, SIGFPE, SIGILL};
    const char *off = getenv("VLR_RAW_KEYS");
    char kbtype, led = 0;
    int fds[2];
    unsigned i;
    struct termios t;

    if (raw != NULL) return 1;
    if (off != NULL && off[0] == '0') return 0;
    if (ioctl(TTY, KDGKBTYPE, &kbtype) != 0) return 0; /* not a real console: pty, ssh, serial line */
    if (ioctl(TTY, KDGKBMODE, &saved_mode) != 0 || (saved_mode != K_XLATE && saved_mode != K_UNICODE)) return 0;
    if (tcgetattr(TTY, &saved_termios) != 0) return 0;
    raw = calloc(1, sizeof *raw);
    if (raw == NULL || load_keymap(raw) != 0 || pipe(fds) != 0) { free(raw); raw = NULL; return 0; }
    ioctl(TTY, KDGKBLED, &led);
    vui_vtraw_init(raw, (led & LED_NUM) != 0);

    guard_pid = fork();
    if (guard_pid == 0) { /* the guard: restores the mode when the pipe closes, however we died */
        char c;

        close(fds[1]);
        setpgid(0, 0);
        for (i = 0; i < sizeof sigs / sizeof sigs[0]; i++) signal(sigs[i], SIG_IGN);
        while (read(fds[0], &c, 1) > 0) {}
        ioctl(TTY, KDSKBMODE, saved_mode);
        _exit(0);
    }
    close(fds[0]);
    if (guard_pid < 0) { close(fds[1]); free(raw); raw = NULL; return 0; } /* no guard, no raw mode */
    fcntl(fds[1], F_SETFD, FD_CLOEXEC);
    guard_pipe = fds[1];
    for (i = 0; i < sizeof sigs / sizeof sigs[0]; i++) signal(sigs[i], fatal);
    if (!atexit_set) { atexit(vlr_vt_stop); atexit_set = 1; }

    t = saved_termios; /* keycode bytes are not text: no input translation at all (showkey does the same) */
    t.c_iflag = 0;
    tcsetattr(TTY, TCSANOW, &t);
    ioctl(TTY, KDSKBMODE, K_MEDIUMRAW);
    return 1;
}

int vlr_vt_active(void) { return raw != NULL; }

int vlr_vt_events(VuiEvent *out, int max)
{
    char buf[64];
    int n, i, count = 0;

    if (raw == NULL || max < 3 * (int)sizeof buf) return 0;
    n = vlr_console_read(buf, (int)sizeof buf);
    if (n < 0) return -1;
    for (i = 0; i < n; i++) {
        VuiEvent e = vui_vtraw_feed(raw, (uint8_t)buf[i]);

        if (raw->switch_to != 0) {
            ioctl(TTY, VT_ACTIVATE, raw->switch_to);
            raw->switch_to = 0;
            vui_vtraw_release_all(raw); /* the releases of Ctrl and Alt go to the other console */
        }
        for (; e.type != VUI_EVENT_NONE; e = vui_vtraw_pop(raw)) out[count++] = e;
    }
    return count;
}
#else
int vlr_vt_start(void) { return 0; }
void vlr_vt_stop(void) {}
int vlr_vt_active(void) { return 0; }
int vlr_vt_events(VuiEvent *out, int max) { (void)out; (void)max; return 0; }
#endif
