/* vapor.tlsraw: a TLS client engine without any I/O (BearSSL, sibling checkout @EXT@/BearSSL). Lua (lua/tls.lua) moves the bytes between the engine and
   a socket stream, so waiting stays in the scheduler and another backend (mbedTLS on NuttX, OpenSSL...) only has to offer the same calls.
     tlsraw.anchors(pem)        -> trust anchors parsed from a PEM bundle (userdata, reusable for many connections), or nil, err
     tlsraw.client(anchors, host) -> engine; the certificate chain AND the host name are verified, there is no switch to turn that off
     e:state() -> bits: 1 closed, 2 has records to send, 4 wants records, 8 can take application data, 16 has application data
     e:take()  -> the records to send to the peer (and marks them sent), or nil     e:put(data) -> bytes consumed (records received from the peer)
     e:send(data) -> bytes accepted (application data to the peer)   e:flush()   e:recv() -> application data or nil   e:close() -> close_notify
     e:error() -> nil, or code, text */
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "bearssl.h"
#include "lauxlib.h"
#include "lua.h"
#include "vlr_platform.h"

#define ANCHORS_MT "vapor.tlsraw.anchors"
#define ENGINE_MT "vapor.tlsraw.engine"

typedef struct {
    br_x509_trust_anchor *list;
    size_t n, cap;
} anchors;

typedef struct {
    br_ssl_client_context sc;
    br_x509_minimal_context xc;
    anchors *ta;
    int ta_ref; /* registry reference keeping the anchors alive */
    unsigned char iobuf[BR_SSL_BUFSIZE_BIDI];
} engine;

/* ---- PEM bundle -> trust anchors ---- */

typedef struct { unsigned char *data; size_t len, cap; } blob;

static void blob_add(void *ctx, const void *buf, size_t len)
{
    blob *b = ctx;

    if (b->len + len > b->cap) {
        size_t cap = b->cap ? b->cap * 2 : 2048;
        unsigned char *p;

        while (cap < b->len + len) cap *= 2;
        p = realloc(b->data, cap);
        if (p == NULL) return;
        b->data = p;
        b->cap = cap;
    }
    if (b->len + len <= b->cap) { memcpy(b->data + b->len, buf, len); b->len += len; }
}

static void dn_add(void *ctx, const void *buf, size_t len) { blob_add(ctx, buf, len); }

static void free_anchor(br_x509_trust_anchor *ta)
{
    free(ta->dn.data);
    if (ta->pkey.key_type == BR_KEYTYPE_RSA) { free(ta->pkey.key.rsa.n); free(ta->pkey.key.rsa.e); }
    else if (ta->pkey.key_type == BR_KEYTYPE_EC) free(ta->pkey.key.ec.q);
}

static void *dup(const void *p, size_t n)
{
    void *q = malloc(n ? n : 1);

    if (q != NULL) memcpy(q, p, n);
    return q;
}

/* one DER certificate -> an anchor appended to a; 0 on success */
static int add_cert(anchors *a, const unsigned char *der, size_t len)
{
    br_x509_decoder_context dc;
    blob dn = {0};
    br_x509_pkey *pk;
    br_x509_trust_anchor ta;

    br_x509_decoder_init(&dc, dn_add, &dn);
    br_x509_decoder_push(&dc, der, len);
    pk = br_x509_decoder_get_pkey(&dc);
    if (pk == NULL || (pk->key_type != BR_KEYTYPE_RSA && pk->key_type != BR_KEYTYPE_EC)) { free(dn.data); return -1; }
    memset(&ta, 0, sizeof ta);
    ta.dn.data = dn.data;
    ta.dn.len = dn.len;
    ta.flags = br_x509_decoder_isCA(&dc) ? BR_X509_TA_CA : 0;
    ta.pkey.key_type = pk->key_type;
    if (pk->key_type == BR_KEYTYPE_RSA) {
        ta.pkey.key.rsa.n = dup(pk->key.rsa.n, pk->key.rsa.nlen);
        ta.pkey.key.rsa.nlen = pk->key.rsa.nlen;
        ta.pkey.key.rsa.e = dup(pk->key.rsa.e, pk->key.rsa.elen);
        ta.pkey.key.rsa.elen = pk->key.rsa.elen;
    } else {
        ta.pkey.key.ec.curve = pk->key.ec.curve;
        ta.pkey.key.ec.q = dup(pk->key.ec.q, pk->key.ec.qlen);
        ta.pkey.key.ec.qlen = pk->key.ec.qlen;
    }
    if (a->n == a->cap) {
        size_t cap = a->cap ? a->cap * 2 : 64;
        br_x509_trust_anchor *p = realloc(a->list, cap * sizeof *p);

        if (p == NULL) { free_anchor(&ta); return -1; }
        a->list = p;
        a->cap = cap;
    }
    a->list[a->n++] = ta;
    return 0;
}

static int l_anchors(lua_State *L)
{
    size_t len;
    const char *pem = luaL_checklstring(L, 1, &len);
    anchors *a = lua_newuserdatauv(L, sizeof *a, 0);
    br_pem_decoder_context pc;
    blob der = {0};
    int inobj = 0, bad = 0;
    size_t pos = 0;

    memset(a, 0, sizeof *a);
    luaL_setmetatable(L, ANCHORS_MT);
    br_pem_decoder_init(&pc);
    while (pos < len) {
        pos += br_pem_decoder_push(&pc, pem + pos, len - pos);
        for (;;) {
            int ev = br_pem_decoder_event(&pc);

            if (ev == 0) break;
            if (ev == BR_PEM_BEGIN_OBJ) {
                const char *name = br_pem_decoder_name(&pc);

                inobj = strcmp(name, "CERTIFICATE") == 0 || strcmp(name, "X509 CERTIFICATE") == 0;
                der.len = 0;
                if (inobj) br_pem_decoder_setdest(&pc, blob_add, &der); else br_pem_decoder_setdest(&pc, 0, 0);
            } else if (ev == BR_PEM_END_OBJ) {
                if (inobj && add_cert(a, der.data, der.len) != 0) bad++; /* a certificate with a key type we cannot use is skipped */
                inobj = 0;
            } else if (ev == BR_PEM_ERROR) {
                bad++;
                inobj = 0;
            }
        }
    }
    free(der.data);
    if (a->n == 0) {
        lua_pushnil(L);
        lua_pushstring(L, "no usable certificates in the PEM text");
        return 2;
    }
    (void)bad;
    return 1;
}

static int anchors_gc(lua_State *L)
{
    anchors *a = luaL_checkudata(L, 1, ANCHORS_MT);
    size_t i;

    for (i = 0; i < a->n; i++) free_anchor(&a->list[i]);
    free(a->list);
    a->list = NULL;
    a->n = 0;
    return 0;
}

static int anchors_len(lua_State *L)
{
    lua_pushinteger(L, (lua_Integer)((anchors *)luaL_checkudata(L, 1, ANCHORS_MT))->n);
    return 1;
}

/* ---- the engine ---- */

static engine *check(lua_State *L) { return luaL_checkudata(L, 1, ENGINE_MT); }

static int l_client(lua_State *L)
{
    anchors *a = luaL_checkudata(L, 1, ANCHORS_MT);
    const char *host = luaL_checkstring(L, 2);
    engine *e;
    unsigned char seed[32];
    uint64_t now = (uint64_t)time(NULL);

    if (vlr_random(seed, sizeof seed) != 0) {
        lua_pushnil(L);
        lua_pushstring(L, "no source of random numbers on this system");
        return 2;
    }
    e = lua_newuserdatauv(L, sizeof *e, 0);
    luaL_setmetatable(L, ENGINE_MT);
    br_ssl_client_init_full(&e->sc, &e->xc, a->list, a->n);
    br_x509_minimal_set_time(&e->xc, (uint32_t)(now / 86400 + 719528), (uint32_t)(now % 86400)); /* days since year 0 */
    br_ssl_engine_set_buffer(&e->sc.eng, e->iobuf, sizeof e->iobuf, 1);
    br_ssl_engine_inject_entropy(&e->sc.eng, seed, sizeof seed);
    if (!br_ssl_client_reset(&e->sc, host, 0)) {
        lua_pushnil(L);
        lua_pushfstring(L, "TLS setup failed (error %d)", br_ssl_engine_last_error(&e->sc.eng));
        return 2;
    }
    lua_pushvalue(L, 1); /* keep the anchors alive as long as the engine */
    e->ta_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    e->ta = a;
    return 1;
}

static int engine_state(lua_State *L)
{
    lua_pushinteger(L, br_ssl_engine_current_state(&check(L)->sc.eng));
    return 1;
}

static int engine_take(lua_State *L)
{
    engine *e = check(L);
    size_t n;
    unsigned char *p = br_ssl_engine_sendrec_buf(&e->sc.eng, &n);

    if (p == NULL || n == 0) { lua_pushnil(L); return 1; }
    lua_pushlstring(L, (char *)p, n);
    br_ssl_engine_sendrec_ack(&e->sc.eng, n);
    return 1;
}

static int engine_put(lua_State *L)
{
    engine *e = check(L);
    size_t len, n;
    const char *data = luaL_checklstring(L, 2, &len);
    unsigned char *p = br_ssl_engine_recvrec_buf(&e->sc.eng, &n);

    if (p == NULL) { lua_pushinteger(L, 0); return 1; }
    if (n > len) n = len;
    memcpy(p, data, n);
    br_ssl_engine_recvrec_ack(&e->sc.eng, n);
    lua_pushinteger(L, (lua_Integer)n);
    return 1;
}

static int engine_send(lua_State *L)
{
    engine *e = check(L);
    size_t len, n;
    const char *data = luaL_checklstring(L, 2, &len);
    unsigned char *p = br_ssl_engine_sendapp_buf(&e->sc.eng, &n);

    if (p == NULL) { lua_pushinteger(L, 0); return 1; }
    if (n > len) n = len;
    memcpy(p, data, n);
    br_ssl_engine_sendapp_ack(&e->sc.eng, n);
    lua_pushinteger(L, (lua_Integer)n);
    return 1;
}

static int engine_flush(lua_State *L)
{
    br_ssl_engine_flush(&check(L)->sc.eng, 0);
    return 0;
}

static int engine_recv(lua_State *L)
{
    engine *e = check(L);
    size_t n;
    unsigned char *p = br_ssl_engine_recvapp_buf(&e->sc.eng, &n);

    if (p == NULL || n == 0) { lua_pushnil(L); return 1; }
    lua_pushlstring(L, (char *)p, n);
    br_ssl_engine_recvapp_ack(&e->sc.eng, n);
    return 1;
}

static int engine_close(lua_State *L)
{
    br_ssl_engine_close(&check(L)->sc.eng);
    return 0;
}

static const char *error_text(int code)
{
    switch (code) {
    case BR_ERR_X509_EXPIRED: return "certificate expired or not yet valid";
    case BR_ERR_X509_NOT_TRUSTED: return "certificate is not trusted (unknown issuer)";
    case BR_ERR_X509_BAD_SERVER_NAME: return "certificate does not match the host name";
    case BR_ERR_X509_INVALID_VALUE: case BR_ERR_X509_TRUNCATED: case BR_ERR_X509_EXTRA_ELEMENT:
    case BR_ERR_X509_UNEXPECTED: return "malformed certificate";
    case BR_ERR_X509_BAD_SIGNATURE: return "certificate signature is bad";
    case BR_ERR_X509_TIME_UNKNOWN: return "cannot check certificate dates";
    case BR_ERR_X509_FORBIDDEN_KEY_USAGE: return "certificate key usage forbids this use";
    case BR_ERR_X509_WEAK_PUBLIC_KEY: return "certificate public key is too weak";
    case BR_ERR_X509_NOT_CA: return "issuer is not a certificate authority";
    case BR_ERR_X509_EMPTY_CHAIN: return "server sent no certificate";
    case BR_ERR_IO: return "connection error";
    case BR_ERR_BAD_VERSION: case BR_ERR_UNSUPPORTED_VERSION: return "no common TLS version";
    case BR_ERR_NO_CLIENT_AUTH: return "client certificate required";
    case BR_ERR_RECV_FATAL_ALERT: return "the server sent a fatal alert";
    default: return "TLS error";
    }
}

static int engine_error(lua_State *L)
{
    int code = br_ssl_engine_last_error(&check(L)->sc.eng);

    if (code == BR_ERR_OK) { lua_pushnil(L); return 1; }
    lua_pushinteger(L, code);
    lua_pushstring(L, error_text(code));
    return 2;
}

static int engine_gc(lua_State *L)
{
    engine *e = check(L);

    luaL_unref(L, LUA_REGISTRYINDEX, e->ta_ref);
    return 0;
}

int luaopen_vapor_tlsraw(lua_State *L)
{
    static const luaL_Reg funcs[] = {{"anchors", l_anchors}, {"client", l_client}, {NULL, NULL}};
    static const luaL_Reg methods[] = {{"state", engine_state}, {"take", engine_take}, {"put", engine_put}, {"send", engine_send},
                                       {"flush", engine_flush}, {"recv", engine_recv}, {"close", engine_close},
                                       {"error", engine_error}, {NULL, NULL}};

    luaL_newmetatable(L, ANCHORS_MT);
    lua_pushcfunction(L, anchors_gc);
    lua_setfield(L, -2, "__gc");
    lua_pushcfunction(L, anchors_len);
    lua_setfield(L, -2, "__len");
    lua_pop(L, 1);
    luaL_newmetatable(L, ENGINE_MT);
    lua_pushcfunction(L, engine_gc);
    lua_setfield(L, -2, "__gc");
    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
    luaL_newlib(L, funcs);
    return 1;
}
