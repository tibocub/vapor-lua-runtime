/*
 * vtinput: decodes terminal input bytes into key/char/mouse events. Pure (no OS calls), used by the posix, win32 and
 * NuttX backends' consoles. Understands UTF-8 text, control keys, CSI/SS3 cursor and function keys with modifiers,
 * Shift+Tab, Alt+key (ESC prefix) and SGR mouse (ESC [ < b;x;y M|m). Bracketed paste is not enabled: pasted text
 * arrives as chars. A lone ESC is only reported by vtinput_flush (the caller waits ~25 ms for more bytes first).
 */
#include <string.h>

#include "vtinput.h"

void vtinput_init(vtinput *d)
{
    memset(d, 0, sizeof *d);
}

static const char *const keynames[] = {
    NULL, "up", "down", "right", "left", "home", "end", "insert", "delete", "pageup", "pagedown", "enter", "tab",
    "backspace", "escape", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "space",
};

const char *vtinput_keyname(int code)
{
    return code > 0 && (size_t)code < sizeof keynames / sizeof keynames[0] ? keynames[code] : NULL;
}

static int key(vtev *e, int code, int mods)
{
    e->type = VT_KEY; e->code = code; e->mods = mods;
    return 1;
}

static int ascii_key(vtev *e, int ch, int mods)
{
    e->type = VT_KEY; e->code = 0; e->mods = mods; e->text[0] = (char)ch; e->text[1] = 0;
    return 1;
}

static int csi_final(vtinput *d, vtev *e, int c)
{
    int p1 = d->nparam > 0 ? d->param[0] : 0, p2 = d->nparam > 1 ? d->param[1] : 0;
    int mods = p2 > 1 ? p2 - 1 : 0;

    if (d->prefix == '<') { /* SGR mouse: b ; x ; y, M press or motion, m release */
        int b = p1, wheel = (b & 64) != 0, motion = (b & 32) != 0, btn = b & 3;

        if ((c != 'M' && c != 'm') || d->nparam < 3) return 0;
        e->type = VT_MOUSE; e->x = d->param[1]; e->y = d->param[2];
        e->mods = ((b & 4) ? 1 : 0) | ((b & 8) ? 2 : 0) | ((b & 16) ? 4 : 0);
        e->code = btn + 1; /* 1 left, 2 middle, 3 right (3 + motion = no button) */
        if (wheel) { e->action = btn == 0 ? VT_SCROLL_UP : VT_SCROLL_DOWN; e->code = 0; }
        else if (c == 'm') e->action = VT_RELEASE;
        else if (motion) { e->action = btn == 3 ? VT_MOVE : VT_DRAG; if (btn == 3) e->code = 0; }
        else e->action = VT_PRESS;
        return 1;
    }
    switch (c) {
    case 'A': return key(e, VT_K_UP, mods);
    case 'B': return key(e, VT_K_DOWN, mods);
    case 'C': return key(e, VT_K_RIGHT, mods);
    case 'D': return key(e, VT_K_LEFT, mods);
    case 'H': return key(e, VT_K_HOME, mods);
    case 'F': return key(e, VT_K_END, mods);
    case 'P': return key(e, VT_K_F1, mods);
    case 'Q': return key(e, VT_K_F1 + 1, mods);
    case 'R': return key(e, VT_K_F1 + 2, mods);
    case 'S': return key(e, VT_K_F1 + 3, mods);
    case 'Z': return key(e, VT_K_TAB, 1); /* Shift+Tab */
    case '~':
        switch (p1) {
        case 1: case 7: return key(e, VT_K_HOME, mods);
        case 2: return key(e, VT_K_INSERT, mods);
        case 3: return key(e, VT_K_DELETE, mods);
        case 4: case 8: return key(e, VT_K_END, mods);
        case 5: return key(e, VT_K_PAGEUP, mods);
        case 6: return key(e, VT_K_PAGEDOWN, mods);
        case 11: case 12: case 13: case 14: case 15: return key(e, VT_K_F1 + (p1 - 11), mods);
        case 17: case 18: case 19: case 20: case 21: return key(e, VT_K_F1 + 5 + (p1 - 17), mods);
        case 23: case 24: return key(e, VT_K_F1 + 10 + (p1 - 23), mods);
        }
    }
    return 0; /* unknown sequence: dropped */
}

int vtinput_feed(vtinput *d, unsigned char c, vtev *e)
{
    memset(e, 0, sizeof *e);
    switch (d->state) {
    case 1: /* after ESC */
        if (c == '[') { d->state = 2; d->nparam = 0; d->prefix = 0; memset(d->param, 0, sizeof d->param); d->have = 0; return 0; }
        if (c == 'O') { d->state = 3; return 0; }
        d->state = 0;
        if (c == 0x1b) { d->state = 1; return key(e, VT_K_ESCAPE, 0); } /* ESC ESC: the first one is a key */
        if (c >= 0x20 && c < 0x7f) return ascii_key(e, c, 2);
        return key(e, VT_K_ESCAPE, 0); /* ESC then a control byte: report the ESC, drop the byte */
    case 2: /* in CSI */
        if ((c >= '0' && c <= '9')) {
            if (d->nparam == 0) d->nparam = 1;
            if (d->nparam <= VT_MAXPARAM) { d->param[d->nparam - 1] = d->param[d->nparam - 1] * 10 + (c - '0'); if (d->param[d->nparam - 1] > 100000) d->param[d->nparam - 1] = 100000; }
            d->have = 1;
            return 0;
        }
        if (c == ';') { if (d->nparam == 0) d->nparam = 1; if (d->nparam < VT_MAXPARAM) d->nparam++; return 0; }
        if (c == '<' || c == '?' || c == '>' || c == '=') { d->prefix = c; return 0; }
        if (c >= 0x20 && c <= 0x2f) return 0; /* intermediates: ignored */
        d->state = 0;
        if (c >= 0x40 && c <= 0x7e) return csi_final(d, e, c);
        return 0;
    case 3: /* SS3: ESC O x */
        d->state = 0;
        if (c >= 'P' && c <= 'S') return key(e, VT_K_F1 + (c - 'P'), 0);
        if (c == 'A') return key(e, VT_K_UP, 0);
        if (c == 'B') return key(e, VT_K_DOWN, 0);
        if (c == 'C') return key(e, VT_K_RIGHT, 0);
        if (c == 'D') return key(e, VT_K_LEFT, 0);
        if (c == 'H') return key(e, VT_K_HOME, 0);
        if (c == 'F') return key(e, VT_K_END, 0);
        return 0;
    case 4: /* UTF-8 continuation */
        if ((c & 0xc0) != 0x80) { d->state = 0; return vtinput_feed(d, c, e); } /* malformed: restart on this byte */
        d->u8[d->u8n++] = (char)c;
        if (--d->u8left > 0) return 0;
        d->state = 0;
        e->type = VT_CHAR; memcpy(e->text, d->u8, d->u8n); e->text[d->u8n] = 0;
        return 1;
    }
    /* ground */
    if (c == 0x1b) { d->state = 1; return 0; }
    if (c == '\r' || c == '\n') return key(e, VT_K_ENTER, 0);
    if (c == '\t') return key(e, VT_K_TAB, 0);
    if (c == 0x7f || c == 0x08) return key(e, VT_K_BACKSPACE, 0);
    if (c == 0) return key(e, VT_K_SPACE, 4);
    if (c < 0x20) return ascii_key(e, 'a' + c - 1, 4); /* Ctrl+letter */
    if (c == ' ') { e->type = VT_CHAR; e->text[0] = ' '; return 1; }
    if (c < 0x80) { e->type = VT_CHAR; e->text[0] = (char)c; return 1; }
    if (c >= 0xc2 && c <= 0xf4) {
        d->u8[0] = (char)c; d->u8n = 1; d->u8left = c >= 0xf0 ? 3 : c >= 0xe0 ? 2 : 1; d->state = 4;
    }
    return 0; /* stray continuation or invalid lead: dropped */
}

int vtinput_pending(const vtinput *d)
{
    return d->state == 1;
}

int vtinput_flush(vtinput *d, vtev *e)
{
    memset(e, 0, sizeof *e);
    if (d->state == 1) { d->state = 0; return key(e, VT_K_ESCAPE, 0); }
    d->state = 0; /* an unfinished sequence is dropped */
    return 0;
}
