/* vapor.netraw backend for Windows: Winsock, non-blocking, polled by vlr_wait (WSAPoll). Handles are SOCKETs cast to int. */
#include <winsock2.h>
#include <ws2tcpip.h>
#include <stdio.h>
#include <string.h>

#include "vlr_platform.h"

static char g_err[160];
static int g_started;

const char *vlr_net_error_text(void) { return g_err; }

static int fail_code(int code)
{
    DWORD n = FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, NULL, (DWORD)code, 0, g_err, sizeof g_err, NULL);

    if (n == 0) snprintf(g_err, sizeof g_err, "socket error %d", code);
    while (n > 0 && (g_err[n - 1] == '\r' || g_err[n - 1] == '\n' || g_err[n - 1] == ' ')) g_err[--n] = 0;
    return VLR_NET_ERR;
}

static int fail(void) { return fail_code(WSAGetLastError()); }

static int start(void)
{
    WSADATA d;

    if (!g_started) {
        int r = WSAStartup(MAKEWORD(2, 2), &d);

        if (r != 0) return fail_code(r);
        g_started = 1;
    }
    return 0;
}

static int nonblock(SOCKET s)
{
    u_long on = 1;

    return ioctlsocket(s, FIONBIO, &on);
}

static int again(int e) { return e == WSAEWOULDBLOCK || e == WSAEINPROGRESS || e == WSAEINTR; }

static int open_socket(const char *host, int port, int type, int passive, int backlog, int *out)
{
    struct addrinfo hints, *res, *ai;
    char svc[16];
    SOCKET fd = INVALID_SOCKET;
    int rc;

    if (start() != 0) return VLR_NET_ERR;
    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = type;
    hints.ai_flags = passive ? AI_PASSIVE : 0;
    snprintf(svc, sizeof svc, "%d", port);
    rc = getaddrinfo(host, svc, &hints, &res);
    if (rc != 0) return fail_code(rc);
    for (ai = res; ai != NULL; ai = ai->ai_next) {
        fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (fd == INVALID_SOCKET) continue;
        if (nonblock(fd) != 0) { closesocket(fd); fd = INVALID_SOCKET; continue; }
        if (passive) {
            if (bind(fd, ai->ai_addr, (int)ai->ai_addrlen) == 0 && (type == SOCK_DGRAM || listen(fd, backlog) == 0)) break;
        } else if (connect(fd, ai->ai_addr, (int)ai->ai_addrlen) == 0 || WSAGetLastError() == WSAEWOULDBLOCK) {
            break;
        }
        closesocket(fd);
        fd = INVALID_SOCKET;
    }
    freeaddrinfo(res);
    if (fd == INVALID_SOCKET) return fail();
    *out = (int)fd;
    return 0;
}

int vlr_net_connect(const char *host, int port, int *h) { return open_socket(host, port, SOCK_STREAM, 0, 0, h); }
int vlr_net_listen(const char *host, int port, int backlog, int *h) { return open_socket(host, port, SOCK_STREAM, 1, backlog, h); }
int vlr_net_udp(const char *host, int port, int *h) { return open_socket(host, port, SOCK_DGRAM, 1, 0, h); }

static void addr_text(const struct sockaddr_storage *ss, char *addr, int addrlen, int *port)
{
    DWORD len = (DWORD)addrlen;
    struct sockaddr_storage copy = *ss;

    *port = ntohs(ss->ss_family == AF_INET ? ((const struct sockaddr_in *)ss)->sin_port : ((const struct sockaddr_in6 *)ss)->sin6_port);
    addr[0] = 0;
    /* the port is reported separately: drop it from the text form */
    if (copy.ss_family == AF_INET) ((struct sockaddr_in *)&copy)->sin_port = 0;
    else ((struct sockaddr_in6 *)&copy)->sin6_port = 0;
    WSAAddressToStringA((LPSOCKADDR)&copy, (DWORD)(copy.ss_family == AF_INET ? sizeof(struct sockaddr_in) : sizeof(struct sockaddr_in6)), NULL, addr, &len);
}

int vlr_net_accept(int h, int *client, char *addr, int addrlen, int *port)
{
    struct sockaddr_storage ss;
    int len = (int)sizeof ss;
    SOCKET fd = accept((SOCKET)h, (struct sockaddr *)&ss, &len);

    if (fd == INVALID_SOCKET) return again(WSAGetLastError()) ? VLR_NET_AGAIN : fail();
    if (nonblock(fd) != 0) { closesocket(fd); return fail(); }
    addr_text(&ss, addr, addrlen, port);
    *client = (int)fd;
    return 0;
}

int vlr_net_status(int h)
{
    int err = 0, len = (int)sizeof err;

    if (getsockopt((SOCKET)h, SOL_SOCKET, SO_ERROR, (char *)&err, &len) != 0) return fail();
    return err != 0 ? fail_code(err) : 0;
}

int vlr_net_recv(int h, char *buf, int n)
{
    int r = recv((SOCKET)h, buf, n, 0);

    if (r > 0) return r;
    if (r == 0) return VLR_NET_EOF;
    return again(WSAGetLastError()) ? VLR_NET_AGAIN : fail();
}

int vlr_net_send(int h, const char *buf, int n)
{
    int r = send((SOCKET)h, buf, n, 0);

    if (r >= 0) return r;
    return again(WSAGetLastError()) ? VLR_NET_AGAIN : fail();
}

int vlr_net_sendto(int h, const char *host, int port, const char *buf, int n)
{
    struct addrinfo hints, *res;
    char svc[16];
    int r, rc;

    if (start() != 0) return VLR_NET_ERR;
    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_DGRAM;
    snprintf(svc, sizeof svc, "%d", port);
    rc = getaddrinfo(host, svc, &hints, &res);
    if (rc != 0) return fail_code(rc);
    r = sendto((SOCKET)h, buf, n, 0, res->ai_addr, (int)res->ai_addrlen);
    freeaddrinfo(res);
    if (r >= 0) return r;
    return again(WSAGetLastError()) ? VLR_NET_AGAIN : fail();
}

int vlr_net_recvfrom(int h, char *buf, int n, char *addr, int addrlen, int *port)
{
    struct sockaddr_storage ss;
    int len = (int)sizeof ss, r = recvfrom((SOCKET)h, buf, n, 0, (struct sockaddr *)&ss, &len);

    if (r < 0) {
        int e = WSAGetLastError();

        /* a UDP "connection reset" is an ICMP echo of an earlier send to a closed port: not a failure of this socket */
        return again(e) || e == WSAECONNRESET ? VLR_NET_AGAIN : fail_code(e);
    }
    addr_text(&ss, addr, addrlen, port);
    return r;
}

int vlr_net_name(int h, int peer, char *addr, int addrlen, int *port)
{
    struct sockaddr_storage ss;
    int len = (int)sizeof ss;

    if ((peer ? getpeername((SOCKET)h, (struct sockaddr *)&ss, &len) : getsockname((SOCKET)h, (struct sockaddr *)&ss, &len)) != 0) return fail();
    addr_text(&ss, addr, addrlen, port);
    return 0;
}

int vlr_net_close(int h) { return closesocket((SOCKET)h); }
