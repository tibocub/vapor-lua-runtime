/* embed NAME file.lua  ->  C source with `const unsigned char vlr_lua_NAME[]` and its length (host tool) */
#include <stdio.h>

int main(int argc, char **argv)
{
    FILE *f;
    int c;
    unsigned n = 0;

    if (argc != 3 || (f = fopen(argv[2], "rb")) == NULL) { fprintf(stderr, "usage: embed name file\n"); return 1; }
    printf("const unsigned char vlr_lua_%s[] = {", argv[1]);
    while ((c = fgetc(f)) != EOF) { printf("%s%u,", n % 16 ? "" : "\n", c); n++; }
    printf("0};\nconst unsigned int vlr_lua_%s_len = %u;\n", argv[1], n);
    return 0;
}
