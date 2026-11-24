#include <stdio.h>
#include <string.h>

#include "lua.h"
#include "vlr.h"

#ifdef __EMSCRIPTEN__
void vlr_wasm_exit(int code); /* platform_wasm.c: tells the page the script ended */
#endif

int main(int argc, char **argv)
{
    int dialect51 = 1, step = 0, i = 1, code, r;
    lua_State *L;
    const char *code_text = NULL;

    for (; i < argc && strncmp(argv[i], "--", 2) == 0; i++) {
        if (strcmp(argv[i], "--dialect=5.4") == 0) dialect51 = 0;
        else if (strcmp(argv[i], "--step") == 0) step = 1; /* drive the loop like an embedding host (tests) */
        else { fprintf(stderr, "vlr: unknown option %s\n", argv[i]); return 2; }
    }
    /* source text to run: -e CODE, or the REPL when there is no script (or -i) */
    if (i < argc && strcmp(argv[i], "-e") == 0) {
        if (i + 1 >= argc) { fprintf(stderr, "vlr: -e needs code\n"); return 2; }
        code_text = argv[i + 1];
        i += 2;
    } else if (i >= argc || strcmp(argv[i], "-i") == 0) {
        code_text = "require('vlr.repl')()";
        if (i < argc) i++;
    }
    L = vlr_newstate(dialect51, NULL, NULL);
    if (L == NULL) return 1;
    if (step || code_text) {
        code = code_text ? vlr_spawn_string(L, code_text, argc - i, argv + i) : vlr_spawn_file(L, argv[i], argc - i - 1, argv + i + 1);
        while (code == 0 && (r = vlr_step(L, step ? 5 : -1, NULL)) > 0) {}
        if (code == 0) code = r < 0 || vlr_failed(L);
    } else {
        code = vlr_run_file(L, argv[i], argc - i - 1, argv + i + 1);
    }
    lua_close(L);
#ifdef __EMSCRIPTEN__
    vlr_wasm_exit(code); /* the loop above blocks through Asyncify, like on any other host */
#endif
    return code;
}
