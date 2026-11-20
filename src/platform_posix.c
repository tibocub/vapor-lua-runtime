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

#ifndef VLR_POSIX_NO_WAIT /* wasm brings its own vlr_caps and a non-blocking vlr_wait */
uint32_t vlr_caps(void)
{
    return VLR_CAP_FS | VLR_CAP_TTY | VLR_CAP_EXEC;
}
#endif

int64_t vlr_now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

#ifndef VLR_POSIX_NO_WAIT
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

#endif

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

#ifdef VLR_POSIX_NO_WAIT
int vlr_exec(const char *cmd) /* wasm: no processes */
{
    errno = ENOSYS;
    return cmd == NULL ? 0 : -1;
}
#elif defined(__NuttX__)
/* NuttX has no system(): run the command through vaporShell (-c). The shell is VLR_NUTTX_SHELL. */
#include <spawn.h>
#include <sys/wait.h>
#ifndef VLR_NUTTX_SHELL
#define VLR_NUTTX_SHELL "vaporshell"
#endif
int vlr_exec(const char *cmd)
{
    char *argv[4];
    pid_t pid;
    int status = 0;

    if (cmd == NULL) return 1;
    argv[0] = (char *)VLR_NUTTX_SHELL;
    argv[1] = (char *)"-c";
    argv[2] = (char *)cmd;
    argv[3] = NULL;
    if (posix_spawnp(&pid, argv[0], NULL, NULL, argv, environ) != 0) return -1;
    if (waitpid(pid, &status, 0) < 0) return -1;
    return WIFEXITED(status) ? WEXITSTATUS(status) : 128;
}
#else
#include <stdlib.h>
#include <sys/wait.h>
int vlr_exec(const char *cmd)
{
    int r;

    if (cmd == NULL) return system(NULL) != 0;
    r = system(cmd);
    if (r == -1) return -1;
    return WIFEXITED(r) ? WEXITSTATUS(r) : 128 + (WIFSIGNALED(r) ? WTERMSIG(r) : 0);
}
#endif

const char *vlr_last_error(void)
{
    return strerror(errno);
}
