/* vlr.netraw backend for POSIX and NuttX (with CONFIG_NET): BSD sockets, non-blocking, polled by vlr_wait. */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <stdlib.h>
#include <netinet/in.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>
#include <arpa/inet.h>

#include "vlr_platform.h"

static char g_err[160];

const char *vlr_net_error_text(void) { return g_err; }

static int fail(void)
{
    snprintf(g_err, sizeof g_err, "%s", strerror(errno));
    return VLR_NET_ERR;
}

static int nonblock(int fd)
{
    int fl = fcntl(fd, F_GETFL, 0);

    return fl < 0 ? -1 : fcntl(fd, F_SETFL, fl | O_NONBLOCK);
}

/* resolves host (NULL = wildcard) and walks the answers until one socket call sequence works; passive: bind, else connect */
static int open_socket(const char *host, int port, int type, int passive, int backlog, int *out)
{
    struct addrinfo hints, *res, *ai;
    char svc[16];
    int fd = -1, rc;

    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = type;
    hints.ai_flags = passive ? AI_PASSIVE : 0;
    snprintf(svc, sizeof svc, "%d", port);
    rc = getaddrinfo(host, svc, &hints, &res);
    if (rc != 0) {
        snprintf(g_err, sizeof g_err, "%s", gai_strerror(rc));
        return VLR_NET_ERR;
    }
    for (ai = res; ai != NULL; ai = ai->ai_next) {
        int one = 1;

        fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (fd < 0) continue;
        if (nonblock(fd) != 0) { close(fd); fd = -1; continue; }
        if (passive) {
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
            if (bind(fd, ai->ai_addr, ai->ai_addrlen) == 0 && (type == SOCK_DGRAM || listen(fd, backlog) == 0)) break;
        } else if (connect(fd, ai->ai_addr, ai->ai_addrlen) == 0 || errno == EINPROGRESS) {
            break;
        }
        close(fd);
        fd = -1;
    }
    freeaddrinfo(res);
    if (fd < 0) return fail();
    *out = fd;
    return 0;
}

int vlr_net_connect(const char *host, int port, int *h) { return open_socket(host, port, SOCK_STREAM, 0, 0, h); }
int vlr_net_listen(const char *host, int port, int backlog, int *h) { return open_socket(host, port, SOCK_STREAM, 1, backlog, h); }
int vlr_net_udp(const char *host, int port, int *h) { return open_socket(host, port, SOCK_DGRAM, 1, 0, h); }

static void addr_text(const struct sockaddr_storage *ss, char *addr, int addrlen, int *port)
{
    const void *a;

    addr[0] = 0;
    if (ss->ss_family == AF_INET) {
        a = &((const struct sockaddr_in *)ss)->sin_addr;
        *port = ntohs(((const struct sockaddr_in *)ss)->sin_port);
    } else {
        a = &((const struct sockaddr_in6 *)ss)->sin6_addr;
        *port = ntohs(((const struct sockaddr_in6 *)ss)->sin6_port);
    }
    inet_ntop(ss->ss_family, a, addr, (socklen_t)addrlen);
}

int vlr_net_accept(int h, int *client, char *addr, int addrlen, int *port)
{
    struct sockaddr_storage ss;
    socklen_t len = sizeof ss;
    int fd = accept(h, (struct sockaddr *)&ss, &len);

    if (fd < 0) return errno == EAGAIN || errno == EWOULDBLOCK ? VLR_NET_AGAIN : fail();
    if (nonblock(fd) != 0) { close(fd); return fail(); }
    addr_text(&ss, addr, addrlen, port);
    *client = fd;
    return 0;
}

int vlr_net_status(int h)
{
    int err = 0;
    socklen_t len = sizeof err;

    if (getsockopt(h, SOL_SOCKET, SO_ERROR, &err, &len) != 0) return fail();
    if (err != 0) { snprintf(g_err, sizeof g_err, "%s", strerror(err)); return VLR_NET_ERR; }
    return 0;
}

int vlr_net_recv(int h, char *buf, int n)
{
    ssize_t r = recv(h, buf, (size_t)n, 0);

    if (r > 0) return (int)r;
    if (r == 0) return VLR_NET_EOF;
    return errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR ? VLR_NET_AGAIN : fail();
}

int vlr_net_send(int h, const char *buf, int n)
{
    ssize_t r;
#ifdef MSG_NOSIGNAL
    r = send(h, buf, (size_t)n, MSG_NOSIGNAL); /* a closed peer is an error return, not SIGPIPE */
#else
    r = send(h, buf, (size_t)n, 0);
#endif
    if (r >= 0) return (int)r;
    return errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR ? VLR_NET_AGAIN : fail();
}

int vlr_net_sendto(int h, const char *host, int port, const char *buf, int n)
{
    struct addrinfo hints, *res;
    char svc[16];
    ssize_t r;
    int rc;

    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_DGRAM;
    snprintf(svc, sizeof svc, "%d", port);
    rc = getaddrinfo(host, svc, &hints, &res);
    if (rc != 0) { snprintf(g_err, sizeof g_err, "%s", gai_strerror(rc)); return VLR_NET_ERR; }
    r = sendto(h, buf, (size_t)n, 0, res->ai_addr, res->ai_addrlen);
    freeaddrinfo(res);
    if (r >= 0) return (int)r;
    return errno == EAGAIN || errno == EWOULDBLOCK ? VLR_NET_AGAIN : fail();
}

int vlr_net_recvfrom(int h, char *buf, int n, char *addr, int addrlen, int *port)
{
    struct sockaddr_storage ss;
    socklen_t len = sizeof ss;
    ssize_t r = recvfrom(h, buf, (size_t)n, 0, (struct sockaddr *)&ss, &len);

    if (r < 0) return errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR ? VLR_NET_AGAIN : fail();
    addr_text(&ss, addr, addrlen, port);
    return (int)r;
}

int vlr_net_name(int h, int peer, char *addr, int addrlen, int *port)
{
    struct sockaddr_storage ss;
    socklen_t len = sizeof ss;

    if ((peer ? getpeername(h, (struct sockaddr *)&ss, &len) : getsockname(h, (struct sockaddr *)&ss, &len)) != 0) return fail();
    addr_text(&ss, addr, addrlen, port);
    return 0;
}

#if !defined(__NuttX__) && !defined(__EMSCRIPTEN__)
#include <pthread.h>
#include <signal.h>

/* a worker thread runs getaddrinfo and writes one line ("OK address" / "ER message") into a pipe; the read end is the waitable handle */
typedef struct { char host[256]; int wfd; } rjob;

static void *resolver(void *arg)
{
    rjob *j = arg;
    struct addrinfo hints, *res;
    char line[200], num[INET6_ADDRSTRLEN + 1];
    sigset_t set;
    int rc;

    sigemptyset(&set);
    sigaddset(&set, SIGPIPE); /* the caller may have given up and closed its end */
    pthread_sigmask(SIG_BLOCK, &set, NULL);
    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    rc = getaddrinfo(j->host, NULL, &hints, &res);
    if (rc != 0) {
        snprintf(line, sizeof line, "ER %s\n", gai_strerror(rc));
    } else {
        num[0] = 0;
        if (res->ai_family == AF_INET) inet_ntop(AF_INET, &((struct sockaddr_in *)res->ai_addr)->sin_addr, num, sizeof num);
        else inet_ntop(AF_INET6, &((struct sockaddr_in6 *)res->ai_addr)->sin6_addr, num, sizeof num);
        snprintf(line, sizeof line, "OK %s\n", num);
        freeaddrinfo(res);
    }
    (void)!write(j->wfd, line, strlen(line));
    close(j->wfd);
    free(j);
    return NULL;
}

int vlr_net_resolve_start(const char *host, int *h)
{
    int fds[2];
    rjob *j;
    pthread_t t;

    if (pipe(fds) != 0) return fail();
    j = malloc(sizeof *j);
    if (j == NULL || strlen(host) >= sizeof j->host) { free(j); close(fds[0]); close(fds[1]); snprintf(g_err, sizeof g_err, "host name too long"); return VLR_NET_ERR; }
    strcpy(j->host, host);
    j->wfd = fds[1];
    nonblock(fds[0]);
    if (pthread_create(&t, NULL, resolver, j) != 0) { free(j); close(fds[0]); close(fds[1]); snprintf(g_err, sizeof g_err, "unsupported"); return VLR_NET_ERR; }
    pthread_detach(t);
    *h = fds[0];
    return 0;
}

int vlr_net_resolve_result(int h, char *addr, int addrlen)
{
    char line[256];
    ssize_t n = read(h, line, sizeof line - 1);

    if (n < 0) return errno == EAGAIN || errno == EINTR ? VLR_NET_AGAIN : fail();
    close(h);
    if (n >= 3 && line[0] == 'O' && line[1] == 'K') {
        line[n] = 0;
        line[strcspn(line, "\n")] = 0;
        snprintf(addr, (size_t)addrlen, "%s", line + 3);
        return 0;
    }
    line[n > 0 ? n : 0] = 0;
    line[strcspn(line, "\n")] = 0;
    snprintf(g_err, sizeof g_err, "%.150s", n > 3 ? line + 3 : "name resolution failed");
    return VLR_NET_ERR;
}
#else
int vlr_net_resolve_start(const char *host, int *h) { (void)host; (void)h; snprintf(g_err, sizeof g_err, "unsupported"); return VLR_NET_ERR; }
int vlr_net_resolve_result(int h, char *addr, int addrlen) { (void)h; (void)addr; (void)addrlen; return VLR_NET_ERR; }
#endif

int vlr_net_close(int h) { return close(h); }
