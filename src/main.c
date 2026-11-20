#include <stdio.h>
#include <string.h>

#include "lua.h"
#include "vlr.h"

int main(int argc, char **argv)
{
    int dialect51 = 1, i = 1, code;
    lua_State *L;

    if (i < argc && strcmp(argv[i], "--dialect=5.4") == 0) { dialect51 = 0; i++; }
    if (i >= argc) {
        fprintf(stderr, "usage: vlr [--dialect=5.4] script.lua [args]\n");
        return 2;
    }
    L = vlr_newstate(dialect51);
    if (L == NULL) return 1;
    code = vlr_run_file(L, argv[i], argc - i - 1, argv + i + 1);
    lua_close(L);
    return code;
}
