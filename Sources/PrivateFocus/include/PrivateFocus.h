#ifndef PRIVATE_FOCUS_H
#define PRIVATE_FOCUS_H

#include <stdint.h>

typedef struct PrivateFocusWindowInfo {
    uint32_t window_id;
    int32_t owner_connection_id;
    int32_t owner_pid;
} PrivateFocusWindowInfo;

int private_focus_window_under_mouse(PrivateFocusWindowInfo *info);
int private_focus_front_window(PrivateFocusWindowInfo *info);
int private_focus_window_without_raise(uint32_t window_id);

#endif
