/* force-included into Lua's own sources (-include) so loslib.c's l_system can call into the core */
#ifndef VLR_LUA_H
#define VLR_LUA_H
int vlr_lua_system(const char *cmd);
#define l_system(cmd) vlr_lua_system(cmd)
#endif
