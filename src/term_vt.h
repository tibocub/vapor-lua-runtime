#ifndef VLR_TERM_VT_H
#define VLR_TERM_VT_H
#include "vaporui.h"

/* Linux console raw keycode input (src/term_vt.c); no-ops on other systems and on terminal emulators */
int vlr_vt_start(void);  /* 1 if the console now reports keycodes (call after vlr_console_raw(1)) */
void vlr_vt_stop(void);  /* before vlr_console_raw(0) */
int vlr_vt_active(void);
int vlr_vt_events(VuiEvent *out, int max); /* read and translate what is queued; room for at least 192 events; -1 at end of input */
#endif
