#include "PrivateFocus.h"

#include <ApplicationServices/ApplicationServices.h>
#include <Carbon/Carbon.h>
#include <dlfcn.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>

#define kCPSUserGenerated 0x200

typedef int (*SLSMainConnectionIDFn)(void);
typedef CGError (*SLSGetCurrentCursorLocationFn)(int cid, CGPoint *point);
typedef OSStatus (*SLSFindWindowAndOwnerFn)(int cid, int zero, int one, int zero_again, CGPoint *screen_point, CGPoint *window_point, uint32_t *wid, int *wcid);
typedef CGError (*SLSGetWindowOwnerFn)(int cid, uint32_t wid, int *wcid);
typedef CGError (*SLSGetConnectionPSNFn)(int cid, ProcessSerialNumber *psn);
typedef CGError (*SLSConnectionGetPIDFn)(int cid, pid_t *pid);
typedef OSStatus (*SLPSGetFrontProcessFn)(ProcessSerialNumber *psn);
typedef CGError (*SLSGetConnectionIDForPSNFn)(int cid, ProcessSerialNumber *psn, int *psn_cid);
typedef CGError (*SLPSSetFrontProcessWithOptionsFn)(ProcessSerialNumber *psn, uint32_t wid, uint32_t mode);
typedef CGError (*SLPSPostEventRecordToFn)(ProcessSerialNumber *psn, uint8_t *bytes);
typedef AXError (*AXUIElementGetWindowFn)(AXUIElementRef ref, uint32_t *wid);

static void *skylight_handle;
static bool load_attempted;
static bool symbols_loaded;
static SLSMainConnectionIDFn SLSMainConnectionID_ptr;
static SLSGetCurrentCursorLocationFn SLSGetCurrentCursorLocation_ptr;
static SLSFindWindowAndOwnerFn SLSFindWindowAndOwner_ptr;
static SLSGetWindowOwnerFn SLSGetWindowOwner_ptr;
static SLSGetConnectionPSNFn SLSGetConnectionPSN_ptr;
static SLSConnectionGetPIDFn SLSConnectionGetPID_ptr;
static SLPSGetFrontProcessFn SLPSGetFrontProcess_ptr;
static SLSGetConnectionIDForPSNFn SLSGetConnectionIDForPSN_ptr;
static SLPSSetFrontProcessWithOptionsFn SLPSSetFrontProcessWithOptions_ptr;
static SLPSPostEventRecordToFn SLPSPostEventRecordTo_ptr;
static AXUIElementGetWindowFn AXUIElementGetWindow_ptr;

static void *load_symbol(const char *name)
{
    return skylight_handle ? dlsym(skylight_handle, name) : 0;
}

static uint32_t focused_window_for_pid(pid_t pid)
{
    if (!AXUIElementGetWindow_ptr || pid <= 0) return 0;

    AXUIElementRef app = AXUIElementCreateApplication(pid);
    if (!app) return 0;

    CFTypeRef focused_window = 0;
    AXError copy_error = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute, &focused_window);
    CFRelease(app);

    if (copy_error != kAXErrorSuccess || !focused_window) {
        return 0;
    }

    uint32_t window_id = 0;
    AXError window_error = AXUIElementGetWindow_ptr((AXUIElementRef) focused_window, &window_id);
    CFRelease(focused_window);

    return window_error == kAXErrorSuccess ? window_id : 0;
}

static uint32_t frontmost_window_for_pid(pid_t pid)
{
    if (pid <= 0) return 0;

    CFArrayRef windows = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
    if (!windows) return 0;

    uint32_t window_id = 0;
    CFIndex count = CFArrayGetCount(windows);

    for (CFIndex i = 0; i < count; ++i) {
        CFDictionaryRef window = CFArrayGetValueAtIndex(windows, i);
        if (!window) continue;

        CFNumberRef owner_pid_ref = CFDictionaryGetValue(window, kCGWindowOwnerPID);
        CFNumberRef layer_ref = CFDictionaryGetValue(window, kCGWindowLayer);
        CFNumberRef window_id_ref = CFDictionaryGetValue(window, kCGWindowNumber);

        int owner_pid = 0;
        int layer = 0;
        int candidate_id = 0;

        if (!owner_pid_ref || !layer_ref || !window_id_ref) continue;
        if (!CFNumberGetValue(owner_pid_ref, kCFNumberIntType, &owner_pid)) continue;
        if (!CFNumberGetValue(layer_ref, kCFNumberIntType, &layer)) continue;
        if (!CFNumberGetValue(window_id_ref, kCFNumberIntType, &candidate_id)) continue;

        if (owner_pid != pid || layer != 0 || candidate_id <= 0) continue;

        window_id = (uint32_t) candidate_id;
        break;
    }

    CFRelease(windows);
    return window_id;
}

static bool private_focus_load(void)
{
    if (load_attempted) return symbols_loaded;
    load_attempted = true;

    skylight_handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
    if (!skylight_handle) return false;

    SLSMainConnectionID_ptr = (SLSMainConnectionIDFn) load_symbol("SLSMainConnectionID");
    SLSGetCurrentCursorLocation_ptr = (SLSGetCurrentCursorLocationFn) load_symbol("SLSGetCurrentCursorLocation");
    SLSFindWindowAndOwner_ptr = (SLSFindWindowAndOwnerFn) load_symbol("SLSFindWindowAndOwner");
    SLSGetWindowOwner_ptr = (SLSGetWindowOwnerFn) load_symbol("SLSGetWindowOwner");
    SLSGetConnectionPSN_ptr = (SLSGetConnectionPSNFn) load_symbol("SLSGetConnectionPSN");
    SLSConnectionGetPID_ptr = (SLSConnectionGetPIDFn) load_symbol("SLSConnectionGetPID");
    SLPSGetFrontProcess_ptr = (SLPSGetFrontProcessFn) load_symbol("_SLPSGetFrontProcess");
    SLSGetConnectionIDForPSN_ptr = (SLSGetConnectionIDForPSNFn) load_symbol("SLSGetConnectionIDForPSN");
    SLPSSetFrontProcessWithOptions_ptr = (SLPSSetFrontProcessWithOptionsFn) load_symbol("_SLPSSetFrontProcessWithOptions");
    SLPSPostEventRecordTo_ptr = (SLPSPostEventRecordToFn) load_symbol("SLPSPostEventRecordTo");
    AXUIElementGetWindow_ptr = (AXUIElementGetWindowFn) dlsym(RTLD_DEFAULT, "_AXUIElementGetWindow");

    symbols_loaded = SLSMainConnectionID_ptr &&
                     SLSGetCurrentCursorLocation_ptr &&
                     SLSFindWindowAndOwner_ptr &&
                     SLSGetWindowOwner_ptr &&
                     SLSGetConnectionPSN_ptr &&
                     SLSConnectionGetPID_ptr &&
                     SLPSGetFrontProcess_ptr &&
                     SLSGetConnectionIDForPSN_ptr &&
                     SLPSSetFrontProcessWithOptions_ptr &&
                     SLPSPostEventRecordTo_ptr &&
                     AXUIElementGetWindow_ptr;
    return symbols_loaded;
}

int private_focus_window_under_mouse(PrivateFocusWindowInfo *info)
{
    if (!info) return -1;
    memset(info, 0, sizeof(*info));

    if (!private_focus_load()) return -2;

    int cid = SLSMainConnectionID_ptr();
    CGPoint point = CGPointZero;
    CGPoint window_point = CGPointZero;
    uint32_t window_id = 0;
    int owner_cid = 0;

    if (SLSGetCurrentCursorLocation_ptr(cid, &point) != kCGErrorSuccess) {
        return -3;
    }

    OSStatus find_status = SLSFindWindowAndOwner_ptr(cid, 0, 1, 0, &point, &window_point, &window_id, &owner_cid);
    if (find_status != noErr || window_id == 0) {
        return -4;
    }

    if (owner_cid == cid) {
        find_status = SLSFindWindowAndOwner_ptr(cid, (int) window_id, -1, 0, &point, &window_point, &window_id, &owner_cid);
        if (find_status != noErr || window_id == 0) {
            return -5;
        }
    }

    pid_t pid = 0;
    if (SLSConnectionGetPID_ptr(owner_cid, &pid) != kCGErrorSuccess) {
        pid = 0;
    }

    info->window_id = window_id;
    info->owner_connection_id = owner_cid;
    info->owner_pid = pid;

    return 0;
}

int private_focus_front_window(PrivateFocusWindowInfo *info)
{
    if (!info) return -1;
    memset(info, 0, sizeof(*info));

    if (!private_focus_load()) return -2;

    int cid = SLSMainConnectionID_ptr();
    ProcessSerialNumber psn = { 0, 0 };
    if (SLPSGetFrontProcess_ptr(&psn) != noErr) {
        return -3;
    }

    int owner_cid = 0;
    if (SLSGetConnectionIDForPSN_ptr(cid, &psn, &owner_cid) != kCGErrorSuccess) {
        return -4;
    }

    pid_t pid = 0;
    if (SLSConnectionGetPID_ptr(owner_cid, &pid) != kCGErrorSuccess) {
        pid = 0;
    }

    info->owner_connection_id = owner_cid;
    info->owner_pid = pid;
    info->window_id = focused_window_for_pid(pid);
    if (info->window_id == 0) {
        info->window_id = frontmost_window_for_pid(pid);
    }

    return 0;
}

static CGError post_key_window_event(ProcessSerialNumber *psn, uint8_t state, uint32_t window_id)
{
    uint8_t bytes[0xf8];
    memset(bytes, 0, sizeof(bytes));

    bytes[0x04] = 0xf8;
    bytes[0x08] = 0x0d;

    bytes[0x8a] = state;
    memcpy(bytes + 0x3c, &window_id, sizeof(uint32_t));
    return SLPSPostEventRecordTo_ptr(psn, bytes);
}

static CGError make_key_window(ProcessSerialNumber *psn, uint32_t window_id)
{
    uint8_t bytes[0xf8];
    memset(bytes, 0, sizeof(bytes));

    bytes[0x04] = 0xf8;
    bytes[0x3a] = 0x10;
    memcpy(bytes + 0x3c, &window_id, sizeof(uint32_t));
    memset(bytes + 0x20, 0xff, 0x10);

    bytes[0x08] = 0x01;
    CGError first_error = SLPSPostEventRecordTo_ptr(psn, bytes);
    if (first_error != kCGErrorSuccess) return first_error;

    bytes[0x08] = 0x02;
    return SLPSPostEventRecordTo_ptr(psn, bytes);
}

int private_focus_window_without_raise(uint32_t window_id)
{
    if (!window_id) return -1;
    if (!private_focus_load()) return -2;

    int cid = SLSMainConnectionID_ptr();

    int owner_cid = 0;
    if (SLSGetWindowOwner_ptr(cid, window_id, &owner_cid) != kCGErrorSuccess) {
        return -3;
    }

    ProcessSerialNumber previous_psn = { 0, 0 };
    PrivateFocusWindowInfo previous = { 0 };
    uint32_t previous_window_id = 0;
    bool has_previous = false;
    if (private_focus_front_window(&previous) == 0 && previous.owner_connection_id != owner_cid) {
        if (SLSGetConnectionPSN_ptr(previous.owner_connection_id, &previous_psn) == kCGErrorSuccess) {
            previous_window_id = previous.window_id;
            has_previous = previous_window_id != 0;
        }
    }

    ProcessSerialNumber psn = { 0, 0 };
    if (SLSGetConnectionPSN_ptr(owner_cid, &psn) != kCGErrorSuccess) {
        return -4;
    }

    CGError front_error = SLPSSetFrontProcessWithOptions_ptr(&psn, window_id, kCPSUserGenerated);
    if (front_error != kCGErrorSuccess) {
        return -5;
    }

    if (has_previous) {
        CGError resign_error = post_key_window_event(&previous_psn, 0x02, previous_window_id);
        if (resign_error != kCGErrorSuccess) return -6;

        usleep(40000);

        CGError activate_error = post_key_window_event(&psn, 0x01, window_id);
        if (activate_error != kCGErrorSuccess) return -7;
    }

    CGError key_error = make_key_window(&psn, window_id);
    if (key_error != kCGErrorSuccess) return -8;

    return 0;
}
