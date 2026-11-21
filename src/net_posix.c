/* vapor.netraw backend for POSIX and NuttX (with CONFIG_NET): BSD sockets, non-blocking, polled by vlr_wait. */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
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

int vlr_net_close(int h) { return close(h); }
