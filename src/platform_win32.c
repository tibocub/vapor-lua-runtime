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

#include <bcrypt.h>
#include <wincrypt.h>

/* the Windows ROOT certificate store as one PEM text (what a bundle file is on other systems) */
int vlr_system_roots(char **pem, size_t *len)
{
    HCERTSTORE st = CertOpenSystemStoreA(0, "ROOT");
    PCCERT_CONTEXT c = NULL;
    size_t cap = 1 << 16, n = 0;
    char *out = malloc(cap);

    if (st == NULL || out == NULL) { if (st) CertCloseStore(st, 0); free(out); return -1; }
    while ((c = CertEnumCertificatesInStore(st, c)) != NULL) {
        DWORD need = 0;

        if (!(c->dwCertEncodingType & X509_ASN_ENCODING)) continue;
        if (!CryptBinaryToStringA(c->pbCertEncoded, c->cbCertEncoded, CRYPT_STRING_BASE64HEADER | CRYPT_STRING_NOCR, NULL, &need)) continue;
        if (n + need + 1 > cap) {
            char *p;

            while (n + need + 1 > cap) cap *= 2;
            if ((p = realloc(out, cap)) == NULL) { free(out); CertCloseStore(st, 0); return -1; }
            out = p;
        }
        if (CryptBinaryToStringA(c->pbCertEncoded, c->cbCertEncoded, CRYPT_STRING_BASE64HEADER | CRYPT_STRING_NOCR, out + n, &need)) n += need;
    }
    CertCloseStore(st, 0);
    out[n] = 0;
    *pem = out;
    *len = n;
    return n > 0 ? 0 : -1;
}
int vlr_random(void *buf, int n) { return BCryptGenRandom(NULL, (PUCHAR)buf, (ULONG)n, BCRYPT_USE_SYSTEM_PREFERRED_RNG) == 0 ? 0 : -1; }

int vlr_exec(const char *cmd)
{
    int r;

    if (cmd == NULL) return 1;
    r = system(cmd); /* shortcut: ANSI code page, not UTF-8; upgrade with _wsystem when a non-ASCII command matters */
    return r == -1 ? (seterr(), -1) : r;
}


