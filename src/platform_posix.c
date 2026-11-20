/* vlr backend for POSIX hosts (Linux, macOS, BSD) */
#define _POSIX_C_SOURCE 200809L
#include <dirent.h>
#include <errno.h>
#include <poll.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include "vlr_platform.h"

uint32_t vlr_caps(void)
{
    return VLR_CAP_FS | VLR_CAP_TTY;
}

int64_t vlr_now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

int vlr_wait(const int *fds, int n, int *ready, int timeout_ms)
{
    struct pollfd p[VLR_MAX_FDS];
    int i, r, count = 0;

    if (n > VLR_MAX_FDS) { errno = EINVAL; return -1; }
    for (i = 0; i < n; i++) { p[i].fd = fds[i]; p[i].events = POLLIN; p[i].revents = 0; }
    r = poll(p, (nfds_t)n, timeout_ms);
    if (r < 0) return errno == EINTR ? 0 : -1;
    for (i = 0; i < n; i++) {
        ready[i] = (p[i].revents & (POLLIN | POLLHUP | POLLERR)) != 0; /* HUP/ERR: a read will report it */
        count += ready[i];
    }
    return count;
}

int vlr_fs_list(const char *path, int (*cb)(void *, const char *), void *ud)
{
    DIR *d = opendir(path);
    struct dirent *e;

    if (d == NULL) return -1;
    while ((e = readdir(d)) != NULL) {
        if (strcmp(e->d_name, ".") == 0 || strcmp(e->d_name, "..") == 0) continue;
        if (cb(ud, e->d_name)) break;
    }
    closedir(d);
    return 0;
}

int vlr_fs_mkdir(const char *path)
{
    return mkdir(path, 0777);
}

int vlr_fs_rmdir(const char *path)
{
    return rmdir(path);
}

int vlr_fs_stat(const char *path, vlr_stat *st)
{
    struct stat s;

    if (stat(path, &s) != 0) return -1;
    st->is_dir = S_ISDIR(s.st_mode);
    st->size = s.st_size;
    st->mtime = s.st_mtime;
    return 0;
}

const char *vlr_last_error(void)
{
    return strerror(errno);
}
