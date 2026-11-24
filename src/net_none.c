/* vlr.netraw for targets without sockets (wasm): every call fails, vlr.caps.net is false there. */
#include <errno.h>

#include "vlr_platform.h"

static int none(void) { return VLR_NET_ERR; }

const char *vlr_net_error_text(void) { return "networking is not available on this target"; }
int vlr_net_connect(const char *host, int port, int *h) { (void)host; (void)port; (void)h; return none(); }
int vlr_net_listen(const char *host, int port, int backlog, int *h) { (void)host; (void)port; (void)backlog; (void)h; return none(); }
int vlr_net_accept(int h, int *client, char *addr, int addrlen, int *port) { (void)h; (void)client; (void)addr; (void)addrlen; (void)port; return none(); }
int vlr_net_status(int h) { (void)h; return none(); }
int vlr_net_recv(int h, char *buf, int n) { (void)h; (void)buf; (void)n; return none(); }
int vlr_net_send(int h, const char *buf, int n) { (void)h; (void)buf; (void)n; return none(); }
int vlr_net_udp(const char *host, int port, int *h) { (void)host; (void)port; (void)h; return none(); }
int vlr_net_sendto(int h, const char *host, int port, const char *buf, int n) { (void)h; (void)host; (void)port; (void)buf; (void)n; return none(); }
int vlr_net_recvfrom(int h, char *buf, int n, char *addr, int addrlen, int *port) { (void)h; (void)buf; (void)n; (void)addr; (void)addrlen; (void)port; return none(); }
int vlr_net_name(int h, int peer, char *addr, int addrlen, int *port) { (void)h; (void)peer; (void)addr; (void)addrlen; (void)port; return none(); }
int vlr_net_close(int h) { (void)h; return 0; }
int vlr_net_resolve_start(const char *host, int *h) { (void)host; (void)h; return none(); }
int vlr_net_resolve_result(int h, char *addr, int addrlen) { (void)h; (void)addr; (void)addrlen; return none(); }
