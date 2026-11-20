/*
 * vlr_platform.h -- the whole porting surface of vlr. The core (src/vlr.c) includes no OS header; a backend
 * (src/platform_<target>.c) implements this file. Return 0 on success, -1 on error unless stated.
 */
#ifndef VLR_PLATFORM_H
#define VLR_PLATFORM_H

#include <stdint.h>

/* capability bits reported to Lua as vapor.caps (a backend ORs what it really supports) */
#define VLR_CAP_FS   0x01
#define VLR_CAP_NET  0x02
#define VLR_CAP_GFX  0x04
#define VLR_CAP_TTY  0x08
#define VLR_CAP_DLOPEN 0x10
#define VLR_CAP_EXEC 0x20

#define VLR_MAX_FDS 64

typedef struct {
    int is_dir;
    int64_t size;
    int64_t mtime; /* seconds since the epoch, 0 if the filesystem has none */
} vlr_stat;

uint32_t vlr_caps(void);

/* monotonic milliseconds */
int64_t vlr_now_ms(void);

/*
 * fds are backend handles: real file descriptors on POSIX and NuttX; on other backends whatever the backend maps
 * (0 is always the console input, 1/2 are not waitable). Windows consoles and wasm have no pollable fds.
 *
 * Block until one of fds[0..n) is readable or timeout_ms elapses (-1 = no timeout, 0 = just poll).
 * Sets ready[i] to 1 or 0. Returns the number of ready fds, 0 on timeout, -1 on error.
 * A backend without blocking (wasm) may return early; the scheduler loops.
 */
int vlr_wait(const int *fds, int n, int *ready, int timeout_ms);

/* calls cb for every entry except . and ..; a non-zero return from cb stops the listing */
int vlr_fs_list(const char *path, int (*cb)(void *ud, const char *name), void *ud);
int vlr_fs_mkdir(const char *path);
int vlr_fs_rmdir(const char *path); /* empty directories only; os.remove cannot do this on Windows */
int vlr_fs_stat(const char *path, vlr_stat *st);

/*
 * Console (terminal) access for input events. Non-blocking: vlr_console_read returns the bytes available now
 * (0 if none, -1 at end of input); wait for readiness with vlr_wait on handle 0 first. vlr_console_raw switches the
 * console between line mode (0) and raw, unechoed input (1; the previous mode is restored by raw(0)). Backends without
 * a terminal (wasm) have no console bytes: the page pushes events directly. vlr_console_size gives columns and rows.
 */
int vlr_console_read(char *buf, int n);
int vlr_console_raw(int enable);
int vlr_console_size(int *cols, int *rows);

/*
 * Runs a shell command line (os.execute). Returns the exit code 0..255, or -1 with vlr_last_error set.
 * cmd == NULL asks whether a shell exists: returns 1 or 0. Backends without one return -1/0 and omit VLR_CAP_EXEC.
 */
int vlr_exec(const char *cmd);

/* flush console output (a partial last line included) before the process or script ends */
void vlr_flush(void);

/* text of the last failed call above */
const char *vlr_last_error(void);

#endif
