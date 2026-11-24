/*
 * vlr_platform.h -- the whole porting surface of vlr. The core (src/vlr.c) includes no OS header; a backend
 * (src/platform_<target>.c) implements this file. Return 0 on success, -1 on error unless stated.
 */
#ifndef VLR_PLATFORM_H
#define VLR_PLATFORM_H

#include <stddef.h>
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

/* or'ed into a handle passed to vlr_wait: wait until it is writable instead of readable (connect, send backpressure).
   The handle is reported ready with the flag still set. */
#define VLR_WRITABLE 0x40000000

/* calls cb for every entry except . and ..; a non-zero return from cb stops the listing */
int vlr_fs_list(const char *path, int (*cb)(void *ud, const char *name), void *ud);
int vlr_fs_mkdir(const char *path);
int vlr_fs_rmdir(const char *path); /* empty directories only; os.remove cannot do this on Windows */
int vlr_fs_stat(const char *path, vlr_stat *st);

/*
 * Networking (optional module "vapor.netraw", capability VLR_CAP_NET). Handles are sockets mapped to ints, waitable
 * with vlr_wait (VLR_WRITABLE for connect completion and send). Everything is non-blocking except name resolution,
 * which blocks the whole process while it runs (shortcut: a resolver handle would be exact).
 * Return codes of the data calls: >0 or 0 = ok (bytes), VLR_NET_AGAIN = try again after vlr_wait, VLR_NET_EOF = peer closed
 * (recv, accept never), VLR_NET_ERR = failed, text in vlr_net_error_text().
 */
#define VLR_NET_AGAIN (-2)
#define VLR_NET_EOF   (-3)
#define VLR_NET_ERR   (-1)
int vlr_net_connect(const char *host, int port, int *h);  /* starts a TCP connect: wait VLR_WRITABLE, then vlr_net_status */
int vlr_net_listen(const char *host, int port, int backlog, int *h); /* host NULL = all interfaces, port 0 = any */
int vlr_net_accept(int h, int *client, char *addr, int addrlen, int *port);
int vlr_net_status(int h);                                /* 0 if the socket has no pending error (connect succeeded) */
int vlr_net_recv(int h, char *buf, int n);
int vlr_net_send(int h, const char *buf, int n);
int vlr_net_udp(const char *host, int port, int *h);      /* bound UDP socket (host NULL = all, port 0 = any) */
int vlr_net_sendto(int h, const char *host, int port, const char *buf, int n);
int vlr_net_recvfrom(int h, char *buf, int n, char *addr, int addrlen, int *port);
int vlr_net_name(int h, int peer, char *addr, int addrlen, int *port); /* local or peer address */
/* Name resolution that does not stop the process: vlr_net_resolve_start returns a waitable handle (wait for it readable with vlr_wait), then
   vlr_net_resolve_result gives the numeric address (0), VLR_NET_AGAIN (not yet) or VLR_NET_ERR; the handle is closed by the result call when it is
   done, or by vlr_net_close if the caller gives up. Targets that cannot (NuttX, wasm) return VLR_NET_ERR from start with the text "unsupported": use the blocking connect. */
int vlr_net_resolve_start(const char *host, int *h);
int vlr_net_resolve_result(int h, char *addr, int addrlen);
int vlr_net_close(int h);
const char *vlr_net_error_text(void);

/* the system's trusted root certificates as PEM text in a malloc'd buffer (Windows certificate store); -1 where there is none (the TLS layer then reads the usual bundle files) */
int vlr_system_roots(char **pem, size_t *len);

/* n random bytes from the operating system's source (TLS seeding); 0 on success, -1 if there is none */
int vlr_random(void *buf, int n);

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
