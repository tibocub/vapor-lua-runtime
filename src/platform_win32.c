/* vlr backend for Windows (mingw or MSVC). Paths in and out are UTF-8. */
#include <winsock2.h>
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "vlr_platform.h"

static char g_err[256];

static void seterr(void)
{
    DWORD n = FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, NULL, GetLastError(), 0,
                             g_err, sizeof g_err, NULL);
    if (n == 0) strcpy(g_err, "error");
    while (n > 0 && (g_err[n - 1] == '\r' || g_err[n - 1] == '\n' || g_err[n - 1] == ' ')) g_err[--n] = 0;
}

const char *vlr_last_error(void) { return g_err; }

void vlr_flush(void) { fflush(NULL); }

static UINT g_oldcp;

static void restore_cp(void) { SetConsoleOutputCP(g_oldcp); }

/* Lua strings are UTF-8 but a console defaults to an OEM code page (print("é") would show mojibake): switch it for the
   life of the process. Runs once, from the first vlr_caps() call at state creation. */
static void utf8_output(void)
{
    DWORD mode;

    if (g_oldcp || !GetConsoleMode(GetStdHandle(STD_OUTPUT_HANDLE), &mode)) return;
    g_oldcp = GetConsoleOutputCP();
    SetConsoleOutputCP(CP_UTF8);
    atexit(restore_cp);
}

uint32_t vlr_caps(void)
{
    utf8_output();
    return VLR_CAP_NET | VLR_CAP_FS | VLR_CAP_TTY | VLR_CAP_EXEC;
}

int64_t vlr_now_ms(void)
{
    LARGE_INTEGER f, c;

    QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&c);
    return (int64_t)(c.QuadPart * 1000 / f.QuadPart);
}

static int g_native;

/* is console input / stdin readable right now? */
static int stdin_ready(void)
{
    HANDLE h = GetStdHandle(STD_INPUT_HANDLE);
    DWORD mode, avail;

    if (GetConsoleMode(h, &mode)) {
        /* the handle is signalled by any record (resize, focus, key-up), but ReadFile only returns for key-downs and
           would block on the rest: drop those records, report readable only when a key-down is queued */
        INPUT_RECORD r;

        while (PeekConsoleInputW(h, &r, 1, &avail) && avail) {
            if (g_native && (r.EventType == MOUSE_EVENT || (r.EventType == KEY_EVENT && r.Event.KeyEvent.bKeyDown))) return 1; /* records are read natively */
            if (r.EventType == KEY_EVENT && r.Event.KeyEvent.bKeyDown) {
                WORD vk = r.Event.KeyEvent.wVirtualKeyCode;

                /* a modifier alone (Shift, Ctrl, Alt, Caps, Win...) produces no bytes: ReadFile would sit waiting for the next key,
                   freezing timers and resize; drop it like the other non-data records */
                if (!(vk == VK_SHIFT || vk == VK_CONTROL || vk == VK_MENU || vk == VK_CAPITAL || vk == VK_NUMLOCK ||
                      vk == VK_SCROLL || vk == VK_LWIN || vk == VK_RWIN)) return 1;
            }
            ReadConsoleInputW(h, &r, 1, &avail);
        }
        return 0;
    }
    if (GetFileType(h) == FILE_TYPE_PIPE) {
        if (!PeekNamedPipe(h, NULL, 0, NULL, &avail, NULL)) return 1; /* broken pipe: a read reports EOF */
        return avail > 0;
    }
    return 1; /* file or NUL: reads never block */
}

int vlr_wait(const int *fds, int n, int *ready, int timeout_ms)
{
    int64_t end = timeout_ms < 0 ? -1 : vlr_now_ms() + timeout_ms;
    WSAPOLLFD p[VLR_MAX_FDS];
    int idx[VLR_MAX_FDS], i, j, ns, count, console;

    /* handle 0 is the console input (polled); anything else is a socket (WSAPoll) */
    for (i = 0, ns = 0, console = 0; i < n; i++) {
        ready[i] = 0;
        if (fds[i] == 0) { console = 1; continue; }
        p[ns].fd = (SOCKET)(fds[i] & ~VLR_WRITABLE);
        p[ns].events = (fds[i] & VLR_WRITABLE) ? POLLWRNORM : POLLRDNORM;
        p[ns].revents = 0;
        idx[ns++] = i;
    }
    for (;;) {
        int64_t left = end < 0 ? 1000000 : end - vlr_now_ms();
        int slice;

        count = 0;
        if (console && stdin_ready()) {
            for (i = 0; i < n; i++) if (fds[i] == 0) { ready[i] = 1; count++; }
        }
        slice = !console && ns > 0 ? (int)(left < 0 ? 0 : left > 1000000 ? 1000000 : left) : 0; /* sockets alone: one exact wait */
        if (ns > 0) {
            int r = WSAPoll(p, (ULONG)ns, count > 0 ? 0 : slice);

            if (r < 0) { seterr(); return -1; }
            for (j = 0; j < ns; j++) {
                if (p[j].revents & (POLLRDNORM | POLLWRNORM | POLLHUP | POLLERR | POLLNVAL)) { ready[idx[j]] = 1; count++; }
            }
        }
        if (count > 0) return count;
        if (left <= 0) return 0;
        if (!(ns > 0 && !console)) Sleep((DWORD)(left < 10 ? left : 10)); /* shortcut: 10 ms polling while the console is involved */
    }
}

static int towide(const char *u8, wchar_t *w, int cap)
{
    return MultiByteToWideChar(CP_UTF8, 0, u8, -1, w, cap) > 0;
}

int vlr_fs_list(const char *path, int (*cb)(void *, const char *), void *ud)
{
    wchar_t pat[MAX_PATH + 4];
    char name[MAX_PATH * 3];
    WIN32_FIND_DATAW fd;
    HANDLE h;
    size_t len;

    if (!towide(path, pat, MAX_PATH)) { seterr(); return -1; }
    len = wcslen(pat);
    wcscpy(pat + len, (len && (pat[len - 1] == L'/' || pat[len - 1] == L'\\')) ? L"*" : L"\\*");
    h = FindFirstFileW(pat, &fd);
    if (h == INVALID_HANDLE_VALUE) { seterr(); return -1; }
    do {
        if (wcscmp(fd.cFileName, L".") == 0 || wcscmp(fd.cFileName, L"..") == 0) continue;
        if (!WideCharToMultiByte(CP_UTF8, 0, fd.cFileName, -1, name, sizeof name, NULL, NULL)) continue;
        if (cb(ud, name)) break;
    } while (FindNextFileW(h, &fd));
    FindClose(h);
    return 0;
}

int vlr_fs_mkdir(const char *path)
{
    wchar_t w[MAX_PATH];

    if (!towide(path, w, MAX_PATH) || !CreateDirectoryW(w, NULL)) { seterr(); return -1; }
    return 0;
}

static DWORD g_inmode, g_outmode;
static int g_raw;

static int g_level;
static unsigned g_prev_buttons;
static WCHAR g_high;

int vlr_console_native(void) { return g_native; }

/* enable: 0 restore, 1 raw, 2 raw + mouse (clicks, drag), 3 raw + motion. The console reports native key and mouse records (no VT input):
   the character, virtual key, scan code and modifier state of every press, so Ctrl/Alt/Shift combinations are exact (vaporUI src/winkeys.c
   turns them into events). Mouse needs ENABLE_MOUSE_INPUT and quick-edit OFF: with quick-edit (the console default, kept unless
   ENABLE_EXTENDED_FLAGS is given without it) clicks and drags select text and never reach the program. ENABLE_PROCESSED_INPUT is off, so Ctrl-C is a key. */
int vlr_console_raw(int enable)
{
    HANDLE in = GetStdHandle(STD_INPUT_HANDLE), out = GetStdHandle(STD_OUTPUT_HANDLE);

    if (enable) {
        DWORD mode = ENABLE_EXTENDED_FLAGS | ENABLE_WINDOW_INPUT;

        if (!g_raw) {
            if (!GetConsoleMode(in, &g_inmode)) return -1;
            GetConsoleMode(out, &g_outmode);
            SetConsoleMode(out, g_outmode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
            SetConsoleCP(CP_UTF8);
            SetConsoleOutputCP(CP_UTF8);
            g_raw = 1;
            g_native = 1;
            g_prev_buttons = 0;
            g_high = 0;
        }
        g_level = enable >= 3 ? 2 : enable == 2 ? 1 : 0;
        if (g_level) mode |= ENABLE_MOUSE_INPUT; else mode |= ENABLE_QUICK_EDIT_MODE; /* selecting text stays possible unless the mouse is wanted */
        SetConsoleMode(in, mode);
    } else if (g_raw) {
        SetConsoleMode(in, g_inmode);
        SetConsoleMode(out, g_outmode);
        g_raw = 0;
        g_native = 0;
    }
    return 0;
}

/* the key typing only itself on the foreground window's layout: ToUnicodeEx with an empty key state and the "do not touch the keyboard
   state" flag (a dead key stays pending). 0 for none or a dead key */
static unsigned unshifted_char(unsigned vk, unsigned scan)
{
    BYTE keys[256] = {0};
    WCHAR buf[4];
    DWORD thread = GetWindowThreadProcessId(GetForegroundWindow(), NULL);
    int n = ToUnicodeEx(vk, scan, keys, buf, 4, 0x4, GetKeyboardLayout(thread));

    return n == 1 ? buf[0] : 0;
}

int vlr_console_record(vlr_record *r)
{
    HANDLE in = GetStdHandle(STD_INPUT_HANDLE), out = GetStdHandle(STD_OUTPUT_HANDLE);
    INPUT_RECORD rec;
    DWORD n;

    while (g_native && PeekConsoleInputW(in, &rec, 1, &n) && n) {
        ReadConsoleInputW(in, &rec, 1, &n);
        memset(r, 0, sizeof *r);
        if (rec.EventType == KEY_EVENT && rec.Event.KeyEvent.bKeyDown) {
            const KEY_EVENT_RECORD *k = &rec.Event.KeyEvent;
            unsigned uc = k->uChar.UnicodeChar;

            if (uc >= 0xD800 && uc < 0xDC00) { g_high = (WCHAR)uc; continue; } /* half a surrogate pair: wait for the other */
            if (uc >= 0xDC00 && uc < 0xE000) uc = g_high ? 0x10000 + (((unsigned)g_high - 0xD800) << 10) + (uc - 0xDC00) : 0;
            g_high = 0;
            r->kind = 1;
            r->vk = k->wVirtualKeyCode;
            r->scan = k->wVirtualScanCode;
            r->uc = uc;
            r->unshifted = unshifted_char(r->vk, r->scan);
            r->ctrl = k->dwControlKeyState;
            return 1;
        }
        if (rec.EventType == MOUSE_EVENT) {
            const MOUSE_EVENT_RECORD *m = &rec.Event.MouseEvent;
            CONSOLE_SCREEN_BUFFER_INFO info;
            int x, y;

            if (!GetConsoleScreenBufferInfo(out, &info)) continue;
            x = m->dwMousePosition.X - info.srWindow.Left; /* positions are in the screen buffer; the app draws in the visible window */
            y = m->dwMousePosition.Y - info.srWindow.Top;
            r->prev_buttons = g_prev_buttons;
            g_prev_buttons = m->dwButtonState & 7u;
            if (x < 0 || y < 0) continue;
            r->kind = 2;
            r->buttons = m->dwButtonState;
            r->flags = m->dwEventFlags;
            r->x = (unsigned)x;
            r->y = (unsigned)y;
            r->ctrl = m->dwControlKeyState;
            r->level = g_level;
            return 1;
        }
        /* key release, focus, menu, buffer size: nothing for the app (resize is polled) */
    }
    return 0;
}

int vlr_console_read(char *buf, int n)
{
    HANDLE in = GetStdHandle(STD_INPUT_HANDLE);
    DWORD got = 0;

    if (g_native) return 0; /* records, not bytes: vlr_console_record */
    if (!stdin_ready()) return 0;
    if (!ReadFile(in, buf, (DWORD)n, &got, NULL)) return -1;
    return got == 0 ? -1 : (int)got;
}

int vlr_console_size(int *cols, int *rows)
{
    CONSOLE_SCREEN_BUFFER_INFO i;

    if (!GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), &i)) return -1;
    *cols = i.srWindow.Right - i.srWindow.Left + 1;
    *rows = i.srWindow.Bottom - i.srWindow.Top + 1;
    return 0;
}

int vlr_exec(const char *cmd)
{
    int r;

    if (cmd == NULL) return 1;
    r = system(cmd); /* shortcut: ANSI code page, not UTF-8; upgrade with _wsystem when a non-ASCII command matters */
    return r == -1 ? (seterr(), -1) : r;
}

int vlr_fs_rmdir(const char *path)
{
    wchar_t w[MAX_PATH];

    if (!towide(path, w, MAX_PATH) || !RemoveDirectoryW(w)) { seterr(); return -1; }
    return 0;
}

int vlr_fs_stat(const char *path, vlr_stat *st)
{
    wchar_t w[MAX_PATH];
    WIN32_FILE_ATTRIBUTE_DATA d;
    ULARGE_INTEGER t;

    if (!towide(path, w, MAX_PATH) || !GetFileAttributesExW(w, GetFileExInfoStandard, &d)) { seterr(); return -1; }
    st->is_dir = (d.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
    st->size = ((int64_t)d.nFileSizeHigh << 32) | d.nFileSizeLow;
    t.LowPart = d.ftLastWriteTime.dwLowDateTime;
    t.HighPart = d.ftLastWriteTime.dwHighDateTime;
    st->mtime = (int64_t)(t.QuadPart / 10000000ULL) - 11644473600LL; /* 1601 -> 1970 */
    return 0;
}
