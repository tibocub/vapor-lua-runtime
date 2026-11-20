/* vlr backend for Windows (mingw or MSVC). Paths in and out are UTF-8. */
#include <windows.h>
#include <stdio.h>
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

uint32_t vlr_caps(void) { return VLR_CAP_FS | VLR_CAP_TTY; }

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
        /* shortcut: any console event (mouse, focus) counts as readable; filter with ReadConsoleInput when keys
           arrive as events, see the keyboard milestone */
        return WaitForSingleObject(h, 0) == WAIT_OBJECT_0;
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
    int i, count;

    for (i = 0; i < n; i++) {
        if (fds[i] != 0) { strcpy(g_err, "only handle 0 (console input) is waitable"); return -1; }
    }
    for (;;) {
        int64_t left;

        for (i = 0, count = 0; i < n; i++) count += (ready[i] = stdin_ready());
        if (count > 0) return count;
        left = end < 0 ? 1000000 : end - vlr_now_ms();
        if (left <= 0) return 0;
        Sleep((DWORD)(left < 10 ? left : 10)); /* shortcut: 10 ms polling, a handle-based wait would be exact */
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
