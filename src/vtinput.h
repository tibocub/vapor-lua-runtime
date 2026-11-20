#ifndef VTINPUT_H
#define VTINPUT_H

enum { VT_CHAR = 1, VT_KEY, VT_MOUSE };
enum { VT_PRESS = 1, VT_RELEASE, VT_DRAG, VT_MOVE, VT_SCROLL_UP, VT_SCROLL_DOWN };
enum { VT_K_UP = 1, VT_K_DOWN, VT_K_RIGHT, VT_K_LEFT, VT_K_HOME, VT_K_END, VT_K_INSERT, VT_K_DELETE, VT_K_PAGEUP,
       VT_K_PAGEDOWN, VT_K_ENTER, VT_K_TAB, VT_K_BACKSPACE, VT_K_ESCAPE, VT_K_F1, VT_K_SPACE = VT_K_F1 + 12 };
#define VT_MAXPARAM 4

typedef struct { /* modifiers: 1 shift, 2 alt, 4 ctrl */
    int type, code, mods, action, x, y;
    char text[8]; /* VT_CHAR: the UTF-8 character; VT_KEY with code 0: the ASCII key */
} vtev;

typedef struct {
    int state, nparam, prefix, have, param[VT_MAXPARAM], u8n, u8left;
    char u8[5];
} vtinput;

void vtinput_init(vtinput *d);
int vtinput_feed(vtinput *d, unsigned char c, vtev *e); /* 1 if e holds an event */
int vtinput_pending(const vtinput *d);                  /* a lone ESC is waiting: flush it after a short pause */
int vtinput_flush(vtinput *d, vtev *e);
const char *vtinput_keyname(int code);

#endif
