#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <CoreGraphics/CoreGraphics.h>
#import <OpenGL/OpenGL.h>
#import <os/log.h>
#import <dirent.h>
#import <dlfcn.h>
#import <execinfo.h>
#import <fcntl.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <errno.h>
#import <math.h>
#import <pthread.h>
#import <signal.h>
#import <stdarg.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <sys/time.h>
#import <time.h>
#import <unistd.h>

/*
 * libsims2_trackpad.dylib (v1.5.0)
 * Free, non-profit & open-source (MIT) Trackpad, Display & Stability helper
 * for lawful owners of The Sims 2: Super Collection (macOS).
 * Software preservation, debugging & interoperability only — no DRM bypass.
 *
 * Features:
 *   1. SDL2 macOS Fullscreen Space & Dock fix (SDL_VIDEO_MAC_FULLSCREEN_SPACES, etc.)
 *   2. Out-of-focus cursor grab/warp protection & Command+Tab orphan window suppression
 *   3. Two-finger pinch gesture (NSEventTypeMagnify) -> native scrollWheel zoom (layout-independent, non-inverted)
 *   4. Two-finger horizontal slide (scrollWheel X) & twist (NSEventTypeRotate) -> dynamic Carbon AZERTY/QWERTY rotation (, / .)
 *   5. Control (^) + left or right click-drag -> SDL_BUTTON_MIDDLE emulation (360° orbit & pitch)
 *   6. Native Option (⌥) camera hand-drag left 100% untouched for the base game
 *   7. Genuine CoreGraphics hardware display-mode filter (real modes closest to 60 Hz, zero synthetic modes)
 *   8. Dynamic fullscreen geometry clamped to NSScreen.visibleFrame under the MacBook notch
 *   9. Silent by default: zero log files written in normal sessions; automatic crash_report.log on crash,
 *      on-demand debug_boot.log when SIMS2_DEBUG=1 or ~/.debug_enabled is present, and opt-in
 *      sims2_patch_diag.log when SIMS2_DIAG_LOG=1 or S2PatchDiagLog=true.
 *
 * Env config (optional overrides):
 *   SIMS2_ROTATE_INVERT=0|1      (default 0)
 *   SIMS2_ROTATE_STEP=<float>    (default 28.0 trackpad points per rotation step)
 *   SIMS2_TWIST_STEP=<float>     (default 12.0 degrees per rotation step)
 *   SIMS2_PINCH_STEP=<float>     (default 0.08 magnification units per zoom step)
 *   SIMS2_CTRL_ORBIT=0|1         (default 1, Control+drag emulates middle mouse button)
 *   SIMS2_OPTION_ORBIT=0|1       (legacy fallback alias if SIMS2_CTRL_ORBIT is unset)
 *   SIMS2_DEBUG=0|1              (default 0, writes ~/Library/Logs/Sims2-Crash-Patch/debug_boot.log)
 *   SIMS2_DIAG_LOG=0|1           (default 0, opt-in writes NSTemporaryDirectory()/sims2_patch_diag.log)
 *   SIMS2_DIAG_OSLOG=0|1         (default 0, mirrors diagnostic entries to os_log)
 *   SIMS2_TRACKPAD_DEBUG=0|1     (default 0, logs via NSLog)
 */

#define SIMS2_PATCH_VERSION "1.5.0"

typedef NS_ENUM(NSInteger, Sims2ScrollAxis) {
    Sims2ScrollAxisNone = 0,
    Sims2ScrollAxisZoomY = 1,
    Sims2ScrollAxisRotateX = 2
};

static IMP gOrigNextEventIMP = NULL;
static IMP gOrigScrollWheelIMP = NULL;
static IMP gOrigButtonNumberIMP = NULL;
static IMP gOrigEventModifierFlagsIMP = NULL;
static IMP gOrigClassModifierFlagsIMP = NULL;
static IMP gOrigIsDirectionInvertedIMP = NULL;
static IMP gOrigMouseDownIMP = NULL;
static IMP gOrigMouseUpIMP = NULL;
static IMP gOrigMouseDraggedIMP = NULL;
static IMP gOrigRightMouseDownIMP = NULL;
static IMP gOrigRightMouseUpIMP = NULL;
static IMP gOrigRightMouseDraggedIMP = NULL;
static IMP gOrigOtherMouseDownIMP = NULL;
static IMP gOrigOtherMouseUpIMP = NULL;
static IMP gOrigOtherMouseDraggedIMP = NULL;
static IMP gOrigMouseMovedIMP = NULL;
static IMP gOrigWindowDidBecomeKeyIMP = NULL;
static IMP gOrigWindowDidResignKeyIMP = NULL;
static IMP gOrigWindowWillEnterFullScreenIMP = NULL;
static IMP gOrigWindowDidEnterFullScreenIMP = NULL;
static IMP gOrigWindowDidFailToEnterFullScreenIMP = NULL;
static IMP gOrigWindowWillExitFullScreenIMP = NULL;
static IMP gOrigWindowDidExitFullScreenIMP = NULL;
static IMP gOrigWindowDidFailToExitFullScreenIMP = NULL;
static IMP gOrigSetFullscreenSpaceIMP = NULL;
static IMP gOrigMiniaturizeIMP = NULL;
static IMP gOrigMakeKeyAndOrderFrontIMP = NULL;
static IMP gOrigOrderFrontRegardlessIMP = NULL;
static IMP gOrigActivateIgnoringOtherAppsIMP = NULL;
static IMP gOrigFocusSomeWindowIMP = NULL;
static IMP gOrigCanBecomeKeyWindowIMP = NULL;
static IMP gOrigCanBecomeMainWindowIMP = NULL;
static IMP gOrigSDLValidateMenuItemIMP = NULL;
static IMP gOrigSDLViewMouseDownCanMoveWindowIMP = NULL;
static IMP gOrigSDLSetStyleMaskIMP = NULL;
static IMP gOrigSDLSetFrameDisplayIMP = NULL;
static IMP gOrigSDLSetFrameDisplayAnimateIMP = NULL;
static IMP gOrigSDLSetContentSizeIMP = NULL;
static IMP gOrigSDLConstrainFrameRectIMP = NULL;
static IMP gOrigSDLSetCollectionBehaviorIMP = NULL;
static IMP gOrigSDLSetLevelIMP = NULL;
static IMP gOrigSDLToggleFullScreenIMP = NULL;
static IMP gOrigSDLSetFrameOriginIMP = NULL;
static IMP gOrigSDLSetFrameTopLeftPointIMP = NULL;
static IMP gOrigLocationInWindowIMP = NULL;
static IMP gOrigMouseLocationOutsideOfEventStreamIMP = NULL;
static IMP gOrigWindowDidResizeIMP = NULL;
static IMP gOrigNSGLSetViewIMP = NULL;
static IMP gOrigNSGLMakeCurrentContextIMP = NULL;
static Class gSDLWindowClass = Nil;

static Sims2ScrollAxis gScrollAxis = Sims2ScrollAxisNone;
static double gScrollAccumX = 0.0;
static double gTwistAccum = 0.0;
static double gPinchAccum = 0.0;
static BOOL gIsTwisting = NO;
static __weak NSEvent *gSuppressedScrollEvent = nil;
static __weak NSEvent *gForcedNonInvertedEvent = nil;
static BOOL gForceScrollNonInverted = NO;

static BOOL gSpoofMiddleButton = NO;
static BOOL gMaskControlModifier = NO;
static BOOL gCtrlMiddleDragActive = NO;
static BOOL gCtrlDragWasRight = NO;
static BOOL gNativeOptionCamHeld = NO;
static BOOL gPostingSyntheticFlagsEvent = NO;
static __weak NSWindow *gLastMouseDownWindow = nil;
static __weak NSWindow *gPrimaryFullscreenWindow = nil;
static __weak id gWindowListener = nil;

static BOOL gAppHasActivatedOnce = NO;
static BOOL gAppIsActive = YES;
static BOOL gAppIsHiding = NO;
static BOOL gAppIsTerminating = NO;
static BOOL gInFullscreenTransition = NO;
static BOOL gUserRequestedFullscreenEnter = NO;
static BOOL gUserRequestedFullscreenExit = NO;
static BOOL gHasCompletedFirstWindowShow = NO;
static BOOL gAllowResizableForSpaceToggle = NO;
static BOOL gHasAppliedPresentationOpts = NO;
static BOOL gAllowExplicitSpaceReactivation = NO;
static CFAbsoluteTime gLastResignTimestamp = 0.0;

static BOOL gDebugBootEnabled = NO;
static FILE *gDebugLogFile = NULL;
static BOOL gDiagLogEnabled = NO;
static BOOL gDiagOsLogEnabled = NO;
static FILE *gDiagLogFile = NULL;
static int gDiagLogFd = -1;
static size_t gDiagLogBytesWritten = 0;
static os_log_t gDiagOsLog = NULL;
static uint64_t gBootMonotonicNs = 0;
static long gBootLocalTzOffsetSec = 0;
static CFAbsoluteTime gLastDiagFlushTime = 0.0;
static CFAbsoluteTime gLastMouseMoveDiagLogTime = 0.0;
static CFAbsoluteTime gLastCamDragDiagLogTime = 0.0;
static NSTimeInterval gLastHandledShortcutEventTimestamp = -1.0;
static pthread_mutex_t gDebugLogMutex = PTHREAD_MUTEX_INITIALIZER;

static const size_t kSims2DiagLogMaxBytes = 5UL * 1024UL * 1024UL;
static const int kSims2MaxNumberedLogs = 20;

static char gLibDir[512] = {0};
static char gLogsRootDir[512] = {0};
static char gLogsDir[512] = {0};
static char gTmpLogsDir[512] = {0};
static char gCrashLogPath[600] = {0};
static char gCrashLogBasename[64] = {0};
static char gCrashLatestLinkPath[600] = {0};
static char gCrashFallbackLogPath[600] = {0};
static char gCrashFallbackBasename[64] = {0};
static char gCrashFallbackLatestLinkPath[600] = {0};
static int gCrashLogNumber = 1;
static int gCrashFallbackLogNumber = 1;
static char gDebugLogPath[600] = {0};
static char gDebugPrevLogPath[600] = {0};
static char gDebugFlagPath[600] = {0};
static char gDiagLogPath[600] = {0};
static char gDiagLogLinkPath[600] = {0};
static char gDiagPrevLogPath[600] = {0};
static int gDiagLogNumber = 1;

static char gCachedHwModel[128] = "unknown";
static char gCachedOsVersion[128] = "unknown";
static char gCachedFrameStr[128] = "unknown";
static char gCachedVisibleFrameStr[128] = "unknown";
static char gLastCxaThrowInfo[384] = "none";
static char gLastHookOrTransition[128] = "boot";
static BOOL gLastKnownInSpace = NO;
static volatile int gCrashReportWritten = 0;

static struct sigaction gPrevSigActions[32];
static uint8_t gCrashAltStackMem[65536];
typedef void (*Sims2TerminateHandler)(void);
static Sims2TerminateHandler gPrevTerminateHandler = NULL;
static NSUncaughtExceptionHandler *gPrevObjCUncaughtExceptionHandler = NULL;

static intptr_t gExecSlide = 0;
static BOOL gNotchFitInProgress = NO;
static NSRect gNotchTargetFrame = {{0, 0}, {0, 0}};
static int gNotchClampAttempts = 0;

static CFAbsoluteTime gLastOptionHoverLogTime = 0.0;
static CFAbsoluteTime gLastScrollLogTime = 0.0;
static CFAbsoluteTime gLastPinchLogTime = 0.0;
static CFAbsoluteTime gLastTwistLogTime = 0.0;
static NSUInteger gLastLoggedModifierMask = 0;

static uint32_t gKeyTapSeq[128] = {0};
static BOOL gKeyTapActive[128] = {NO};

static BOOL gInvertRotation = NO;
static BOOL gEnableOptionOrbit = YES;
static double gRotateStep = 28.0;
static double gTwistStep = 12.0;
static double gPinchStep = 0.08;
static BOOL gDebug = NO;

static uint16_t gCachedLeftRotateKey = 43;
static uint16_t gCachedRightRotateKey = 47;

static NSString * const kSims2PrefDiagLogKey = @"S2PatchDiagLog";
static NSString * const kSims2PrefWindowedWidthKey = @"S2PatchWindowedWidth";
static NSString * const kSims2PrefWindowedHeightKey = @"S2PatchWindowedHeight";
static NSString * const kSims2WindowTitle = @"Les Sims™ 2 : Super Collection";

static BOOL gDiagLogPrefEnabled = NO;
static BOOL gWindowedModeActive = NO;
static NSInteger gRawHardwareScreenWidth = 1800;
static NSInteger gRawHardwareScreenHeight = 1169;
static NSInteger gNotchTopInset = 0;
static NSInteger gNativeScreenWidth = 1800;
static NSInteger gNativeScreenHeight = 1131;
static NSInteger gPrimaryRawScreenWidth = 1800;
static NSInteger gPrimaryRawScreenHeight = 1169;
static NSInteger gPrimaryNotchTopInset = 0;
static NSInteger gPrimaryNativeScreenHeight = 1131;
static NSInteger gTargetWindowWidth = 0;
static NSInteger gTargetWindowHeight = 0;
static size_t gLastExposedModeWidth = 0;
static size_t gLastExposedModeHeight = 0;
static size_t gLastExposedModeHz = 60;
static CGFloat gEngineFbW = 1800.0;
static CGFloat gEngineFbH = 1131.0;
static BOOL gHasCapturedInitialEngineFb = NO;
static CGFloat gActiveFramebufferWidth = 1800.0;
static CGFloat gActiveFramebufferHeight = 1131.0;
static BOOL gForceCenterWindowedFrame = YES;
static BOOL gSuppressSDLResizeNotification = NO;
static BOOL gPendingOpenGLSurfaceSync = NO;
static volatile int32_t gModeTransitionInProgress = 0;
static volatile uint64_t gDisplayTransitionGen = 0;
static volatile uint64_t gOpenGLRefreshSeq = 0;
static volatile uint64_t gSpaceReactivateSeq = 0;
static CGFloat gLastAppliedGlBackingScale = 0.0;
static __weak NSScreen *gLastAppliedGlScreen = nil;
static __weak NSScreen *gExitFullscreenTargetScreen = nil;
static NSRect gExitFullscreenTargetFrame = {{0.0, 0.0}, {0.0, 0.0}};
static BOOL gHasExitFullscreenTarget = NO;
static CFAbsoluteTime gExitFullscreenTargetSetTime = 0.0;
static BOOL gUserWindowMoveInProgress = NO;
static CFAbsoluteTime gLastModeToggleTime = 0.0;
static CFAbsoluteTime gLastWarpDiagLogTime = 0.0;
static CGPoint gLastWarpLoggedFbPt = { -9999.0, -9999.0 };
static CFAbsoluteTime gLastDidMoveDiagLogTime = 0.0;
static NSRect gCachedContentScreenRect = {{0.0, 0.0}, {0.0, 0.0}};
static CGFloat gCachedRawPrimaryScreenH = 0.0;
static CGFloat gCachedSdlOriginX = 0.0;
static CGFloat gCachedSdlOriginY = 0.0;
static BOOL gCachedWarpGeometryValid = NO;
static __weak NSOpenGLContext *gGameOpenGLContext = nil;
static __thread BOOL tProjectMouseLocationForSDL = NO;
static __thread BOOL tClampDragProjectionForSDL = NO;
static __thread BOOL tInMouseDownHandler = NO;
static __thread BOOL tInMouseUpHandler = NO;
static __thread BOOL tInMouseMotionHandler = NO;

static uint64_t bump_display_transition_gen(void) {
    return __atomic_add_fetch(&gDisplayTransitionGen, 1ULL, __ATOMIC_ACQ_REL);
}

static uint64_t current_display_transition_gen(void) {
    return __atomic_load_n(&gDisplayTransitionGen, __ATOMIC_ACQUIRE);
}

static void ensure_dir_exists(const char *path) {
    if (!path || path[0] == '\0') {
        return;
    }
    if (mkdir(path, 0755) != 0 && errno != EEXIST) {
        // Best-effort directory creation
    }
}

static void debuglog_write(const char *category, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
static BOOL is_sdl_game_window(id winObj);
static BOOL is_secondary_orphan_game_window(id winObj);
static void enforce_primary_window_borderless_fullscreen(NSWindow *win, const char *reason);
static NSScreen *resolve_screen_for_rect(NSRect rect, NSScreen *fallbackScreen);
static NSRect compute_aspect_fitted_fullscreen_rect(NSRect screenUsableRect, double fbW, double fbH);
static NSRect compute_expected_fullscreen_space_frame(NSWindow *win);
static void ensure_fullscreen_space_geometry(NSWindow *win, const char *reason);
static void refresh_opengl_surface_for_screen_or_backing_change(NSWindow *win, const char *reason);
static void remember_exit_fullscreen_target_screen(NSWindow *win, const char *reason);
static void clear_exit_fullscreen_target_screen(void);
static NSScreen *resolve_active_exit_fullscreen_target_screen(void);
static void restore_game_window_focus_and_input(NSWindow *win, const char *reason);
static BOOL query_sdl_window_rect(NSWindow *win, CGFloat *outX, CGFloat *outY, CGFloat *outW, CGFloat *outH);
static BOOL query_sdl_window_logical_size(NSWindow *win, CGFloat *outW, CGFloat *outH);
static NSRect query_window_content_screen_rect(NSWindow *win);
static void sync_sdl_window_origin_to_frame(NSWindow *win, const char *reason);
static void sync_sdl_window_logical_size_to_engine_fb(NSWindow *win, const char *reason);
static size_t hook_CGDisplayPixelsHigh(CGDirectDisplayID display);
static CGError hook_CGWarpMouseCursorPosition(CGPoint newCursorPosition);
static CGError hook_CGDisplayMoveCursorToPoint(CGDirectDisplayID display, CGPoint point);
static void ensure_sdl_responder_chain(NSWindow *win, const char *reason);
static void safe_set_sdl_window_style_mask(NSWindow *win, NSWindowStyleMask newMask, const char *reason);
static NSWindowCollectionBehavior sanitize_mission_control_collection_behavior(NSWindowCollectionBehavior behavior);
static void flush_stuck_modifier_state_to_sdl(NSWindow *win, const char *reason);
static void toggle_windowed_fullscreen_mode(void);
static void cycle_next_resolution(void);
static void select_default_windowed_resolution_if_native(NSWindow *win);
static CGFloat query_primary_screen_height_for_cg(void);
static void ensure_sims2_display_menu_installed(void);
static void rebuild_sims2_display_menu_resolution_items(NSWindow *win);
static void update_sims2_display_menu_state(void);
static void apply_opengl_surface_backing_size(NSWindow *win);
static void apply_opengl_surface_backing_size_ex(NSWindow *win, BOOL forceUpdate);
static NSOpenGLContext *resolve_game_opengl_context(NSWindow *win);
static NSWindow *resolve_primary_game_window(void);
static void diaglog_init_if_enabled(void);
static void diaglog_flush(void);

static double diag_elapsed_seconds(void) {
    uint64_t nowNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    if (gBootMonotonicNs == 0 || nowNs < gBootMonotonicNs) {
        return 0.0;
    }
    return (double)(nowNs - gBootMonotonicNs) / 1e9;
}

static BOOL diag_category_needs_immediate_flush(const char *cat) {
    if (!cat) {
        return NO;
    }
    return (strcmp(cat, "BOOT") == 0 ||
            strcmp(cat, "INIT") == 0 ||
            strcmp(cat, "APP") == 0 ||
            strcmp(cat, "WIN") == 0 ||
            strcmp(cat, "SPACE") == 0 ||
            strcmp(cat, "GL") == 0 ||
            strcmp(cat, "PREF") == 0 ||
            strcmp(cat, "MENU") == 0 ||
            strcmp(cat, "DISPLAY") == 0 ||
            strcmp(cat, "FOCUS") == 0 ||
            strcmp(cat, "KEY") == 0 ||
            strcmp(cat, "HOOK") == 0);
}

static void record_last_hook_state(const char *tag) {
    if (!tag || tag[0] == '\0') {
        return;
    }
    strlcpy(gLastHookOrTransition, tag, sizeof(gLastHookOrTransition));
}

static int parse_numbered_log_index(const char *name, const char *prefix, const char *suffix) {
    if (!name || !prefix || !suffix) {
        return -1;
    }
    size_t pLen = strlen(prefix);
    size_t sLen = strlen(suffix);
    size_t nLen = strlen(name);
    if (nLen <= pLen + sLen) {
        return -1;
    }
    if (strncmp(name, prefix, pLen) != 0) {
        return -1;
    }
    if (strcmp(name + nLen - sLen, suffix) != 0) {
        return -1;
    }
    const char *digits = name + pLen;
    size_t dLen = nLen - pLen - sLen;
    if (dLen == 0 || dLen > 9) {
        return -1;
    }
    int val = 0;
    for (size_t i = 0; i < dLen; i++) {
        if (digits[i] < '0' || digits[i] > '9') {
            return -1;
        }
        val = val * 10 + (digits[i] - '0');
    }
    return (val > 0) ? val : -1;
}

typedef struct {
    int number;
    char filename[128];
} Sims2NumberedLogEntry;

static int cmp_numbered_log_entries(const void *a, const void *b) {
    const Sims2NumberedLogEntry *ea = (const Sims2NumberedLogEntry *)a;
    const Sims2NumberedLogEntry *eb = (const Sims2NumberedLogEntry *)b;
    if (ea->number < eb->number) return -1;
    if (ea->number > eb->number) return 1;
    return strcmp(ea->filename, eb->filename);
}

/*
 * Boot-only scanner (never called from a signal handler): scans dirPath if it already exists
 * (never creates it), computes the next free sequence number (max + 1, starting at 1),
 * and soft-prunes only the oldest matching files when exceeding maxKeep (20).
 */
static int scan_and_prune_numbered_logs(const char *dirPath,
                                        const char *prefix,
                                        const char *suffix,
                                        int maxKeep,
                                        BOOL reserveForNewFile) {
    if (!dirPath || dirPath[0] == '\0' || !prefix || !suffix) {
        return 1;
    }
    DIR *d = opendir(dirPath);
    if (!d) {
        return 1;
    }
    Sims2NumberedLogEntry entries[256];
    size_t count = 0;
    int maxNum = 0;
    struct dirent *de = NULL;
    while ((de = readdir(d)) != NULL) {
        int num = parse_numbered_log_index(de->d_name, prefix, suffix);
        if (num > 0) {
            if (num > maxNum) {
                maxNum = num;
            }
            if (count < (sizeof(entries) / sizeof(entries[0]))) {
                entries[count].number = num;
                strlcpy(entries[count].filename, de->d_name, sizeof(entries[count].filename));
                count++;
            }
        }
    }
    closedir(d);

    int keepLimit = reserveForNewFile ? (maxKeep - 1) : maxKeep;
    if (keepLimit < 1) {
        keepLimit = 1;
    }
    if ((int)count > keepLimit) {
        qsort(entries, count, sizeof(entries[0]), cmp_numbered_log_entries);
        size_t toDelete = count - (size_t)keepLimit;
        for (size_t i = 0; i < toDelete; i++) {
            char delPath[768];
            int n = snprintf(delPath, sizeof(delPath), "%s/%s", dirPath, entries[i].filename);
            if (n > 0 && (size_t)n < sizeof(delPath)) {
                unlink(delPath);
            }
        }
    }
    return maxNum + 1;
}

static void diaglog_rotate_locked(void) {
    if (!gDiagLogFile || gDiagLogPath[0] == '\0') {
        return;
    }
    fflush(gDiagLogFile);
    fclose(gDiagLogFile);
    gDiagLogFile = NULL;
    gDiagLogFd = -1;
    if (gDiagPrevLogPath[0] != '\0') {
        rename(gDiagLogPath, gDiagPrevLogPath);
    }
    FILE *fp = fopen(gDiagLogPath, "w");
    if (fp) {
        setvbuf(fp, NULL, _IOFBF, 16384);
        gDiagLogFile = fp;
        gDiagLogFd = fileno(fp);
        gDiagLogBytesWritten = 0;
        int n = fprintf(gDiagLogFile, "[+%09.3fs] [DIAG] Rotated diagnostic log (limit=%zu bytes)\n",
                        diag_elapsed_seconds(), kSims2DiagLogMaxBytes);
        if (n > 0) {
            gDiagLogBytesWritten += (size_t)n;
        }
    } else {
        gDiagLogEnabled = NO;
    }
}

static void diaglog_flush(void) {
    pthread_mutex_lock(&gDebugLogMutex);
    if (gDiagLogFile) {
        fflush(gDiagLogFile);
        gLastDiagFlushTime = CFAbsoluteTimeGetCurrent();
    }
    if (gDebugLogFile) {
        fflush(gDebugLogFile);
    }
    pthread_mutex_unlock(&gDebugLogMutex);
}

static void diaglog_init_if_enabled(void) {
    const char *envDiag = getenv("SIMS2_DIAG_LOG");
    /* Opt-in diagnostic telemetry: disabled by default for zero disk I/O in normal gameplay.
       Enable explicitly via SIMS2_DIAG_LOG=1 or `defaults write com.aspyr.sims2.appstore S2PatchDiagLog -bool true`. */
    BOOL envEnabled = (envDiag && envDiag[0] == '1');
    BOOL envDisabled = (envDiag && envDiag[0] == '0');
    BOOL prefEnabled = (!envDisabled && [[NSUserDefaults standardUserDefaults] boolForKey:kSims2PrefDiagLogKey]);
    gDiagLogPrefEnabled = prefEnabled;
    BOOL enabled = (envEnabled || prefEnabled);
    const char *envOsLog = getenv("SIMS2_DIAG_OSLOG");
    gDiagOsLogEnabled = (envOsLog && envOsLog[0] == '1');
    if (gDiagOsLogEnabled && !gDiagOsLog) {
        gDiagOsLog = os_log_create("com.sims2patch.diag", "runtime");
    }
    if (!enabled) {
        gDiagLogEnabled = NO;
        return;
    }

    const char *envDiagDir = getenv("SIMS2_DIAG_LOG_DIR");
    NSString *tmpDir = (envDiagDir && envDiagDir[0] != '\0')
        ? [NSString stringWithUTF8String:envDiagDir]
        : NSTemporaryDirectory();
    if (!tmpDir || [tmpDir length] == 0) {
        gDiagLogEnabled = NO;
        return;
    }
    NSString *cleanDir = [tmpDir stringByStandardizingPath];
    const char *dirCStr = [cleanDir fileSystemRepresentation];
    if (!dirCStr || dirCStr[0] == '\0') {
        gDiagLogEnabled = NO;
        return;
    }

    gDiagLogNumber = scan_and_prune_numbered_logs(dirCStr, "sims2_patch_diag_", ".log",
                                                  kSims2MaxNumberedLogs, YES);
    char diagBase[64];
    snprintf(diagBase, sizeof(diagBase), "sims2_patch_diag_%03d.log", gDiagLogNumber);
    snprintf(gDiagLogPath, sizeof(gDiagLogPath), "%s/%s", dirCStr, diagBase);
    snprintf(gDiagLogLinkPath, sizeof(gDiagLogLinkPath), "%s/sims2_patch_diag.log", dirCStr);
    snprintf(gDiagPrevLogPath, sizeof(gDiagPrevLogPath), "%s/sims2_patch_diag.prev.log", dirCStr);

    FILE *fp = fopen(gDiagLogPath, "w");
    if (!fp) {
        gDiagLogEnabled = NO;
        return;
    }
    setvbuf(fp, NULL, _IOFBF, 16384);

    /* Maintain $TMPDIR/sims2_patch_diag.log symlink -> active numbered log (e.g. sims2_patch_diag_001.log) */
    unlink(gDiagLogLinkPath);
    symlink(diagBase, gDiagLogLinkPath);

    pthread_mutex_lock(&gDebugLogMutex);
    gDiagLogFile = fp;
    gDiagLogFd = fileno(fp);
    gDiagLogBytesWritten = 0;
    gDiagLogEnabled = YES;
    gLastDiagFlushTime = CFAbsoluteTimeGetCurrent();
    pthread_mutex_unlock(&gDebugLogMutex);
    atexit(diaglog_flush);
}

static void debuglog_write(const char *category, const char *fmt, ...) {
    if (!fmt || (!gDebugBootEnabled && !gDiagLogEnabled && !gDiagOsLogEnabled)) {
        return;
    }
    struct timeval tv;
    gettimeofday(&tv, NULL);
    time_t sec = tv.tv_sec;
    struct tm tm_info;
    localtime_r(&sec, &tm_info);
    double elapsedSec = diag_elapsed_seconds();

    char msgBuf[1536];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(msgBuf, sizeof(msgBuf), fmt, ap);
    va_end(ap);

    const char *cat = category ? category : "LOG";

    if (gDiagOsLogEnabled && gDiagOsLog) {
        os_log_info(gDiagOsLog, "[+%{public}09.3fs] [%{public}s] %{public}s",
                    elapsedSec, cat, msgBuf);
    }

    pthread_mutex_lock(&gDebugLogMutex);
    if (gDebugBootEnabled && gDebugLogFile) {
        fprintf(gDebugLogFile, "[+%09.3fs] [%02d:%02d:%02d.%03d] [%s] %s\n",
                elapsedSec,
                tm_info.tm_hour, tm_info.tm_min, tm_info.tm_sec, (int)(tv.tv_usec / 1000),
                cat, msgBuf);
        fflush(gDebugLogFile);
    }
    if (gDiagLogEnabled && gDiagLogFile) {
        int written = fprintf(gDiagLogFile, "[+%09.3fs] [%02d:%02d:%02d.%03d] [%s] %s\n",
                              elapsedSec,
                              tm_info.tm_hour, tm_info.tm_min, tm_info.tm_sec, (int)(tv.tv_usec / 1000),
                              cat, msgBuf);
        if (written > 0) {
            gDiagLogBytesWritten += (size_t)written;
        }
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (diag_category_needs_immediate_flush(cat) || (now - gLastDiagFlushTime) >= 0.5) {
            fflush(gDiagLogFile);
            gLastDiagFlushTime = now;
        }
        if (gDiagLogBytesWritten >= kSims2DiagLogMaxBytes) {
            diaglog_rotate_locked();
        }
    }
    pthread_mutex_unlock(&gDebugLogMutex);
}

static void strip_trailing_slashes(char *path) {
    if (!path) {
        return;
    }
    size_t len = strlen(path);
    while (len > 1 && path[len - 1] == '/') {
        path[--len] = '\0';
    }
}

static void init_log_paths_and_system_info(void) {
    time_t bootSec = time(NULL);
    struct tm bootTm;
    if (localtime_r(&bootSec, &bootTm) != NULL) {
        gBootLocalTzOffsetSec = bootTm.tm_gmtoff;
    }

    const char *home = getenv("HOME");
    if (!home || home[0] == '\0') {
        NSString *nsHome = NSHomeDirectory();
        home = nsHome ? [nsHome UTF8String] : NULL;
    }
    if (home && home[0] != '\0') {
        snprintf(gLibDir, sizeof(gLibDir), "%s/Library", home);
        snprintf(gLogsRootDir, sizeof(gLogsRootDir), "%s/Library/Logs", home);
        snprintf(gLogsDir, sizeof(gLogsDir), "%s/Library/Logs/Sims2-Crash-Patch", home);
        strip_trailing_slashes(gLogsDir);

        /* Pre-compute next numbered crash log path at boot (never creates gLogsDir on clean run,
           soft-prunes only oldest files beyond 20, 100% outside any signal handler). */
        gCrashLogNumber = scan_and_prune_numbered_logs(gLogsDir, "sims2_crash_", ".log",
                                                       kSims2MaxNumberedLogs, NO);
        snprintf(gCrashLogBasename, sizeof(gCrashLogBasename), "sims2_crash_%03d.log", gCrashLogNumber);
        snprintf(gCrashLogPath, sizeof(gCrashLogPath), "%s/%s", gLogsDir, gCrashLogBasename);
        snprintf(gCrashLatestLinkPath, sizeof(gCrashLatestLinkPath), "%s/crash_report.log", gLogsDir);

        snprintf(gDebugLogPath, sizeof(gDebugLogPath), "%s/debug_boot.log", gLogsDir);
        snprintf(gDebugPrevLogPath, sizeof(gDebugPrevLogPath), "%s/debug_boot.previous.log", gLogsDir);
        snprintf(gDebugFlagPath, sizeof(gDebugFlagPath), "%s/.debug_enabled", gLogsDir);
    }

    /* Pre-compute $TMPDIR fallback crash log path in static C buffers (async-signal-safe fallback) */
    const char *envDiagDir = getenv("SIMS2_DIAG_LOG_DIR");
    const char *tmpCStr = NULL;
    if (envDiagDir && envDiagDir[0] != '\0') {
        tmpCStr = envDiagDir;
    } else {
        NSString *nsTmp = NSTemporaryDirectory();
        if (nsTmp && [nsTmp length] > 0) {
            tmpCStr = [[nsTmp stringByStandardizingPath] fileSystemRepresentation];
        }
        if (!tmpCStr || tmpCStr[0] == '\0') {
            tmpCStr = getenv("TMPDIR");
        }
        if (!tmpCStr || tmpCStr[0] == '\0') {
            tmpCStr = "/tmp";
        }
    }
    if (tmpCStr && tmpCStr[0] != '\0') {
        strlcpy(gTmpLogsDir, tmpCStr, sizeof(gTmpLogsDir));
        strip_trailing_slashes(gTmpLogsDir);
        gCrashFallbackLogNumber = scan_and_prune_numbered_logs(gTmpLogsDir, "sims2_crash_", ".log",
                                                               kSims2MaxNumberedLogs, NO);
        snprintf(gCrashFallbackBasename, sizeof(gCrashFallbackBasename),
                 "sims2_crash_%03d.log", gCrashFallbackLogNumber);
        snprintf(gCrashFallbackLogPath, sizeof(gCrashFallbackLogPath),
                 "%s/%s", gTmpLogsDir, gCrashFallbackBasename);
        snprintf(gCrashFallbackLatestLinkPath, sizeof(gCrashFallbackLatestLinkPath),
                 "%s/crash_report.log", gTmpLogsDir);
    }

    size_t modelLen = sizeof(gCachedHwModel) - 1;
    if (sysctlbyname("hw.model", gCachedHwModel, &modelLen, NULL, 0) == 0 && modelLen > 0) {
        gCachedHwModel[modelLen] = '\0';
    } else {
        snprintf(gCachedHwModel, sizeof(gCachedHwModel), "unknown");
    }

    size_t osLen = sizeof(gCachedOsVersion) - 1;
    if (sysctlbyname("kern.osproductversion", gCachedOsVersion, &osLen, NULL, 0) == 0 && osLen > 0) {
        gCachedOsVersion[osLen] = '\0';
    } else {
        NSOperatingSystemVersion v = [[NSProcessInfo processInfo] operatingSystemVersion];
        snprintf(gCachedOsVersion, sizeof(gCachedOsVersion), "%ld.%ld.%ld",
                 (long)v.majorVersion, (long)v.minorVersion, (long)v.patchVersion);
    }

    CGRect bounds = CGDisplayBounds(CGMainDisplayID());
    if (bounds.size.width > 0.0 && bounds.size.height > 0.0) {
        snprintf(gCachedFrameStr, sizeof(gCachedFrameStr), "%.0fx%.0f@(%.0f,%.0f)",
                 bounds.size.width, bounds.size.height, bounds.origin.x, bounds.origin.y);
    }
}

static void update_cached_screen_geometry(NSScreen *scr) {
    NSScreen *target = scr ?: [NSScreen mainScreen];
    if (!target) {
        return;
    }
    NSRect sf = target.frame;
    NSRect vf = target.visibleFrame;
    snprintf(gCachedFrameStr, sizeof(gCachedFrameStr), "%.0fx%.0f@(%.0f,%.0f) scale=%.1f",
             sf.size.width, sf.size.height, sf.origin.x, sf.origin.y, target.backingScaleFactor);
    snprintf(gCachedVisibleFrameStr, sizeof(gCachedVisibleFrameStr), "%.0fx%.0f@(%.0f,%.0f)",
             vf.size.width, vf.size.height, vf.origin.x, vf.origin.y);
}

static void debuglog_init_if_enabled(void) {
    const char *envDbg = getenv("SIMS2_DEBUG");
    BOOL envEnabled = (envDbg && envDbg[0] == '1');
    struct stat flagSt;
    BOOL flagEnabled = (gDebugFlagPath[0] != '\0' && stat(gDebugFlagPath, &flagSt) == 0);

    if (!envEnabled && !flagEnabled) {
        gDebugBootEnabled = NO;
        return;
    }
    if (gLogsDir[0] == '\0' || gDebugLogPath[0] == '\0') {
        return;
    }

    ensure_dir_exists(gLibDir);
    ensure_dir_exists(gLogsRootDir);
    ensure_dir_exists(gLogsDir);

    struct stat logSt;
    if (stat(gDebugLogPath, &logSt) == 0) {
        rename(gDebugLogPath, gDebugPrevLogPath);
    }

    FILE *fp = fopen(gDebugLogPath, "w");
    if (!fp) {
        return;
    }
    pthread_mutex_lock(&gDebugLogMutex);
    gDebugLogFile = fp;
    gDebugBootEnabled = YES;
    pthread_mutex_unlock(&gDebugLogMutex);
}

static void write_all_fd(int fd, const char *buf, size_t len) {
    size_t off = 0;
    while (off < len) {
        ssize_t n = write(fd, buf + off, len - off);
        if (n <= 0) {
            if (errno == EINTR) {
                continue;
            }
            break;
        }
        off += (size_t)n;
    }
}

static void write_cstr_fd(int fd, const char *s) {
    if (!s) {
        return;
    }
    write_all_fd(fd, s, strlen(s));
}

static void write_int_fd(int fd, long val) {
    char buf[32];
    int idx = (int)sizeof(buf);
    unsigned long uval;
    BOOL neg = NO;
    if (val < 0) {
        neg = YES;
        uval = (unsigned long)(-(val + 1)) + 1UL;
    } else {
        uval = (unsigned long)val;
    }
    if (uval == 0) {
        buf[--idx] = '0';
    } else {
        while (uval > 0 && idx > 1) {
            buf[--idx] = (char)('0' + (uval % 10UL));
            uval /= 10UL;
        }
    }
    if (neg && idx > 0) {
        buf[--idx] = '-';
    }
    write_all_fd(fd, buf + idx, (size_t)((int)sizeof(buf) - idx));
}

static void write_hex_fd(int fd, uintptr_t val) {
    static const char hex[] = "0123456789abcdef";
    char buf[24];
    int idx = (int)sizeof(buf);
    if (val == 0) {
        buf[--idx] = '0';
    } else {
        while (val > 0 && idx > 2) {
            buf[--idx] = hex[val & 0xFUL];
            val >>= 4;
        }
    }
    buf[--idx] = 'x';
    buf[--idx] = '0';
    write_all_fd(fd, buf + idx, (size_t)((int)sizeof(buf) - idx));
}

static const char *signal_label(int sig) {
    switch (sig) {
        case SIGSEGV: return "SIGSEGV";
        case SIGABRT: return "SIGABRT";
        case SIGBUS:  return "SIGBUS";
        case SIGILL:  return "SIGILL";
        case SIGFPE:  return "SIGFPE";
        default:      return "SIGNAL";
    }
}

static void write_2digit_fd(int fd, int val) {
    char buf[2];
    if (val < 0) val = 0;
    if (val > 99) val = val % 100;
    buf[0] = (char)('0' + (val / 10));
    buf[1] = (char)('0' + (val % 10));
    write_all_fd(fd, buf, 2);
}

static void write_3digit_fd(int fd, int val) {
    char buf[3];
    if (val < 0) val = 0;
    if (val > 999) val = val % 1000;
    buf[0] = (char)('0' + (val / 100));
    buf[1] = (char)('0' + ((val / 10) % 10));
    buf[2] = (char)('0' + (val % 10));
    write_all_fd(fd, buf, 3);
}

/* Pure-integer, 100% async-signal-safe civil timestamp formatter (zero locks, zero heap) */
static void write_local_timestamp_fd(int fd) {
    struct timespec ts;
    if (clock_gettime(CLOCK_REALTIME, &ts) != 0) {
        write_cstr_fd(fd, "unknown");
        return;
    }
    int64_t localSec = (int64_t)ts.tv_sec + (int64_t)gBootLocalTzOffsetSec;
    int64_t days = localSec / 86400;
    int64_t rem = localSec % 86400;
    if (rem < 0) {
        rem += 86400;
        days -= 1;
    }
    int hour = (int)(rem / 3600);
    int minute = (int)((rem % 3600) / 60);
    int second = (int)(rem % 60);

    /* Civil calendar conversion (Howard Hinnant algorithm) */
    int64_t z = days + 719468;
    int64_t era = (z >= 0 ? z : z - 146096) / 146097;
    uint64_t doe = (uint64_t)(z - era * 146097);
    uint64_t yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    int64_t y = (int64_t)yoe + era * 400;
    uint64_t doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    uint64_t mp = (5 * doy + 2) / 153;
    int day = (int)(doy - (153 * mp + 2) / 5 + 1);
    int month = (int)(mp + (mp < 10 ? 3 : -9));
    if (month <= 2) {
        y += 1;
    }

    write_int_fd(fd, (long)y);
    write_cstr_fd(fd, "-");
    write_2digit_fd(fd, month);
    write_cstr_fd(fd, "-");
    write_2digit_fd(fd, day);
    write_cstr_fd(fd, " ");
    write_2digit_fd(fd, hour);
    write_cstr_fd(fd, ":");
    write_2digit_fd(fd, minute);
    write_cstr_fd(fd, ":");
    write_2digit_fd(fd, second);

    uint64_t nowNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    if (gBootMonotonicNs > 0 && nowNs >= gBootMonotonicNs) {
        uint64_t elapsedMs = (nowNs - gBootMonotonicNs) / 1000000ULL;
        write_cstr_fd(fd, " (+");
        write_int_fd(fd, (long)(elapsedMs / 1000ULL));
        write_cstr_fd(fd, ".");
        write_3digit_fd(fd, (int)(elapsedMs % 1000ULL));
        write_cstr_fd(fd, "s uptime)");
    }
}

static const char *path_basename_cstr(const char *path) {
    if (!path || path[0] == '\0') {
        return "<unknown>";
    }
    const char *slash = strrchr(path, '/');
    return (slash && slash[1] != '\0') ? (slash + 1) : path;
}

static void flush_diaglog_for_crash_async_safe(void) {
    if (gDiagLogEnabled && gDiagLogFile) {
        if (pthread_mutex_trylock(&gDebugLogMutex) == 0) {
            fflush(gDiagLogFile);
            if (gDebugLogFile) {
                fflush(gDebugLogFile);
            }
            pthread_mutex_unlock(&gDebugLogMutex);
        }
    }
    if (gDiagLogFd >= 0) {
        fsync(gDiagLogFd);
    }
}

static void write_crash_report_async_safe(const char *reason, int sig, siginfo_t *info) {
    if (!__sync_bool_compare_and_swap(&gCrashReportWritten, 0, 1)) {
        return;
    }

    /* Flush diagnostic telemetry immediately so pre-crash context is never lost */
    flush_diaglog_for_crash_async_safe();

    const char *usedPath = NULL;
    const char *usedBase = NULL;
    const char *usedLink = NULL;
    int usedNum = gCrashLogNumber;
    int fd = -1;

    if (gCrashLogPath[0] != '\0') {
        mkdir(gLibDir, 0755);
        mkdir(gLogsRootDir, 0755);
        mkdir(gLogsDir, 0755);
        fd = open(gCrashLogPath, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0644);
        if (fd >= 0) {
            usedPath = gCrashLogPath;
            usedBase = gCrashLogBasename;
            usedLink = gCrashLatestLinkPath;
            usedNum = gCrashLogNumber;
        }
    }
    if (fd < 0 && gCrashFallbackLogPath[0] != '\0') {
        fd = open(gCrashFallbackLogPath, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0644);
        if (fd >= 0) {
            usedPath = gCrashFallbackLogPath;
            usedBase = gCrashFallbackBasename;
            usedLink = gCrashFallbackLatestLinkPath;
            usedNum = gCrashFallbackLogNumber;
        }
    }
    if (fd < 0) {
        return;
    }

    write_cstr_fd(fd, "=== Sims 2 Crash Patch — Automatic Crash Report ===\n");
    write_cstr_fd(fd, "Timestamp     : ");
    write_local_timestamp_fd(fd);
    write_cstr_fd(fd, "\nCrash Log #   : ");
    write_int_fd(fd, (long)usedNum);
    if (usedPath) {
        write_cstr_fd(fd, " (");
        write_cstr_fd(fd, usedPath);
        write_cstr_fd(fd, ")");
    }
    write_cstr_fd(fd, "\nPatch Version : " SIMS2_PATCH_VERSION "\n");
    write_cstr_fd(fd, "PID           : ");
    write_int_fd(fd, (long)getpid());
    write_cstr_fd(fd, "\nMac Model     : ");
    write_cstr_fd(fd, gCachedHwModel);
    write_cstr_fd(fd, "\nmacOS Version : ");
    write_cstr_fd(fd, gCachedOsVersion);
    write_cstr_fd(fd, "\nScreen frame  : ");
    write_cstr_fd(fd, gCachedFrameStr);
    write_cstr_fd(fd, "\nvisibleFrame  : ");
    write_cstr_fd(fd, gCachedVisibleFrameStr);
    write_cstr_fd(fd, "\nReason        : ");
    write_cstr_fd(fd, reason ? reason : "unknown");
    if (sig > 0) {
        write_cstr_fd(fd, " (");
        write_cstr_fd(fd, signal_label(sig));
        write_cstr_fd(fd, " #");
        write_int_fd(fd, (long)sig);
        write_cstr_fd(fd, ")");
    }
    if (info != NULL) {
        write_cstr_fd(fd, "\nSignal Code   : ");
        write_int_fd(fd, (long)info->si_code);
        write_cstr_fd(fd, "\nFault Address : ");
        write_hex_fd(fd, (uintptr_t)info->si_addr);
    }
    write_cstr_fd(fd, "\nPatch State   : windowed=");
    write_int_fd(fd, gWindowedModeActive ? 1 : 0);
    write_cstr_fd(fd, " inSpace=");
    write_int_fd(fd, gLastKnownInSpace ? 1 : 0);
    write_cstr_fd(fd, " hasFirstShow=");
    write_int_fd(fd, gHasCompletedFirstWindowShow ? 1 : 0);
    write_cstr_fd(fd, " inFsTrans=");
    write_int_fd(fd, gInFullscreenTransition ? 1 : 0);
    write_cstr_fd(fd, " fb=");
    write_int_fd(fd, (long)gEngineFbW);
    write_cstr_fd(fd, "x");
    write_int_fd(fd, (long)gEngineFbH);
    write_cstr_fd(fd, " target=");
    write_int_fd(fd, (long)gTargetWindowWidth);
    write_cstr_fd(fd, "x");
    write_int_fd(fd, (long)gTargetWindowHeight);
    write_cstr_fd(fd, " lastHook=");
    write_cstr_fd(fd, gLastHookOrTransition);
    if (gDiagLogEnabled && gDiagLogPath[0] != '\0') {
        write_cstr_fd(fd, "\nDiag Log      : ");
        write_cstr_fd(fd, gDiagLogPath);
    }
    write_cstr_fd(fd, "\nLast C++ Throw: ");
    write_cstr_fd(fd, gLastCxaThrowInfo);
    write_cstr_fd(fd, "\n\n--- Symbolized Backtrace ---\n");

    void *frames[64];
    int nframes = backtrace(frames, 64);
    if (nframes > 0) {
        BOOL anyResolved = NO;
        for (int i = 0; i < nframes; i++) {
            uintptr_t addr = (uintptr_t)frames[i];
            Dl_info dli;
            memset(&dli, 0, sizeof(dli));
            write_cstr_fd(fd, "#");
            write_int_fd(fd, (long)i);
            write_cstr_fd(fd, "  ");
            write_hex_fd(fd, addr);
            write_cstr_fd(fd, "  ");
            if (dladdr(frames[i], &dli) != 0 && dli.dli_fbase != NULL) {
                anyResolved = YES;
                const char *imgName = path_basename_cstr(dli.dli_fname);
                uintptr_t imgOff = (addr >= (uintptr_t)dli.dli_fbase)
                    ? (addr - (uintptr_t)dli.dli_fbase)
                    : 0;
                write_cstr_fd(fd, imgName);
                write_cstr_fd(fd, " + ");
                write_hex_fd(fd, imgOff);
                write_cstr_fd(fd, "  ");
                if (dli.dli_sname && dli.dli_sname[0] != '\0') {
                    write_cstr_fd(fd, dli.dli_sname);
                    if (dli.dli_saddr && addr >= (uintptr_t)dli.dli_saddr) {
                        write_cstr_fd(fd, " + ");
                        write_hex_fd(fd, addr - (uintptr_t)dli.dli_saddr);
                    }
                } else {
                    write_cstr_fd(fd, "<unnamed>");
                }
            } else {
                write_cstr_fd(fd, "<unknown>");
            }
            write_cstr_fd(fd, "\n");
        }
        if (!anyResolved) {
            backtrace_symbols_fd(frames, nframes, fd);
        }
    } else {
        write_cstr_fd(fd, "(unavailable)\n");
    }

    fsync(fd);
    close(fd);

    /* Update latest crash_report.log symlink -> sims2_crash_NNN.log (async-signal-safe POSIX calls) */
    if (usedLink && usedLink[0] != '\0' && usedBase && usedBase[0] != '\0') {
        unlink(usedLink);
        symlink(usedBase, usedLink);
    }
}

static void sims2_crash_signal_handler(int sig, siginfo_t *info, void *uap) {
    (void)uap;
    write_crash_report_async_safe("Fatal Signal", sig, info);
    /* Restore SIG_DFL and re-raise (never exit early) so macOS ReportCrash receives
       the uncaught fatal signal and generates a native .ips crash report too. */
    struct sigaction dfl;
    memset(&dfl, 0, sizeof(dfl));
    dfl.sa_handler = SIG_DFL;
    sigemptyset(&dfl.sa_mask);
    if (sig > 0 && sig < 32) {
        sigaction(sig, &dfl, NULL);
        sigset_t unblock;
        sigemptyset(&unblock);
        sigaddset(&unblock, sig);
        sigprocmask(SIG_UNBLOCK, &unblock, NULL);
        raise(sig);
    }
}

static void sims2_uncaught_objc_exception_handler(NSException *exception) {
    char reason[320];
    const char *name = (exception && [exception name]) ? [[exception name] UTF8String] : "NSException";
    const char *desc = (exception && [exception reason]) ? [[exception reason] UTF8String] : "unknown";
    snprintf(reason, sizeof(reason), "Uncaught ObjC NSException: %.96s — %.180s",
             name ? name : "NSException", desc ? desc : "unknown");
    write_crash_report_async_safe(reason, 0, NULL);
    if (gPrevObjCUncaughtExceptionHandler &&
        gPrevObjCUncaughtExceptionHandler != sims2_uncaught_objc_exception_handler) {
        gPrevObjCUncaughtExceptionHandler(exception);
    }
}

static void sims2_terminate_handler(void) {
    typedef const void *(*CurrentExcTypeFn)(void);
    CurrentExcTypeFn curExcFn = (CurrentExcTypeFn)dlsym(RTLD_DEFAULT, "__cxa_current_exception_type");
    const char *excName = NULL;
    if (curExcFn) {
        const void *ti = curExcFn();
        if (ti) {
            excName = *(const char * const *)((const char *)ti + sizeof(void *));
        }
    }
    char reason[256];
    if (excName && excName[0] != '\0') {
        snprintf(reason, sizeof(reason), "C++ std::terminate (exception: %.180s)", excName);
    } else {
        snprintf(reason, sizeof(reason), "C++ std::terminate");
    }
    write_crash_report_async_safe(reason, 0, NULL);

    if (gPrevTerminateHandler && gPrevTerminateHandler != sims2_terminate_handler) {
        gPrevTerminateHandler();
    }
    abort();
}

static void install_crash_handlers(void) {
    /* Dedicated alternate signal stack so stack overflows & deep faults still capture a full report */
    stack_t altStack;
    memset(&altStack, 0, sizeof(altStack));
    altStack.ss_sp = gCrashAltStackMem;
    altStack.ss_size = sizeof(gCrashAltStackMem);
    altStack.ss_flags = 0;
    sigaltstack(&altStack, NULL);

    static const int kCrashSignals[] = { SIGSEGV, SIGABRT, SIGBUS, SIGILL, SIGFPE };
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = sims2_crash_signal_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_SIGINFO | SA_ONSTACK | SA_NODEFER;

    for (size_t i = 0; i < sizeof(kCrashSignals) / sizeof(kCrashSignals[0]); i++) {
        int sig = kCrashSignals[i];
        if (sig > 0 && sig < 32) {
            sigaction(sig, &sa, &gPrevSigActions[sig]);
        }
    }

    gPrevObjCUncaughtExceptionHandler = NSGetUncaughtExceptionHandler();
    NSSetUncaughtExceptionHandler(&sims2_uncaught_objc_exception_handler);

    typedef Sims2TerminateHandler (*SetTerminateFn)(Sims2TerminateHandler);
    SetTerminateFn setTermFn = (SetTerminateFn)dlsym(RTLD_DEFAULT, "_ZSt13set_terminatePFvvE");
    if (setTermFn) {
        gPrevTerminateHandler = setTermFn(sims2_terminate_handler);
    }
}

static void log_msg(NSString *msg) {
    if (gDebug) {
        NSLog(@"[Sims2Trackpad] %@", msg);
    }
}

/*
 * Resolve unshifted virtual keycodes for ',' (rotate left) and '.' (rotate right)
 * matching SDL2's Cocoa_UpdateKeymap UCKeyTranslate Pass 1 (modifierKeyState = 0).
 */
static void resolve_camera_rotate_keycodes_from_layout(const UCKeyboardLayout *layout,
                                                       UInt8 kbdType,
                                                       uint16_t *outLeftKey,
                                                       uint16_t *outRightKey) {
    uint16_t leftKey = 43;
    uint16_t rightKey = 47;
    BOOL foundLeft = NO;
    BOOL foundRight = NO;
    if (layout && outLeftKey && outRightKey) {
        for (UInt16 kc = 0; kc < 128; kc++) {
            if (kc >= 65 && kc <= 92) {
                continue;
            }
            UInt32 deadKeyState = 0;
            UniChar chars[4] = {0};
            UniCharCount actualLen = 0;
            OSStatus status = UCKeyTranslate(layout,
                                             kc,
                                             kUCKeyActionDisplay,
                                             0,
                                             kbdType,
                                             kUCKeyTranslateNoDeadKeysMask,
                                             &deadKeyState,
                                             4,
                                             &actualLen,
                                             chars);
            if (status == noErr && actualLen == 1) {
                if (!foundLeft && chars[0] == (UniChar)',') {
                    leftKey = kc;
                    foundLeft = YES;
                } else if (!foundRight && chars[0] == (UniChar)'.') {
                    rightKey = kc;
                    foundRight = YES;
                }
            }
        }
    }
    if (outLeftKey) {
        *outLeftKey = leftKey;
    }
    if (outRightKey) {
        *outRightKey = rightKey;
    }
}

static void resolve_camera_rotate_keycodes(uint16_t *outLeftKey, uint16_t *outRightKey) {
    uint16_t leftKey = 43;
    uint16_t rightKey = 47;

    TISInputSourceRef src = TISCopyCurrentKeyboardLayoutInputSource();
    if (src) {
        CFDataRef layoutData = (CFDataRef)TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData);
        if (layoutData && CFDataGetLength(layoutData) > 0) {
            const UCKeyboardLayout *layout = (const UCKeyboardLayout *)CFDataGetBytePtr(layoutData);
            resolve_camera_rotate_keycodes_from_layout(layout, LMGetKbdType(), &leftKey, &rightKey);
        }
        CFRelease(src);
    }

    gCachedLeftRotateKey = leftKey;
    gCachedRightRotateKey = rightKey;
    if (outLeftKey) {
        *outLeftKey = leftKey;
    }
    if (outRightKey) {
        *outRightKey = rightKey;
    }
}

static void release_key_immediately(uint16_t keyCode, NSString *ch) {
    if (keyCode >= 128 || !gKeyTapActive[keyCode]) {
        return;
    }
    gKeyTapActive[keyCode] = NO;
    gKeyTapSeq[keyCode]++;

    NSWindow *win = [NSApp keyWindow];
    NSInteger winNum = win ? [win windowNumber] : 0;
    NSTimeInterval ts = [[NSProcessInfo processInfo] systemUptime];
    NSEvent *upEv = [NSEvent keyEventWithType:NSEventTypeKeyUp
                                     location:NSZeroPoint
                                modifierFlags:0
                                    timestamp:ts
                                 windowNumber:winNum
                                      context:nil
                                   characters:ch
                  charactersIgnoringModifiers:ch
                                    isARepeat:NO
                                      keyCode:keyCode];
    if (upEv) {
        [NSApp postEvent:upEv atStart:NO];
    }
}

static void release_active_rotate_keys(void) {
    release_key_immediately(gCachedLeftRotateKey, @",");
    release_key_immediately(gCachedRightRotateKey, @".");
    release_key_immediately(43, @",");
    release_key_immediately(46, @",");
    release_key_immediately(47, @".");
}

/*
 * Hold camera rotation key for 75 ms (extendable on continuous swipe/twist)
 * because Sims2XP_Exe evaluates 0xBC / 0xBE in continuous hold mode (ecx = 2).
 */
static void trigger_or_extend_rotate_key(uint16_t keyCode, uint16_t oppositeKeyCode, NSString *ch, NSString *oppositeCh) {
    if (keyCode >= 128) {
        return;
    }
    NSWindow *win = [NSApp keyWindow];
    if (!win || ![win isVisible]) {
        return;
    }

    if (oppositeKeyCode < 128 && oppositeKeyCode != keyCode && gKeyTapActive[oppositeKeyCode]) {
        release_key_immediately(oppositeKeyCode, oppositeCh);
    }

    NSInteger winNum = [win windowNumber];
    if (!gKeyTapActive[keyCode]) {
        NSTimeInterval ts = [[NSProcessInfo processInfo] systemUptime];
        NSEvent *downEv = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                           location:NSZeroPoint
                                      modifierFlags:0
                                          timestamp:ts
                                       windowNumber:winNum
                                            context:nil
                                         characters:ch
                        charactersIgnoringModifiers:ch
                                          isARepeat:NO
                                            keyCode:keyCode];
        if (!downEv) {
            return;
        }
        gKeyTapActive[keyCode] = YES;
        [NSApp postEvent:downEv atStart:NO];
    }

    uint32_t seq = ++gKeyTapSeq[keyCode];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(75 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        if (gKeyTapSeq[keyCode] != seq || !gKeyTapActive[keyCode]) {
            return;
        }
        gKeyTapActive[keyCode] = NO;
        NSTimeInterval upTs = [[NSProcessInfo processInfo] systemUptime];
        NSWindow *curWin = [NSApp keyWindow];
        NSInteger curWinNum = curWin ? [curWin windowNumber] : winNum;
        NSEvent *upEv = [NSEvent keyEventWithType:NSEventTypeKeyUp
                                         location:NSZeroPoint
                                    modifierFlags:0
                                        timestamp:upTs
                                     windowNumber:curWinNum
                                          context:nil
                                       characters:ch
                      charactersIgnoringModifiers:ch
                                        isARepeat:NO
                                          keyCode:keyCode];
        if (upEv) {
            [NSApp postEvent:upEv atStart:NO];
        }
    });
}

static void post_rotation_key(BOOL rotateRight) {
    uint16_t leftKey = 43;
    uint16_t rightKey = 47;
    resolve_camera_rotate_keycodes(&leftKey, &rightKey);

    BOOL targetRight = gInvertRotation ? !rotateRight : rotateRight;
    if (targetRight) {
        trigger_or_extend_rotate_key(rightKey, leftKey, @".", @",");
    } else {
        trigger_or_extend_rotate_key(leftKey, rightKey, @",", @".");
    }
}

static id resolve_window_listener(void) {
    id listener = gWindowListener;
    if (listener) {
        return listener;
    }
    Class listenerCls = objc_getClass("Cocoa_WindowListener");
    NSWindow *win = [NSApp keyWindow];
    id delegate = win ? [win delegate] : nil;
    if (delegate && (!listenerCls || [delegate isKindOfClass:listenerCls]) &&
        [delegate respondsToSelector:@selector(scrollWheel:)]) {
        gWindowListener = delegate;
        return delegate;
    }
    return nil;
}

static void post_pinch_zoom_scroll(int direction) {
    CGEventRef cgEv = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitLine, 2, (int32_t)direction, 0);
    if (!cgEv) {
        return;
    }
    NSEvent *scrollEv = [NSEvent eventWithCGEvent:cgEv];
    CFRelease(cgEv);
    if (!scrollEv) {
        return;
    }

    id listener = resolve_window_listener();
    if (listener && gOrigScrollWheelIMP) {
        typedef void (*ScrollFn)(id, SEL, NSEvent *);
        BOOL prevForce = gForceScrollNonInverted;
        gForceScrollNonInverted = YES;
        ((ScrollFn)gOrigScrollWheelIMP)(listener, @selector(scrollWheel:), scrollEv);
        gForceScrollNonInverted = prevForce;
        return;
    }

    /* Guarantee non-inversion even if first pinch happens before gWindowListener is captured */
    gForcedNonInvertedEvent = scrollEv;
    [NSApp postEvent:scrollEv atStart:NO];
}

static void handle_scroll_event(NSEvent *event) {
    gSuppressedScrollEvent = nil;
    if (![event hasPreciseScrollingDeltas]) {
        return;
    }

    NSEventPhase phase = [event phase];
    NSEventPhase momentum = [event momentumPhase];

    if (phase == NSEventPhaseBegan || phase == NSEventPhaseMayBegin) {
        gScrollAxis = Sims2ScrollAxisNone;
        gScrollAccumX = 0.0;
    }

    if (momentum != NSEventPhaseNone) {
        if (gScrollAxis == Sims2ScrollAxisRotateX || gIsTwisting) {
            gSuppressedScrollEvent = event;
        }
        return;
    }

    if (gIsTwisting) {
        gSuppressedScrollEvent = event;
        return;
    }

    if (phase == NSEventPhaseEnded || phase == NSEventPhaseCancelled) {
        if (gScrollAxis != Sims2ScrollAxisNone) {
            debuglog_write("GESTURE", "SCROLL_END axis=%ld phase=%lu",
                           (long)gScrollAxis, (unsigned long)phase);
        }
        gScrollAxis = Sims2ScrollAxisNone;
        gScrollAccumX = 0.0;
        return;
    }

    double dx = [event scrollingDeltaX];
    double dy = [event scrollingDeltaY];
    double fingerRightDx = [event isDirectionInvertedFromDevice] ? -dx : dx;

    if (gScrollAxis == Sims2ScrollAxisNone) {
        double adx = fabs(fingerRightDx);
        double ady = fabs(dy);
        if (adx > 1.5 || ady > 1.5) {
            if (adx > ady * 1.35) {
                gScrollAxis = Sims2ScrollAxisRotateX;
                debuglog_write("GESTURE", "SCROLL_LOCK axis=RotateX dx=%.2f dy=%.2f inv=%d",
                               fingerRightDx, dy, [event isDirectionInvertedFromDevice] ? 1 : 0);
            } else {
                gScrollAxis = Sims2ScrollAxisZoomY;
                debuglog_write("GESTURE", "SCROLL_LOCK axis=ZoomY dx=%.2f dy=%.2f inv=%d",
                               fingerRightDx, dy, [event isDirectionInvertedFromDevice] ? 1 : 0);
            }
        }
    }

    if (gScrollAxis == Sims2ScrollAxisZoomY) {
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if ((now - gLastScrollLogTime) >= 0.25) {
            gLastScrollLogTime = now;
            debuglog_write("GESTURE", "SCROLL_ZOOM dx=%.2f dy=%.2f phase=%lu",
                           dx, dy, (unsigned long)phase);
        }
    }

    if (gScrollAxis == Sims2ScrollAxisRotateX) {
        gSuppressedScrollEvent = event;
        if ((gScrollAccumX > 0.0 && fingerRightDx < -1.0) ||
            (gScrollAccumX < 0.0 && fingerRightDx > 1.0)) {
            gScrollAccumX = 0.0;
        }
        gScrollAccumX += fingerRightDx;
        int steps = 0;
        BOOL rotatedRight = NO;
        while (gScrollAccumX >= gRotateStep && steps < 3) {
            gScrollAccumX -= gRotateStep;
            post_rotation_key(YES);
            rotatedRight = YES;
            steps++;
        }
        while (gScrollAccumX <= -gRotateStep && steps < 3) {
            gScrollAccumX += gRotateStep;
            post_rotation_key(NO);
            rotatedRight = NO;
            steps++;
        }
        if (steps > 0) {
            CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
            if ((now - gLastScrollLogTime) >= 0.25) {
                gLastScrollLogTime = now;
                debuglog_write("GESTURE", "SCROLL_ROTATE dir=%s steps=%d dx=%.2f",
                               rotatedRight ? "right" : "left", steps, fingerRightDx);
            }
        }
    }
}

static void handle_rotate_event(NSEvent *event) {
    NSEventPhase phase = [event phase];
    if (phase == NSEventPhaseBegan || phase == NSEventPhaseMayBegin) {
        gIsTwisting = YES;
        gTwistAccum = 0.0;
        debuglog_write("GESTURE", "TWIST_BEGIN");
        return;
    }
    if (phase == NSEventPhaseEnded || phase == NSEventPhaseCancelled) {
        gIsTwisting = NO;
        gTwistAccum = 0.0;
        debuglog_write("GESTURE", "TWIST_END");
        return;
    }

    gIsTwisting = YES;
    double clockwiseDeg = -[event rotation];
    if ((gTwistAccum > 0.0 && clockwiseDeg < -0.5) ||
        (gTwistAccum < 0.0 && clockwiseDeg > 0.5)) {
        gTwistAccum = 0.0;
    }
    gTwistAccum += clockwiseDeg;
    int steps = 0;
    BOOL rotatedRight = NO;
    while (gTwistAccum >= gTwistStep && steps < 3) {
        gTwistAccum -= gTwistStep;
        post_rotation_key(YES);
        rotatedRight = YES;
        steps++;
    }
    while (gTwistAccum <= -gTwistStep && steps < 3) {
        gTwistAccum += gTwistStep;
        post_rotation_key(NO);
        rotatedRight = NO;
        steps++;
    }
    if (steps > 0) {
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if ((now - gLastTwistLogTime) >= 0.25) {
            gLastTwistLogTime = now;
            debuglog_write("GESTURE", "TWIST_ROTATE dir=%s steps=%d deg=%.2f keys=(%u,%u)",
                           rotatedRight ? "right" : "left", steps, clockwiseDeg,
                           gCachedLeftRotateKey, gCachedRightRotateKey);
        }
    }
}

static void handle_magnify_event(NSEvent *event) {
    NSEventPhase phase = [event phase];
    if (phase == NSEventPhaseBegan || phase == NSEventPhaseMayBegin) {
        gPinchAccum = 0.0;
        debuglog_write("GESTURE", "PINCH_BEGIN");
        return;
    }
    if (phase == NSEventPhaseEnded || phase == NSEventPhaseCancelled) {
        gPinchAccum = 0.0;
        debuglog_write("GESTURE", "PINCH_END");
        return;
    }

    double mag = [event magnification];
    gPinchAccum += mag;
    int steps = 0;
    int lastDir = 0;
    while (gPinchAccum >= gPinchStep && steps < 4) {
        gPinchAccum -= gPinchStep;
        post_pinch_zoom_scroll(1);
        lastDir = 1;
        steps++;
    }
    while (gPinchAccum <= -gPinchStep && steps < 4) {
        gPinchAccum += gPinchStep;
        post_pinch_zoom_scroll(-1);
        lastDir = -1;
        steps++;
    }
    if (steps > 0) {
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if ((now - gLastPinchLogTime) >= 0.25) {
            gLastPinchLogTime = now;
            debuglog_write("GESTURE", "PINCH_ZOOM dir=%d steps=%d mag=%.3f", lastDir, steps, mag);
        }
    }
}

static NSEventModifierFlags raw_event_modifier_flags(NSEvent *event) {
    if (!event) {
        return 0;
    }
    typedef NSEventModifierFlags (*Fn)(id, SEL);
    return gOrigEventModifierFlagsIMP ? ((Fn)gOrigEventModifierFlagsIMP)(event, @selector(modifierFlags)) : [event modifierFlags];
}

static void release_ctrl_middle_drag(id listener) {
    if (!gCtrlMiddleDragActive) {
        return;
    }
    id targetListener = listener ?: resolve_window_listener();
    NSWindow *win = gLastMouseDownWindow ?: resolve_primary_game_window();
    IMP upIMP = gOrigMouseUpIMP;
    SEL upSEL = @selector(mouseUp:);
    BOOL wasRight = gCtrlDragWasRight;
    NSEventType upType = wasRight ? NSEventTypeRightMouseUp : NSEventTypeLeftMouseUp;

    /* Clear state BEFORE sending synthetic mouse-up to guarantee re-entrancy safety */
    gCtrlMiddleDragActive = NO;
    gCtrlDragWasRight = NO;
    gLastMouseDownWindow = nil;

    debuglog_write("CTRL_ORBIT", "END_SYNTH btn=%s win=%p listener=%p",
                   wasRight ? "right" : "left",
                   (__bridge void *)win,
                   (__bridge void *)targetListener);

    if (win && upIMP && targetListener) {
        NSRect cb = win.contentView ? win.contentView.bounds : NSMakeRect(0.0, 0.0, 640.0, 480.0);
        NSPoint safePt = NSMakePoint(floor(cb.size.width * 0.5), floor(cb.size.height * 0.5));
        NSTimeInterval ts = [[NSProcessInfo processInfo] systemUptime];
        NSEvent *synthUp = [NSEvent mouseEventWithType:upType
                                              location:safePt
                                         modifierFlags:0
                                             timestamp:ts
                                          windowNumber:[win windowNumber]
                                               context:nil
                                           eventNumber:0
                                            clickCount:1
                                              pressure:0.0];
        if (synthUp) {
            typedef void (*MouseUpFn)(id, SEL, NSEvent *);
            BOOL prevProj = tProjectMouseLocationForSDL;
            BOOL prevUp = tInMouseUpHandler;
            tProjectMouseLocationForSDL = NO;
            tInMouseUpHandler = YES;
            gSpoofMiddleButton = YES;
            gMaskControlModifier = YES;
            ((MouseUpFn)upIMP)(targetListener, upSEL, synthUp);
            gSpoofMiddleButton = NO;
            gMaskControlModifier = NO;
            tInMouseUpHandler = prevUp;
            tProjectMouseLocationForSDL = prevProj;
        }
    }
    CGEventFlags liveCg = CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState);
    if ((liveCg & kCGEventFlagMaskControl) == 0) {
        flush_stuck_modifier_state_to_sdl(win, "ctrl-orbit-release");
    }
}

static void format_key_label(NSEvent *ev, char *outBuf, size_t outBufSize) {
    if (!outBuf || outBufSize == 0) {
        return;
    }
    outBuf[0] = '\0';
    if (!ev) {
        snprintf(outBuf, outBufSize, "?");
        return;
    }
    unsigned short kc = [ev keyCode];
    switch (kc) {
        case 36: snprintf(outBuf, outBufSize, "Return"); return;
        case 48: snprintf(outBuf, outBufSize, "Tab"); return;
        case 49: snprintf(outBuf, outBufSize, "Space"); return;
        case 51: snprintf(outBuf, outBufSize, "Delete"); return;
        case 53: snprintf(outBuf, outBufSize, "Escape"); return;
        case 55: snprintf(outBuf, outBufSize, "LCommand"); return;
        case 56: snprintf(outBuf, outBufSize, "LShift"); return;
        case 58: snprintf(outBuf, outBufSize, "LOption"); return;
        case 59: snprintf(outBuf, outBufSize, "LControl"); return;
        case 60: snprintf(outBuf, outBufSize, "RShift"); return;
        case 61: snprintf(outBuf, outBufSize, "ROption"); return;
        case 62: snprintf(outBuf, outBufSize, "RControl"); return;
        case 76: snprintf(outBuf, outBufSize, "NumpadEnter"); return;
        case 123: snprintf(outBuf, outBufSize, "Left"); return;
        case 124: snprintf(outBuf, outBufSize, "Right"); return;
        case 125: snprintf(outBuf, outBufSize, "Down"); return;
        case 126: snprintf(outBuf, outBufSize, "Up"); return;
        default: break;
    }
    if ([ev type] == NSEventTypeKeyDown || [ev type] == NSEventTypeKeyUp) {
        NSString *chars = [ev charactersIgnoringModifiers];
        if (chars && [chars length] > 0) {
            unichar ch = [chars characterAtIndex:0];
            if (ch >= 33 && ch < 127) {
                snprintf(outBuf, outBufSize, "%c", (char)ch);
                return;
            }
            snprintf(outBuf, outBufSize, "U+%04X", (unsigned int)ch);
            return;
        }
    }
    snprintf(outBuf, outBufSize, "kc=%u", (unsigned int)kc);
}

static void describe_keyboard_source(NSEvent *ev, char *outBuf, size_t outBufSize) {
    if (!outBuf || outBufSize == 0) {
        return;
    }
    if (!ev) {
        snprintf(outBuf, outBufSize, "null");
        return;
    }
    CGEventRef cgEv = [ev CGEvent];
    if (!cgEv) {
        snprintf(outBuf, outBufSize, "synth");
        return;
    }
    int64_t kbdType = CGEventGetIntegerValueField(cgEv, kCGKeyboardEventKeyboardType);
    int64_t srcPid = CGEventGetIntegerValueField(cgEv, kCGEventSourceUnixProcessID);
    int64_t srcState = CGEventGetIntegerValueField(cgEv, kCGEventSourceStateID);
    if (srcPid != 0) {
        snprintf(outBuf, outBufSize, "injected(pid=%lld,kbd=%lld)", (long long)srcPid, (long long)kbdType);
    } else {
        const char *layoutKind = (kbdType == 41) ? "ISO" : ((kbdType == 40) ? "ANSI" : ((kbdType == 42) ? "JIS" : "HID"));
        snprintf(outBuf, outBufSize, "hw(%s,kbd=%lld,st=%lld)", layoutKind, (long long)kbdType, (long long)srcState);
    }
}

/*
 * Prevent stuck modifiers (Command/Option/Control) in SDL2 after shortcuts,
 * menu tracking, Space transitions, or releasing Option/Control outside a windowed canvas.
 * Note: Cocoa_WindowListener::flagsChanged: (0x100103510) is an empty no-op in SDL2;
 * Cocoa_HandleKeyEvent (0x1000fda10) only runs via NSApp event dispatch/pump, so posting
 * NSEventTypeFlagsChanged through NSApp guarantees SDL2 updates its live modifier mask
 * (and clears stuck Option/Control camera cursors ↻ / [↔]).
 */
static void flush_stuck_modifier_state_to_sdl(NSWindow *win, const char *reason) {
    if (!NSApp || gPostingSyntheticFlagsEvent) {
        return;
    }
    CGEventFlags liveCgFlags = CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState);
    NSEventModifierFlags cleanFlags = 0;
    BOOL forceClearAll = (reason &&
                          (strncmp(reason, "shortcut", 8) == 0 ||
                           strncmp(reason, "option-cam-reset", 16) == 0));
    if (!forceClearAll) {
        if (liveCgFlags & kCGEventFlagMaskShift) cleanFlags |= NSEventModifierFlagShift;
        if (liveCgFlags & kCGEventFlagMaskControl) cleanFlags |= NSEventModifierFlagControl;
        if (liveCgFlags & kCGEventFlagMaskAlternate) cleanFlags |= NSEventModifierFlagOption;
        if (liveCgFlags & kCGEventFlagMaskCommand) cleanFlags |= NSEventModifierFlagCommand;
    }
    @try {
        NSWindow *targetWin = win ?: resolve_primary_game_window();
        NSInteger winNum = targetWin ? [targetWin windowNumber] : 0;
        NSTimeInterval ts = [[NSProcessInfo processInfo] systemUptime];
        unsigned short flushKeyCode = forceClearAll ? 55 : 58;
        if (reason && strncmp(reason, "ctrl-", 5) == 0) {
            flushKeyCode = 59;
        }
        gPostingSyntheticFlagsEvent = YES;
        NSEvent *flagsEv = [NSEvent keyEventWithType:NSEventTypeFlagsChanged
                                            location:NSZeroPoint
                                       modifierFlags:cleanFlags
                                           timestamp:ts
                                        windowNumber:winNum
                                             context:nil
                                          characters:@""
                         charactersIgnoringModifiers:@""
                                           isARepeat:NO
                                             keyCode:flushKeyCode];
        if (flagsEv) {
            /* Post at front of queue so SDL2 Cocoa_HandleKeyEvent updates its modifier mask once cleanly */
            [NSApp postEvent:flagsEv atStart:YES];
            /* Guard against SDL2's 0xC0000 (Control|Option) AltGr early-return quirk (0x1000fdbba):
               if both Control and Option were previously seen and we are clearing both to 0,
               step through Option-only -> 0 so SDL2 never drops the transition. */
            if ((cleanFlags & (NSEventModifierFlagControl | NSEventModifierFlagOption)) == 0 &&
                (gLastLoggedModifierMask & (NSEventModifierFlagControl | NSEventModifierFlagOption)) ==
                (NSEventModifierFlagControl | NSEventModifierFlagOption)) {
                NSEvent *stepEv = [NSEvent keyEventWithType:NSEventTypeFlagsChanged
                                                   location:NSZeroPoint
                                              modifierFlags:NSEventModifierFlagOption
                                                  timestamp:ts
                                               windowNumber:winNum
                                                    context:nil
                                                 characters:@""
                                charactersIgnoringModifiers:@""
                                                  isARepeat:NO
                                                    keyCode:59];
                if (stepEv) {
                    [NSApp postEvent:stepEv atStart:YES];
                }
            }
            debuglog_write("MOD", "Flushed SDL modifier state (%s) -> cleanFlags=0x%lx liveCG=0x%llx",
                           reason ? reason : "sync",
                           (unsigned long)cleanFlags,
                           (unsigned long long)liveCgFlags);
        }
        gPostingSyntheticFlagsEvent = NO;
    } @catch (NSException *ex) {
        gPostingSyntheticFlagsEvent = NO;
        debuglog_write("MOD", "flush_stuck_modifier_state_to_sdl exception: %s",
                       ex.reason ? [ex.reason UTF8String] : "unknown");
    }
}

static BOOL try_accept_shortcut_trigger(const char *actionName,
                                        const char *triggerSource,
                                        NSTimeInterval eventTs,
                                        double minIntervalSec,
                                        BOOL blockDuringFsTransition) {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (blockDuringFsTransition && gInFullscreenTransition) {
        debuglog_write("KEY", "DEDUP ignored %s from %s (fullscreen transition in progress)",
                       actionName, triggerSource);
        return NO;
    }
    if (eventTs > 0.0 && gLastHandledShortcutEventTimestamp > 0.0 &&
        fabs(eventTs - gLastHandledShortcutEventTimestamp) < 0.015) {
        debuglog_write("KEY", "DEDUP ignored %s from %s (duplicate NSEvent ts=%.4f)",
                       actionName, triggerSource, eventTs);
        return NO;
    }
    double dt = now - gLastModeToggleTime;
    if (gLastModeToggleTime > 0.0 && dt < minIntervalSec) {
        debuglog_write("KEY", "DEDUP ignored %s from %s (debounce dt=%.3fs < %.2fs)",
                       actionName, triggerSource, dt, minIntervalSec);
        return NO;
    }
    gLastModeToggleTime = now;
    if (eventTs > 0.0) {
        gLastHandledShortcutEventTimestamp = eventTs;
    }
    debuglog_write("KEY", "ACCEPTED %s from %s (ts=%.4f)", actionName, triggerSource, eventTs);
    return YES;
}

static void toggle_windowed_fullscreen_mode_ex(NSTimeInterval eventTs, const char *source);
static void cycle_next_resolution_ex(NSTimeInterval eventTs, const char *source);

static NSEvent *swizzled_nextEventMatchingMask(id self, SEL _cmd, NSEventMask mask,
                                               NSDate *expiration, NSRunLoopMode mode, BOOL dequeue) {
    if (gPendingOpenGLSurfaceSync) {
        NSWindow *primaryWin = resolve_primary_game_window();
        if (primaryWin && resolve_game_opengl_context(primaryWin) != nil) {
            apply_opengl_surface_backing_size_ex(primaryWin, NO);
        }
    }
    if (gCtrlMiddleDragActive || gNativeOptionCamHeld) {
        CGEventFlags liveCgFlags = CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState);
        if (gCtrlMiddleDragActive &&
            ((liveCgFlags & kCGEventFlagMaskControl) == 0 || ([NSEvent pressedMouseButtons] & 0x7) == 0)) {
            release_ctrl_middle_drag(resolve_window_listener());
        }
        if (gNativeOptionCamHeld && (liveCgFlags & kCGEventFlagMaskAlternate) == 0) {
            gNativeOptionCamHeld = NO;
            debuglog_write("OPTION_CAM", "RELEASE_LIVE_SYNC windowed=%d", gWindowedModeActive ? 1 : 0);
            flush_stuck_modifier_state_to_sdl(resolve_primary_game_window(), "option-cam-live-release");
        }
    }
    typedef NSEvent *(*Fn)(id, SEL, NSEventMask, NSDate *, NSRunLoopMode, BOOL);
    NSEvent *ev = ((Fn)gOrigNextEventIMP)(self, _cmd, mask, expiration, mode, dequeue);
    if (ev && dequeue) {
        NSEventType t = [ev type];
        if (t == NSEventTypeScrollWheel) {
            handle_scroll_event(ev);
        } else if (t == NSEventTypeRotate) {
            handle_rotate_event(ev);
        } else if (t == NSEventTypeMagnify) {
            handle_magnify_event(ev);
        } else if (t == NSEventTypeKeyDown || t == NSEventTypeKeyUp) {
            NSEventModifierFlags rawFlags = raw_event_modifier_flags(ev);
            NSEventModifierFlags cleanMods = rawFlags & (NSEventModifierFlagOption |
                                                         NSEventModifierFlagCommand |
                                                         NSEventModifierFlagControl |
                                                         NSEventModifierFlagShift);
            unsigned short kc = [ev keyCode];
            /* Two strictly separated Command-only display shortcuts (no Option/Control/Shift,
             * leaving Option 100% untouched for The Sims 2 camera and never intercepting macOS
             * system shortcuts Cmd+Q/H/M/W/Tab):
             *   1. Command + Return (kc == 36 || kc == 76): toggle Fullscreen Space <-> Windowed
             *   2. Command + R (kc == 15): cycle Windowed resolutions ONLY (strict no-op in Fullscreen)
             */
            BOOL isOurShortcutKey = (kc == 36 || kc == 76 || kc == 15);
            if (isOurShortcutKey && cleanMods == NSEventModifierFlagCommand) {
                if (t == NSEventTypeKeyDown && !ev.isARepeat) {
                    char srcDesc[64];
                    describe_keyboard_source(ev, srcDesc, sizeof(srcDesc));
                    NSTimeInterval evTs = [ev timestamp];
                    if (kc == 36 || kc == 76) {
                        debuglog_write("KEY", "Command + Return intercepted (kc=%u src=%s) -> toggling Fullscreen/Windowed mode",
                                       (unsigned int)kc, srcDesc);
                        flush_stuck_modifier_state_to_sdl(resolve_primary_game_window(), "shortcut-cmd-return");
                        toggle_windowed_fullscreen_mode_ex(evTs, "hotkey");
                    } else if (kc == 15) {
                        if (!gWindowedModeActive) {
                            debuglog_write("KEY", "Command + R ignored in Fullscreen (windowed-only, src=%s)", srcDesc);
                        } else {
                            debuglog_write("KEY", "Command + R intercepted (kc=15 src=%s) -> cycling windowed resolution", srcDesc);
                            flush_stuck_modifier_state_to_sdl(resolve_primary_game_window(), "shortcut-cmd-r");
                            cycle_next_resolution_ex(evTs, "hotkey");
                        }
                    }
                }
                return nil;
            }
            if (![ev isARepeat] && (gDebugBootEnabled || gDiagLogEnabled || gDiagOsLogEnabled)) {
                char keyLabel[32];
                char srcDesc[64];
                format_key_label(ev, keyLabel, sizeof(keyLabel));
                describe_keyboard_source(ev, srcDesc, sizeof(srcDesc));
                debuglog_write("KEY", "%s kc=%u key=%s src=%s mods=0x%lx ctrl=%d opt=%d shift=%d cmd=%d",
                               (t == NSEventTypeKeyDown) ? "keyDown" : "keyUp",
                               (unsigned int)kc,
                               keyLabel,
                               srcDesc,
                               (unsigned long)rawFlags,
                               (rawFlags & NSEventModifierFlagControl) ? 1 : 0,
                               (rawFlags & NSEventModifierFlagOption) ? 1 : 0,
                               (rawFlags & NSEventModifierFlagShift) ? 1 : 0,
                               (rawFlags & NSEventModifierFlagCommand) ? 1 : 0);
            }
        } else if (t == NSEventTypeFlagsChanged) {
            NSEventModifierFlags rawFlags = raw_event_modifier_flags(ev);
            BOOL optHeldNow = (rawFlags & NSEventModifierFlagOption) != 0;
            BOOL cmdHeldNow = (rawFlags & NSEventModifierFlagCommand) != 0;
            if (optHeldNow && !cmdHeldNow) {
                if (!gNativeOptionCamHeld) {
                    gNativeOptionCamHeld = YES;
                    debuglog_write("OPTION_CAM", "START kc=%u windowed=%d",
                                   (unsigned int)[ev keyCode], gWindowedModeActive ? 1 : 0);
                }
            } else if (gNativeOptionCamHeld && !optHeldNow) {
                gNativeOptionCamHeld = NO;
                debuglog_write("OPTION_CAM", "END kc=%u windowed=%d",
                               (unsigned int)[ev keyCode], gWindowedModeActive ? 1 : 0);
            }
            if (gCtrlMiddleDragActive && ((rawFlags & NSEventModifierFlagControl) == 0)) {
                release_ctrl_middle_drag(resolve_window_listener());
            }
            if (gDebugBootEnabled || gDiagLogEnabled || gDiagOsLogEnabled) {
                NSUInteger trackedMods = rawFlags & (NSEventModifierFlagControl |
                                                     NSEventModifierFlagOption |
                                                     NSEventModifierFlagShift |
                                                     NSEventModifierFlagCommand);
                if (trackedMods != gLastLoggedModifierMask) {
                    gLastLoggedModifierMask = trackedMods;
                    char keyLabel[32];
                    char srcDesc[64];
                    format_key_label(ev, keyLabel, sizeof(keyLabel));
                    describe_keyboard_source(ev, srcDesc, sizeof(srcDesc));
                    debuglog_write("MOD", "flagsChanged kc=%u(%s) src=%s ctrl=%d opt=%d shift=%d cmd=%d (raw=0x%lx)",
                                   (unsigned int)[ev keyCode], keyLabel, srcDesc,
                                   (trackedMods & NSEventModifierFlagControl) ? 1 : 0,
                                   (trackedMods & NSEventModifierFlagOption) ? 1 : 0,
                                   (trackedMods & NSEventModifierFlagShift) ? 1 : 0,
                                   (trackedMods & NSEventModifierFlagCommand) ? 1 : 0,
                                   (unsigned long)rawFlags);
                }
            }
        }
    }
    return ev;
}

static void swizzled_scrollWheel(id self, SEL _cmd, NSEvent *event) {
    gWindowListener = self;
    if (event && event == gSuppressedScrollEvent) {
        gSuppressedScrollEvent = nil;
        return;
    }
    BOOL isForcedEvent = (event && event == gForcedNonInvertedEvent);
    if (isForcedEvent) {
        gForceScrollNonInverted = YES;
    }
    typedef void (*Fn)(id, SEL, NSEvent *);
    if (gOrigScrollWheelIMP) {
        BOOL prevProj = tProjectMouseLocationForSDL;
        tProjectMouseLocationForSDL = YES;
        ((Fn)gOrigScrollWheelIMP)(self, _cmd, event);
        tProjectMouseLocationForSDL = prevProj;
    }
    if (isForcedEvent) {
        gForceScrollNonInverted = NO;
        gForcedNonInvertedEvent = nil;
    }
}

static NSInteger swizzled_buttonNumber(id self, SEL _cmd) {
    if (gSpoofMiddleButton) {
        return 2; // SDL_BUTTON_MIDDLE
    }
    typedef NSInteger (*Fn)(id, SEL);
    return ((Fn)gOrigButtonNumberIMP)(self, _cmd);
}

static NSEventModifierFlags swizzled_eventModifierFlags(id self, SEL _cmd) {
    typedef NSEventModifierFlags (*Fn)(id, SEL);
    NSEventModifierFlags flags = gOrigEventModifierFlagsIMP ? ((Fn)gOrigEventModifierFlagsIMP)(self, _cmd) : 0;
    if (gMaskControlModifier || gCtrlMiddleDragActive) {
        flags &= ~NSEventModifierFlagControl;
    }
    return flags;
}

static NSEventModifierFlags swizzled_classModifierFlags(id self, SEL _cmd) {
    typedef NSEventModifierFlags (*Fn)(id, SEL);
    NSEventModifierFlags flags = gOrigClassModifierFlagsIMP ? ((Fn)gOrigClassModifierFlagsIMP)(self, _cmd) : 0;
    if (gMaskControlModifier || gCtrlMiddleDragActive) {
        flags &= ~NSEventModifierFlagControl;
    }
    return flags;
}

static BOOL swizzled_isDirectionInvertedFromDevice(id self, SEL _cmd) {
    if (gForceScrollNonInverted || (self && self == gForcedNonInvertedEvent)) {
        return NO;
    }
    typedef BOOL (*Fn)(id, SEL);
    return gOrigIsDirectionInvertedIMP ? ((Fn)gOrigIsDirectionInvertedIMP)(self, _cmd) : NO;
}

static BOOL is_mouse_event_for_sdl_projection(NSEventType t) {
    switch (t) {
        case NSEventTypeLeftMouseDown:
        case NSEventTypeLeftMouseUp:
        case NSEventTypeLeftMouseDragged:
        case NSEventTypeRightMouseDown:
        case NSEventTypeRightMouseUp:
        case NSEventTypeRightMouseDragged:
        case NSEventTypeOtherMouseDown:
        case NSEventTypeOtherMouseUp:
        case NSEventTypeOtherMouseDragged:
        case NSEventTypeMouseMoved:
        case NSEventTypeScrollWheel:
            return YES;
        default:
            return NO;
    }
}

/*
 * Strict SDL2 initialization guard: during Cocoa_CreateWindow (0x1001042d0), AppKit executes
 * -[NSWindow initWithContentRect:...] -> _fromScreenCommonCode: -> setFrameOrigin: BEFORE SDL2
 * attaches Cocoa_WindowListener and driverdata (SDL_WindowData*). Calling SDL2's -[SDLWindow findSDLWindow]
 * (0x100101980) while any window in _this->windows still has driverdata == NULL crashes at 0x8(%rcx).
 * Instead, verify delegate == Cocoa_WindowListener, contentView != nil, and read _data directly in O(1)
 * with explicit NULL and nswindow-identity checks.
 */
static BOOL is_sdl_window_fully_attached(NSWindow *win) {
    if (!win || ![win contentView]) {
        return NO;
    }
    id delegate = [win delegate];
    if (!delegate) {
        return NO;
    }
    Class listenerCls = objc_getClass("Cocoa_WindowListener");
    if (listenerCls && ![delegate isKindOfClass:listenerCls]) {
        return NO;
    }
    return YES;
}

static uint8_t *safe_get_sdl_window_for_nswindow(NSWindow *win) {
    if (!is_sdl_window_fully_attached(win)) {
        return NULL;
    }
    id delegate = [win delegate];
    static ptrdiff_t sListenerDataIvarOffset = -1;
    static dispatch_once_t sOnce;
    dispatch_once(&sOnce, ^{
        Class listenerCls = objc_getClass("Cocoa_WindowListener");
        if (listenerCls) {
            Ivar iv = class_getInstanceVariable(listenerCls, "_data");
            if (iv) {
                sListenerDataIvarOffset = ivar_getOffset(iv);
            }
        }
    });
    if (sListenerDataIvarOffset < 0) {
        return NULL;
    }
    /* SDL_WindowData layout (verified in Sims2XP_Exe Cocoa_WindowListener._data):
       +0x00 = SDL_Window *window, +0x08 = NSWindow *nswindow */
    const uint8_t *driverData =
        *(const uint8_t * const *)((const uint8_t *)(__bridge const void *)delegate + sListenerDataIvarOffset);
    if (!driverData) {
        return NULL;
    }
    const void *boundWin = *(const void * const *)(driverData + 0x08);
    if (boundWin != (__bridge const void *)win) {
        return NULL;
    }
    return *(uint8_t * const *)(driverData + 0x00);
}

static BOOL query_sdl_window_rect(NSWindow *win, CGFloat *outX, CGFloat *outY, CGFloat *outW, CGFloat *outH) {
    const uint8_t *sdlWin = safe_get_sdl_window_for_nswindow(win);
    if (!sdlWin) {
        return NO;
    }
    int32_t x = 0, y = 0, w = 0, h = 0;
    memcpy(&x, sdlWin + 0x20, sizeof(x));
    memcpy(&y, sdlWin + 0x24, sizeof(y));
    memcpy(&w, sdlWin + 0x28, sizeof(w));
    memcpy(&h, sdlWin + 0x2c, sizeof(h));
    if (w >= 640 && w <= 8192 && h >= 480 && h <= 8192) {
        if (outX) *outX = (CGFloat)x;
        if (outY) *outY = (CGFloat)y;
        if (outW) *outW = (CGFloat)w;
        if (outH) *outH = (CGFloat)h;
        return YES;
    }
    return NO;
}

static BOOL query_sdl_window_logical_size(NSWindow *win, CGFloat *outW, CGFloat *outH) {
    return query_sdl_window_rect(win, NULL, NULL, outW, outH);
}

static NSRect query_window_content_screen_rect(NSWindow *win) {
    if (!win) {
        return NSZeroRect;
    }
    if (win.contentView) {
        NSRect bounds = win.contentView.bounds;
        if (bounds.size.width >= 1.0 && bounds.size.height >= 1.0) {
            NSRect inWin = [win.contentView convertRect:bounds toView:nil];
            return [win convertRectToScreen:inWin];
        }
    }
    return [win contentRectForFrameRect:win.frame];
}

/*
 * CoreGraphics global display coordinates always place (0,0) at the top-left of the primary
 * display (NSScreen.screens[0]), NEVER win.screen. Always use screens[0].frame.size.height
 * (with CGDisplayBounds(CGMainDisplayID()) fallback) so AppKit -> CG Y conversion remains
 * exact on secondary displays with screen.frame.origin != (0,0).
 */
static CGFloat query_primary_screen_height_for_cg(void) {
    if ([NSThread isMainThread] && NSApp != nil) {
        NSArray<NSScreen *> *screens = [NSScreen screens];
        if (screens && [screens count] > 0) {
            NSScreen *primary = [screens objectAtIndex:0];
            if (primary && primary.frame.size.height >= 480.0) {
                return primary.frame.size.height;
            }
        }
    }
    CGFloat cgH = CGDisplayBounds(CGMainDisplayID()).size.height;
    if (cgH >= 480.0) {
        return cgH;
    }
    return (CGFloat)gRawHardwareScreenHeight;
}

/*
 * Synchronize SDL_Window->x / SDL_Window->y (offsets 0x20 / 0x24) with the real
 * live NSWindow content rect in SDL2's exact top-left coordinate system
 * (matching Cocoa_WindowListener::windowDidMove: at 0x100102489) and refresh
 * the thread-safe inverse-warp geometry cache.
 */
static void sync_sdl_window_origin_to_frame(NSWindow *win, const char *reason) {
    if (!is_sdl_window_fully_attached(win) || !is_sdl_game_window(win) || is_secondary_orphan_game_window(win)) {
        return;
    }
    uint8_t *sdlWin = safe_get_sdl_window_for_nswindow(win);
    if (!sdlWin) {
        return;
    }
    NSRect contentScreen = query_window_content_screen_rect(win);
    if (contentScreen.size.width < 1.0 || contentScreen.size.height < 1.0) {
        return;
    }
    CGFloat rawPrimaryH = query_primary_screen_height_for_cg();
    CGFloat hookedDisplayH = (CGFloat)hook_CGDisplayPixelsHigh(CGMainDisplayID());
    if (hookedDisplayH < 480.0) {
        hookedDisplayH = (CGFloat)gNativeScreenHeight;
    }
    int32_t targetX = (int32_t)llround(contentScreen.origin.x);
    int32_t targetY = (int32_t)llround(hookedDisplayH - NSMaxY(contentScreen));

    gCachedContentScreenRect = contentScreen;
    gCachedRawPrimaryScreenH = rawPrimaryH;
    gCachedSdlOriginX = (CGFloat)targetX;
    gCachedSdlOriginY = (CGFloat)targetY;
    gCachedWarpGeometryValid = YES;

    int32_t curX = 0, curY = 0;
    memcpy(&curX, sdlWin + 0x20, sizeof(curX));
    memcpy(&curY, sdlWin + 0x24, sizeof(curY));
    if (curX != targetX || curY != targetY) {
        memcpy(sdlWin + 0x20, &targetX, sizeof(targetX));
        memcpy(sdlWin + 0x24, &targetY, sizeof(targetY));
        NSRect wf = win.frame;
        debuglog_write("WIN", "Synced SDL_Window origin (%s): (%d,%d) -> (%d,%d) winFrame=%.0fx%.0f@(%.0f,%.0f) contentScreen=%.0fx%.0f@(%.0f,%.0f)",
                       reason ? reason : "sync",
                       curX, curY, targetX, targetY,
                       wf.size.width, wf.size.height, wf.origin.x, wf.origin.y,
                       contentScreen.size.width, contentScreen.size.height,
                       contentScreen.origin.x, contentScreen.origin.y);
    }
}

/*
 * SDL2 Cocoa_WindowListener::windowDidEnterFullScreen: (0x100102f7b) and
 * windowDidExitFullScreen: (0x1001033a4) explicitly zero out sdlWin->w/h (0x28/0x2c)
 * before calling windowDidResize:. When we suppress SDL resize (Windowed mode),
 * restore sdlWin->w/h to gEngineFbW x gEngineFbH AND sync sdlWin->x/y so
 * SDL_UpdateMouseFocus and Cocoa_WarpMouse never use stale bounds or origins.
 */
static void sync_sdl_window_logical_size_to_engine_fb(NSWindow *win, const char *reason) {
    if (!is_sdl_window_fully_attached(win) || !is_sdl_game_window(win) || is_secondary_orphan_game_window(win)) {
        return;
    }
    sync_sdl_window_origin_to_frame(win, reason);
    if (!gHasCapturedInitialEngineFb || gEngineFbW < 640.0 || gEngineFbH < 480.0) {
        return;
    }
    uint8_t *sdlWin = safe_get_sdl_window_for_nswindow(win);
    if (!sdlWin) {
        return;
    }
    int32_t curW = 0, curH = 0;
    memcpy(&curW, sdlWin + 0x28, sizeof(curW));
    memcpy(&curH, sdlWin + 0x2c, sizeof(curH));
    int32_t targetW = (int32_t)llround(gEngineFbW);
    int32_t targetH = (int32_t)llround(gEngineFbH);
    BOOL inSpace = ((win.styleMask & NSWindowStyleMaskFullScreen) != 0);
    gLastKnownInSpace = inSpace;
    /* In native Fullscreen Space, allow <= 2 pt rounding difference (e.g. 38 vs 39 pt notch menu bar)
       without thrashing sdlWin->w/h back and forth on every resize; always repair 0x0 or > 2 pt drift. */
    if (!gWindowedModeActive && inSpace && curW >= 640 && curH >= 480 &&
        abs(curW - targetW) <= 2 && abs(curH - targetH) <= 2) {
        return;
    }
    if (curW != targetW || curH != targetH) {
        memcpy(sdlWin + 0x28, &targetW, sizeof(targetW));
        memcpy(sdlWin + 0x2c, &targetH, sizeof(targetH));
        debuglog_write("WIN", "Synced SDL_Window logical size (%s): %dx%d -> %dx%d",
                       reason ? reason : "sync", curW, curH, targetW, targetH);
    }
}

static void ensure_sdl_responder_chain(NSWindow *win, const char *reason) {
    if (!win || !is_sdl_game_window(win) || is_secondary_orphan_game_window(win)) {
        return;
    }
    NSView *cv = [win contentView];
    if (!cv) {
        return;
    }
    id listener = [win delegate];
    Class listenerCls = objc_getClass("Cocoa_WindowListener");
    if (!listener || (listenerCls && ![listener isKindOfClass:listenerCls])) {
        listener = gWindowListener;
    }
    if (!listener || listener == cv || ![listener isKindOfClass:[NSResponder class]]) {
        return;
    }
    /* Guard against any responder cycle */
    NSResponder *cursor = [(NSResponder *)listener nextResponder];
    int hops = 0;
    while (cursor && hops < 16) {
        if (cursor == cv) {
            return;
        }
        cursor = [cursor nextResponder];
        hops++;
    }
    if ([cv nextResponder] != listener) {
        NSResponder *prev = [cv nextResponder];
        [cv setNextResponder:(NSResponder *)listener];
        debuglog_write("FOCUS", "Restored contentView.nextResponder (%s): %s -> %s",
                       reason ? reason : "sync",
                       prev ? object_getClassName(prev) : "nil",
                       object_getClassName(listener));
    }
}

static void safe_set_sdl_window_style_mask(NSWindow *win, NSWindowStyleMask newMask, const char *reason) {
    if (!win) {
        return;
    }
    /* Mirror SDL2's exact responder detach/reattach sequence around setStyleMask: because
       AppKit replaces NSThemeFrame and resets contentView.nextResponder. */
    NSView *cv = [win contentView];
    id listener = [win delegate];
    Class listenerCls = objc_getClass("Cocoa_WindowListener");
    BOOL hadListener = (cv && listener && (!listenerCls || [listener isKindOfClass:listenerCls]) &&
                        [cv nextResponder] == listener);
    if (hadListener) {
        [cv setNextResponder:nil];
    }
    gSuppressSDLResizeNotification = YES;
    if (gOrigSDLSetStyleMaskIMP && gSDLWindowClass && [win isKindOfClass:gSDLWindowClass]) {
        typedef void (*StyleFn)(id, SEL, NSWindowStyleMask);
        ((StyleFn)gOrigSDLSetStyleMaskIMP)(win, @selector(setStyleMask:), newMask);
    } else {
        [win setStyleMask:newMask];
    }
    gSuppressSDLResizeNotification = NO;
    ensure_sdl_responder_chain(win, reason ? reason : "safe_setStyleMask");
}

static NSPoint raw_event_location_in_window(NSEvent *event, NSWindow *targetWin) {
    if (!event) {
        return NSZeroPoint;
    }
    typedef NSPoint (*LocFn)(id, SEL);
    NSPoint rawLoc = gOrigLocationInWindowIMP
        ? ((LocFn)gOrigLocationInWindowIMP)(event, @selector(locationInWindow))
        : [event locationInWindow];
    if (!targetWin) {
        return rawLoc;
    }
    NSWindow *evWin = [event window];
    if (!evWin) {
        /* When event.window == nil, AppKit's -[NSEvent locationInWindow] returns global screen coordinates. */
        return [targetWin convertPointFromScreen:rawLoc];
    }
    if (evWin != targetWin) {
        NSPoint screenPt = [evWin convertPointToScreen:rawLoc];
        return [targetWin convertPointFromScreen:screenPt];
    }
    return rawLoc;
}

static NSPoint project_window_point_for_sdl(NSWindow *win, NSPoint rawLoc, BOOL *outOutsideContent) {
    if (outOutsideContent) {
        *outOutsideContent = NO;
    }
    if (!win || !is_sdl_game_window(win) || is_secondary_orphan_game_window(win)) {
        return rawLoc;
    }
    NSView *contentView = [win contentView];
    if (!contentView) {
        return rawLoc;
    }
    NSPoint pt = [contentView convertPoint:rawLoc fromView:nil];
    NSRect contentBounds = [contentView bounds];
    CGFloat contentW = contentBounds.size.width;
    CGFloat contentH = contentBounds.size.height;
    if (contentW < 1.0 || contentH < 1.0) {
        return rawLoc;
    }

    CGFloat fbW = (gEngineFbW >= 640.0) ? gEngineFbW : contentW;
    CGFloat fbH = (gEngineFbH >= 480.0) ? gEngineFbH : contentH;
    CGFloat sdlW = fbW;
    CGFloat sdlH = fbH;
    query_sdl_window_logical_size(win, &sdlW, &sdlH);

    /* Immediate integral pass-through in 1:1 Fullscreen (tolerating <= 2 pt notch menu-bar rounding),
       except bottom/right exact boundary clamping so SDL_UpdateMouseFocus never drops edge clicks. */
    if (!gWindowedModeActive &&
        fabs(contentW - fbW) <= 2.0 && fabs(contentH - fbH) <= 2.0 &&
        fabs(sdlW - fbW) <= 2.0 && fabs(sdlH - fbH) <= 2.0) {
        CGFloat px = rawLoc.x;
        CGFloat py = rawLoc.y;
        if (px >= sdlW) px = sdlW - 1.0;
        if (py >= 0.0 && py < 1.0) py = 1.0;
        return NSMakePoint(px, py);
    }

    BOOL isOutside = (pt.y >= contentView.bounds.size.height || pt.y < 0.0 ||
                      pt.x < 0.0 || pt.x > contentView.bounds.size.width);
    if (isOutside) {
        if (outOutsideContent) {
            *outOutsideContent = YES;
        }
        if (!tClampDragProjectionForSDL) {
            /* Pass-through on titlebar or outside contentView so Cocoa handles window drag & buttons natively */
            return rawLoc;
        }
        /* During an active camera/mouse drag in Windowed mode, clamp smoothly to contentView edges
           before scaling so dragging past a window border never snaps back to unprojected coordinates. */
        if (pt.x < 0.0) pt.x = 0.0;
        if (pt.x > contentW) pt.x = contentW;
        if (pt.y < 0.0) pt.y = 0.0;
        if (pt.y > contentH) pt.y = contentH;
    }

    /* Project contentView bottom-left coords (pt.x, pt.y) so SDL's Cocoa_WindowListener::mouseMoved:
       (x = out.x, y = sdlWindow->h - out.y) matches exact engine top-down coords (u * fbW, (1 - v) * fbH),
       clamped strictly within [0, sdlW - 1] x [1, sdlH] so SDL_UpdateMouseFocus never emits LEAVE on the bottom HUD. */
    CGFloat x_sdl = pt.x * (fbW / contentW);
    CGFloat y_sdl = (sdlH - fbH) + pt.y * (fbH / contentH);
    if (sdlW >= 640.0 && sdlH >= 480.0) {
        if (x_sdl < 0.0) x_sdl = 0.0;
        if (x_sdl > sdlW - 1.0) x_sdl = sdlW - 1.0;
        if (y_sdl < 1.0) y_sdl = 1.0;
        if (y_sdl > sdlH) y_sdl = sdlH;
    }
    return NSMakePoint(x_sdl, y_sdl);
}

static BOOL is_event_outside_content_view(NSWindow *win, NSEvent *event) {
    if (!win || !event || !win.contentView || !is_sdl_game_window(win)) {
        return NO;
    }
    NSPoint rawLoc = raw_event_location_in_window(event, win);
    NSPoint pt = [win.contentView convertPoint:rawLoc fromView:nil];
    NSRect cb = win.contentView.bounds;
    return (pt.y >= cb.size.height || pt.y < 0.0 || pt.x < 0.0 || pt.x > cb.size.width);
}

static NSPoint swizzled_locationInWindow(id self, SEL _cmd) {
    typedef NSPoint (*Fn)(id, SEL);
    NSPoint rawLoc = gOrigLocationInWindowIMP ? ((Fn)gOrigLocationInWindowIMP)(self, _cmd) : NSZeroPoint;
    static __thread BOOL tInLoc = NO;
    /* Only project during SDL Cocoa_WindowListener motion/scroll callbacks so AppKit NSThemeFrame
       hit-testing AND SDL mouseDown:'s NSMouseInRect(..., contentView.frame, NO) always see raw coords. */
    if (!tProjectMouseLocationForSDL || tInLoc || !self) {
        return rawLoc;
    }
    NSEvent *event = (NSEvent *)self;
    NSEventType evType = [event type];
    if (!is_mouse_event_for_sdl_projection(evType)) {
        return rawLoc;
    }
    NSWindow *win = [event window];
    NSWindow *primaryWin = resolve_primary_game_window();
    if (!win || !is_sdl_game_window(win) || is_secondary_orphan_game_window(win)) {
        NSWindow *keyWin = [NSApp keyWindow];
        if (keyWin && is_sdl_game_window(keyWin) && !is_secondary_orphan_game_window(keyWin)) {
            win = keyWin;
        } else if (primaryWin && is_sdl_game_window(primaryWin)) {
            win = primaryWin;
        } else {
            return rawLoc;
        }
    }
    tInLoc = YES;
    NSPoint locInWin = raw_event_location_in_window(event, win);
    NSPoint projected = project_window_point_for_sdl(win, locInWin, NULL);
    tInLoc = NO;
    return projected;
}

static NSPoint swizzled_mouseLocationOutsideOfEventStream(id self, SEL _cmd) {
    typedef NSPoint (*Fn)(id, SEL);
    NSPoint rawLoc = gOrigMouseLocationOutsideOfEventStreamIMP
        ? ((Fn)gOrigMouseLocationOutsideOfEventStreamIMP)(self, _cmd)
        : NSZeroPoint;
    static __thread BOOL tInOutsideLoc = NO;
    if (!tProjectMouseLocationForSDL || tInOutsideLoc || !self) {
        return rawLoc;
    }
    NSWindow *win = (NSWindow *)self;
    if (!is_sdl_game_window(win) || is_secondary_orphan_game_window(win)) {
        return rawLoc;
    }
    tInOutsideLoc = YES;
    BOOL outside = NO;
    NSPoint projected = project_window_point_for_sdl(win, rawLoc, &outside);
    tInOutsideLoc = NO;
    if (outside && gWindowedModeActive) {
        /* When activating a windowed game by clicking its gray titlebar, return an out-of-bounds
           point so SDL's windowDidBecomeKey: (0x1001029b3) does not spoof a false in-canvas move. */
        return NSMakePoint(-1.0, -1.0);
    }
    return projected;
}

static void invoke_sdl_mouse_imp(IMP origIMP, id self, SEL _cmd, NSEvent *event) {
    if (!origIMP) {
        return;
    }
    typedef void (*Fn)(id, SEL, NSEvent *);
    BOOL prevProj = tProjectMouseLocationForSDL;
    tProjectMouseLocationForSDL = YES;
    ((Fn)origIMP)(self, _cmd, event);
    tProjectMouseLocationForSDL = prevProj;
}

static void invoke_sdl_mouse_imp_raw(IMP origIMP, id self, SEL _cmd, NSEvent *event) {
    if (!origIMP) {
        return;
    }
    typedef void (*Fn)(id, SEL, NSEvent *);
    BOOL prevProj = tProjectMouseLocationForSDL;
    tProjectMouseLocationForSDL = NO;
    ((Fn)origIMP)(self, _cmd, event);
    tProjectMouseLocationForSDL = prevProj;
}

static void sync_sdl_cursor_position_before_click(id self, NSEvent *event) {
    if (!gOrigMouseMovedIMP || !event) {
        return;
    }
    NSWindow *evWin = [event window] ?: [NSApp keyWindow];
    if (!evWin || !is_sdl_game_window(evWin) || is_secondary_orphan_game_window(evWin)) {
        return;
    }
    if (gWindowedModeActive && is_event_outside_content_view(evWin, event)) {
        return;
    }
    BOOL prevMotion = tInMouseMotionHandler;
    tInMouseMotionHandler = YES;
    invoke_sdl_mouse_imp(gOrigMouseMovedIMP, self, @selector(mouseMoved:), event);
    tInMouseMotionHandler = prevMotion;
}

static void diaglog_mouse_event(const char *kind, NSWindow *evWin, NSEvent *event, NSEventModifierFlags rawFlags) {
    if (!event || !evWin || (!gDebugBootEnabled && !gDiagLogEnabled && !gDiagOsLogEnabled)) {
        return;
    }
    typedef NSPoint (*LocFn)(id, SEL);
    NSPoint rawLoc = raw_event_location_in_window(event, evWin);
    NSPoint outsideLoc = gOrigMouseLocationOutsideOfEventStreamIMP
        ? ((LocFn)gOrigMouseLocationOutsideOfEventStreamIMP)(evWin, @selector(mouseLocationOutsideOfEventStream))
        : [evWin mouseLocationOutsideOfEventStream];
    BOOL outside = NO;
    NSPoint projLoc = project_window_point_for_sdl(evWin, rawLoc, &outside);
    NSRect cb = evWin.contentView ? evWin.contentView.bounds : NSZeroRect;
    NSRect cf = evWin.contentView ? evWin.contentView.frame : NSZeroRect;
    BOOL inRect = evWin.contentView ? NSMouseInRect(rawLoc, cf, NO) : NO;
    CGFloat sdlX = 0.0, sdlY = 0.0, sdlW = 0.0, sdlH = 0.0;
    query_sdl_window_rect(evWin, &sdlX, &sdlY, &sdlW, &sdlH);
    NSResponder *fr = [evWin firstResponder];
    NSResponder *cvNext = evWin.contentView ? [evWin.contentView nextResponder] : nil;
    debuglog_write("MOUSE",
                   "%s raw=(%.1f,%.1f) outside=(%.1f,%.1f) proj=(%.1f,%.1f) sdlY=%.1f "
                   "content=%.0fx%.0f sdl=%.0fx%.0f@(%.0f,%.0f) fb=%.0fx%.0f "
                   "inRect=%d out=%d key=%d evWin=%d fr=%s cvNext=%s mods=0x%lx",
                   kind ? kind : "ev",
                   rawLoc.x, rawLoc.y,
                   outsideLoc.x, outsideLoc.y,
                   projLoc.x, projLoc.y,
                   (sdlH > 0.0 ? (sdlH - projLoc.y) : -1.0),
                   cb.size.width, cb.size.height,
                   sdlW, sdlH, sdlX, sdlY,
                   gEngineFbW, gEngineFbH,
                   inRect ? 1 : 0, outside ? 1 : 0,
                   [evWin isKeyWindow] ? 1 : 0,
                   ([event window] != nil) ? 1 : 0,
                   fr ? object_getClassName(fr) : "nil",
                   cvNext ? object_getClassName(cvNext) : "nil",
                   (unsigned long)rawFlags);
}

static void handle_camera_mouse_down(id self, SEL _cmd, NSEvent *event, IMP origIMP, BOOL isRight) {
    if (!origIMP) {
        return;
    }
    /* Prevent double-swizzle re-entrancy when SDL2 rightMouseDown:/otherMouseDown: tail-calls [self mouseDown:] */
    if (tInMouseDownHandler) {
        invoke_sdl_mouse_imp_raw(origIMP, self, _cmd, event);
        return;
    }
    gWindowListener = self;
    if (gUserWindowMoveInProgress && ([NSEvent pressedMouseButtons] & 1) == 0) {
        gUserWindowMoveInProgress = NO;
    }
    if (gWindowedModeActive && event && !gSpoofMiddleButton) {
        NSWindow *evWin = [event window];
        if (evWin && is_event_outside_content_view(evWin, event)) {
            return;
        }
    }
    if (gSpoofMiddleButton) {
        tInMouseDownHandler = YES;
        invoke_sdl_mouse_imp_raw(origIMP, self, _cmd, event);
        tInMouseDownHandler = NO;
        return;
    }

    NSWindow *evWin = [event window] ?: [NSApp keyWindow];
    if (evWin && is_sdl_game_window(evWin) && !is_secondary_orphan_game_window(evWin)) {
        ensure_sdl_responder_chain(evWin, "mouseDown");
    }

    /* Sync SDL2's mouse->x/y via projected mouseMoved: BEFORE mouseDown:, then call
       Cocoa_WindowListener::mouseDown: with RAW locationInWindow so its internal
       NSMouseInRect([event locationInWindow], contentView.frame, NO) passes for 100% of contentView. */
    sync_sdl_cursor_position_before_click(self, event);
    NSEventModifierFlags rawFlags = raw_event_modifier_flags(event);
    if (evWin && is_sdl_game_window(evWin)) {
        diaglog_mouse_event(isRight ? "rightDown" : "leftDown", evWin, event, rawFlags);
    }

    BOOL ctrlHeld = (rawFlags & NSEventModifierFlagControl) != 0;
    BOOL optHeld = (rawFlags & NSEventModifierFlagOption) != 0;
    BOOL cmdHeld = (rawFlags & NSEventModifierFlagCommand) != 0;

    if (optHeld && !cmdHeld) {
        gNativeOptionCamHeld = YES;
    }

    if (gEnableOptionOrbit && !gCtrlMiddleDragActive && ctrlHeld && !cmdHeld) {
        gCtrlMiddleDragActive = YES;
        gCtrlDragWasRight = isRight;
        gLastMouseDownWindow = evWin ?: [event window];
        debuglog_write("CTRL_ORBIT", "START btn=%s win=%p windowed=%d",
                       isRight ? "right" : "left",
                       (__bridge void *)gLastMouseDownWindow,
                       gWindowedModeActive ? 1 : 0);
        gSpoofMiddleButton = YES;
        gMaskControlModifier = YES;
        tInMouseDownHandler = YES;
        invoke_sdl_mouse_imp_raw(origIMP, self, _cmd, event);
        tInMouseDownHandler = NO;
        gSpoofMiddleButton = NO;
        gMaskControlModifier = NO;
        return;
    }
    if (gCtrlMiddleDragActive) {
        return;
    }
    if (isRight && [event type] == NSEventTypeRightMouseDown) {
        debuglog_write("CAM", "NATIVE_RIGHT_CLICK_DOWN opt=%d win=%p windowed=%d",
                       optHeld ? 1 : 0, (__bridge void *)[event window],
                       gWindowedModeActive ? 1 : 0);
    } else if (!isRight && [event type] == NSEventTypeLeftMouseDown && optHeld) {
        debuglog_write("OPTION_CAM", "LEFT_CLICK_DOWN win=%p windowed=%d",
                       (__bridge void *)[event window], gWindowedModeActive ? 1 : 0);
    }
    tInMouseDownHandler = YES;
    invoke_sdl_mouse_imp_raw(origIMP, self, _cmd, event);
    tInMouseDownHandler = NO;
}

static void handle_camera_mouse_drag(id self, SEL _cmd, NSEvent *event, IMP origIMP, BOOL isRight) {
    if (!origIMP) {
        return;
    }
    if (tInMouseMotionHandler) {
        invoke_sdl_mouse_imp(origIMP, self, _cmd, event);
        return;
    }
    gWindowListener = self;
    if (gUserWindowMoveInProgress && ([NSEvent pressedMouseButtons] & 1) == 0) {
        gUserWindowMoveInProgress = NO;
    }
    if (gWindowedModeActive && gUserWindowMoveInProgress) {
        return;
    }
    NSEventModifierFlags rawFlags = raw_event_modifier_flags(event);
    if (gCtrlMiddleDragActive) {
        CGEventFlags liveCg = CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState);
        if ((rawFlags & NSEventModifierFlagControl) == 0 ||
            (liveCg & kCGEventFlagMaskControl) == 0 ||
            ([NSEvent pressedMouseButtons] & 0x7) == 0) {
            release_ctrl_middle_drag(self);
            return;
        }
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if ((now - gLastCamDragDiagLogTime) >= 0.35) {
            gLastCamDragDiagLogTime = now;
            NSWindow *evWin = [event window] ?: resolve_primary_game_window();
            NSPoint rawPt = raw_event_location_in_window(event, evWin);
            debuglog_write("CTRL_ORBIT", "DRAG btn=%s wasRight=%d raw=(%.1f,%.1f) delta=(%.1f,%.1f) windowed=%d",
                           isRight ? "right" : "left",
                           gCtrlDragWasRight ? 1 : 0,
                           rawPt.x, rawPt.y,
                           [event deltaX], [event deltaY],
                           gWindowedModeActive ? 1 : 0);
        }
        /* Forward drags regardless of left/right polarity (macOS Control+click can switch mouseDragged/rightMouseDragged)
           and clamp projected drag coordinates smoothly to contentView edges in windowed mode. */
        gSpoofMiddleButton = YES;
        gMaskControlModifier = YES;
        BOOL prevClamp = tClampDragProjectionForSDL;
        tClampDragProjectionForSDL = YES;
        tInMouseMotionHandler = YES;
        invoke_sdl_mouse_imp(origIMP, self, _cmd, event);
        tInMouseMotionHandler = NO;
        tClampDragProjectionForSDL = prevClamp;
        gSpoofMiddleButton = NO;
        gMaskControlModifier = NO;
        return;
    }
    BOOL optHeld = (rawFlags & NSEventModifierFlagOption) != 0;
    if (optHeld) {
        gNativeOptionCamHeld = YES;
    }
    if (isRight || optHeld) {
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if ((now - gLastCamDragDiagLogTime) >= 0.35) {
            gLastCamDragDiagLogTime = now;
            NSWindow *evWin = [event window] ?: resolve_primary_game_window();
            NSPoint rawPt = raw_event_location_in_window(event, evWin);
            debuglog_write(optHeld ? "OPTION_CAM" : "CAM",
                           "DRAG btn=%s opt=%d raw=(%.1f,%.1f) delta=(%.1f,%.1f) windowed=%d",
                           isRight ? "right" : "left",
                           optHeld ? 1 : 0,
                           rawPt.x, rawPt.y,
                           [event deltaX], [event deltaY],
                           gWindowedModeActive ? 1 : 0);
        }
    }
    BOOL prevClamp = tClampDragProjectionForSDL;
    tClampDragProjectionForSDL = YES;
    tInMouseMotionHandler = YES;
    invoke_sdl_mouse_imp(origIMP, self, _cmd, event);
    tInMouseMotionHandler = NO;
    tClampDragProjectionForSDL = prevClamp;
}

static void handle_camera_mouse_up(id self, SEL _cmd, NSEvent *event, IMP origIMP, BOOL isRight) {
    if (!origIMP) {
        return;
    }
    if (tInMouseUpHandler) {
        invoke_sdl_mouse_imp_raw(origIMP, self, _cmd, event);
        return;
    }
    gWindowListener = self;
    gUserWindowMoveInProgress = NO;
    if (gSpoofMiddleButton) {
        tInMouseUpHandler = YES;
        invoke_sdl_mouse_imp_raw(origIMP, self, _cmd, event);
        tInMouseUpHandler = NO;
        return;
    }
    if (gCtrlMiddleDragActive) {
        /* Release cleanly on matching button OR when no mouse button remains pressed
           (guards against AppKit Control+left-click down/up polarity mismatch leaving ↻ stuck). */
        if (isRight == gCtrlDragWasRight || ([NSEvent pressedMouseButtons] & 0x3) == 0) {
            debuglog_write("CTRL_ORBIT", "END btn=%s wasRight=%d windowed=%d",
                           isRight ? "right" : "left",
                           gCtrlDragWasRight ? 1 : 0,
                           gWindowedModeActive ? 1 : 0);
            gCtrlMiddleDragActive = NO;
            gCtrlDragWasRight = NO;
            gLastMouseDownWindow = nil;
            gSpoofMiddleButton = YES;
            gMaskControlModifier = YES;
            tInMouseUpHandler = YES;
            invoke_sdl_mouse_imp_raw(origIMP, self, _cmd, event);
            tInMouseUpHandler = NO;
            gSpoofMiddleButton = NO;
            gMaskControlModifier = NO;
        }
        return;
    }
    if (isRight && [event type] == NSEventTypeRightMouseUp) {
        debuglog_write("CAM", "NATIVE_RIGHT_CLICK_UP win=%p", (__bridge void *)[event window]);
    }
    tInMouseUpHandler = YES;
    invoke_sdl_mouse_imp_raw(origIMP, self, _cmd, event);
    tInMouseUpHandler = NO;
}

static void swizzled_mouseDown(id self, SEL _cmd, NSEvent *event) {
    handle_camera_mouse_down(self, _cmd, event, gOrigMouseDownIMP, NO);
}

static void swizzled_mouseUp(id self, SEL _cmd, NSEvent *event) {
    handle_camera_mouse_up(self, _cmd, event, gOrigMouseUpIMP, NO);
}

static void swizzled_mouseDragged(id self, SEL _cmd, NSEvent *event) {
    handle_camera_mouse_drag(self, _cmd, event, gOrigMouseDraggedIMP, NO);
}

static void swizzled_rightMouseDown(id self, SEL _cmd, NSEvent *event) {
    handle_camera_mouse_down(self, _cmd, event, gOrigRightMouseDownIMP, YES);
}

static void swizzled_rightMouseUp(id self, SEL _cmd, NSEvent *event) {
    handle_camera_mouse_up(self, _cmd, event, gOrigRightMouseUpIMP, YES);
}

static void swizzled_rightMouseDragged(id self, SEL _cmd, NSEvent *event) {
    handle_camera_mouse_drag(self, _cmd, event, gOrigRightMouseDraggedIMP, YES);
}

static void swizzled_otherMouseDown(id self, SEL _cmd, NSEvent *event) {
    if (!gOrigOtherMouseDownIMP) {
        return;
    }
    if (tInMouseDownHandler) {
        invoke_sdl_mouse_imp_raw(gOrigOtherMouseDownIMP, self, _cmd, event);
        return;
    }
    gWindowListener = self;
    if (gWindowedModeActive && event) {
        NSWindow *evWin = [event window];
        if (evWin && is_event_outside_content_view(evWin, event)) {
            return;
        }
    }
    NSWindow *evWin = [event window] ?: [NSApp keyWindow];
    if (evWin && is_sdl_game_window(evWin)) {
        diaglog_mouse_event("otherDown", evWin, event, raw_event_modifier_flags(event));
    }
    sync_sdl_cursor_position_before_click(self, event);
    tInMouseDownHandler = YES;
    invoke_sdl_mouse_imp_raw(gOrigOtherMouseDownIMP, self, _cmd, event);
    tInMouseDownHandler = NO;
}

static void swizzled_otherMouseUp(id self, SEL _cmd, NSEvent *event) {
    if (!gOrigOtherMouseUpIMP) {
        return;
    }
    if (tInMouseUpHandler) {
        invoke_sdl_mouse_imp_raw(gOrigOtherMouseUpIMP, self, _cmd, event);
        return;
    }
    gWindowListener = self;
    gUserWindowMoveInProgress = NO;
    if (gCtrlMiddleDragActive) {
        release_ctrl_middle_drag(self);
    }
    tInMouseUpHandler = YES;
    invoke_sdl_mouse_imp_raw(gOrigOtherMouseUpIMP, self, _cmd, event);
    tInMouseUpHandler = NO;
}

static void swizzled_otherMouseDragged(id self, SEL _cmd, NSEvent *event) {
    if (!gOrigOtherMouseDraggedIMP) {
        return;
    }
    if (tInMouseMotionHandler) {
        invoke_sdl_mouse_imp(gOrigOtherMouseDraggedIMP, self, _cmd, event);
        return;
    }
    gWindowListener = self;
    if (gUserWindowMoveInProgress && ([NSEvent pressedMouseButtons] & 1) == 0) {
        gUserWindowMoveInProgress = NO;
    }
    if (gWindowedModeActive && gUserWindowMoveInProgress) {
        return;
    }
    BOOL prevClamp = tClampDragProjectionForSDL;
    tClampDragProjectionForSDL = YES;
    tInMouseMotionHandler = YES;
    invoke_sdl_mouse_imp(gOrigOtherMouseDraggedIMP, self, _cmd, event);
    tInMouseMotionHandler = NO;
    tClampDragProjectionForSDL = prevClamp;
}

/*
 * Prevent SDL2 Cocoa_WindowListener::mouseMoved: from calling CGDisplayMoveCursorToPoint
 * when the game window is inactive or not key (Space transitions / Cmd+Tab / Dock clicks),
 * or while hovering the gray macOS titlebar in Windowed mode.
 */
static void swizzled_mouseMoved(id self, SEL _cmd, NSEvent *event) {
    if (tInMouseMotionHandler) {
        invoke_sdl_mouse_imp(gOrigMouseMovedIMP, self, _cmd, event);
        return;
    }
    gWindowListener = self;
    if (gUserWindowMoveInProgress && ([NSEvent pressedMouseButtons] & 1) == 0) {
        gUserWindowMoveInProgress = NO;
    }
    if (gCtrlMiddleDragActive && ([NSEvent pressedMouseButtons] & 0x7) == 0) {
        release_ctrl_middle_drag(self);
    }
    NSWindow *win = [event window] ?: [NSApp keyWindow];
    if (!gAppIsActive || ![NSApp isActive] || !win || ![win isKeyWindow]) {
        return;
    }
    if (gWindowedModeActive && event && (gUserWindowMoveInProgress || is_event_outside_content_view(win, event))) {
        return;
    }
    NSEventModifierFlags rawFlags = raw_event_modifier_flags(event);
    BOOL optHeld = (rawFlags & NSEventModifierFlagOption) != 0;
    if (optHeld) {
        gNativeOptionCamHeld = YES;
    } else if (gNativeOptionCamHeld) {
        CGEventFlags liveCg = CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState);
        if ((liveCg & kCGEventFlagMaskAlternate) == 0) {
            gNativeOptionCamHeld = NO;
            debuglog_write("OPTION_CAM", "RELEASE_ON_MOVE windowed=%d", gWindowedModeActive ? 1 : 0);
            flush_stuck_modifier_state_to_sdl(win, "option-cam-move-release");
        }
    }
    if ((gDebugBootEnabled || gDiagLogEnabled || gDiagOsLogEnabled) && event && [event type] == NSEventTypeMouseMoved) {
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (optHeld && (now - gLastOptionHoverLogTime) >= 0.35) {
            gLastOptionHoverLogTime = now;
            NSPoint rawPt = raw_event_location_in_window(event, win);
            NSPoint projPt = project_window_point_for_sdl(win, rawPt, NULL);
            debuglog_write("OPTION_CAM", "HOVER_MOVE raw=(%.1f,%.1f) proj=(%.1f,%.1f) delta=(%.1f,%.1f) windowed=%d",
                           rawPt.x, rawPt.y, projPt.x, projPt.y,
                           [event deltaX], [event deltaY],
                           gWindowedModeActive ? 1 : 0);
        } else if ((now - gLastMouseMoveDiagLogTime) >= 1.0 && is_sdl_game_window(win)) {
            gLastMouseMoveDiagLogTime = now;
            diaglog_mouse_event("move", win, event, rawFlags);
        }
    }
    tInMouseMotionHandler = YES;
    invoke_sdl_mouse_imp(gOrigMouseMovedIMP, self, _cmd, event);
    tInMouseMotionHandler = NO;
}

static void reset_gesture_and_key_state(id listener) {
    release_ctrl_middle_drag(listener);
    if (gNativeOptionCamHeld) {
        gNativeOptionCamHeld = NO;
        debuglog_write("OPTION_CAM", "RELEASE_ON_RESET windowed=%d", gWindowedModeActive ? 1 : 0);
        flush_stuck_modifier_state_to_sdl(resolve_primary_game_window(), "option-cam-reset");
    }
    release_active_rotate_keys();
    gScrollAxis = Sims2ScrollAxisNone;
    gIsTwisting = NO;
    gScrollAccumX = 0.0;
    gTwistAccum = 0.0;
    gPinchAccum = 0.0;
    gSuppressedScrollEvent = nil;
    gForcedNonInvertedEvent = nil;
    gForceScrollNonInverted = NO;
}

static BOOL should_suppress_focus_steal_or_fullscreen_exit(void) {
    if (!gAppHasActivatedOnce) {
        return NO;
    }
    if (!gAppIsActive) {
        return YES;
    }
    if (NSApp && ![NSApp isActive]) {
        return YES;
    }
    if (gLastResignTimestamp > 0.0 && (CFAbsoluteTimeGetCurrent() - gLastResignTimestamp) < 2.0) {
        return YES;
    }
    return NO;
}

static BOOL is_sdl_game_window(id winObj) {
    if (!winObj || ![winObj isKindOfClass:[NSWindow class]]) {
        return NO;
    }
    if (gSDLWindowClass && [winObj isKindOfClass:gSDLWindowClass]) {
        return YES;
    }
    NSWindow *win = (NSWindow *)winObj;
    id delegate = [win delegate];
    Class listenerCls = objc_getClass("Cocoa_WindowListener");
    if (delegate && listenerCls && [delegate isKindOfClass:listenerCls]) {
        return YES;
    }
    return NO;
}

static BOOL swizzled_sdlValidateMenuItem(id self, SEL _cmd, NSMenuItem *menuItem) {
    if (menuItem && [menuItem action] == @selector(toggleFullScreen:) &&
        !is_secondary_orphan_game_window(self)) {
        return YES;
    }
    if (gOrigSDLValidateMenuItemIMP) {
        typedef BOOL (*Fn)(id, SEL, NSMenuItem *);
        return ((Fn)gOrigSDLValidateMenuItemIMP)(self, _cmd, menuItem);
    }
    return YES;
}

static BOOL swizzled_sdlViewMouseDownCanMoveWindow(id self, SEL _cmd) {
    (void)self;
    (void)_cmd;
    /* Prevent AppKit from interpreting clicks inside SDLView content canvas as window drags */
    return NO;
}

static NSWindowStyleMask sanitize_sdl_style_mask(NSWindowStyleMask mask) {
    if (gWindowedModeActive) {
        /* Resizable + FullScreenPrimary enables macOS green fullscreen traffic-light button */
        return (NSWindowStyleMaskTitled |
                NSWindowStyleMaskClosable |
                NSWindowStyleMaskMiniaturizable |
                NSWindowStyleMaskResizable);
    }
    if ((mask & NSWindowStyleMaskFullScreen) != 0 || gAllowResizableForSpaceToggle || gInFullscreenTransition) {
        /* Preserve native macOS Fullscreen Space styleMask (0x400f) so menu bar & Space transitions stay clean */
        NSWindowStyleMask spaceMask = (mask & (NSWindowStyleMaskTitled |
                                               NSWindowStyleMaskClosable |
                                               NSWindowStyleMaskMiniaturizable |
                                               NSWindowStyleMaskResizable |
                                               NSWindowStyleMaskFullScreen));
        return spaceMask ? spaceMask : (NSWindowStyleMaskTitled |
                                        NSWindowStyleMaskClosable |
                                        NSWindowStyleMaskMiniaturizable |
                                        NSWindowStyleMaskResizable |
                                        (mask & NSWindowStyleMaskFullScreen));
    }
    return NSWindowStyleMaskBorderless;
}

static void apply_borderless_presentation_options(BOOL wantHiddenDesktopUI) {
    if (!NSApp) {
        return;
    }
    @try {
        NSApplicationPresentationOptions hiddenOpts = (NSApplicationPresentationHideDock |
                                                       NSApplicationPresentationHideMenuBar);
        NSApplicationPresentationOptions curOpts = [NSApp presentationOptions];
        if (wantHiddenDesktopUI) {
            if (!gHasAppliedPresentationOpts || (curOpts & hiddenOpts) != hiddenOpts) {
                [NSApp setPresentationOptions:hiddenOpts];
                gHasAppliedPresentationOpts = YES;
            }
        } else if (gHasAppliedPresentationOpts ||
                   (curOpts != NSApplicationPresentationDefault &&
                    (curOpts & NSApplicationPresentationFullScreen) == 0)) {
            /* Never clobber AppKit's own NSApplicationPresentationFullScreen (0x400) while inside a native Space. */
            [NSApp setPresentationOptions:NSApplicationPresentationDefault];
            gHasAppliedPresentationOpts = NO;
        }
    } @catch (NSException *ex) {
        debuglog_write("WIN", "presentationOptions exception: %s",
                       ex.reason ? [ex.reason UTF8String] : "unknown");
        gHasAppliedPresentationOpts = NO;
    }
}

static NSScreen *resolve_screen_for_rect(NSRect rect, NSScreen *fallbackScreen) {
    if ([NSThread isMainThread] && NSApp != nil) {
        NSArray<NSScreen *> *screens = [NSScreen screens];
        if (screens && [screens count] > 0) {
            if (rect.size.width >= 1.0 && rect.size.height >= 1.0) {
                NSPoint center = NSMakePoint(NSMidX(rect), NSMidY(rect));
                for (NSScreen *s in screens) {
                    if (NSPointInRect(center, s.frame)) {
                        return s;
                    }
                }
                NSScreen *bestScreen = nil;
                CGFloat bestArea = 0.0;
                for (NSScreen *s in screens) {
                    NSRect inter = NSIntersectionRect(rect, s.frame);
                    CGFloat area = inter.size.width * inter.size.height;
                    if (area > bestArea) {
                        bestArea = area;
                        bestScreen = s;
                    }
                }
                if (bestScreen) {
                    return bestScreen;
                }
            }
        }
    }
    if (fallbackScreen) {
        return fallbackScreen;
    }
    return ([NSThread isMainThread] && NSApp != nil) ? [NSScreen mainScreen] : nil;
}

static NSRect compute_aspect_fitted_fullscreen_rect(NSRect screenUsableRect, double fbW, double fbH) {
    if (screenUsableRect.size.width < 1.0 || screenUsableRect.size.height < 1.0 ||
        fbW < 1.0 || fbH < 1.0) {
        return screenUsableRect;
    }
    double screenAspect = (double)screenUsableRect.size.width / (double)screenUsableRect.size.height;
    double fbAspect = fbW / fbH;
    double relDiff = fabs(screenAspect - fbAspect) / fbAspect;
    if (relDiff <= 0.02) {
        /* Same aspect ratio within 2% (e.g. notched MacBook usable frame vs FB,
           or native 1920x1080 on 16:9 external primary display): fill 100% edge-to-edge. */
        return screenUsableRect;
    }
    if (screenAspect > fbAspect) {
        /* Wider display (e.g. 16:9 TV showing 16:10 MacBook FB): centered pillarbox, zero stretch. */
        CGFloat fitH = screenUsableRect.size.height;
        CGFloat fitW = (CGFloat)llround((double)fitH * fbAspect);
        if (fitW > screenUsableRect.size.width) {
            fitW = screenUsableRect.size.width;
        }
        CGFloat fitX = screenUsableRect.origin.x + floor((screenUsableRect.size.width - fitW) * 0.5);
        return NSMakeRect(fitX, screenUsableRect.origin.y, fitW, fitH);
    }
    /* Taller display (e.g. 16:10 MacBook showing 16:9 TV FB): centered letterbox, zero stretch. */
    CGFloat fitW = screenUsableRect.size.width;
    CGFloat fitH = (CGFloat)llround((double)fitW / fbAspect);
    if (fitH > screenUsableRect.size.height) {
        fitH = screenUsableRect.size.height;
    }
    CGFloat fitY = screenUsableRect.origin.y + floor((screenUsableRect.size.height - fitH) * 0.5);
    return NSMakeRect(screenUsableRect.origin.x, fitY, fitW, fitH);
}

static void detect_native_screen_resolution(NSWindow *win) {
    NSScreen *scr = nil;
    if ([NSThread isMainThread] && NSApp != nil) {
        NSArray<NSScreen *> *screens = [NSScreen screens];
        if (screens && [screens count] > 0) {
            NSScreen *primary = [screens objectAtIndex:0];
            if (primary && primary.frame.size.width >= 640.0 && primary.frame.size.height >= 480.0) {
                NSInteger pRawW = (NSInteger)llround(primary.frame.size.width);
                NSInteger pRawH = (NSInteger)llround(primary.frame.size.height);
                CGFloat pSafeTop = 0.0;
                if (@available(macOS 12.0, *)) {
                    pSafeTop = primary.safeAreaInsets.top;
                }
                NSInteger pInset = (pSafeTop > 0.5 && pSafeTop < 120.0) ? (NSInteger)llround(pSafeTop) : 0;
                gPrimaryRawScreenWidth = pRawW;
                gPrimaryRawScreenHeight = pRawH;
                gPrimaryNotchTopInset = pInset;
                gPrimaryNativeScreenHeight = ((pRawH - pInset) >= 480) ? (pRawH - pInset) : pRawH;
            }
        }
        scr = (win && win.screen) ? win.screen : [NSScreen mainScreen];
    }
    if (scr && scr.frame.size.width >= 640.0 && scr.frame.size.height >= 480.0) {
        NSInteger rawW = (NSInteger)llround(scr.frame.size.width);
        NSInteger rawH = (NSInteger)llround(scr.frame.size.height);
        CGFloat safeTop = 0.0;
        if (@available(macOS 12.0, *)) {
            safeTop = scr.safeAreaInsets.top;
        }
        NSInteger inset = (safeTop > 0.5 && safeTop < 120.0) ? (NSInteger)llround(safeTop) : 0;
        gRawHardwareScreenWidth = rawW;
        gRawHardwareScreenHeight = rawH;
        gNotchTopInset = inset;
        gNativeScreenWidth = rawW;
        gNativeScreenHeight = ((rawH - inset) >= 480) ? (rawH - inset) : rawH;
        return;
    }
    CGRect bounds = CGDisplayBounds(CGMainDisplayID());
    if (bounds.size.width >= 640.0 && bounds.size.height >= 480.0) {
        gRawHardwareScreenWidth = (NSInteger)llround(bounds.size.width);
        gRawHardwareScreenHeight = (NSInteger)llround(bounds.size.height);
        gPrimaryRawScreenWidth = gRawHardwareScreenWidth;
        gPrimaryRawScreenHeight = gRawHardwareScreenHeight;
        gNativeScreenWidth = gRawHardwareScreenWidth;
        NSInteger usableH = gRawHardwareScreenHeight - gNotchTopInset;
        gNativeScreenHeight = (usableH >= 480) ? usableH : gRawHardwareScreenHeight;
        NSInteger pUsableH = gPrimaryRawScreenHeight - gPrimaryNotchTopInset;
        gPrimaryNativeScreenHeight = (pUsableH >= 480) ? pUsableH : gPrimaryRawScreenHeight;
    }
}

static NSRect compute_expected_fullscreen_space_frame(NSWindow *win) {
    detect_native_screen_resolution(win);
    NSScreen *scr = (win && win.screen) ? win.screen : [NSScreen mainScreen];
    if (!scr) {
        return NSMakeRect(0.0, 0.0, (CGFloat)gNativeScreenWidth, (CGFloat)gNativeScreenHeight);
    }
    update_cached_screen_geometry(scr);
    NSRect sf = scr.frame;
    NSRect vf = scr.visibleFrame;
    if (sf.size.width < 640.0 || sf.size.height < 480.0) {
        return (vf.size.width >= 640.0 && vf.size.height >= 480.0) ? vf : sf;
    }
    CGFloat safeTopInset = 0.0;
    if (@available(macOS 12.0, *)) {
        safeTopInset = scr.safeAreaInsets.top;
    }
    if (safeTopInset > 0.5 && safeTopInset < 120.0) {
        /* Mac with physical notch: Space fills width x height below notch, matching macOS Space height
           when visibleFrame reflects NSMenuBarReplicantWindow (e.g. <= 2.5 pt rounding). */
        CGFloat usableH = sf.size.height - safeTopInset;
        if (vf.size.height >= 480.0 && fabs(vf.size.height - usableH) <= 2.5) {
            usableH = vf.size.height;
        }
        NSRect notchUsable = NSMakeRect(sf.origin.x, sf.origin.y, sf.size.width, usableH);
        if (gHasCapturedInitialEngineFb && gEngineFbW >= 640.0 && gEngineFbH >= 480.0) {
            return compute_aspect_fitted_fullscreen_rect(notchUsable, (double)gEngineFbW, (double)gEngineFbH);
        }
        return notchUsable;
    }
    /* Mac without notch or external monitor: aspect-fit engine FB inside full screen frame (zero stretch). */
    if (gHasCapturedInitialEngineFb && gEngineFbW >= 640.0 && gEngineFbH >= 480.0) {
        return compute_aspect_fitted_fullscreen_rect(sf, (double)gEngineFbW, (double)gEngineFbH);
    }
    return sf;
}

static void ensure_fullscreen_space_geometry(NSWindow *win, const char *reason) {
    if (!win || gWindowedModeActive || !is_sdl_game_window(win) || is_secondary_orphan_game_window(win)) {
        return;
    }
    BOOL inSpace = ((win.styleMask & NSWindowStyleMaskFullScreen) != 0);
    if (!inSpace) {
        return;
    }
    NSRect expectedSpace = compute_expected_fullscreen_space_frame(win);
    if (expectedSpace.size.width < 640.0 || expectedSpace.size.height < 480.0) {
        return;
    }
    NSRect curFrame = win.frame;
    NSRect curContent = win.contentView ? win.contentView.bounds : curFrame;
    BOOL frameMismatch = (fabs(curFrame.size.width - expectedSpace.size.width) > 4.0 ||
                          fabs(curFrame.size.height - expectedSpace.size.height) > 4.0 ||
                          fabs(curFrame.origin.x - expectedSpace.origin.x) > 4.0 ||
                          fabs(curFrame.origin.y - expectedSpace.origin.y) > 4.0);
    BOOL contentMismatch = (fabs(curContent.size.width - expectedSpace.size.width) > 4.0 ||
                            fabs(curContent.size.height - expectedSpace.size.height) > 4.0);
    if (!frameMismatch && !contentMismatch) {
        return;
    }
    debuglog_write("WIN", "Fullscreen Space geometry mismatch (%s): frame=%.0fx%.0f@(%.0f,%.0f) content=%.0fx%.0f -> fitting %.0fx%.0f@(%.0f,%.0f)",
                   reason ? reason : "spaceCheck",
                   curFrame.size.width, curFrame.size.height, curFrame.origin.x, curFrame.origin.y,
                   curContent.size.width, curContent.size.height,
                   expectedSpace.size.width, expectedSpace.size.height,
                   expectedSpace.origin.x, expectedSpace.origin.y);
    BOOL prevNotch = gNotchFitInProgress;
    BOOL prevSuppress = gSuppressSDLResizeNotification;
    gNotchFitInProgress = YES;
    gSuppressSDLResizeNotification = YES;
    if (![win.backgroundColor isEqual:[NSColor blackColor]]) {
        [win setBackgroundColor:[NSColor blackColor]];
    }
    if (gOrigSDLSetFrameDisplayIMP && gSDLWindowClass && [win isKindOfClass:gSDLWindowClass]) {
        typedef void (*FrameFn)(id, SEL, NSRect, BOOL);
        ((FrameFn)gOrigSDLSetFrameDisplayIMP)(win, @selector(setFrame:display:), expectedSpace, YES);
    } else {
        [win setFrame:expectedSpace display:YES];
    }
    if (win.contentView) {
        NSRect exactBounds = NSMakeRect(0.0, 0.0, expectedSpace.size.width, expectedSpace.size.height);
        if (!NSEqualRects(win.contentView.frame, exactBounds)) {
            [win.contentView setFrame:exactBounds];
        }
    }
    gSuppressSDLResizeNotification = prevSuppress;
    gNotchFitInProgress = prevNotch;
    sync_sdl_window_logical_size_to_engine_fb(win, "ensureSpaceGeometry");
    ensure_sdl_responder_chain(win, "ensureSpaceGeometry");
    apply_opengl_surface_backing_size_ex(win, YES);
}

static NSRect compute_primary_game_frame(NSWindow *win) {
    detect_native_screen_resolution(win);
    NSScreen *scr = (win && win.screen) ? win.screen : [NSScreen mainScreen];
    if (!scr) {
        return win ? win.frame : NSMakeRect(0.0, 0.0, (CGFloat)gNativeScreenWidth, (CGFloat)gNativeScreenHeight);
    }
    update_cached_screen_geometry(scr);
    NSRect sf = scr.frame;
    NSRect vf = scr.visibleFrame;
    if (sf.size.width < 640.0 || sf.size.height < 480.0) {
        return vf.size.width >= 640.0 ? vf : sf;
    }
    BOOL inSpace = win ? ((win.styleMask & NSWindowStyleMaskFullScreen) != 0) : NO;
    if (inSpace) {
        return compute_expected_fullscreen_space_frame(win);
    }
    CGFloat safeTopInset = 0.0;
    if (@available(macOS 12.0, *)) {
        safeTopInset = scr.safeAreaInsets.top;
    }
    CGFloat targetH = sf.size.height;
    if (safeTopInset > 0.5 && safeTopInset < 120.0) {
        /* Option A: exact usable height directly below the physical notch (e.g. 1800x1131) */
        targetH = sf.size.height - safeTopInset;
    }
    if (targetH < 480.0) {
        return (vf.size.width >= 640.0 && vf.size.height >= 480.0) ? vf : sf;
    }
    return NSMakeRect(sf.origin.x, sf.origin.y, sf.size.width, targetH);
}

static BOOL is_reduced_target_resolution(void) {
    return (gTargetWindowWidth >= 640 && gTargetWindowHeight >= 480 &&
            (gTargetWindowWidth < gNativeScreenWidth || gTargetWindowHeight < gNativeScreenHeight));
}

static NSUserDefaults *sims2_user_defaults(void) {
    /* Exclusively use [NSUserDefaults standardUserDefaults] to avoid any cross-container TCC prompt. */
    return [NSUserDefaults standardUserDefaults];
}

static void save_windowed_size_preference(void) {
    if (!is_reduced_target_resolution()) {
        return;
    }
    NSUserDefaults *defaults = sims2_user_defaults();
    [defaults setInteger:gTargetWindowWidth forKey:kSims2PrefWindowedWidthKey];
    [defaults setInteger:gTargetWindowHeight forKey:kSims2PrefWindowedHeightKey];
    if (gDiagLogPrefEnabled) {
        [defaults setBool:YES forKey:kSims2PrefDiagLogKey];
    }
    [defaults synchronize];
    CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
    debuglog_write("PREF", "Saved preferred windowed size: %ldx%ld",
                   (long)gTargetWindowWidth, (long)gTargetWindowHeight);
}

static void load_display_preferences_from_defaults(void) {
    detect_native_screen_resolution(nil);
    /* Always boot in native macOS Fullscreen Space (never auto-launch windowed). */
    gWindowedModeActive = NO;

    NSUserDefaults *defaults = sims2_user_defaults();
    NSInteger savedW = [defaults integerForKey:kSims2PrefWindowedWidthKey];
    NSInteger savedH = [defaults integerForKey:kSims2PrefWindowedHeightKey];
    if (savedW >= 640 && savedH >= 480 &&
        savedW <= gNativeScreenWidth && savedH <= gNativeScreenHeight &&
        (savedW < gNativeScreenWidth || savedH < gNativeScreenHeight)) {
        gTargetWindowWidth = savedW;
        gTargetWindowHeight = savedH;
    } else if (!is_reduced_target_resolution()) {
        gTargetWindowWidth = 0;
        gTargetWindowHeight = 0;
    }
    debuglog_write("PREF", "Startup mode: native macOS Fullscreen (windowed=0, native=%ldx%ld, notch=%ld, savedWindowed=%ldx%ld)",
                   (long)gNativeScreenWidth, (long)gNativeScreenHeight,
                   (long)gNotchTopInset,
                   (long)gTargetWindowWidth, (long)gTargetWindowHeight);
}

static BOOL engine_fb_is_widescreen_16_9(void) {
    if (gHasCapturedInitialEngineFb && gEngineFbW >= 640.0 && gEngineFbH >= 480.0) {
        return ((double)gEngineFbW / (double)gEngineFbH) >= 1.70;
    }
    if (gNativeScreenWidth >= 640 && gNativeScreenHeight >= 480) {
        return ((double)gNativeScreenWidth / (double)gNativeScreenHeight) >= 1.70;
    }
    return NO;
}

static size_t build_windowed_resolution_list(NSWindow *win, NSInteger outW[4], NSInteger outH[4]) {
    detect_native_screen_resolution(win);
    NSScreen *scr = (win && win.screen) ? win.screen : [NSScreen mainScreen];
    NSRect vf = scr ? scr.visibleFrame : NSMakeRect(0.0, 0.0, (CGFloat)gNativeScreenWidth, (CGFloat)gNativeScreenHeight);
    NSWindowStyleMask titledMask = (NSWindowStyleMaskTitled |
                                    NSWindowStyleMaskClosable |
                                    NSWindowStyleMaskMiniaturizable |
                                    NSWindowStyleMaskResizable);
    BOOL is16by9Fb = engine_fb_is_widescreen_16_9();

    static const NSInteger kWindowedPresets16x10[][2] = {
        { 1512, 982 },
        { 1440, 900 },
        { 1280, 800 },
    };
    static const NSInteger kSmallScreenPresets16x10[][2] = {
        { 1152, 720 },
        { 1024, 640 },
        { 960,  600 },
    };
    static const NSInteger kWindowedPresets16x9[][2] = {
        { 1600, 900 },
        { 1366, 768 },
        { 1280, 720 },
    };
    static const NSInteger kSmallScreenPresets16x9[][2] = {
        { 1152, 648 },
        { 1024, 576 },
        { 960,  540 },
    };

    const NSInteger (*mainPresets)[2] = is16by9Fb ? kWindowedPresets16x9 : kWindowedPresets16x10;
    const NSInteger (*smallPresets)[2] = is16by9Fb ? kSmallScreenPresets16x9 : kSmallScreenPresets16x10;
    size_t count = 0;
    for (size_t i = 0; i < 3 && count < 4; i++) {
        NSInteger pw = mainPresets[i][0];
        NSInteger ph = mainPresets[i][1];
        if (pw > gNativeScreenWidth || ph > gNativeScreenHeight ||
            (pw == gNativeScreenWidth && ph == gNativeScreenHeight)) {
            continue;
        }
        NSRect outer = [NSWindow frameRectForContentRect:NSMakeRect(0.0, 0.0, (CGFloat)pw, (CGFloat)ph)
                                               styleMask:titledMask];
        if (outer.size.width <= vf.size.width && outer.size.height <= vf.size.height) {
            outW[count] = pw;
            outH[count] = ph;
            count++;
        }
    }
    for (size_t i = 0; i < 3 && count < 2; i++) {
        NSInteger pw = smallPresets[i][0];
        NSInteger ph = smallPresets[i][1];
        if (pw > gNativeScreenWidth || ph > gNativeScreenHeight ||
            (pw == gNativeScreenWidth && ph == gNativeScreenHeight)) {
            continue;
        }
        NSRect outer = [NSWindow frameRectForContentRect:NSMakeRect(0.0, 0.0, (CGFloat)pw, (CGFloat)ph)
                                               styleMask:titledMask];
        if (outer.size.width <= vf.size.width && outer.size.height <= vf.size.height) {
            outW[count] = pw;
            outH[count] = ph;
            count++;
        }
    }
    if (count == 0) {
        outW[0] = is16by9Fb ? 1024 : 1024;
        outH[0] = is16by9Fb ? 576  : 640;
        count = 1;
    }
    return count;
}

static void resolve_compatible_windowed_size_on_screen(NSScreen *scr, NSInteger *ioW, NSInteger *ioH) {
    if (!ioW || !ioH) {
        return;
    }
    NSRect vf = scr ? scr.visibleFrame : NSMakeRect(0.0, 0.0, (CGFloat)gNativeScreenWidth, (CGFloat)gNativeScreenHeight);
    NSWindowStyleMask titledMask = (NSWindowStyleMaskTitled |
                                    NSWindowStyleMaskClosable |
                                    NSWindowStyleMaskMiniaturizable |
                                    NSWindowStyleMaskResizable);
    NSRect outer = [NSWindow frameRectForContentRect:NSMakeRect(0.0, 0.0, (CGFloat)(*ioW), (CGFloat)(*ioH))
                                           styleMask:titledMask];
    if (outer.size.width <= vf.size.width && outer.size.height <= vf.size.height) {
        return;
    }
    BOOL is16by9Fb = engine_fb_is_widescreen_16_9();
    static const NSInteger kCompatPresets16x10[][2] = {
        { 1512, 982 },
        { 1440, 900 },
        { 1280, 800 },
        { 1152, 720 },
        { 1024, 640 },
        { 960,  600 },
    };
    static const NSInteger kCompatPresets16x9[][2] = {
        { 1600, 900 },
        { 1366, 768 },
        { 1280, 720 },
        { 1152, 648 },
        { 1024, 576 },
        { 960,  540 },
    };
    const NSInteger (*presets)[2] = is16by9Fb ? kCompatPresets16x9 : kCompatPresets16x10;
    for (size_t i = 0; i < 6; i++) {
        NSRect testOuter = [NSWindow frameRectForContentRect:NSMakeRect(0.0, 0.0, (CGFloat)presets[i][0], (CGFloat)presets[i][1])
                                                   styleMask:titledMask];
        if (testOuter.size.width <= vf.size.width && testOuter.size.height <= vf.size.height) {
            *ioW = presets[i][0];
            *ioH = presets[i][1];
            return;
        }
    }
    *ioW = 1024;
    *ioH = is16by9Fb ? 576 : 640;
}

static void resolve_compatible_windowed_size(NSWindow *win, NSInteger *ioW, NSInteger *ioH) {
    NSScreen *scr = win ? resolve_screen_for_rect(win.frame, win.screen) : [NSScreen mainScreen];
    resolve_compatible_windowed_size_on_screen(scr, ioW, ioH);
}

static NSRect compute_windowed_game_frame_on_screen(NSWindow *win,
                                                    NSScreen *targetScreen,
                                                    NSInteger targetW,
                                                    NSInteger targetH,
                                                    BOOL centerInVisible) {
    NSScreen *scr = targetScreen ?: (win ? resolve_screen_for_rect(win.frame, win.screen) : [NSScreen mainScreen]);
    NSRect vf = scr ? scr.visibleFrame : NSMakeRect(0.0, 0.0, (CGFloat)gNativeScreenWidth, (CGFloat)gNativeScreenHeight);
    resolve_compatible_windowed_size_on_screen(scr, &targetW, &targetH);
    NSRect contentRect = NSMakeRect(0.0, 0.0, (CGFloat)targetW, (CGFloat)targetH);
    NSWindowStyleMask titledMask = (NSWindowStyleMaskTitled |
                                    NSWindowStyleMaskClosable |
                                    NSWindowStyleMaskMiniaturizable |
                                    NSWindowStyleMaskResizable);
    NSRect outerRect = (win && (win.styleMask & NSWindowStyleMaskTitled) != 0 && (win.styleMask & NSWindowStyleMaskFullScreen) == 0)
        ? [win frameRectForContentRect:contentRect]
        : [NSWindow frameRectForContentRect:contentRect styleMask:titledMask];
    if (!centerInVisible && win) {
        NSRect curF = win.frame;
        outerRect.origin = curF.origin;
    } else {
        outerRect.origin.x = vf.origin.x + floor((vf.size.width - outerRect.size.width) * 0.5);
        outerRect.origin.y = vf.origin.y + floor((vf.size.height - outerRect.size.height) * 0.5);
    }
    CGFloat maxTop = vf.origin.y + vf.size.height;
    CGFloat maxRight = vf.origin.x + vf.size.width;
    if (outerRect.origin.y + outerRect.size.height > maxTop) {
        outerRect.origin.y = maxTop - outerRect.size.height;
    }
    if (outerRect.origin.y < vf.origin.y) {
        outerRect.origin.y = vf.origin.y;
    }
    if (outerRect.origin.x + outerRect.size.width > maxRight) {
        outerRect.origin.x = maxRight - outerRect.size.width;
    }
    if (outerRect.origin.x < vf.origin.x) {
        outerRect.origin.x = vf.origin.x;
    }
    return outerRect;
}

static NSRect compute_windowed_game_frame(NSWindow *win, NSInteger targetW, NSInteger targetH, BOOL centerInVisible) {
    NSScreen *scr = win ? resolve_screen_for_rect(win.frame, win.screen) : [NSScreen mainScreen];
    return compute_windowed_game_frame_on_screen(win, scr, targetW, targetH, centerInVisible);
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static void swizzled_nsglSetView(id self, SEL _cmd, NSView *view) {
    if (gOrigNSGLSetViewIMP) {
        typedef void (*Fn)(id, SEL, NSView *);
        ((Fn)gOrigNSGLSetViewIMP)(self, _cmd, view);
    }
    if (view && self) {
        NSWindow *w = [view window];
        BOOL isPrimaryGameWin = (w && is_sdl_game_window(w) && !is_secondary_orphan_game_window(w));
        if (!w || isPrimaryGameWin || !gGameOpenGLContext) {
            BOOL ctxChanged = (gGameOpenGLContext != (NSOpenGLContext *)self);
            gGameOpenGLContext = (NSOpenGLContext *)self;
            debuglog_write("GL", "Captured gGameOpenGLContext=%p via setView:%p win=%p changed=%d windowed=%d",
                           (__bridge void *)self, (__bridge void *)view, (__bridge void *)w,
                           ctxChanged ? 1 : 0, gWindowedModeActive ? 1 : 0);
            if (isPrimaryGameWin && (gPendingOpenGLSurfaceSync || gWindowedModeActive || ctxChanged)) {
                /* Re-sync kCGLCPSurfaceBackingSize & SDL_Window geometry whenever the engine
                   attaches or recreates its OpenGL context (e.g. in-game Graphics Options Apply). */
                __weak NSWindow *weakWin = w;
                if ([NSThread isMainThread]) {
                    sync_sdl_window_logical_size_to_engine_fb(w, "nsglSetView");
                    apply_opengl_surface_backing_size_ex(w, YES);
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSWindow *liveWin = weakWin;
                    if (liveWin && !gAppIsTerminating) {
                        sync_sdl_window_logical_size_to_engine_fb(liveWin, "nsglSetView-async");
                        apply_opengl_surface_backing_size_ex(liveWin, YES);
                    }
                });
            }
        }
    }
}

static void swizzled_nsglMakeCurrentContext(id self, SEL _cmd) {
    if (gOrigNSGLMakeCurrentContextIMP) {
        typedef void (*Fn)(id, SEL);
        ((Fn)gOrigNSGLMakeCurrentContextIMP)(self, _cmd);
    }
    static __weak NSOpenGLContext *sIgnoredNonGameCtx = nil;
    if (!self || self == gGameOpenGLContext || self == sIgnoredNonGameCtx) {
        return;
    }
    NSOpenGLContext *ctx = (NSOpenGLContext *)self;
    NSView *v = [ctx view];
    if (!v) {
        return;
    }
    NSWindow *w = [v window];
    if (!gGameOpenGLContext || (w && is_sdl_game_window(w) && !is_secondary_orphan_game_window(w))) {
        BOOL wasReplaced = (gGameOpenGLContext != nil);
        gGameOpenGLContext = ctx;
        debuglog_write("GL", "Captured gGameOpenGLContext=%p via makeCurrentContext (replaced=%d win=%p)",
                       (__bridge void *)self, wasReplaced ? 1 : 0, (__bridge void *)w);
        if (w && is_sdl_game_window(w) && !is_secondary_orphan_game_window(w) &&
            (wasReplaced || gPendingOpenGLSurfaceSync || gWindowedModeActive)) {
            __weak NSWindow *weakWin = w;
            dispatch_async(dispatch_get_main_queue(), ^{
                NSWindow *liveWin = weakWin;
                if (liveWin && !gAppIsTerminating) {
                    sync_sdl_window_logical_size_to_engine_fb(liveWin, "nsglMakeCurrent-async");
                    apply_opengl_surface_backing_size_ex(liveWin, YES);
                }
            });
        }
    } else {
        sIgnoredNonGameCtx = ctx;
    }
}

static NSOpenGLContext *resolve_game_opengl_context(NSWindow *win) {
    if (gGameOpenGLContext) {
        return gGameOpenGLContext;
    }
    if (win && win.contentView) {
        if ([win.contentView isKindOfClass:[NSOpenGLView class]]) {
            NSOpenGLContext *ctx = [(NSOpenGLView *)win.contentView openGLContext];
            if (ctx) {
                gGameOpenGLContext = ctx;
                return ctx;
            }
        }
        for (NSView *sub in [win.contentView subviews]) {
            if ([sub isKindOfClass:[NSOpenGLView class]]) {
                NSOpenGLContext *ctx = [(NSOpenGLView *)sub openGLContext];
                if (ctx) {
                    gGameOpenGLContext = ctx;
                    return ctx;
                }
            }
        }
    }
    NSOpenGLContext *cur = [NSOpenGLContext currentContext];
    if (cur) {
        gGameOpenGLContext = cur;
    }
    return cur;
}

static void apply_opengl_surface_backing_size_ex(NSWindow *win, BOOL forceUpdate) {
    detect_native_screen_resolution(win);
    NSOpenGLContext *nsglCtx = resolve_game_opengl_context(win);
    CGLContextObj cglCtx = nsglCtx ? (CGLContextObj)[nsglCtx CGLContextObj] : CGLGetCurrentContext();
    if (!cglCtx) {
        gPendingOpenGLSurfaceSync = YES;
        debuglog_write("GL", "apply_opengl_surface_backing_size deferred (no CGLContextObj yet)");
        return;
    }
    gPendingOpenGLSurfaceSync = NO;

    NSRect contentRect = (win && win.contentView)
        ? win.contentView.bounds
        : (win ? [win contentRectForFrameRect:win.frame] : NSZeroRect);
    CGFloat contentW = contentRect.size.width;
    CGFloat contentH = contentRect.size.height;
    CGFloat backingScale = 1.0;
    if (win && win.contentView && [win.contentView wantsBestResolutionOpenGLSurface] &&
        win.backingScaleFactor > 0.0) {
        backingScale = win.backingScaleFactor;
    }

    CGFloat fbW = (gEngineFbW >= 640.0) ? gEngineFbW : contentW;
    CGFloat fbH = (gEngineFbH >= 480.0) ? gEngineFbH : contentH;
    BOOL needsBackingScale = (contentW >= 640.0 && contentH >= 480.0 &&
                              (fabs(fbW - contentW) > 2.0 || fabs(fbH - contentH) > 2.0));

    GLint wasEnabled = 0;
    GLint curDims[2] = { 0, 0 };
    CGLLockContext(cglCtx);
    CGLIsEnabled(cglCtx, kCGLCESurfaceBackingSize, &wasEnabled);
    if (wasEnabled) {
        CGLGetParameter(cglCtx, kCGLCPSurfaceBackingSize, curDims);
    }
    CGLUnlockContext(cglCtx);

    CGFloat winScale = (win && win.backingScaleFactor > 0.0) ? win.backingScaleFactor : 1.0;
    NSScreen *winScreen = win ? win.screen : nil;
    BOOL backingOrScreenChanged = (fabs(winScale - gLastAppliedGlBackingScale) > 0.01 ||
                                   winScreen != gLastAppliedGlScreen);

    if (needsBackingScale) {
        /* Anti-cropping & GPU scaling safety net (Windowed mode or mismatched engine FB):
           lock kCGLCPSurfaceBackingSize to { gEngineFbW, gEngineFbH } without redundant [nsglCtx update] calls
           so AppleMetalOpenGLRenderer never recreates CAMetalLayer drawables mid-frame. */
        GLint dims[2] = {
            (GLint)llround(fbW * backingScale),
            (GLint)llround(fbH * backingScale)
        };
        gActiveFramebufferWidth = fbW;
        gActiveFramebufferHeight = fbH;
        if (!forceUpdate && !backingOrScreenChanged && wasEnabled && curDims[0] == dims[0] && curDims[1] == dims[1]) {
            return;
        }
        CGLLockContext(cglCtx);
        CGLSetParameter(cglCtx, kCGLCPSurfaceBackingSize, dims);
        CGLEnable(cglCtx, kCGLCESurfaceBackingSize);
        CGLUpdateContext(cglCtx);
        CGLUnlockContext(cglCtx);
        if (nsglCtx) {
            [nsglCtx update];
        }
        if (win && win.contentView && [NSThread isMainThread]) {
            [win.contentView setNeedsDisplay:YES];
        }
        gLastAppliedGlBackingScale = winScale;
        gLastAppliedGlScreen = winScreen;
        debuglog_write("GL", "Set kCGLCPSurfaceBackingSize=%dx%d (prev=%dx%d en=%d) into content=%.0fx%.0f (windowed=%d scale=%.1f winScale=%.1f force=%d)",
                       dims[0], dims[1], curDims[0], curDims[1], wasEnabled, contentW, contentH,
                       gWindowedModeActive ? 1 : 0, backingScale, winScale,
                       forceUpdate ? 1 : 0);
    } else {
        /* Exact 1:1 native match */
        if (contentW >= 640.0 && contentH >= 480.0) {
            gActiveFramebufferWidth = contentW;
            gActiveFramebufferHeight = contentH;
        }
        if (!forceUpdate && !backingOrScreenChanged && !wasEnabled) {
            return;
        }
        CGLLockContext(cglCtx);
        CGLDisable(cglCtx, kCGLCESurfaceBackingSize);
        CGLUpdateContext(cglCtx);
        CGLUnlockContext(cglCtx);
        if (nsglCtx) {
            [nsglCtx update];
        }
        if (win && win.contentView && [NSThread isMainThread]) {
            [win.contentView setNeedsDisplay:YES];
        }
        gLastAppliedGlBackingScale = winScale;
        gLastAppliedGlScreen = winScreen;
        debuglog_write("GL", "Native 1:1 surface: disabled kCGLCESurfaceBackingSize (prevEn=%d fb=%.0fx%.0f content=%.0fx%.0f winScale=%.1f force=%d)",
                       wasEnabled, gActiveFramebufferWidth, gActiveFramebufferHeight,
                       contentW, contentH, winScale, forceUpdate ? 1 : 0);
    }
}

static void apply_opengl_surface_backing_size(NSWindow *win) {
    apply_opengl_surface_backing_size_ex(win, NO);
}

static void refresh_opengl_surface_for_screen_or_backing_change(NSWindow *win, const char *reason) {
    if (!win || gAppIsTerminating || !is_sdl_game_window(win) || is_secondary_orphan_game_window(win)) {
        return;
    }
    /* Update lightweight screen/menu/SDL metadata immediately, NEVER mutate setFrame: synchronously
       while inactive (e.g. mid-Mission-Control Space drag between monitors), and coalesce all rapid
       DidChangeBackingProperties / DidChangeScreen / DidChangeScreenParameters bursts into a single
       debounced OpenGL + geometry settle pass (140 ms) via gOpenGLRefreshSeq. */
    detect_native_screen_resolution(win);
    update_cached_screen_geometry(win.screen ?: [NSScreen mainScreen]);
    rebuild_sims2_display_menu_resolution_items(win);
    update_sims2_display_menu_state();
    sync_sdl_window_logical_size_to_engine_fb(win, reason ? reason : "screenOrBackingChange");

    uint64_t mySeq = __atomic_add_fetch(&gOpenGLRefreshSeq, 1ULL, __ATOMIC_ACQ_REL);
    uint64_t refreshGen = current_display_transition_gen();
    __weak NSWindow *weakWin = win;
    const char *reasonTag = reason ? reason : "screenOrBackingChange";

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(140 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), ^{
        if (__atomic_load_n(&gOpenGLRefreshSeq, __ATOMIC_ACQUIRE) != mySeq ||
            current_display_transition_gen() != refreshGen ||
            gInFullscreenTransition || gAppIsTerminating) {
            return;
        }
        NSWindow *w = weakWin;
        if (!w || !is_sdl_window_fully_attached(w)) {
            return;
        }
        detect_native_screen_resolution(w);
        update_cached_screen_geometry(w.screen ?: [NSScreen mainScreen]);
        rebuild_sims2_display_menu_resolution_items(w);
        update_sims2_display_menu_state();
        BOOL wInSpace = ((w.styleMask & NSWindowStyleMaskFullScreen) != 0);
        BOOL appActive = (NSApp && [NSApp isActive] && !gAppIsHiding);
        if (!gWindowedModeActive && wInSpace && appActive) {
            /* Only fit Space geometry once active & WindowServer/NSToolbarFullScreenWindow have settled. */
            ensure_fullscreen_space_geometry(w, reasonTag);
        }
        sync_sdl_window_logical_size_to_engine_fb(w, reasonTag);
        BOOL forceGl = (reasonTag &&
                        (strcmp(reasonTag, "ActiveSpaceDidChange") == 0 ||
                         strcmp(reasonTag, "ActiveSpaceVisibleRefresh") == 0 ||
                         strcmp(reasonTag, "ActiveSpaceDidChangeReactivate") == 0 ||
                         strcmp(reasonTag, "didExitFullScreenSettle") == 0 ||
                         strcmp(reasonTag, "DidBecomeActive") == 0));
        apply_opengl_surface_backing_size_ex(w, forceGl);
        if (w.contentView) {
            [w.contentView setNeedsDisplay:YES];
        }
        debuglog_write("GL", "Coalesced OpenGL refresh (%s) screen=%.0fx%.0f@(%.0f,%.0f) scale=%.1f inSpace=%d active=%d windowed=%d",
                       reasonTag,
                       w.screen ? w.screen.frame.size.width : 0.0,
                       w.screen ? w.screen.frame.size.height : 0.0,
                       w.screen ? w.screen.frame.origin.x : 0.0,
                       w.screen ? w.screen.frame.origin.y : 0.0,
                       w.backingScaleFactor,
                       wInSpace ? 1 : 0,
                       appActive ? 1 : 0,
                       gWindowedModeActive ? 1 : 0);
    });
}
#pragma clang diagnostic pop

static void clear_exit_fullscreen_target_screen(void) {
    gExitFullscreenTargetScreen = nil;
    gExitFullscreenTargetFrame = NSZeroRect;
    gHasExitFullscreenTarget = NO;
    gExitFullscreenTargetSetTime = 0.0;
}

static void remember_exit_fullscreen_target_screen(NSWindow *win, const char *reason) {
    if (!win) {
        return;
    }
    NSScreen *srcScreen = win.screen ?: resolve_screen_for_rect(win.frame, nil);
    if (!srcScreen) {
        return;
    }
    NSInteger tw = (gTargetWindowWidth >= 640) ? gTargetWindowWidth : 1512;
    NSInteger th = (gTargetWindowHeight >= 480) ? gTargetWindowHeight : 982;
    resolve_compatible_windowed_size_on_screen(srcScreen, &tw, &th);
    NSRect targetFrame = compute_windowed_game_frame_on_screen(win, srcScreen, tw, th, YES);
    gExitFullscreenTargetScreen = srcScreen;
    gExitFullscreenTargetFrame = targetFrame;
    gHasExitFullscreenTarget = YES;
    gExitFullscreenTargetSetTime = CFAbsoluteTimeGetCurrent();
    debuglog_write("WIN", "Remembered exit-fullscreen target (%s): screen=%.0fx%.0f@(%.0f,%.0f) target=%.0fx%.0f@(%.0f,%.0f)",
                   reason ? reason : "exitFS",
                   srcScreen.frame.size.width, srcScreen.frame.size.height,
                   srcScreen.frame.origin.x, srcScreen.frame.origin.y,
                   targetFrame.size.width, targetFrame.size.height,
                   targetFrame.origin.x, targetFrame.origin.y);
}

static NSScreen *resolve_active_exit_fullscreen_target_screen(void) {
    if (!gHasExitFullscreenTarget || !gExitFullscreenTargetScreen) {
        return nil;
    }
    if (gUserWindowMoveInProgress || ([NSEvent pressedMouseButtons] & 1) != 0) {
        clear_exit_fullscreen_target_screen();
        return nil;
    }
    if (gExitFullscreenTargetSetTime > 0.0 &&
        (CFAbsoluteTimeGetCurrent() - gExitFullscreenTargetSetTime) > 3.0) {
        clear_exit_fullscreen_target_screen();
        return nil;
    }
    NSScreen *saved = gExitFullscreenTargetScreen;
    NSArray<NSScreen *> *screens = ([NSThread isMainThread] && NSApp != nil) ? [NSScreen screens] : nil;
    if (screens && [screens containsObject:saved]) {
        return saved;
    }
    clear_exit_fullscreen_target_screen();
    return nil;
}

static BOOL is_secondary_orphan_game_window(id winObj) {
    if (!gPrimaryFullscreenWindow || !winObj || winObj == gPrimaryFullscreenWindow) {
        return NO;
    }
    if (!is_sdl_game_window(winObj)) {
        return NO;
    }
    NSWindow *win = (NSWindow *)winObj;
    if (([win styleMask] & NSWindowStyleMaskFullScreen) != 0) {
        return NO;
    }
    return YES;
}

static void neutralize_single_orphan_window(NSWindow *win) {
    if (!win) {
        return;
    }
    [win setIgnoresMouseEvents:YES];
    [win setCollectionBehavior:(NSWindowCollectionBehaviorStationary | NSWindowCollectionBehaviorIgnoresCycle)];
    if ([win isVisible]) {
        id delegate = [win delegate];
        SEL pauseSel = @selector(pauseVisibleObservation);
        SEL resumeSel = @selector(resumeVisibleObservation);
        if (delegate && [delegate respondsToSelector:pauseSel]) {
            IMP pauseIMP = [delegate methodForSelector:pauseSel];
            if (pauseIMP) {
                ((void (*)(id, SEL))pauseIMP)(delegate, pauseSel);
            }
        }
        [win orderOut:nil];
        if (delegate && [delegate respondsToSelector:resumeSel]) {
            IMP resumeIMP = [delegate methodForSelector:resumeSel];
            if (resumeIMP) {
                ((void (*)(id, SEL))resumeIMP)(delegate, resumeSel);
            }
        }
        debuglog_write("WIN", "Neutralized secondary orphan SDLWindow win=%p (primary=%p)",
                       (__bridge void *)win, (__bridge void *)gPrimaryFullscreenWindow);
    }
}

static void neutralize_secondary_orphan_windows(NSWindow *primaryWin) {
    if (primaryWin) {
        gPrimaryFullscreenWindow = primaryWin;
    }
    if (!gPrimaryFullscreenWindow || !NSApp) {
        return;
    }
    for (NSWindow *w in [NSApp windows]) {
        if (is_secondary_orphan_game_window(w)) {
            neutralize_single_orphan_window(w);
        }
    }
}

/*
 * Safe extractor for NSWindowDelegate callbacks: standard notification callbacks receive
 * NSNotification* (with [note object] == NSWindow*), whereas windowDidFailToEnterFullScreen:
 * and windowDidFailToExitFullScreen: receive NSWindow* directly per AppKit NSWindowDelegate.
 */
static NSWindow *extract_nswindow_from_delegate_arg(id arg) {
    if (!arg) {
        return nil;
    }
    if ([arg isKindOfClass:[NSWindow class]]) {
        return (NSWindow *)arg;
    }
    if ([arg isKindOfClass:[NSNotification class]]) {
        id obj = [(NSNotification *)arg object];
        if (obj && [obj isKindOfClass:[NSWindow class]]) {
            return (NSWindow *)obj;
        }
    }
    return nil;
}

static BOOL is_callable_orig_imp(IMP imp) {
    if (!imp) {
        return NO;
    }
#if defined(__x86_64__) || defined(__arm64__)
    if (imp == _objc_msgForward) {
        return NO;
    }
#endif
    return YES;
}

static void swizzled_windowDidBecomeKey(id self, SEL _cmd, NSNotification *notification) {
    gWindowListener = self;
    NSWindow *winObj = extract_nswindow_from_delegate_arg(notification);
    BOOL isWin = (winObj != nil);
    NSRect frame = isWin ? winObj.frame : NSZeroRect;
    BOOL isFS = isWin ? ((winObj.styleMask & NSWindowStyleMaskFullScreen) != 0) : NO;

    if (isFS && isWin) {
        neutralize_secondary_orphan_windows(winObj);
    } else if (is_secondary_orphan_game_window(winObj)) {
        neutralize_single_orphan_window(winObj);
        debuglog_write("WIN", "SUPPRESSED orphan windowDidBecomeKey win=%p -> restoring primary=%p",
                       (__bridge void *)winObj, (__bridge void *)gPrimaryFullscreenWindow);
        if (gAppIsActive && (!NSApp || [NSApp isActive]) &&
            gPrimaryFullscreenWindow && gOrigMakeKeyAndOrderFrontIMP) {
            typedef void (*OrderFn)(id, SEL, id);
            ((OrderFn)gOrigMakeKeyAndOrderFrontIMP)(gPrimaryFullscreenWindow,
                                                    @selector(makeKeyAndOrderFront:),
                                                    nil);
        }
        return;
    }

    if (!NSApp || [NSApp isActive]) {
        gAppHasActivatedOnce = YES;
        gAppIsActive = YES;
        gLastResignTimestamp = 0.0;
    }
    debuglog_write("WIN", "windowDidBecomeKey win=%p active=%d fs=%d frame=%.0fx%.0f",
                   (__bridge void *)winObj, (NSApp && [NSApp isActive]) ? 1 : 0, isFS ? 1 : 0,
                   frame.size.width, frame.size.height);

    if (is_callable_orig_imp(gOrigWindowDidBecomeKeyIMP)) {
        typedef void (*BecomeFn)(id, SEL, NSNotification *);
        BOOL prevProj = tProjectMouseLocationForSDL;
        tProjectMouseLocationForSDL = YES;
        ((BecomeFn)gOrigWindowDidBecomeKeyIMP)(self, _cmd, notification);
        tProjectMouseLocationForSDL = prevProj;
    }
    if (isWin && is_sdl_game_window(winObj) && !is_secondary_orphan_game_window(winObj)) {
        ensure_sdl_responder_chain(winObj, "windowDidBecomeKey");
        if (winObj.contentView && [winObj firstResponder] != winObj.contentView) {
            [winObj makeFirstResponder:winObj.contentView];
        }
        [winObj setAcceptsMouseMovedEvents:YES];
        CGAssociateMouseAndMouseCursorPosition(true);
    }
}

static void swizzled_windowDidResignKey(id self, SEL _cmd, NSNotification *notification) {
    NSWindow *winObj = extract_nswindow_from_delegate_arg(notification);
    if (is_secondary_orphan_game_window(winObj)) {
        debuglog_write("WIN", "IGNORED orphan windowDidResignKey win=%p", (__bridge void *)winObj);
        return;
    }
    gWindowListener = self;
    gLastResignTimestamp = CFAbsoluteTimeGetCurrent();
    reset_gesture_and_key_state(self);
    CGAssociateMouseAndMouseCursorPosition(true);
    CGDisplayShowCursor(kCGDirectMainDisplay);
    debuglog_write("WIN", "windowDidResignKey win=%p active=%d",
                   (__bridge void *)winObj, (NSApp && [NSApp isActive]) ? 1 : 0);

    if (is_callable_orig_imp(gOrigWindowDidResignKeyIMP)) {
        typedef void (*ResignFn)(id, SEL, NSNotification *);
        ((ResignFn)gOrigWindowDidResignKeyIMP)(self, _cmd, notification);
    }
}

static void swizzled_windowWillEnterFullScreen(id self, SEL _cmd, NSNotification *notification) {
    gWindowListener = self;
    gInFullscreenTransition = YES;
    gAllowResizableForSpaceToggle = YES;
    gWindowedModeActive = NO;
    clear_exit_fullscreen_target_screen();
    NSWindow *winObj = extract_nswindow_from_delegate_arg(notification);
    if (winObj) {
        neutralize_secondary_orphan_windows(winObj);
        apply_borderless_presentation_options(NO);
    }
    debuglog_write("WIN", "windowWillEnterFullScreen win=%p userReq=%d",
                   (__bridge void *)winObj, gUserRequestedFullscreenEnter ? 1 : 0);

    if (is_callable_orig_imp(gOrigWindowWillEnterFullScreenIMP)) {
        typedef void (*EnterFSFn)(id, SEL, NSNotification *);
        ((EnterFSFn)gOrigWindowWillEnterFullScreenIMP)(self, _cmd, notification);
    }
    if (winObj) {
        ensure_sdl_responder_chain(winObj, "windowWillEnterFullScreen");
    }
}

static void swizzled_windowDidEnterFullScreen(id self, SEL _cmd, NSNotification *notification) {
    gWindowListener = self;
    NSWindow *win = extract_nswindow_from_delegate_arg(notification);
    if (!win) {
        win = resolve_primary_game_window();
    }
    if (win && ((win.styleMask & NSWindowStyleMaskFullScreen) == 0)) {
        /* Guard against SDL2's windowDidFailToExitFullScreen: tail-calling [self windowDidEnterFullScreen:nil]
           when macOS actually already exited the Fullscreen Space (fs=0). */
        debuglog_write("WIN", "IGNORED spurious windowDidEnterFullScreen win=%p (fs=0 windowed=%d)",
                       (__bridge void *)win, gWindowedModeActive ? 1 : 0);
        return;
    }
    gInFullscreenTransition = NO;
    gAllowResizableForSpaceToggle = NO;
    gUserRequestedFullscreenEnter = NO;
    gHasCompletedFirstWindowShow = YES;
    gWindowedModeActive = NO;
    gLastKnownInSpace = YES;
    record_last_hook_state("windowDidEnterFullScreen");
    uint64_t enterGen = current_display_transition_gen();
    if (win) {
        if (!gHasCapturedInitialEngineFb) {
            CGFloat sdlW = 0.0, sdlH = 0.0;
            if (query_sdl_window_logical_size(win, &sdlW, &sdlH)) {
                gEngineFbW = sdlW;
                gEngineFbH = sdlH;
                gHasCapturedInitialEngineFb = YES;
                debuglog_write("WIN", "Captured engine FB before didEnterFullScreen: %.0fx%.0f", gEngineFbW, gEngineFbH);
            }
        }
        neutralize_secondary_orphan_windows(win);
        apply_borderless_presentation_options(NO);
    }
    debuglog_write("WIN", "windowDidEnterFullScreen win=%p frame=%.0fx%.0f",
                   (__bridge void *)win,
                   win ? win.frame.size.width : 0.0,
                   win ? win.frame.size.height : 0.0);

    if (is_callable_orig_imp(gOrigWindowDidEnterFullScreenIMP)) {
        typedef void (*DidEnterFSFn)(id, SEL, NSNotification *);
        ((DidEnterFSFn)gOrigWindowDidEnterFullScreenIMP)(self, _cmd, notification);
    }
    if (win) {
        /* Verify Space window matches aspect-fitted usable Space rect (zero 16:10 -> 16:9 stretching) */
        ensure_fullscreen_space_geometry(win, "didEnterFullScreen");
        sync_sdl_window_logical_size_to_engine_fb(win, "windowDidEnterFullScreen");
        rebuild_sims2_display_menu_resolution_items(win);
        update_sims2_display_menu_state();
        ensure_sdl_responder_chain(win, "windowDidEnterFullScreen");
        apply_opengl_surface_backing_size_ex(win, YES);
        flush_stuck_modifier_state_to_sdl(win, "didEnterFullScreen");
        restore_game_window_focus_and_input(win, "didEnterFullScreen");

        /* Generation-guarded post-Space settle check in case macOS delivers a late frame nudge or backing change */
        __weak NSWindow *weakWin = win;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(80 * NSEC_PER_MSEC)),
                       dispatch_get_main_queue(), ^{
            if (current_display_transition_gen() != enterGen || gInFullscreenTransition || gAppIsTerminating) {
                return;
            }
            NSWindow *w = weakWin;
            if (w && !gWindowedModeActive && ((w.styleMask & NSWindowStyleMaskFullScreen) != 0)) {
                ensure_fullscreen_space_geometry(w, "didEnterFullScreenSettle");
                apply_opengl_surface_backing_size_ex(w, YES);
            }
        });
    }
}

static void swizzled_windowDidFailToEnterFullScreen(id self, SEL _cmd, id windowOrNote) {
    gWindowListener = self;
    gInFullscreenTransition = NO;
    gAllowResizableForSpaceToggle = NO;
    gUserRequestedFullscreenEnter = NO;
    record_last_hook_state("windowDidFailToEnterFullScreen");
    uint64_t failGen = current_display_transition_gen();
    NSWindow *win = extract_nswindow_from_delegate_arg(windowOrNote);
    BOOL stillInSpace = (win && ((win.styleMask & NSWindowStyleMaskFullScreen) != 0));
    gLastKnownInSpace = stillInSpace;
    debuglog_write("WIN", "windowDidFailToEnterFullScreen win=%p stillInSpace=%d windowed=%d",
                   (__bridge void *)win, stillInSpace ? 1 : 0, gWindowedModeActive ? 1 : 0);

    if (is_callable_orig_imp(gOrigWindowDidFailToEnterFullScreenIMP)) {
        typedef void (*FailFSFn)(id, SEL, id);
        ((FailFSFn)gOrigWindowDidFailToEnterFullScreenIMP)(self, _cmd, windowOrNote);
    }

    if (win && !stillInSpace && !gAppIsTerminating) {
        /* Clean rollback: Dock/AppKit rejected Fullscreen Space entry and left the window
           on the Desktop -> restore coherent Windowed state + CGL backing + focus/modifiers. */
        gWindowedModeActive = YES;
        gLastKnownInSpace = NO;
        select_default_windowed_resolution_if_native(win);
        update_sims2_display_menu_state();
        __weak NSWindow *weakWin = win;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (current_display_transition_gen() != failGen || gInFullscreenTransition || gAppIsTerminating) {
                return;
            }
            NSWindow *w = weakWin;
            if (w && gWindowedModeActive && ((w.styleMask & NSWindowStyleMaskFullScreen) == 0)) {
                enforce_primary_window_borderless_fullscreen(w, "failEnterFullScreenRollback");
                apply_opengl_surface_backing_size_ex(w, YES);
                flush_stuck_modifier_state_to_sdl(w, "failEnterFullScreenRollback");
                restore_game_window_focus_and_input(w, "failEnterFullScreenRollback");
            }
        });
    }
}

static void swizzled_windowWillExitFullScreen(id self, SEL _cmd, NSNotification *notification) {
    gWindowListener = self;
    gInFullscreenTransition = YES;
    gAllowResizableForSpaceToggle = YES;
    reset_gesture_and_key_state(self);
    if (gUserRequestedFullscreenExit || (NSApp && [NSApp isActive] && !gAppIsTerminating && !gAppIsHiding)) {
        /* User exited native Space (via green button / Window menu / Command+Return) -> enter Windowed cleanly */
        gWindowedModeActive = YES;
        gForceCenterWindowedFrame = YES;
    }
    NSWindow *winObj = extract_nswindow_from_delegate_arg(notification);
    if (!gHasExitFullscreenTarget && winObj) {
        remember_exit_fullscreen_target_screen(winObj, "windowWillExitFullScreen");
    }
    debuglog_write("WIN", "windowWillExitFullScreen win=%p active=%d userReqExit=%d windowed=%d",
                   (__bridge void *)winObj,
                   (NSApp && [NSApp isActive]) ? 1 : 0,
                   gUserRequestedFullscreenExit ? 1 : 0,
                   gWindowedModeActive ? 1 : 0);

    if (is_callable_orig_imp(gOrigWindowWillExitFullScreenIMP)) {
        typedef void (*ExitFSFn)(id, SEL, NSNotification *);
        ((ExitFSFn)gOrigWindowWillExitFullScreenIMP)(self, _cmd, notification);
    }
}

static void swizzled_windowDidExitFullScreen(id self, SEL _cmd, NSNotification *notification) {
    gWindowListener = self;
    gInFullscreenTransition = NO;
    gAllowResizableForSpaceToggle = NO;
    gUserRequestedFullscreenExit = NO;
    gHasCompletedFirstWindowShow = YES;
    gLastKnownInSpace = NO;
    record_last_hook_state("windowDidExitFullScreen");
    uint64_t exitGen = current_display_transition_gen();
    NSWindow *win = extract_nswindow_from_delegate_arg(notification);
    /* NEVER clear gPrimaryFullscreenWindow here; keeping it prevents orphan/re-entry bugs */
    if (win && is_sdl_game_window(win) && !is_secondary_orphan_game_window(win)) {
        gPrimaryFullscreenWindow = win;
        if (!gHasCapturedInitialEngineFb) {
            CGFloat sdlW = 0.0, sdlH = 0.0;
            if (query_sdl_window_logical_size(win, &sdlW, &sdlH)) {
                gEngineFbW = sdlW;
                gEngineFbH = sdlH;
                gHasCapturedInitialEngineFb = YES;
            }
        }
    }
    debuglog_write("WIN", "windowDidExitFullScreen win=%p active=%d windowed=%d",
                   (__bridge void *)win,
                   (NSApp && [NSApp isActive]) ? 1 : 0,
                   gWindowedModeActive ? 1 : 0);

    if (is_callable_orig_imp(gOrigWindowDidExitFullScreenIMP)) {
        typedef void (*DidExitFSFn)(id, SEL, NSNotification *);
        ((DidExitFSFn)gOrigWindowDidExitFullScreenIMP)(self, _cmd, notification);
    }
    if (win && !gAppIsTerminating && is_sdl_game_window(win) && !is_secondary_orphan_game_window(win)) {
        sync_sdl_window_logical_size_to_engine_fb(win, "windowDidExitFullScreen");
        NSScreen *exitScr = resolve_active_exit_fullscreen_target_screen();
        if (gWindowedModeActive) {
            if (!is_reduced_target_resolution()) {
                NSInteger defW = 1512, defH = 982;
                if (exitScr) {
                    resolve_compatible_windowed_size_on_screen(exitScr, &defW, &defH);
                } else {
                    resolve_compatible_windowed_size(win, &defW, &defH);
                }
                gTargetWindowWidth = defW;
                gTargetWindowHeight = defH;
            }
        }
        update_sims2_display_menu_state();
        ensure_sdl_responder_chain(win, "windowDidExitFullScreen");
        flush_stuck_modifier_state_to_sdl(win, "didExitFullScreen");
        __weak NSWindow *weakWin = win;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (current_display_transition_gen() != exitGen || gInFullscreenTransition || gAppIsTerminating) {
                return;
            }
            NSWindow *w = weakWin;
            if (w && gWindowedModeActive) {
                enforce_primary_window_borderless_fullscreen(w, "didExitFullScreen");
                restore_game_window_focus_and_input(w, "didExitFullScreen");
            }
        });
        /* Post-exit settle check (180 ms): neutralize any late AppKit Space-exit frame callback (~118 ms)
           that attempts to snap the exited window back onto screens[0] instead of the TV / origin screen. */
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(180 * NSEC_PER_MSEC)),
                       dispatch_get_main_queue(), ^{
            if (current_display_transition_gen() != exitGen || gInFullscreenTransition || gAppIsTerminating) {
                return;
            }
            NSWindow *w = weakWin;
            NSScreen *savedExitScr = resolve_active_exit_fullscreen_target_screen();
            if (w && gWindowedModeActive && ((w.styleMask & NSWindowStyleMaskFullScreen) == 0) &&
                [NSEvent pressedMouseButtons] == 0 && !gUserWindowMoveInProgress && savedExitScr) {
                NSScreen *curScr = resolve_screen_for_rect(w.frame, w.screen);
                if (curScr != savedExitScr) {
                    debuglog_write("WIN", "Post-exit settle restoring window to exit screen %.0fx%.0f@(%.0f,%.0f) from frame=%.0fx%.0f@(%.0f,%.0f)",
                                   savedExitScr.frame.size.width, savedExitScr.frame.size.height,
                                   savedExitScr.frame.origin.x, savedExitScr.frame.origin.y,
                                   w.frame.size.width, w.frame.size.height,
                                   w.frame.origin.x, w.frame.origin.y);
                    gForceCenterWindowedFrame = YES;
                    enforce_primary_window_borderless_fullscreen(w, "didExitFullScreenSettle");
                    refresh_opengl_surface_for_screen_or_backing_change(w, "didExitFullScreenSettle");
                    restore_game_window_focus_and_input(w, "didExitFullScreenSettle");
                }
            }
            clear_exit_fullscreen_target_screen();
        });
    }
}

static void swizzled_windowDidFailToExitFullScreen(id self, SEL _cmd, id windowOrNote) {
    gWindowListener = self;
    gInFullscreenTransition = NO;
    gAllowResizableForSpaceToggle = NO;
    gUserRequestedFullscreenExit = NO;
    record_last_hook_state("windowDidFailToExitFullScreen");
    uint64_t failGen = current_display_transition_gen();
    NSWindow *win = extract_nswindow_from_delegate_arg(windowOrNote);
    if (!win) {
        win = resolve_primary_game_window();
    }
    BOOL stillInSpace = (win && ((win.styleMask & NSWindowStyleMaskFullScreen) != 0));
    gLastKnownInSpace = stillInSpace;
    gWindowedModeActive = !stillInSpace;
    debuglog_write("WIN", "windowDidFailToExitFullScreen win=%p stillInSpace=%d windowed=%d",
                   (__bridge void *)win, stillInSpace ? 1 : 0, gWindowedModeActive ? 1 : 0);

    if (!stillInSpace) {
        /* Window HAS actually exited the Fullscreen Space (fs=0): NEVER call Aspyr's original IMP
           (0x1001030e0 sets _inFullscreenSpace=YES and calls [self windowDidEnterFullScreen:nil],
           which corrupted styleMask -> 0x0 and windowed -> 0!). Finalize Windowed mode cleanly. */
        if (win) {
            select_default_windowed_resolution_if_native(win);
            gForceCenterWindowedFrame = YES;
        }
        apply_borderless_presentation_options(NO);
        rebuild_sims2_display_menu_resolution_items(win);
        update_sims2_display_menu_state();
        if (win && !gAppIsTerminating) {
            enforce_primary_window_borderless_fullscreen(win, "failExitFullScreenToWindowed");
            apply_opengl_surface_backing_size_ex(win, YES);
            __weak NSWindow *weakWin = win;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (current_display_transition_gen() != failGen || gInFullscreenTransition || gAppIsTerminating) {
                    return;
                }
                NSWindow *w = weakWin;
                if (w && gWindowedModeActive && ((w.styleMask & NSWindowStyleMaskFullScreen) == 0)) {
                    enforce_primary_window_borderless_fullscreen(w, "failExitFullScreenToWindowedAsync");
                    apply_opengl_surface_backing_size_ex(w, YES);
                    flush_stuck_modifier_state_to_sdl(w, "failExitFullScreenToWindowed");
                    restore_game_window_focus_and_input(w, "failExitFullScreenToWindowed");
                }
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(180 * NSEC_PER_MSEC)),
                           dispatch_get_main_queue(), ^{
                if (current_display_transition_gen() != failGen || gInFullscreenTransition || gAppIsTerminating) {
                    return;
                }
                NSWindow *w = weakWin;
                NSScreen *savedExitScr = resolve_active_exit_fullscreen_target_screen();
                if (w && gWindowedModeActive && ((w.styleMask & NSWindowStyleMaskFullScreen) == 0) &&
                    [NSEvent pressedMouseButtons] == 0 && !gUserWindowMoveInProgress && savedExitScr) {
                    NSScreen *curScr = resolve_screen_for_rect(w.frame, w.screen);
                    if (curScr != savedExitScr) {
                        gForceCenterWindowedFrame = YES;
                        enforce_primary_window_borderless_fullscreen(w, "didExitFullScreenSettle");
                        refresh_opengl_surface_for_screen_or_backing_change(w, "didExitFullScreenSettle");
                    }
                }
                clear_exit_fullscreen_target_screen();
            });
        }
        return;
    }

    /* Window genuinely remained inside Fullscreen Space (stillInSpace == YES). */
    clear_exit_fullscreen_target_screen();
    if (is_callable_orig_imp(gOrigWindowDidFailToExitFullScreenIMP)) {
        typedef void (*FailExitFSFn)(id, SEL, id);
        ((FailExitFSFn)gOrigWindowDidFailToExitFullScreenIMP)(self, _cmd, windowOrNote);
    }
    rebuild_sims2_display_menu_resolution_items(win);
    update_sims2_display_menu_state();
    if (win && !gAppIsTerminating) {
        __weak NSWindow *weakWin = win;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (current_display_transition_gen() != failGen || gInFullscreenTransition || gAppIsTerminating) {
                return;
            }
            NSWindow *w = weakWin;
            if (w && !gWindowedModeActive && ((w.styleMask & NSWindowStyleMaskFullScreen) != 0)) {
                ensure_fullscreen_space_geometry(w, "failExitFullScreenStillInSpace");
                apply_opengl_surface_backing_size_ex(w, YES);
                flush_stuck_modifier_state_to_sdl(w, "failExitFullScreenStillInSpace");
                restore_game_window_focus_and_input(w, "failExitFullScreenStillInSpace");
            }
        });
    }
}

static BOOL swizzled_setFullscreenSpace(id self, SEL _cmd, BOOL state) {
    gWindowListener = self;
    /* If user explicitly switched to Windowed mode during the session, reject spontaneous SDL fullscreen
       Space requests immediately (return NO) so Cocoa_SetWindowFullscreenSpace exits in 0 ms! */
    if (state && gWindowedModeActive && !gUserRequestedFullscreenEnter) {
        debuglog_write("WIN", "Skipped setFullscreenSpace:YES (Windowed mode active -> 0ms fast exit)");
        return NO;
    }
    BOOL primaryInSpace = (gPrimaryFullscreenWindow &&
                           (([gPrimaryFullscreenWindow styleMask] & NSWindowStyleMaskFullScreen) != 0));
    if (!state && !gAppIsTerminating && !gAppIsHiding && !(NSApp && [NSApp isHidden]) &&
        !gUserRequestedFullscreenExit && !gWindowedModeActive &&
        (should_suppress_focus_steal_or_fullscreen_exit() || primaryInSpace)) {
        CFAbsoluteTime dt = (gLastResignTimestamp > 0.0) ? (CFAbsoluteTimeGetCurrent() - gLastResignTimestamp) : -1.0;
        debuglog_write("WIN", "SUPPRESSED setFullscreenSpace:NO (active=%d nsActive=%d primaryFS=%d dt=%.3fs)",
                       gAppIsActive ? 1 : 0, (NSApp && [NSApp isActive]) ? 1 : 0,
                       primaryInSpace ? 1 : 0, dt);
        return YES;
    }
    debuglog_write("WIN", "setFullscreenSpace:%d (active=%d hiding=%d windowed=%d)",
                   state ? 1 : 0, gAppIsActive ? 1 : 0, gAppIsHiding ? 1 : 0,
                   gWindowedModeActive ? 1 : 0);
    if (state) {
        apply_borderless_presentation_options(NO);
        NSWindow *primaryWin = resolve_primary_game_window();
        if (primaryWin) {
            NSWindowCollectionBehavior beh = sanitize_mission_control_collection_behavior(primaryWin.collectionBehavior);
            if (gOrigSDLSetCollectionBehaviorIMP && gSDLWindowClass && [primaryWin isKindOfClass:gSDLWindowClass]) {
                typedef void (*BehFn)(id, SEL, NSWindowCollectionBehavior);
                ((BehFn)gOrigSDLSetCollectionBehaviorIMP)(primaryWin, @selector(setCollectionBehavior:), beh);
            } else {
                [primaryWin setCollectionBehavior:beh];
            }
        }
    }
    if (gOrigSetFullscreenSpaceIMP) {
        typedef BOOL (*Fn)(id, SEL, BOOL);
        BOOL prevAllow = gAllowResizableForSpaceToggle;
        gAllowResizableForSpaceToggle = YES;
        BOOL res = ((Fn)gOrigSetFullscreenSpaceIMP)(self, _cmd, state);
        gAllowResizableForSpaceToggle = prevAllow;
        return res;
    }
    return NO;
}

static void swizzled_miniaturize(id self, SEL _cmd, id sender) {
    if (is_sdl_game_window(self) && sender == nil) {
        NSWindow *win = (NSWindow *)self;
        BOOL isFullscreen = (([win styleMask] & NSWindowStyleMaskFullScreen) != 0);
        if (isFullscreen || gInFullscreenTransition || should_suppress_focus_steal_or_fullscreen_exit()) {
            debuglog_write("WIN", "SUPPRESSED miniaturize: (fs=%d trans=%d active=%d) win=%p",
                           isFullscreen ? 1 : 0, gInFullscreenTransition ? 1 : 0,
                           gAppIsActive ? 1 : 0, (__bridge void *)win);
            return;
        }
    }
    if (is_sdl_game_window(self)) {
        debuglog_write("WIN", "miniaturize: sender=%p win=%p", (__bridge void *)sender, (__bridge void *)self);
    }
    if (gOrigMiniaturizeIMP) {
        typedef void (*Fn)(id, SEL, id);
        ((Fn)gOrigMiniaturizeIMP)(self, _cmd, sender);
    }
}

static void swizzled_makeKeyAndOrderFront(id self, SEL _cmd, id sender) {
    if (is_secondary_orphan_game_window(self)) {
        neutralize_single_orphan_window((NSWindow *)self);
        debuglog_write("WIN", "SUPPRESSED orphan makeKeyAndOrderFront: win=%p -> primary=%p",
                       (__bridge void *)self, (__bridge void *)gPrimaryFullscreenWindow);
        if (gAppIsActive && (!NSApp || [NSApp isActive]) &&
            gPrimaryFullscreenWindow && ![gPrimaryFullscreenWindow isKeyWindow] &&
            gOrigMakeKeyAndOrderFrontIMP) {
            typedef void (*Fn)(id, SEL, id);
            ((Fn)gOrigMakeKeyAndOrderFrontIMP)(gPrimaryFullscreenWindow, _cmd, sender);
        }
        return;
    }
    if (is_sdl_game_window(self) && should_suppress_focus_steal_or_fullscreen_exit()) {
        debuglog_write("WIN", "SUPPRESSED makeKeyAndOrderFront: (active=%d nsActive=%d) win=%p",
                       gAppIsActive ? 1 : 0, (NSApp && [NSApp isActive]) ? 1 : 0, (__bridge void *)self);
        return;
    }
    if (is_sdl_game_window(self) && !gModeTransitionInProgress && !gInFullscreenTransition) {
        NSWindow *win = (NSWindow *)self;
        BOOL inSpace = ((win.styleMask & NSWindowStyleMaskFullScreen) != 0);
        BOOL userDragging = (gWindowedModeActive && ([NSEvent pressedMouseButtons] != 0 || gUserWindowMoveInProgress));
        if (!userDragging && !inSpace && win.frame.size.width >= 640.0 && win.frame.size.height >= 480.0) {
            enforce_primary_window_borderless_fullscreen(win, "makeKeyAndOrderFront");
        }
    }
    if (gOrigMakeKeyAndOrderFrontIMP) {
        typedef void (*Fn)(id, SEL, id);
        ((Fn)gOrigMakeKeyAndOrderFrontIMP)(self, _cmd, sender);
    }
}

static void swizzled_orderFrontRegardless(id self, SEL _cmd) {
    if (is_secondary_orphan_game_window(self)) {
        neutralize_single_orphan_window((NSWindow *)self);
        debuglog_write("WIN", "SUPPRESSED orphan orderFrontRegardless win=%p", (__bridge void *)self);
        return;
    }
    if (is_sdl_game_window(self) && should_suppress_focus_steal_or_fullscreen_exit()) {
        debuglog_write("WIN", "SUPPRESSED orderFrontRegardless (active=%d nsActive=%d) win=%p",
                       gAppIsActive ? 1 : 0, (NSApp && [NSApp isActive]) ? 1 : 0, (__bridge void *)self);
        return;
    }
    if (is_sdl_game_window(self) && !gModeTransitionInProgress && !gInFullscreenTransition) {
        NSWindow *win = (NSWindow *)self;
        BOOL inSpace = ((win.styleMask & NSWindowStyleMaskFullScreen) != 0);
        BOOL userDragging = (gWindowedModeActive && ([NSEvent pressedMouseButtons] != 0 || gUserWindowMoveInProgress));
        if (!userDragging && !inSpace && win.frame.size.width >= 640.0 && win.frame.size.height >= 480.0) {
            enforce_primary_window_borderless_fullscreen(win, "orderFrontRegardless");
        }
    }
    if (gOrigOrderFrontRegardlessIMP) {
        typedef void (*Fn)(id, SEL);
        ((Fn)gOrigOrderFrontRegardlessIMP)(self, _cmd);
    }
}

static BOOL swizzled_canBecomeKeyWindow(id self, SEL _cmd) {
    if (is_secondary_orphan_game_window(self)) {
        return NO;
    }
    if (gOrigCanBecomeKeyWindowIMP) {
        typedef BOOL (*Fn)(id, SEL);
        return ((Fn)gOrigCanBecomeKeyWindowIMP)(self, _cmd);
    }
    return YES;
}

static BOOL swizzled_canBecomeMainWindow(id self, SEL _cmd) {
    if (is_secondary_orphan_game_window(self)) {
        return NO;
    }
    if (gOrigCanBecomeMainWindowIMP) {
        typedef BOOL (*Fn)(id, SEL);
        return ((Fn)gOrigCanBecomeMainWindowIMP)(self, _cmd);
    }
    return YES;
}

static void swizzled_focusSomeWindow(id self, SEL _cmd, NSNotification *notification) {
    if (gPrimaryFullscreenWindow) {
        neutralize_secondary_orphan_windows(gPrimaryFullscreenWindow);
        debuglog_write("WIN", "focusSomeWindow: redirected to primary fullscreen win=%p (isKey=%d)",
                       (__bridge void *)gPrimaryFullscreenWindow,
                       [gPrimaryFullscreenWindow isKeyWindow] ? 1 : 0);
        if (![gPrimaryFullscreenWindow isKeyWindow] && gOrigMakeKeyAndOrderFrontIMP) {
            typedef void (*Fn)(id, SEL, id);
            ((Fn)gOrigMakeKeyAndOrderFrontIMP)(gPrimaryFullscreenWindow,
                                               @selector(makeKeyAndOrderFront:),
                                               nil);
        }
        return;
    }
    if (gOrigFocusSomeWindowIMP) {
        typedef void (*Fn)(id, SEL, NSNotification *);
        ((Fn)gOrigFocusSomeWindowIMP)(self, _cmd, notification);
    }
}

static void swizzled_activateIgnoringOtherApps(id self, SEL _cmd, BOOL flag) {
    if (flag && !gAllowExplicitSpaceReactivation && gAppHasActivatedOnce &&
        (!gAppIsActive || (gLastResignTimestamp > 0.0 && (CFAbsoluteTimeGetCurrent() - gLastResignTimestamp) < 2.0))) {
        CFAbsoluteTime dt = (gLastResignTimestamp > 0.0) ? (CFAbsoluteTimeGetCurrent() - gLastResignTimestamp) : -1.0;
        debuglog_write("WIN", "SUPPRESSED activateIgnoringOtherApps:YES (active=%d dt=%.3fs)",
                       gAppIsActive ? 1 : 0, dt);
        return;
    }
    if (gOrigActivateIgnoringOtherAppsIMP) {
        typedef void (*Fn)(id, SEL, BOOL);
        ((Fn)gOrigActivateIgnoringOtherAppsIMP)(self, _cmd, flag);
    }
}

static BOOL is_main_sized_sdl_window(NSWindow *win, NSRect rect) {
    if (!win || is_secondary_orphan_game_window(win)) {
        return NO;
    }
    if (gPrimaryFullscreenWindow && win == gPrimaryFullscreenWindow) {
        return YES;
    }
    if (rect.size.width >= 640.0 && rect.size.height >= 480.0) {
        return YES;
    }
    NSRect curF = win.frame;
    if (curF.size.width >= 640.0 && curF.size.height >= 480.0) {
        return YES;
    }
    return NO;
}

static NSWindowCollectionBehavior sanitize_mission_control_collection_behavior(NSWindowCollectionBehavior behavior) {
    /* Standard Mission Control & native macOS Fullscreen Space behavior:
       Managed | ParticipatesInCycle | FullScreenPrimary (NEVER FullScreenNone, which broke SDL2's
       setFullscreenSpace: and caused a 37.5s 3x10,000-iteration spin-lock on launch + grayed green button). */
    NSWindowCollectionBehavior forbidden = (NSWindowCollectionBehaviorStationary |
                                            NSWindowCollectionBehaviorTransient |
                                            NSWindowCollectionBehaviorIgnoresCycle |
                                            NSWindowCollectionBehaviorFullScreenAuxiliary |
                                            NSWindowCollectionBehaviorFullScreenNone);
    NSWindowCollectionBehavior clean = (behavior & ~forbidden);
    clean |= (NSWindowCollectionBehaviorManaged |
              NSWindowCollectionBehaviorParticipatesInCycle |
              NSWindowCollectionBehaviorFullScreenPrimary);
    return clean;
}

static void swizzled_sdlSetStyleMask(id self, SEL _cmd, NSWindowStyleMask styleMask) {
    NSWindow *win = (NSWindow *)self;
    if (!win || ![win delegate]) {
        if (gOrigSDLSetStyleMaskIMP) {
            typedef void (*Fn)(id, SEL, NSWindowStyleMask);
            ((Fn)gOrigSDLSetStyleMaskIMP)(self, _cmd, styleMask);
        }
        return;
    }
    NSWindowStyleMask cleanMask = (gModeTransitionInProgress || gInFullscreenTransition ||
                                   is_secondary_orphan_game_window(win))
        ? styleMask
        : sanitize_sdl_style_mask(styleMask);
    if (cleanMask != styleMask) {
        debuglog_write("WIN", "SDLWindow setStyleMask: sanitized 0x%lx -> 0x%lx win=%p",
                       (unsigned long)styleMask, (unsigned long)cleanMask, (__bridge void *)win);
    }
    if (gOrigSDLSetStyleMaskIMP) {
        typedef void (*Fn)(id, SEL, NSWindowStyleMask);
        ((Fn)gOrigSDLSetStyleMaskIMP)(self, _cmd, cleanMask);
    }
    if (!is_secondary_orphan_game_window(win)) {
        ensure_sdl_responder_chain(win, "swizzled_sdlSetStyleMask");
    }
}

static void swizzled_sdlSetLevel(id self, SEL _cmd, NSWindowLevel level) {
    NSWindow *win = (NSWindow *)self;
    if (!win || ![win delegate]) {
        if (gOrigSDLSetLevelIMP) {
            typedef void (*Fn)(id, SEL, NSWindowLevel);
            ((Fn)gOrigSDLSetLevelIMP)(self, _cmd, level);
        }
        return;
    }
    NSWindowLevel cleanLevel = level;
    if (!is_secondary_orphan_game_window(win) && is_main_sized_sdl_window(win, win.frame)) {
        cleanLevel = NSNormalWindowLevel;
    }
    if (cleanLevel != level) {
        debuglog_write("WIN", "SDLWindow setLevel: clamped %ld -> NSNormalWindowLevel win=%p",
                       (long)level, (__bridge void *)win);
    }
    if (gOrigSDLSetLevelIMP) {
        typedef void (*Fn)(id, SEL, NSWindowLevel);
        ((Fn)gOrigSDLSetLevelIMP)(self, _cmd, cleanLevel);
    }
}

static void swizzled_sdlSetCollectionBehavior(id self, SEL _cmd, NSWindowCollectionBehavior behavior) {
    NSWindow *win = (NSWindow *)self;
    if (!win || ![win delegate]) {
        if (gOrigSDLSetCollectionBehaviorIMP) {
            typedef void (*Fn)(id, SEL, NSWindowCollectionBehavior);
            ((Fn)gOrigSDLSetCollectionBehaviorIMP)(self, _cmd, behavior);
        }
        return;
    }
    NSWindowCollectionBehavior cleanBehavior = is_secondary_orphan_game_window(win)
        ? behavior
        : sanitize_mission_control_collection_behavior(behavior);
    if (cleanBehavior != behavior) {
        debuglog_write("WIN", "SDLWindow setCollectionBehavior: 0x%lx -> 0x%lx win=%p",
                       (unsigned long)behavior, (unsigned long)cleanBehavior, (__bridge void *)win);
    }
    if (gOrigSDLSetCollectionBehaviorIMP) {
        typedef void (*Fn)(id, SEL, NSWindowCollectionBehavior);
        ((Fn)gOrigSDLSetCollectionBehaviorIMP)(self, _cmd, cleanBehavior);
    }
}

static NSRect swizzled_sdlConstrainFrameRect(id self, SEL _cmd, NSRect frameRect, NSScreen *screen) {
    NSWindow *win = (NSWindow *)self;
    if (!win || ![win delegate]) {
        if (gOrigSDLConstrainFrameRectIMP) {
            typedef NSRect (*Fn)(id, SEL, NSRect, NSScreen *);
            return ((Fn)gOrigSDLConstrainFrameRectIMP)(self, _cmd, frameRect, screen);
        }
        return frameRect;
    }
    BOOL inSpace = ((win.styleMask & NSWindowStyleMaskFullScreen) != 0);
    if (inSpace) {
        /* Never let Aspyr's Display-0 constrainFrameRect:toScreen: (0x100101050) pull a Fullscreen Space off a secondary monitor. */
        return frameRect;
    }
    if (gWindowedModeActive || gInFullscreenTransition || gHasExitFullscreenTarget) {
        /* Bypass Aspyr's hardcoded SDL_GetDisplayBounds(0) clamp (0x100101050) BOTH during steady
           windowed drags AND during native Fullscreen Space exit animations (where fs=0, style=0x8,
           and gInFullscreenTransition=1 used to fall through and bounce TV windows to x=288 on screens[0]). */
        NSRect r = frameRect;
        NSArray<NSScreen *> *screens = ([NSThread isMainThread] && NSApp != nil) ? [NSScreen screens] : nil;
        NSScreen *exitScr = resolve_active_exit_fullscreen_target_screen();
        NSScreen *containingScreen = nil;
        BOOL intersectsAnyScreen = NO;
        if (screens && [screens count] > 0 && r.size.width >= 1.0 && r.size.height >= 1.0) {
            NSPoint center = NSMakePoint(NSMidX(r), NSMidY(r));
            for (NSScreen *s in screens) {
                if (NSPointInRect(center, s.frame)) {
                    containingScreen = s;
                    intersectsAnyScreen = YES;
                    break;
                }
                if (NSIntersectsRect(r, s.frame)) {
                    intersectsAnyScreen = YES;
                }
            }
        }
        if (exitScr && screens && [screens count] > 1 && containingScreen && containingScreen != exitScr &&
            gExitFullscreenTargetFrame.size.width >= 640.0 && gExitFullscreenTargetFrame.size.height >= 480.0) {
            /* AppKit tried to bounce an exiting multi-monitor Fullscreen Space back onto screens[0]:
               redirect straight onto the screen where the Space was exited. */
            debuglog_write("WIN", "constrainFrameRect kept exiting Space on origin screen: %.0fx%.0f@(%.0f,%.0f) -> %.0fx%.0f@(%.0f,%.0f)",
                           r.size.width, r.size.height, r.origin.x, r.origin.y,
                           gExitFullscreenTargetFrame.size.width, gExitFullscreenTargetFrame.size.height,
                           gExitFullscreenTargetFrame.origin.x, gExitFullscreenTargetFrame.origin.y);
            return gExitFullscreenTargetFrame;
        }
        NSScreen *targetScreen = containingScreen ?: (exitScr ?: resolve_screen_for_rect(r, screen ?: win.screen));
        if (containingScreen || intersectsAnyScreen) {
            if (targetScreen) {
                NSRect vf = targetScreen.visibleFrame;
                if (vf.size.height >= 200.0) {
                    CGFloat maxTop = vf.origin.y + vf.size.height;
                    if (NSMaxY(r) > maxTop) {
                        r.origin.y = maxTop - r.size.height;
                    }
                    if (NSMaxY(r) < vf.origin.y + 40.0) {
                        r.origin.y = vf.origin.y + 40.0 - r.size.height;
                    }
                }
            }
            return r;
        }
        if (screen != nil && targetScreen != nil) {
            /* Window is completely off all connected screens (e.g. external monitor unplugged):
               delegate to AppKit's NSWindow superclass on targetScreen so it remains reachable. */
            IMP superConstrainIMP = [NSWindow instanceMethodForSelector:@selector(constrainFrameRect:toScreen:)];
            if (superConstrainIMP) {
                typedef NSRect (*SuperFn)(id, SEL, NSRect, NSScreen *);
                return ((SuperFn)superConstrainIMP)(self, _cmd, r, targetScreen);
            }
        }
        return r;
    }
    if (!gWindowedModeActive && !inSpace && !gInFullscreenTransition &&
        gHasCompletedFirstWindowShow && is_main_sized_sdl_window(win, frameRect)) {
        return (gNotchFitInProgress || gModeTransitionInProgress) ? frameRect : compute_primary_game_frame(win);
    }
    if (gOrigSDLConstrainFrameRectIMP) {
        typedef NSRect (*Fn)(id, SEL, NSRect, NSScreen *);
        return ((Fn)gOrigSDLConstrainFrameRectIMP)(self, _cmd, frameRect, screen);
    }
    return frameRect;
}

static void sync_content_view_to_window_bounds(NSWindow *win, NSRect targetFrame) {
    if (!win || !win.contentView) {
        return;
    }
    NSRect bounds;
    if (!gWindowedModeActive && (win.styleMask & NSWindowStyleMaskTitled) == 0) {
        bounds = NSMakeRect(0.0, 0.0, targetFrame.size.width, targetFrame.size.height);
    } else {
        NSRect contentRect = [win contentRectForFrameRect:win.frame];
        if (contentRect.size.width < 1.0 || contentRect.size.height < 1.0) {
            contentRect = [win contentRectForFrameRect:targetFrame];
        }
        bounds = NSMakeRect(0.0, 0.0, contentRect.size.width, contentRect.size.height);
    }
    if (!NSEqualRects(win.contentView.frame, bounds)) {
        [win.contentView setFrame:bounds];
    }
}

static void swizzled_sdlSetFrameOrigin(id self, SEL _cmd, NSPoint pt) {
    NSWindow *win = (NSWindow *)self;
    if (!win || ![win delegate]) {
        /* Early -[NSWindow initWithContentRect:...] -> _fromScreenCommonCode: -> setFrameOrigin:
           before SDL2 attaches Cocoa_WindowListener / driverdata: forward directly to original IMP. */
        if (gOrigSDLSetFrameOriginIMP) {
            typedef void (*Fn)(id, SEL, NSPoint);
            ((Fn)gOrigSDLSetFrameOriginIMP)(self, _cmd, pt);
        }
        return;
    }
    BOOL inSpace = ((win.styleMask & NSWindowStyleMaskFullScreen) != 0);
    if (!gNotchFitInProgress && !gModeTransitionInProgress && is_main_sized_sdl_window(win, win.frame)) {
        if (!gWindowedModeActive && (inSpace || gInFullscreenTransition)) {
            NSRect expectedSpace = compute_expected_fullscreen_space_frame(win);
            if (fabs(pt.x - expectedSpace.origin.x) > 4.0 || fabs(pt.y - expectedSpace.origin.y) > 4.0) {
                debuglog_write("WIN", "Blocked stale setFrameOrigin:(%.0f,%.0f) during/in Fullscreen Space",
                               pt.x, pt.y);
                return;
            }
        }
        if (!gInFullscreenTransition && gWindowedModeActive) {
            /* Never block user/AppKit titlebar drags; only filter programmatic SDL resets to exact (0,0)
               when no mouse button is held and no manual move is in progress. */
            BOOL isProgrammaticOriginReset = (fabs(pt.x) <= 1.0 && fabs(pt.y) <= 1.0);
            if (isProgrammaticOriginReset && [NSEvent pressedMouseButtons] == 0 && !gUserWindowMoveInProgress) {
                debuglog_write("WIN", "Blocked programmatic SDLWindow setFrameOrigin:(%.0f,%.0f) in windowed mode",
                               pt.x, pt.y);
                return;
            }
        }
    }
    if (gOrigSDLSetFrameOriginIMP) {
        typedef void (*Fn)(id, SEL, NSPoint);
        ((Fn)gOrigSDLSetFrameOriginIMP)(self, _cmd, pt);
    }
    if (is_sdl_window_fully_attached(win) && is_sdl_game_window(win) && !is_secondary_orphan_game_window(win)) {
        sync_sdl_window_origin_to_frame(win, "setFrameOrigin");
    }
}

static void swizzled_sdlSetFrameTopLeftPoint(id self, SEL _cmd, NSPoint pt) {
    NSWindow *win = (NSWindow *)self;
    if (!win || ![win delegate]) {
        if (gOrigSDLSetFrameTopLeftPointIMP) {
            typedef void (*Fn)(id, SEL, NSPoint);
            ((Fn)gOrigSDLSetFrameTopLeftPointIMP)(self, _cmd, pt);
        }
        return;
    }
    BOOL inSpace = ((win.styleMask & NSWindowStyleMaskFullScreen) != 0);
    if (!gNotchFitInProgress && !gModeTransitionInProgress && is_main_sized_sdl_window(win, win.frame)) {
        if (!gWindowedModeActive && (inSpace || gInFullscreenTransition)) {
            NSRect expectedSpace = compute_expected_fullscreen_space_frame(win);
            CGFloat expectedTop = expectedSpace.origin.y + expectedSpace.size.height;
            if (fabs(pt.x - expectedSpace.origin.x) > 4.0 || fabs(pt.y - expectedTop) > 4.0) {
                debuglog_write("WIN", "Blocked stale setFrameTopLeftPoint:(%.0f,%.0f) during/in Fullscreen Space",
                               pt.x, pt.y);
                return;
            }
        }
        if (!gInFullscreenTransition && gWindowedModeActive) {
            BOOL isProgrammaticOriginReset = (fabs(pt.x) <= 1.0 &&
                                              (fabs(pt.y) <= 1.0 ||
                                               fabs(pt.y - (CGFloat)gRawHardwareScreenHeight) <= 2.0 ||
                                               fabs(pt.y - (CGFloat)gNativeScreenHeight) <= 2.0));
            if (isProgrammaticOriginReset && [NSEvent pressedMouseButtons] == 0 && !gUserWindowMoveInProgress) {
                debuglog_write("WIN", "Blocked programmatic SDLWindow setFrameTopLeftPoint:(%.0f,%.0f) in windowed mode",
                               pt.x, pt.y);
                return;
            }
        }
    }
    if (gOrigSDLSetFrameTopLeftPointIMP) {
        typedef void (*Fn)(id, SEL, NSPoint);
        ((Fn)gOrigSDLSetFrameTopLeftPointIMP)(self, _cmd, pt);
    }
    if (is_sdl_window_fully_attached(win) && is_sdl_game_window(win) && !is_secondary_orphan_game_window(win)) {
        sync_sdl_window_origin_to_frame(win, "setFrameTopLeftPoint");
    }
}

static BOOL should_clamp_stale_windowed_frame_during_fullscreen(NSWindow *win, NSRect frameRect, NSRect *outFullSpace) {
    if (!win || gWindowedModeActive || gNotchFitInProgress || gModeTransitionInProgress ||
        !is_main_sized_sdl_window(win, frameRect)) {
        return NO;
    }
    if (!gInFullscreenTransition && NSApp && ![NSApp isActive]) {
        /* Never fight Mission Control while relocating a Fullscreen Space across monitors (active=0). */
        return NO;
    }
    BOOL inSpace = ((win.styleMask & NSWindowStyleMaskFullScreen) != 0);
    if (!inSpace && !gInFullscreenTransition) {
        return NO;
    }
    NSRect expectedSpace = compute_expected_fullscreen_space_frame(win);
    if (expectedSpace.size.width < 640.0 || expectedSpace.size.height < 480.0) {
        return NO;
    }
    BOOL frameMismatched = (fabs(frameRect.size.width - expectedSpace.size.width) > 20.0 ||
                            fabs(frameRect.size.height - expectedSpace.size.height) > 40.0);
    if (!frameMismatched) {
        return NO;
    }
    /* Already in Space OR window had already expanded for Space transition -> enforce exact aspect-fitted Space rect */
    BOOL curAlreadyFull = (win.frame.size.width >= expectedSpace.size.width - 4.0 &&
                           win.frame.size.height >= expectedSpace.size.height - 4.0);
    if (inSpace || curAlreadyFull) {
        if (outFullSpace) {
            *outFullSpace = expectedSpace;
        }
        return YES;
    }
    return NO;
}

static NSRect compute_anti_tiling_windowed_frame(NSWindow *win, NSRect requestedRect, BOOL *outAcceptedAsIs) {
    if (outAcceptedAsIs) {
        *outAcceptedAsIs = NO;
    }
    NSScreen *targetScreen = resolve_screen_for_rect(requestedRect, win ? win.screen : nil);
    NSInteger compatW = (gTargetWindowWidth >= 640) ? gTargetWindowWidth : 1440;
    NSInteger compatH = (gTargetWindowHeight >= 480) ? gTargetWindowHeight : 900;
    if ([NSEvent pressedMouseButtons] == 0 && !gUserWindowMoveInProgress) {
        NSScreen *exitScr = resolve_active_exit_fullscreen_target_screen();
        NSArray<NSScreen *> *screens = ([NSThread isMainThread] && NSApp != nil) ? [NSScreen screens] : nil;
        if (exitScr && screens && [screens count] > 1 && targetScreen != exitScr) {
            resolve_compatible_windowed_size_on_screen(exitScr, &compatW, &compatH);
            return compute_windowed_game_frame_on_screen(win, exitScr, compatW, compatH, YES);
        }
    }
    resolve_compatible_windowed_size_on_screen(targetScreen, &compatW, &compatH);
    NSRect expectedOuter = [win frameRectForContentRect:NSMakeRect(0.0, 0.0, (CGFloat)compatW, (CGFloat)compatH)];
    BOOL sizeMatches = (fabs(requestedRect.size.width - expectedOuter.size.width) <= 2.0 &&
                        fabs(requestedRect.size.height - expectedOuter.size.height) <= 2.0);
    BOOL isExactZeroOrigin = (fabs(requestedRect.origin.x) <= 1.0 && fabs(requestedRect.origin.y) <= 1.0);
    if (sizeMatches && !isExactZeroOrigin) {
        if (outAcceptedAsIs) {
            *outAcceptedAsIs = YES;
        }
        return requestedRect;
    }
    /* Anti Window-Tiling ping-pong: pin size to selected preset while keeping window on targetScreen
       (e.g. TV at x >= 1800) instead of letting macOS Tiling stretch to visibleFrame or snapping to screens[0]. */
    NSRect vf = targetScreen ? targetScreen.visibleFrame : NSMakeRect(0.0, 0.0, (CGFloat)gNativeScreenWidth, (CGFloat)gNativeScreenHeight);
    NSRect result = expectedOuter;
    if (isExactZeroOrigin || requestedRect.size.width < 1.0 || requestedRect.size.height < 1.0) {
        return compute_windowed_game_frame_on_screen(win, targetScreen, compatW, compatH, YES);
    }
    /* Preserve horizontal center of requestedRect inside targetScreen, clamp cleanly inside targetScreen.visibleFrame */
    result.origin.x = floor(NSMidX(requestedRect) - result.size.width * 0.5);
    result.origin.y = floor(NSMaxY(requestedRect) - result.size.height);
    CGFloat maxTop = vf.origin.y + vf.size.height;
    CGFloat maxRight = vf.origin.x + vf.size.width;
    if (result.origin.y + result.size.height > maxTop) {
        result.origin.y = maxTop - result.size.height;
    }
    if (result.origin.y < vf.origin.y) {
        result.origin.y = vf.origin.y;
    }
    if (result.origin.x + result.size.width > maxRight) {
        result.origin.x = maxRight - result.size.width;
    }
    if (result.origin.x < vf.origin.x) {
        result.origin.x = vf.origin.x;
    }
    return result;
}

static void swizzled_sdlSetFrameDisplay(id self, SEL _cmd, NSRect frameRect, BOOL flag) {
    NSWindow *win = (NSWindow *)self;
    if (!win || ![win delegate]) {
        if (gOrigSDLSetFrameDisplayIMP) {
            typedef void (*Fn)(id, SEL, NSRect, BOOL);
            ((Fn)gOrigSDLSetFrameDisplayIMP)(self, _cmd, frameRect, flag);
        }
        return;
    }
    NSRect finalRect = frameRect;
    BOOL inSpace = ((win.styleMask & NSWindowStyleMaskFullScreen) != 0);
    NSRect fullSpaceRect = NSZeroRect;
    if (should_clamp_stale_windowed_frame_during_fullscreen(win, frameRect, &fullSpaceRect)) {
        debuglog_write("WIN", "Clamped stale windowed setFrame %.0fx%.0f@(%.0f,%.0f) -> Space %.0fx%.0f@(%.0f,%.0f)",
                       frameRect.size.width, frameRect.size.height, frameRect.origin.x, frameRect.origin.y,
                       fullSpaceRect.size.width, fullSpaceRect.size.height,
                       fullSpaceRect.origin.x, fullSpaceRect.origin.y);
        finalRect = fullSpaceRect;
        if (gOrigSDLSetFrameDisplayIMP) {
            typedef void (*Fn)(id, SEL, NSRect, BOOL);
            gNotchFitInProgress = YES;
            ((Fn)gOrigSDLSetFrameDisplayIMP)(self, _cmd, finalRect, flag);
            gNotchFitInProgress = NO;
        }
        sync_sdl_window_origin_to_frame(win, "clamped-space-setFrame");
        return;
    }
    if (!gNotchFitInProgress && !gModeTransitionInProgress && !gInFullscreenTransition && !inSpace &&
        is_main_sized_sdl_window(win, frameRect)) {
        if (gWindowedModeActive && ([NSEvent pressedMouseButtons] != 0 || gUserWindowMoveInProgress)) {
            BOOL acceptedAsIs = NO;
            NSRect guardedRect = compute_anti_tiling_windowed_frame(win, frameRect, &acceptedAsIs);
            if (acceptedAsIs) {
                /* User live titlebar drag at exact preset size across any screen: pass straight through */
                if (gOrigSDLSetFrameDisplayIMP) {
                    typedef void (*Fn)(id, SEL, NSRect, BOOL);
                    ((Fn)gOrigSDLSetFrameDisplayIMP)(self, _cmd, frameRect, flag);
                }
                sync_sdl_window_origin_to_frame(win, "liveDrag-setFrame");
                return;
            }
            /* macOS Window Tiling tried to inflate size during drag -> pin size on targetScreen, zero ping-pong */
            debuglog_write("WIN", "Neutralized Window Tiling setFrame %.0fx%.0f@(%.0f,%.0f) -> %.0fx%.0f@(%.0f,%.0f)",
                           frameRect.size.width, frameRect.size.height, frameRect.origin.x, frameRect.origin.y,
                           guardedRect.size.width, guardedRect.size.height, guardedRect.origin.x, guardedRect.origin.y);
            gNotchFitInProgress = YES;
            BOOL prevSuppress = gSuppressSDLResizeNotification;
            gSuppressSDLResizeNotification = YES;
            if (gOrigSDLSetFrameDisplayIMP) {
                typedef void (*Fn)(id, SEL, NSRect, BOOL);
                ((Fn)gOrigSDLSetFrameDisplayIMP)(self, _cmd, guardedRect, flag);
            }
            sync_content_view_to_window_bounds(win, guardedRect);
            sync_sdl_window_origin_to_frame(win, "antiTiling-setFrame");
            gSuppressSDLResizeNotification = prevSuppress;
            gNotchFitInProgress = NO;
            return;
        }
        if (!gWindowedModeActive && !gHasCompletedFirstWindowShow) {
            /* Let SDL's initial boot window frame pass cleanly into native Fullscreen Space */
            if (gOrigSDLSetFrameDisplayIMP) {
                typedef void (*Fn)(id, SEL, NSRect, BOOL);
                ((Fn)gOrigSDLSetFrameDisplayIMP)(self, _cmd, frameRect, flag);
            }
            return;
        }
        NSWindowStyleMask curStyle = [win styleMask];
        NSWindowStyleMask cleanStyle = sanitize_sdl_style_mask(curStyle);
        if (cleanStyle != curStyle) {
            gNotchFitInProgress = YES;
            safe_set_sdl_window_style_mask(win, cleanStyle, "swizzled_setFrameDisplay");
            gNotchFitInProgress = NO;
        }
        if (gWindowedModeActive) {
            finalRect = compute_anti_tiling_windowed_frame(win, frameRect, NULL);
        } else {
            finalRect = compute_primary_game_frame(win);
        }
        if (fabs(finalRect.size.width - frameRect.size.width) > 1.0 ||
            fabs(finalRect.size.height - frameRect.size.height) > 1.0 ||
            fabs(finalRect.origin.x - frameRect.origin.x) > 1.0 ||
            fabs(finalRect.origin.y - frameRect.origin.y) > 1.0) {
            debuglog_write("WIN", "SDLWindow setFrame clamped %.0fx%.0f@(%.0f,%.0f) -> %.0fx%.0f@(%.0f,%.0f)",
                           frameRect.size.width, frameRect.size.height, frameRect.origin.x, frameRect.origin.y,
                           finalRect.size.width, finalRect.size.height, finalRect.origin.x, finalRect.origin.y);
        }
        gNotchFitInProgress = YES;
        BOOL prevSuppress = gSuppressSDLResizeNotification;
        gSuppressSDLResizeNotification = YES;
        if (gOrigSDLSetFrameDisplayIMP) {
            typedef void (*Fn)(id, SEL, NSRect, BOOL);
            ((Fn)gOrigSDLSetFrameDisplayIMP)(self, _cmd, finalRect, flag);
        }
        sync_content_view_to_window_bounds(win, finalRect);
        sync_sdl_window_origin_to_frame(win, "clamped-setFrame");
        gSuppressSDLResizeNotification = prevSuppress;
        gNotchFitInProgress = NO;
        return;
    }
    if (gOrigSDLSetFrameDisplayIMP) {
        typedef void (*Fn)(id, SEL, NSRect, BOOL);
        ((Fn)gOrigSDLSetFrameDisplayIMP)(self, _cmd, finalRect, flag);
    }
    if (is_sdl_window_fully_attached(win) && is_sdl_game_window(win) && !is_secondary_orphan_game_window(win)) {
        sync_sdl_window_origin_to_frame(win, "setFrameDisplay");
    }
}

static void swizzled_sdlSetFrameDisplayAnimate(id self, SEL _cmd, NSRect frameRect, BOOL displayFlag, BOOL animateFlag) {
    NSWindow *win = (NSWindow *)self;
    if (!win || ![win delegate]) {
        if (gOrigSDLSetFrameDisplayAnimateIMP) {
            typedef void (*Fn)(id, SEL, NSRect, BOOL, BOOL);
            ((Fn)gOrigSDLSetFrameDisplayAnimateIMP)(self, _cmd, frameRect, displayFlag, animateFlag);
        }
        return;
    }
    NSRect finalRect = frameRect;
    BOOL inSpace = ((win.styleMask & NSWindowStyleMaskFullScreen) != 0);
    NSRect fullSpaceRect = NSZeroRect;
    if (should_clamp_stale_windowed_frame_during_fullscreen(win, frameRect, &fullSpaceRect)) {
        debuglog_write("WIN", "Clamped stale windowed setFrameAnimate %.0fx%.0f@(%.0f,%.0f) -> Space %.0fx%.0f@(%.0f,%.0f)",
                       frameRect.size.width, frameRect.size.height, frameRect.origin.x, frameRect.origin.y,
                       fullSpaceRect.size.width, fullSpaceRect.size.height,
                       fullSpaceRect.origin.x, fullSpaceRect.origin.y);
        finalRect = fullSpaceRect;
        if (gOrigSDLSetFrameDisplayAnimateIMP) {
            typedef void (*Fn)(id, SEL, NSRect, BOOL, BOOL);
            gNotchFitInProgress = YES;
            ((Fn)gOrigSDLSetFrameDisplayAnimateIMP)(self, _cmd, finalRect, displayFlag, NO);
            gNotchFitInProgress = NO;
        }
        sync_sdl_window_origin_to_frame(win, "clamped-setFrameAnimate");
        return;
    }
    if (!gNotchFitInProgress && !gModeTransitionInProgress && !gInFullscreenTransition && !inSpace &&
        is_main_sized_sdl_window(win, frameRect)) {
        if (gWindowedModeActive && ([NSEvent pressedMouseButtons] != 0 || gUserWindowMoveInProgress)) {
            BOOL acceptedAsIs = NO;
            NSRect guardedRect = compute_anti_tiling_windowed_frame(win, frameRect, &acceptedAsIs);
            if (acceptedAsIs) {
                if (gOrigSDLSetFrameDisplayAnimateIMP) {
                    typedef void (*Fn)(id, SEL, NSRect, BOOL, BOOL);
                    ((Fn)gOrigSDLSetFrameDisplayAnimateIMP)(self, _cmd, frameRect, displayFlag, animateFlag);
                }
                sync_sdl_window_origin_to_frame(win, "liveDrag-setFrameAnimate");
                return;
            }
            debuglog_write("WIN", "Neutralized Window Tiling setFrameAnimate %.0fx%.0f@(%.0f,%.0f) -> %.0fx%.0f@(%.0f,%.0f)",
                           frameRect.size.width, frameRect.size.height, frameRect.origin.x, frameRect.origin.y,
                           guardedRect.size.width, guardedRect.size.height, guardedRect.origin.x, guardedRect.origin.y);
            gNotchFitInProgress = YES;
            BOOL prevSuppress = gSuppressSDLResizeNotification;
            gSuppressSDLResizeNotification = YES;
            if (gOrigSDLSetFrameDisplayAnimateIMP) {
                typedef void (*Fn)(id, SEL, NSRect, BOOL, BOOL);
                ((Fn)gOrigSDLSetFrameDisplayAnimateIMP)(self, _cmd, guardedRect, displayFlag, NO);
            }
            sync_content_view_to_window_bounds(win, guardedRect);
            sync_sdl_window_origin_to_frame(win, "antiTiling-setFrameAnimate");
            gSuppressSDLResizeNotification = prevSuppress;
            gNotchFitInProgress = NO;
            return;
        }
        if (!gWindowedModeActive && !gHasCompletedFirstWindowShow) {
            if (gOrigSDLSetFrameDisplayAnimateIMP) {
                typedef void (*Fn)(id, SEL, NSRect, BOOL, BOOL);
                ((Fn)gOrigSDLSetFrameDisplayAnimateIMP)(self, _cmd, frameRect, displayFlag, animateFlag);
            }
            return;
        }
        NSWindowStyleMask curStyle = [win styleMask];
        NSWindowStyleMask cleanStyle = sanitize_sdl_style_mask(curStyle);
        if (cleanStyle != curStyle) {
            gNotchFitInProgress = YES;
            safe_set_sdl_window_style_mask(win, cleanStyle, "swizzled_setFrameDisplayAnimate");
            gNotchFitInProgress = NO;
        }
        if (gWindowedModeActive) {
            finalRect = compute_anti_tiling_windowed_frame(win, frameRect, NULL);
        } else {
            finalRect = compute_primary_game_frame(win);
        }
        gNotchFitInProgress = YES;
        BOOL prevSuppress = gSuppressSDLResizeNotification;
        gSuppressSDLResizeNotification = YES;
        if (gOrigSDLSetFrameDisplayAnimateIMP) {
            typedef void (*Fn)(id, SEL, NSRect, BOOL, BOOL);
            ((Fn)gOrigSDLSetFrameDisplayAnimateIMP)(self, _cmd, finalRect, displayFlag, NO);
        }
        sync_content_view_to_window_bounds(win, finalRect);
        sync_sdl_window_origin_to_frame(win, "clamped-setFrameAnimate");
        gSuppressSDLResizeNotification = prevSuppress;
        gNotchFitInProgress = NO;
        return;
    }
    if (gOrigSDLSetFrameDisplayAnimateIMP) {
        typedef void (*Fn)(id, SEL, NSRect, BOOL, BOOL);
        ((Fn)gOrigSDLSetFrameDisplayAnimateIMP)(self, _cmd, finalRect, displayFlag, animateFlag);
    }
    if (is_sdl_window_fully_attached(win) && is_sdl_game_window(win) && !is_secondary_orphan_game_window(win)) {
        sync_sdl_window_origin_to_frame(win, "setFrameDisplayAnimate");
    }
}

static void swizzled_sdlSetContentSize(id self, SEL _cmd, NSSize newSize) {
    NSWindow *win = (NSWindow *)self;
    if (!win || ![win delegate]) {
        if (gOrigSDLSetContentSizeIMP) {
            typedef void (*Fn)(id, SEL, NSSize);
            ((Fn)gOrigSDLSetContentSizeIMP)(self, _cmd, newSize);
        }
        return;
    }
    record_last_hook_state("setContentSize");
    if (!gNotchFitInProgress && !gModeTransitionInProgress &&
        is_main_sized_sdl_window(win, NSMakeRect(0.0, 0.0, newSize.width, newSize.height))) {
        if (newSize.width >= 640.0 && newSize.height >= 480.0) {
            /* Guard against a windowed target-size feedback loop overwriting gEngineFbW/H while
               preserving genuine engine framebuffer changes (e.g. in-game Graphics Options Apply). */
            BOOL matchesReducedWindowedTarget = (gWindowedModeActive &&
                                                 gHasCapturedInitialEngineFb &&
                                                 gTargetWindowWidth >= 640 && gTargetWindowHeight >= 480 &&
                                                 fabs(newSize.width - (CGFloat)gTargetWindowWidth) <= 2.0 &&
                                                 fabs(newSize.height - (CGFloat)gTargetWindowHeight) <= 2.0 &&
                                                 (gLastExposedModeWidth == 0 ||
                                                  fabs(newSize.width - (CGFloat)gLastExposedModeWidth) > 2.0 ||
                                                  fabs(newSize.height - (CGFloat)gLastExposedModeHeight) > 2.0));
            if (!matchesReducedWindowedTarget) {
                gEngineFbW = newSize.width;
                gEngineFbH = newSize.height;
                gHasCapturedInitialEngineFb = YES;
            }
        }
        BOOL inSpace = ((win.styleMask & NSWindowStyleMaskFullScreen) != 0);
        debuglog_write("WIN", "SDLWindow setContentSize:(%.0fx%.0f) engineFb=(%.0fx%.0f) inSpace=%d trans=%d windowed=%d",
                       newSize.width, newSize.height, gEngineFbW, gEngineFbH,
                       inSpace ? 1 : 0, gInFullscreenTransition ? 1 : 0, gWindowedModeActive ? 1 : 0);
        if (inSpace || gInFullscreenTransition || (!gWindowedModeActive && !gHasCompletedFirstWindowShow)) {
            if (!inSpace && !gInFullscreenTransition && gOrigSDLSetContentSizeIMP) {
                typedef void (*Fn)(id, SEL, NSSize);
                ((Fn)gOrigSDLSetContentSizeIMP)(self, _cmd, newSize);
            }
            sync_sdl_window_logical_size_to_engine_fb(win, "setContentSize-fs");
            apply_opengl_surface_backing_size_ex(win, YES);
            return;
        }
        enforce_primary_window_borderless_fullscreen(win, "setContentSize");
        sync_sdl_window_logical_size_to_engine_fb(win, "setContentSize-win");
        apply_opengl_surface_backing_size_ex(win, YES);
        return;
    }
    if (gOrigSDLSetContentSizeIMP) {
        typedef void (*Fn)(id, SEL, NSSize);
        ((Fn)gOrigSDLSetContentSizeIMP)(self, _cmd, newSize);
    }
}

static void swizzled_sdlToggleFullScreen(id self, SEL _cmd, id sender) {
    NSWindow *win = (NSWindow *)self;
    BOOL inSpace = ((win.styleMask & NSWindowStyleMaskFullScreen) != 0);
    if (is_sdl_game_window(win) && !is_secondary_orphan_game_window(win)) {
        bump_display_transition_gen();
        /* Distinguish interactive green-button / Window menu clicks vs programmatic SDL boot calls */
        BOOL isInteractiveUserToggle = (sender != win);
        if (inSpace) {
            gUserRequestedFullscreenExit = YES;
            gWindowedModeActive = YES;
            gForceCenterWindowedFrame = YES;
            if (!is_reduced_target_resolution()) {
                NSInteger defW = 1512, defH = 982;
                resolve_compatible_windowed_size(win, &defW, &defH);
                gTargetWindowWidth = defW;
                gTargetWindowHeight = defH;
            }
            remember_exit_fullscreen_target_screen(win, "sdlToggleFullScreenExit");
        } else {
            gUserRequestedFullscreenEnter = YES;
            gWindowedModeActive = NO;
            clear_exit_fullscreen_target_screen();
            NSWindowCollectionBehavior beh = sanitize_mission_control_collection_behavior(win.collectionBehavior);
            if (gOrigSDLSetCollectionBehaviorIMP && gSDLWindowClass && [win isKindOfClass:gSDLWindowClass]) {
                typedef void (*BehFn)(id, SEL, NSWindowCollectionBehavior);
                ((BehFn)gOrigSDLSetCollectionBehaviorIMP)(win, @selector(setCollectionBehavior:), beh);
            } else {
                [win setCollectionBehavior:beh];
            }
        }
        gInFullscreenTransition = YES;
        update_sims2_display_menu_state();
        debuglog_write("WIN", "SDLWindow toggleFullScreen: sender=%p interactive=%d inSpace=%d -> targetWindowed=%d",
                       (__bridge void *)sender, isInteractiveUserToggle ? 1 : 0,
                       inSpace ? 1 : 0, gWindowedModeActive ? 1 : 0);
    }
    if (gOrigSDLToggleFullScreenIMP) {
        typedef void (*Fn)(id, SEL, id);
        BOOL prevAllow = gAllowResizableForSpaceToggle;
        gAllowResizableForSpaceToggle = YES;
        ((Fn)gOrigSDLToggleFullScreenIMP)(self, _cmd, sender);
        gAllowResizableForSpaceToggle = prevAllow;
    }
}

static IMP swizzle_instance_method(Class cls, SEL sel, IMP newIMP) {
    if (!cls) {
        return NULL;
    }
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        return NULL;
    }
    return method_setImplementation(m, newIMP);
}

static void swizzle_target_class_method(Class targetCls, SEL sel, IMP newIMP, IMP *outOrigIMP) {
    if (!targetCls || !sel || !newIMP) {
        return;
    }
    Method m = class_getInstanceMethod(targetCls, sel);
    if (!m) {
        return;
    }
    const char *types = method_getTypeEncoding(m);
    IMP curIMP = method_getImplementation(m);
    if (class_addMethod(targetCls, sel, newIMP, types)) {
        if (outOrigIMP) {
            *outOrigIMP = curIMP;
        }
    } else {
        IMP prev = method_setImplementation(m, newIMP);
        if (outOrigIMP) {
            *outOrigIMP = prev;
        }
    }
}

/*
 * Autonomous minimal hardware display-mode filter (CGDisplayCopyAllDisplayModes):
 * returns ONLY the single optimal real CoreGraphics 32-bit ARGB mode closest to
 * 60 Hz (active logical desktop mode when <= 2560x1600, else best <= 2560x1600
 * matching aspect ratio) so the menu has zero bloated/broken intermediate modes.
 */
static BOOL is_32bit_argb_pixel_encoding(CGDisplayModeRef mode) {
    if (!mode) {
        return NO;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CFStringRef enc = CGDisplayModeCopyPixelEncoding(mode);
#pragma clang diagnostic pop
    if (!enc) {
        return NO;
    }
    BOOL ok = (CFStringCompare(enc, CFSTR("--------RRRRRRRRGGGGGGGGBBBBBBBB"),
                               kCFCompareCaseInsensitive) == kCFCompareEqualTo);
    CFRelease(enc);
    return ok;
}

static BOOL is_better_display_mode(CGDisplayModeRef candidate,
                                    CGDisplayModeRef best,
                                    size_t curW,
                                    size_t curH,
                                    BOOL requireExactDesktop) {
    if (!candidate || !is_32bit_argb_pixel_encoding(candidate)) {
        return NO;
    }
    size_t w = CGDisplayModeGetWidth(candidate);
    size_t h = CGDisplayModeGetHeight(candidate);
    if (w < 800 || h < 600 || w <= h || w > 2560 || h > 1600) {
        return NO;
    }
    if (requireExactDesktop && (w != curW || h != curH)) {
        return NO;
    }
    if (!best) {
        return YES;
    }

    size_t bw = CGDisplayModeGetWidth(best);
    size_t bh = CGDisplayModeGetHeight(best);
    if (!requireExactDesktop && curW > 0 && curH > 0) {
        double targetAspect = (double)curW / (double)curH;
        double cAspectDiff = fabs(((double)w / (double)h) - targetAspect);
        double bAspectDiff = fabs(((double)bw / (double)bh) - targetAspect);
        BOOL cAspectOk = (cAspectDiff <= 0.03);
        BOOL bAspectOk = (bAspectDiff <= 0.03);
        if (cAspectOk != bAspectOk) {
            return cAspectOk;
        }
        size_t cArea = w * h;
        size_t bArea = bw * bh;
        if (cArea != bArea) {
            return cArea > bArea;
        }
    }

    double cHz = CGDisplayModeGetRefreshRate(candidate);
    double bHz = CGDisplayModeGetRefreshRate(best);
    double cDelta = fabs((cHz > 0.1 ? cHz : 60.0) - 60.0);
    double bDelta = fabs((bHz > 0.1 ? bHz : 60.0) - 60.0);
    if (cDelta < bDelta - 0.5) {
        return YES;
    }
    if (bDelta < cDelta - 0.5) {
        return NO;
    }
    BOOL c1x = (CGDisplayModeGetPixelWidth(candidate) == w && CGDisplayModeGetPixelHeight(candidate) == h);
    BOOL b1x = (CGDisplayModeGetPixelWidth(best) == bw && CGDisplayModeGetPixelHeight(best) == bh);
    return (c1x && !b1x);
}

static CGDisplayModeRef find_optimal_mode_in_array(CFArrayRef modes,
                                                   size_t curW,
                                                   size_t curH,
                                                   BOOL requireExactDesktop) {
    if (!modes) {
        return NULL;
    }
    CFIndex count = CFArrayGetCount(modes);
    CGDisplayModeRef best = NULL;
    for (CFIndex i = 0; i < count; i++) {
        CGDisplayModeRef m = (CGDisplayModeRef)CFArrayGetValueAtIndex(modes, i);
        if (is_better_display_mode(m, best, curW, curH, requireExactDesktop)) {
            best = m;
        }
    }
    return best;
}

static CGDisplayModeRef select_real_display_mode_for_target(CGDirectDisplayID display,
                                                            CFArrayRef initialModes,
                                                            size_t targetW,
                                                            size_t targetH,
                                                            BOOL requireExact) {
    CGDisplayModeRef selected = find_optimal_mode_in_array(initialModes, targetW, targetH, requireExact);
    if (selected) {
        CGDisplayModeRetain(selected);
        return selected;
    }
    CFMutableDictionaryRef dupOpts = CFDictionaryCreateMutable(kCFAllocatorDefault, 1,
                                                               &kCFTypeDictionaryKeyCallBacks,
                                                               &kCFTypeDictionaryValueCallBacks);
    if (!dupOpts) {
        return NULL;
    }
    CFDictionarySetValue(dupOpts, kCGDisplayShowDuplicateLowResolutionModes, kCFBooleanTrue);
    CFArrayRef extraDupModes = CGDisplayCopyAllDisplayModes(display, dupOpts);
    CFRelease(dupOpts);
    if (!extraDupModes) {
        return NULL;
    }
    selected = find_optimal_mode_in_array(extraDupModes, targetW, targetH, requireExact);
    if (selected) {
        CGDisplayModeRetain(selected);
    }
    CFRelease(extraDupModes);
    return selected;
}

static size_t hook_CGDisplayModeGetHeight(CGDisplayModeRef mode) {
    if (!mode) {
        return 0;
    }
    if (gPrimaryNotchTopInset == 0 && [NSThread isMainThread] && NSApp != nil) {
        detect_native_screen_resolution(nil);
    }
    size_t w = CGDisplayModeGetWidth(mode);
    size_t h = CGDisplayModeGetHeight(mode);
    if (gPrimaryNotchTopInset > 0 &&
        (NSInteger)w == gPrimaryRawScreenWidth &&
        (NSInteger)h == gPrimaryRawScreenHeight) {
        return (size_t)gPrimaryNativeScreenHeight;
    }
    return h;
}

static size_t hook_CGDisplayModeGetPixelHeight(CGDisplayModeRef mode) {
    if (!mode) {
        return 0;
    }
    if (gPrimaryNotchTopInset == 0 && [NSThread isMainThread] && NSApp != nil) {
        detect_native_screen_resolution(nil);
    }
    size_t w = CGDisplayModeGetWidth(mode);
    size_t h = CGDisplayModeGetHeight(mode);
    size_t ph = CGDisplayModeGetPixelHeight(mode);
    if (gPrimaryNotchTopInset > 0 && h > 0 &&
        (NSInteger)w == gPrimaryRawScreenWidth &&
        (NSInteger)h == gPrimaryRawScreenHeight) {
        if (ph == h) {
            return (size_t)gPrimaryNativeScreenHeight;
        }
        return (size_t)llround((double)gPrimaryNativeScreenHeight * ((double)ph / (double)h));
    }
    return ph;
}

static size_t hook_CGDisplayPixelsHigh(CGDirectDisplayID display) {
    size_t h = CGDisplayPixelsHigh(display);
    if (display == CGMainDisplayID()) {
        if (gPrimaryNotchTopInset == 0 && [NSThread isMainThread] && NSApp != nil) {
            detect_native_screen_resolution(nil);
        }
        if (gPrimaryNotchTopInset > 0 && (NSInteger)h == gPrimaryRawScreenHeight) {
            return (size_t)gPrimaryNativeScreenHeight;
        }
    }
    return h;
}

static CGRect hook_CGDisplayBounds(CGDirectDisplayID display) {
    CGRect r = CGDisplayBounds(display);
    if (display == CGMainDisplayID()) {
        if (gPrimaryNotchTopInset == 0 && [NSThread isMainThread] && NSApp != nil) {
            detect_native_screen_resolution(nil);
        }
        if (gPrimaryNotchTopInset > 0 &&
            (NSInteger)llround(r.size.width) == gPrimaryRawScreenWidth &&
            (NSInteger)llround(r.size.height) == gPrimaryRawScreenHeight) {
            r.size.height = (CGFloat)gPrimaryNativeScreenHeight;
        }
    }
    return r;
}

static CGDisplayModeRef hook_CGDisplayCopyDisplayMode(CGDirectDisplayID display) {
    if ([NSThread isMainThread] && NSApp != nil) {
        detect_native_screen_resolution(nil);
    }
    return CGDisplayCopyDisplayMode(display);
}

static CFArrayRef hook_CGDisplayCopyAllDisplayModes(CGDirectDisplayID display,
                                                    CFDictionaryRef options) {
    if ([NSThread isMainThread] && NSApp != nil) {
        detect_native_screen_resolution(nil);
    }
    CFArrayRef realModes = CGDisplayCopyAllDisplayModes(display, options);
    if (!realModes) {
        debuglog_write("DISPLAY", "CGDisplayCopyAllDisplayModes(display=%u) -> NULL", (unsigned)display);
        return NULL;
    }

    size_t curW = 0, curH = 0;
    CGDisplayModeRef cur = CGDisplayCopyDisplayMode(display);
    if (cur) {
        curW = CGDisplayModeGetWidth(cur);
        curH = CGDisplayModeGetHeight(cur);
        CGDisplayModeRelease(cur);
    }

    BOOL desktopWithinCap = (curW >= 800 && curH >= 600 && curW > curH && curW <= 2560 && curH <= 1600);
    CGDisplayModeRef selectedRetained = NULL;

    /* Expose ONLY the active screen's native usable resolution (below notch when safeAreaInsets.top > 0,
       full native when safeAreaInsets.top == 0, capped <= 2560x1600 for 4K/5K external monitors). */
    if (desktopWithinCap) {
        selectedRetained = select_real_display_mode_for_target(display, realModes, curW, curH, YES);
    }
    if (!selectedRetained) {
        selectedRetained = select_real_display_mode_for_target(display, realModes, curW, curH, NO);
    }

    CFIndex realCount = CFArrayGetCount(realModes);
    if (!selectedRetained) {
        debuglog_write("DISPLAY", "filter kept 0/%ld modes -> returning unfiltered macOS list", (long)realCount);
        return realModes;
    }

    CFMutableArrayRef result = CFArrayCreateMutable(kCFAllocatorDefault, 1, &kCFTypeArrayCallBacks);
    if (!result) {
        CGDisplayModeRelease(selectedRetained);
        return realModes;
    }
    CFArrayAppendValue(result, selectedRetained);

    size_t exposedW = CGDisplayModeGetWidth(selectedRetained);
    size_t exposedH = hook_CGDisplayModeGetHeight(selectedRetained);
    double exposedHzRaw = CGDisplayModeGetRefreshRate(selectedRetained);
    size_t exposedHz = (exposedHzRaw >= 45.0 && exposedHzRaw <= 100.0) ? (size_t)llround(exposedHzRaw) : 60;
    if (display == CGMainDisplayID() || gLastExposedModeWidth == 0) {
        gLastExposedModeWidth = exposedW;
        gLastExposedModeHeight = exposedH;
        gLastExposedModeHz = exposedHz;
    }

    if (gDebugBootEnabled || gDiagLogEnabled || gDiagOsLogEnabled) {
        static int sLoggedEnum = 0;
        if (sLoggedEnum < 6) {
            sLoggedEnum++;
            debuglog_write("DISPLAY", "CGDisplayCopyAllDisplayModes(display=%u) real=%ld kept=1 desktop=%zux%zu exposed=%zux%zu@%zu (notch=%ld)",
                           (unsigned)display, (long)realCount, curW, curH,
                           exposedW, exposedH, exposedHz,
                           (long)gNotchTopInset);
        }
    }

    CGDisplayModeRelease(selectedRetained);
    CFRelease(realModes);
    return (CFArrayRef)result;
}

/*
 * Safe variadic wrapper for Sims2XP_Exe's _sscanf (rebound via __DATA,__la_symbol_ptr).
 * Prevents boot SIGSEGV at 0x1006ea404 (uncaught nGZGraphic::cError after 800x600 fallback)
 * whenever the engine's saved activeDeviceDisplayMode ("%ux%ux%ux%u") does not match the
 * single native usable mode currently exposed by hook_CGDisplayCopyAllDisplayModes (e.g. after
 * upgrading from v1.4.1 1800x1169 to notched 1800x1131, unplugging/switching monitors, or
 * changing macOS display scaling) — with zero direct filesystem config access and zero TCC alerts.
 */
static int hook_sscanf(const char *str, const char *fmt, ...) {
    if (!str || !fmt) {
        return EOF;
    }
    va_list ap;
    va_start(ap, fmt);

    va_list apScan;
    va_copy(apScan, ap);
    int ret = vsscanf(str, fmt, apScan);
    va_end(apScan);

    if (ret == 4 && str && fmt &&
        fmt[0] == '%' && fmt[1] == 'u' &&
        strcmp(fmt, "%ux%ux%ux%u") == 0 &&
        gLastExposedModeWidth > 0 && gLastExposedModeHeight > 0) {
        va_list apExtract;
        va_copy(apExtract, ap);
        unsigned int *outW = va_arg(apExtract, unsigned int *);
        unsigned int *outH = va_arg(apExtract, unsigned int *);
        unsigned int *outBpp = va_arg(apExtract, unsigned int *);
        unsigned int *outHz = va_arg(apExtract, unsigned int *);
        va_end(apExtract);

        if (outW && outH && outBpp && outHz) {
            unsigned int targetW = (unsigned int)gLastExposedModeWidth;
            unsigned int targetH = (unsigned int)gLastExposedModeHeight;
            unsigned int targetHz = (gLastExposedModeHz >= 45 && gLastExposedModeHz <= 100)
                ? (unsigned int)gLastExposedModeHz
                : 60U;
            if (*outW != targetW || *outH != targetH || *outBpp != 32U ||
                (*outHz != 0U && *outHz != targetHz)) {
                debuglog_write("DISPLAY",
                               "Normalized stale activeDeviceDisplayMode %ux%ux%ux%u -> %ux%ux32x%u (prevents 800x600/SIGSEGV)",
                               *outW, *outH, *outBpp, *outHz, targetW, targetH, targetHz);
                *outW = targetW;
                *outH = targetH;
                *outBpp = 32U;
                *outHz = targetHz;
            }
        }
    }

    va_end(ap);
    return ret;
}

typedef void (*Sims2CxaThrowFn)(void *, void *, void (*)(void *));
static Sims2CxaThrowFn gRealCxaThrow = NULL;
static int gCxaThrowLogged = 0;

__attribute__((noreturn))
static void hook_cxa_throw(void *thrownException, void *tinfo, void (*dest)(void *)) {
    const char *typeName = "?";
    if (tinfo) {
        const char *n = *(const char * const *)((const char *)tinfo + sizeof(void *));
        if (n) {
            typeName = n;
        }
    }
    uintptr_t caller = (uintptr_t)__builtin_return_address(0);
    uintptr_t unslid = caller - (uintptr_t)gExecSlide;
    snprintf(gLastCxaThrowInfo, sizeof(gLastCxaThrowInfo),
             "type=%.180s caller=0x%lx (exe 0x%lx)",
             typeName, (unsigned long)caller, (unsigned long)unslid);

    if (gDebugBootEnabled && gCxaThrowLogged < 200) {
        gCxaThrowLogged++;
        debuglog_write("CXX_THROW", "#%d type=%s caller=0x%lx (exe 0x%lx) obj=%p",
                       gCxaThrowLogged, typeName, (unsigned long)caller, (unsigned long)unslid, thrownException);
        if (thrownException && typeName && strstr(typeName, "basic_string")) {
            const unsigned char *s = (const unsigned char *)thrownException;
            const char *text = (s[0] & 1) ? *(const char * const *)(s + 16) : (const char *)(s + 1);
            if (text) {
                debuglog_write("CXX_THROW", "  what=\"%.300s\"", text);
            }
        }
    }
    if (!gRealCxaThrow) {
        gRealCxaThrow = (Sims2CxaThrowFn)dlsym(RTLD_DEFAULT, "__cxa_throw");
    }
    gRealCxaThrow(thrownException, tinfo, dest);
    __builtin_unreachable();
}

/*
 * Inverse cursor warp projection (engine fb -> contentView -> real macOS CG screen coords).
 * Sims2XP_Exe's SetCursorPos (0x1000b8200) -> SDL_WarpMouseInWindow (0x1000ef170) ->
 * Cocoa_WarpMouse (0x1000ff420) adds (sdlWin->x, sdlWin->y) to unscaled engine framebuffer
 * coordinates (fbX, fbY) and calls CGWarpMouseCursorPosition / CGDisplayMoveCursorToPoint.
 * Without inverse projection, pie-menu clicks and camera anchors (Option / right-drag / Control)
 * in Windowed mode (1512x982 / 1440x900 / 1280x800) teleport the physical macOS cursor away
 * from the clicked object or completely outside the game window onto the Desktop.
 */
static BOOL compute_inverse_warp_point(CGPoint sdlGlobalPt,
                                       CGFloat sdlWinX,
                                       CGFloat sdlWinY,
                                       CGFloat fbW,
                                       CGFloat fbH,
                                       NSRect contentScreenRect,
                                       CGFloat rawPrimaryScreenH,
                                       CGPoint *outCgGlobalPt,
                                       CGPoint *outFbPt,
                                       CGPoint *outContentTopDownPt) {
    if (fbW < 640.0 || fbH < 480.0 ||
        contentScreenRect.size.width < 1.0 || contentScreenRect.size.height < 1.0 ||
        rawPrimaryScreenH < 480.0) {
        return NO;
    }
    CGFloat fbX = sdlGlobalPt.x - sdlWinX;
    CGFloat fbY = sdlGlobalPt.y - sdlWinY;
    if (fbX < -64.0 || fbX > fbW + 64.0 || fbY < -64.0 || fbY > fbH + 64.0) {
        return NO;
    }
    if (fbX < 0.0) fbX = 0.0;
    if (fbX > fbW - 1.0) fbX = fbW - 1.0;
    if (fbY < 0.0) fbY = 0.0;
    if (fbY > fbH - 1.0) fbY = fbH - 1.0;

    CGFloat contentW = contentScreenRect.size.width;
    CGFloat contentH = contentScreenRect.size.height;
    /* When downscaling (content < fb), map integer engine pixel k to pixel center (k + 0.5)
       so Cocoa_WindowListener::mouseMoved:'s cvttsd2si truncation round-trips back to exact k
       with 0 px drift on 2x Retina (0.5 pt) displays during held camera warps. */
    CGFloat halfX = (contentW < fbW - 2.0) ? 0.5 : 0.0;
    CGFloat halfY = (contentH < fbH - 2.0) ? 0.5 : 0.0;
    CGFloat contentX = (fbX + halfX) * (contentW / fbW);
    CGFloat contentYTopDown = (fbY + halfY) * (contentH / fbH);
    if (contentX < 0.0) contentX = 0.0;
    if (contentX > contentW - 1.0) contentX = contentW - 1.0;
    if (contentYTopDown < 0.0) contentYTopDown = 0.0;
    if (contentYTopDown > contentH - 1.0) contentYTopDown = contentH - 1.0;

    /* Convert AppKit contentScreenRect (bottom-left global) to real CoreGraphics top-left global coords
       (using raw hardware primary display height so notched MacBooks keep 0.0 px vertical accuracy too). */
    CGFloat cgContentOriginX = contentScreenRect.origin.x;
    CGFloat cgContentOriginY = rawPrimaryScreenH - NSMaxY(contentScreenRect);
    CGPoint mappedCgPt = CGPointMake(cgContentOriginX + contentX, cgContentOriginY + contentYTopDown);

    if (outCgGlobalPt) *outCgGlobalPt = mappedCgPt;
    if (outFbPt) *outFbPt = CGPointMake(fbX, fbY);
    if (outContentTopDownPt) *outContentTopDownPt = CGPointMake(contentX, contentYTopDown);
    return YES;
}

static BOOL resolve_inverse_warp_target_cg_point(const char *apiName,
                                                 CGPoint sdlGlobalPt,
                                                 CGPoint *outMappedCgPt,
                                                 BOOL *outShouldSuppress) {
    if (outShouldSuppress) {
        *outShouldSuppress = NO;
    }
    if (outMappedCgPt) {
        *outMappedCgPt = sdlGlobalPt;
    }
    if (!gAppIsActive || gUserWindowMoveInProgress || gInFullscreenTransition) {
        if (outShouldSuppress) {
            *outShouldSuppress = YES;
        }
        return NO;
    }

    CGFloat sdlX = 0.0, sdlY = 0.0, sdlW = 0.0, sdlH = 0.0;
    CGFloat fbW = gEngineFbW;
    CGFloat fbH = gEngineFbH;
    NSRect contentScreenRect = NSZeroRect;
    CGFloat rawPrimaryScreenH = 0.0;
    BOOL haveGeometry = NO;

    if ([NSThread isMainThread]) {
        if (NSApp && ![NSApp isActive]) {
            if (outShouldSuppress) {
                *outShouldSuppress = YES;
            }
            return NO;
        }
        NSWindow *win = resolve_primary_game_window();
        if (win && is_sdl_game_window(win) && !is_secondary_orphan_game_window(win)) {
            if (![win isKeyWindow]) {
                if (outShouldSuppress) {
                    *outShouldSuppress = YES;
                }
                return NO;
            }
            contentScreenRect = query_window_content_screen_rect(win);
            rawPrimaryScreenH = query_primary_screen_height_for_cg();
            if (query_sdl_window_rect(win, &sdlX, &sdlY, &sdlW, &sdlH)) {
                if (fbW < 640.0) fbW = sdlW;
                if (fbH < 480.0) fbH = sdlH;
                haveGeometry = YES;
                gCachedContentScreenRect = contentScreenRect;
                gCachedRawPrimaryScreenH = rawPrimaryScreenH;
                gCachedSdlOriginX = sdlX;
                gCachedSdlOriginY = sdlY;
                gCachedWarpGeometryValid = YES;
            }
        }
    } else if (gCachedWarpGeometryValid) {
        contentScreenRect = gCachedContentScreenRect;
        rawPrimaryScreenH = gCachedRawPrimaryScreenH;
        sdlX = gCachedSdlOriginX;
        sdlY = gCachedSdlOriginY;
        haveGeometry = YES;
    }

    if (!haveGeometry) {
        return NO;
    }

    CGPoint mappedCgPt = sdlGlobalPt;
    CGPoint fbPt = CGPointZero;
    CGPoint contentPt = CGPointZero;
    if (!compute_inverse_warp_point(sdlGlobalPt, sdlX, sdlY, fbW, fbH,
                                    contentScreenRect, rawPrimaryScreenH,
                                    &mappedCgPt, &fbPt, &contentPt)) {
        return NO;
    }

    if (outMappedCgPt) {
        *outMappedCgPt = mappedCgPt;
    }
    if (gDebugBootEnabled || gDiagLogEnabled || gDiagOsLogEnabled) {
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        BOOL distinctTarget = (fabs(fbPt.x - gLastWarpLoggedFbPt.x) > 20.0 ||
                               fabs(fbPt.y - gLastWarpLoggedFbPt.y) > 20.0);
        if (distinctTarget || (now - gLastWarpDiagLogTime) >= 0.25) {
            gLastWarpDiagLogTime = now;
            gLastWarpLoggedFbPt = fbPt;
            debuglog_write("WARP",
                           "%s fb=(%.1f,%.1f) -> content=(%.1f,%.1f) -> screen=(%.1f,%.1f) "
                           "[rawIn=(%.1f,%.1f) sdlOrigin=(%.0f,%.0f) contentScreen=%.0fx%.0f@(%.0f,%.0f) rawH=%.0f windowed=%d]",
                           apiName ? apiName : "warp",
                           fbPt.x, fbPt.y,
                           contentPt.x, contentPt.y,
                           mappedCgPt.x, mappedCgPt.y,
                           sdlGlobalPt.x, sdlGlobalPt.y,
                           sdlX, sdlY,
                           contentScreenRect.size.width, contentScreenRect.size.height,
                           contentScreenRect.origin.x, contentScreenRect.origin.y,
                           rawPrimaryScreenH,
                           gWindowedModeActive ? 1 : 0);
        }
    }
    return YES;
}

static CGError hook_CGWarpMouseCursorPosition(CGPoint newCursorPosition) {
    static __thread BOOL tInWarpHook = NO;
    if (tInWarpHook) {
        return CGWarpMouseCursorPosition(newCursorPosition);
    }
    tInWarpHook = YES;
    CGPoint targetPt = newCursorPosition;
    BOOL shouldSuppress = NO;
    resolve_inverse_warp_target_cg_point("CGWarpMouseCursorPosition", newCursorPosition, &targetPt, &shouldSuppress);
    if (shouldSuppress) {
        tInWarpHook = NO;
        return kCGErrorSuccess;
    }
    CGError err = CGWarpMouseCursorPosition(targetPt);
    tInWarpHook = NO;
    return err;
}

static CGError hook_CGDisplayMoveCursorToPoint(CGDirectDisplayID display, CGPoint point) {
    static __thread BOOL tInMoveCursorHook = NO;
    if (tInMoveCursorHook) {
        return CGDisplayMoveCursorToPoint(display, point);
    }
    tInMoveCursorHook = YES;
    CGPoint targetGlobalPt = point;
    BOOL shouldSuppress = NO;
    BOOL mapped = resolve_inverse_warp_target_cg_point("CGDisplayMoveCursorToPoint", point, &targetGlobalPt, &shouldSuppress);
    if (shouldSuppress) {
        tInMoveCursorHook = NO;
        return kCGErrorSuccess;
    }
    CGPoint displayLocalPt = targetGlobalPt;
    if (mapped && display != CGMainDisplayID()) {
        CGRect dispBounds = CGDisplayBounds(display);
        displayLocalPt.x -= dispBounds.origin.x;
        displayLocalPt.y -= dispBounds.origin.y;
    }
    CGError err = CGDisplayMoveCursorToPoint(display, displayLocalPt);
    tInMoveCursorHook = NO;
    return err;
}

static void debuglog_window_geometry(const char *reason, NSWindow *win) {
    if ((!gDebugBootEnabled && !gDiagLogEnabled && !gDiagOsLogEnabled) || !win) {
        return;
    }
    NSScreen *scr = win.screen ?: [NSScreen mainScreen];
    NSRect f = win.frame;
    NSRect cb = win.contentView ? win.contentView.bounds : NSZeroRect;
    NSRect sf = scr ? scr.frame : NSZeroRect;
    NSRect vf = scr ? scr.visibleFrame : NSZeroRect;
    CGFloat safeTop = 0.0;
    if (scr) {
        if (@available(macOS 12.0, *)) {
            safeTop = scr.safeAreaInsets.top;
        }
    }
    BOOL fs = (win.styleMask & NSWindowStyleMaskFullScreen) != 0;
    NSApplicationPresentationOptions presOpts = NSApp ? [NSApp presentationOptions] : 0;
    debuglog_write("WIN", "%s win=%p class=%s fs=%d style=0x%lx collBeh=0x%lx pres=0x%lx "
                   "frame=%.0fx%.0f@(%.0f,%.0f) content=%.0fx%.0f fb=%.0fx%.0f "
                   "screen=%.0fx%.0f visible=%.0fx%.0f@(%.0f,%.0f) safeTop=%.0f "
                   "windowed=%d target=%ldx%ld scale=%.1f",
                   reason, (__bridge void *)win, object_getClassName(win), fs,
                   (unsigned long)win.styleMask,
                   (unsigned long)win.collectionBehavior,
                   (unsigned long)presOpts,
                   f.size.width, f.size.height, f.origin.x, f.origin.y,
                   cb.size.width, cb.size.height,
                   gEngineFbW, gEngineFbH,
                   sf.size.width, sf.size.height,
                   vf.size.width, vf.size.height, vf.origin.x, vf.origin.y,
                   safeTop,
                   gWindowedModeActive ? 1 : 0,
                   (long)gTargetWindowWidth, (long)gTargetWindowHeight,
                   scr ? scr.backingScaleFactor : 0.0);
}

static NSWindow *resolve_primary_game_window(void) {
    if (gPrimaryFullscreenWindow && is_sdl_game_window(gPrimaryFullscreenWindow)) {
        return gPrimaryFullscreenWindow;
    }
    if (!NSApp) {
        return nil;
    }
    NSWindow *keyWin = [NSApp keyWindow];
    if (keyWin && is_sdl_game_window(keyWin) && !is_secondary_orphan_game_window(keyWin)) {
        gPrimaryFullscreenWindow = keyWin;
        return keyWin;
    }
    for (NSWindow *w in [NSApp windows]) {
        if (is_sdl_game_window(w) && !is_secondary_orphan_game_window(w) &&
            w.frame.size.width >= 640.0 && w.frame.size.height >= 480.0) {
            gPrimaryFullscreenWindow = w;
            return w;
        }
    }
    return nil;
}

static void swizzled_windowDidResize(id self, SEL _cmd, NSNotification *notification) {
    gWindowListener = self;
    NSWindow *win = extract_nswindow_from_delegate_arg(notification);
    BOOL suppressForScale = NO;
    if (win && is_sdl_game_window(win) && !is_secondary_orphan_game_window(win) &&
        gHasCapturedInitialEngineFb && win.contentView &&
        (gHasCompletedFirstWindowShow || gWindowedModeActive || ((win.styleMask & NSWindowStyleMaskFullScreen) != 0))) {
        NSSize cs = win.contentView.bounds.size;
        if (fabs(cs.width - gEngineFbW) > 2.0 || fabs(cs.height - gEngineFbH) > 2.0) {
            suppressForScale = YES;
        }
    }
    if (gSuppressSDLResizeNotification || gModeTransitionInProgress || gNotchFitInProgress ||
        gWindowedModeActive || suppressForScale) {
        if (win && is_sdl_game_window(win) && !is_secondary_orphan_game_window(win)) {
            sync_sdl_window_logical_size_to_engine_fb(win, "suppressedDidResize");
            apply_opengl_surface_backing_size_ex(win, NO);
        }
        return;
    }
    if (gOrigWindowDidResizeIMP) {
        typedef void (*Fn)(id, SEL, NSNotification *);
        ((Fn)gOrigWindowDidResizeIMP)(self, _cmd, notification);
    }
    if (win && is_sdl_game_window(win) && !is_secondary_orphan_game_window(win)) {
        sync_sdl_window_logical_size_to_engine_fb(win, "windowDidResize");
        apply_opengl_surface_backing_size_ex(win, NO);
    }
}

static void restore_game_window_focus_and_input(NSWindow *win, const char *reason) {
    if (!win || !is_sdl_game_window(win) || is_secondary_orphan_game_window(win)) {
        return;
    }
    if (!NSApp || ![NSApp isActive] || gAppIsHiding || gAppIsTerminating) {
        return;
    }
    gAppHasActivatedOnce = YES;
    gAppIsActive = YES;
    gLastResignTimestamp = 0.0;

    /* Reset any residual modifier / drag / transition state left over from a Space or Cmd+Tab switch */
    reset_gesture_and_key_state(resolve_window_listener());
    gSpoofMiddleButton = NO;
    gMaskControlModifier = NO;
    if (([NSEvent pressedMouseButtons] & 1) == 0) {
        gUserWindowMoveInProgress = NO;
    }

    /* Re-associate mouse cursor in case switching Spaces dissociated cursor position */
    CGAssociateMouseAndMouseCursorPosition(true);
    CGDisplayShowCursor(kCGDirectMainDisplay);

    /* Reapply presentation options cleanly without disturbing window geometry or firstResponder */
    BOOL inSpace = (([win styleMask] & NSWindowStyleMaskFullScreen) != 0);
    apply_borderless_presentation_options(!gWindowedModeActive && !inSpace && !gInFullscreenTransition);

    /* Restore SDL responder chain, key window, firstResponder and mouse-moved delivery */
    ensure_sdl_responder_chain(win, reason ? reason : "restoreFocus");
    if (![win isKeyWindow]) {
        if (gOrigMakeKeyAndOrderFrontIMP) {
            typedef void (*OrderFn)(id, SEL, id);
            ((OrderFn)gOrigMakeKeyAndOrderFrontIMP)(win, @selector(makeKeyAndOrderFront:), nil);
        } else {
            [win makeKeyAndOrderFront:nil];
        }
    }
    if (win.contentView && [win firstResponder] != win.contentView) {
        [win makeFirstResponder:win.contentView];
    }
    [win setAcceptsMouseMovedEvents:YES];
    flush_stuck_modifier_state_to_sdl(win, reason ? reason : "restoreFocus");

    debuglog_write("FOCUS", "Restored focus & input (%s) win=%p isKey=%d firstResp=%s cvNext=%s inSpace=%d windowed=%d",
                   reason ? reason : "unknown",
                   (__bridge void *)win,
                   [win isKeyWindow] ? 1 : 0,
                   [win firstResponder] ? object_getClassName([win firstResponder]) : "nil",
                   (win.contentView && [win.contentView nextResponder]) ? object_getClassName([win.contentView nextResponder]) : "nil",
                   inSpace ? 1 : 0,
                   gWindowedModeActive ? 1 : 0);
}

static void apply_window_level_and_mission_control_behavior(NSWindow *win) {
    if (!win) {
        return;
    }
    if ([win level] != NSNormalWindowLevel) {
        if (gOrigSDLSetLevelIMP && gSDLWindowClass && [win isKindOfClass:gSDLWindowClass]) {
            typedef void (*LvlFn)(id, SEL, NSWindowLevel);
            ((LvlFn)gOrigSDLSetLevelIMP)(win, @selector(setLevel:), NSNormalWindowLevel);
        } else {
            [win setLevel:NSNormalWindowLevel];
        }
    }
    NSWindowCollectionBehavior curBehavior = win.collectionBehavior;
    NSWindowCollectionBehavior targetBehavior = sanitize_mission_control_collection_behavior(curBehavior);
    if (curBehavior != targetBehavior) {
        if (gOrigSDLSetCollectionBehaviorIMP && gSDLWindowClass && [win isKindOfClass:gSDLWindowClass]) {
            typedef void (*BehFn)(id, SEL, NSWindowCollectionBehavior);
            ((BehFn)gOrigSDLSetCollectionBehaviorIMP)(win, @selector(setCollectionBehavior:), targetBehavior);
        } else {
            [win setCollectionBehavior:targetBehavior];
        }
    }
}

static void enforce_primary_window_borderless_fullscreen_locked(NSWindow *win, const char *reason) {
    if (!is_sdl_window_fully_attached(win) || !is_sdl_game_window(win) || is_secondary_orphan_game_window(win)) {
        return;
    }
    NSRect curF = win.frame;
    if (curF.size.width < 640.0 && curF.size.height < 480.0 && win != gPrimaryFullscreenWindow) {
        return;
    }
    NSScreen *scr = win.screen ?: [NSScreen mainScreen];
    if (!scr) {
        return;
    }
    if (!gPrimaryFullscreenWindow) {
        gPrimaryFullscreenWindow = win;
    }
    detect_native_screen_resolution(win);
    ensure_sims2_display_menu_installed();
    update_sims2_display_menu_state();

    if (!gHasCapturedInitialEngineFb) {
        CGFloat sdlW = 0.0, sdlH = 0.0;
        if (query_sdl_window_logical_size(win, &sdlW, &sdlH)) {
            gEngineFbW = sdlW;
            gEngineFbH = sdlH;
            gHasCapturedInitialEngineFb = YES;
            debuglog_write("WIN", "Captured initial engine FB from SDL_Window: %.0fx%.0f", gEngineFbW, gEngineFbH);
        } else if (win.contentView &&
                   win.contentView.bounds.size.width >= 640.0 &&
                   win.contentView.bounds.size.height >= 480.0) {
            gEngineFbW = win.contentView.bounds.size.width;
            gEngineFbH = win.contentView.bounds.size.height;
            gHasCapturedInitialEngineFb = YES;
            debuglog_write("WIN", "Captured initial engine FB from contentView: %.0fx%.0f", gEngineFbW, gEngineFbH);
        } else {
            NSRect initialFs = compute_primary_game_frame(win);
            if (initialFs.size.width >= 640.0 && initialFs.size.height >= 480.0) {
                gEngineFbW = initialFs.size.width;
                gEngineFbH = initialFs.size.height;
                gHasCapturedInitialEngineFb = YES;
            }
        }
    }

    BOOL isExplicitTransition = (reason &&
                                 (strcmp(reason, "toggleMode") == 0 ||
                                  strcmp(reason, "cycleResolution") == 0 ||
                                  strcmp(reason, "selectResolution") == 0 ||
                                  strcmp(reason, "didExitFullScreen") == 0 ||
                                  strcmp(reason, "didExitFullScreenSettle") == 0 ||
                                  strcmp(reason, "failExitFullScreenToWindowed") == 0 ||
                                  strcmp(reason, "failExitFullScreenToWindowedAsync") == 0 ||
                                  strcmp(reason, "bootEnterFullscreen") == 0 ||
                                  strcmp(reason, "fullscreenSettle") == 0));

    BOOL inSpace = ((win.styleMask & NSWindowStyleMaskFullScreen) != 0);
    gLastKnownInSpace = inSpace;
    record_last_hook_state(reason ? reason : "enforceWindow");

    if (gWindowedModeActive) {
        if (inSpace) {
            if (!gInFullscreenTransition) {
                remember_exit_fullscreen_target_screen(win, "toggleFullScreenExit");
                gUserRequestedFullscreenExit = YES;
                gInFullscreenTransition = YES;
                gAllowResizableForSpaceToggle = YES;
                debuglog_write("WIN", "Exiting native Fullscreen Space -> Windowed (%s)", reason ? reason : "windowed");
                if (gOrigSDLToggleFullScreenIMP && gSDLWindowClass && [win isKindOfClass:gSDLWindowClass]) {
                    typedef void (*ToggleFn)(id, SEL, id);
                    ((ToggleFn)gOrigSDLToggleFullScreenIMP)(win, @selector(toggleFullScreen:), nil);
                } else {
                    [win toggleFullScreen:nil];
                }
            }
            return;
        }
        gHasCompletedFirstWindowShow = YES;
        /* 1. Show macOS menu bar & Dock, release cursor grab, enable Mission Control + FullScreenPrimary (green button) */
        apply_borderless_presentation_options(NO);
        CGAssociateMouseAndMouseCursorPosition(true);
        CGDisplayShowCursor(kCGDirectMainDisplay);
        apply_window_level_and_mission_control_behavior(win);

        /* 2. Force real gray macOS titlebar with active green fullscreen button (Titled | Closable | Miniaturizable | Resizable) */
        NSWindowStyleMask titledStyle = (NSWindowStyleMaskTitled |
                                         NSWindowStyleMaskClosable |
                                         NSWindowStyleMaskMiniaturizable |
                                         NSWindowStyleMaskResizable);
        NSWindowStyleMask curStyle = win.styleMask;
        BOOL styleChanged = (curStyle != titledStyle);
        if (styleChanged) {
            debuglog_write("WIN", "windowed styleMask 0x%lx -> 0x%lx (%s) win=%p",
                           (unsigned long)curStyle, (unsigned long)titledStyle,
                           reason ? reason : "windowed", (__bridge void *)win);
            safe_set_sdl_window_style_mask(win, titledStyle, "windowed-styleMask");
        }
        [win setMinSize:NSMakeSize(640.0, 480.0)];

        if (![win.backgroundColor isEqual:[NSColor blackColor]]) {
            [win setBackgroundColor:[NSColor blackColor]];
        }
        if (![win isOpaque]) {
            [win setOpaque:YES];
        }
        if (![win.title isEqualToString:kSims2WindowTitle]) {
            [win setTitle:kSims2WindowTitle];
        }
        [win setTitleVisibility:NSWindowTitleVisible];
        [win setTitlebarAppearsTransparent:NO];
        if (![win hasShadow]) {
            [win setHasShadow:YES];
        }
        [win setMovable:YES];
        [win setMovableByWindowBackground:NO];

        /* 3. Compute compatible outer frame inside NSScreen.visibleFrame (preserving origin screen on Space exit) */
        NSScreen *exitTargetScr = resolve_active_exit_fullscreen_target_screen();
        NSInteger targetW = (gTargetWindowWidth >= 640) ? gTargetWindowWidth : 1440;
        NSInteger targetH = (gTargetWindowHeight >= 480) ? gTargetWindowHeight : 900;
        if (exitTargetScr) {
            resolve_compatible_windowed_size_on_screen(exitTargetScr, &targetW, &targetH);
        } else {
            resolve_compatible_windowed_size(win, &targetW, &targetH);
        }
        if (targetW != gTargetWindowWidth || targetH != gTargetWindowHeight) {
            gTargetWindowWidth = targetW;
            gTargetWindowHeight = targetH;
            update_sims2_display_menu_state();
        }

        NSRect liveCurF = win.frame;
        NSRect expectedOuter = [win frameRectForContentRect:NSMakeRect(0.0, 0.0, (CGFloat)targetW, (CGFloat)targetH)];
        BOOL sizeMatches = (fabs(liveCurF.size.width - expectedOuter.size.width) <= 1.5 &&
                            fabs(liveCurF.size.height - expectedOuter.size.height) <= 1.5);
        BOOL userDragging = ([NSEvent pressedMouseButtons] != 0 || gUserWindowMoveInProgress || [win inLiveResize]);
        if (!isExplicitTransition && !styleChanged && sizeMatches && !gForceCenterWindowedFrame && userDragging) {
            /* Never interfere with an active user titlebar drag or live resize */
            return;
        }

        BOOL offExitScreen = (exitTargetScr != nil && resolve_screen_for_rect(liveCurF, win.screen) != exitTargetScr);
        BOOL shouldCenter = gForceCenterWindowedFrame || !sizeMatches || offExitScreen;
        NSRect targetOuter = exitTargetScr
            ? compute_windowed_game_frame_on_screen(win, exitTargetScr, targetW, targetH, shouldCenter)
            : compute_windowed_game_frame(win, targetW, targetH, shouldCenter);
        gForceCenterWindowedFrame = NO;

        /* 4. Apply outer frame & exact contentView bounds (excluding titlebar), suppress SDL resize
              so SDL keeps window->w/h == gEngineFbW/gEngineFbH and CGL scales 100% of the UI */
        BOOL needFrameChange = (!sizeMatches ||
                                fabs(liveCurF.origin.x - targetOuter.origin.x) > 1.0 ||
                                fabs(liveCurF.origin.y - targetOuter.origin.y) > 1.0);
        if (needFrameChange) {
            gSuppressSDLResizeNotification = YES;
            if (gOrigSDLSetFrameDisplayIMP && gSDLWindowClass && [win isKindOfClass:gSDLWindowClass]) {
                typedef void (*FrameFn)(id, SEL, NSRect, BOOL);
                ((FrameFn)gOrigSDLSetFrameDisplayIMP)(win, @selector(setFrame:display:), targetOuter, YES);
            } else {
                [win setFrame:targetOuter display:YES];
            }
            gSuppressSDLResizeNotification = NO;
        }
        sync_content_view_to_window_bounds(win, targetOuter);
        sync_sdl_window_logical_size_to_engine_fb(win, "after-windowed");
        ensure_sdl_responder_chain(win, "after-windowed");
        apply_opengl_surface_backing_size_ex(win, (isExplicitTransition || styleChanged || needFrameChange));

        if (isExplicitTransition || styleChanged || (NSApp && [NSApp isActive] && ![win isKeyWindow])) {
            if (gOrigMakeKeyAndOrderFrontIMP) {
                typedef void (*OrderFn)(id, SEL, id);
                ((OrderFn)gOrigMakeKeyAndOrderFrontIMP)(win, @selector(makeKeyAndOrderFront:), nil);
            } else {
                [win makeKeyAndOrderFront:nil];
            }
            if (win.contentView) {
                [win makeFirstResponder:win.contentView];
            }
        }
        [win setAcceptsMouseMovedEvents:YES];
        if (isExplicitTransition || styleChanged || needFrameChange) {
            [win invalidateShadow];
            [win display];
        }
        debuglog_window_geometry("after-windowed", win);
        return;
    }

    /* === BORDERLESS FULLSCREEN (gWindowedModeActive == NO) ===
     * Primary path: native macOS Fullscreen Space (Managed | ParticipatesInCycle | FullScreenPrimary),
     * giving automatic notch exclusion, zero menu bar overlay, and instant ~0.5s launch.
     * Borderless fallback (if Space entry is unavailable):
     *   1. Mission Control level (NSNormalWindowLevel) & collectionBehavior (FullScreenPrimary)
     *   2. setStyleMask:NSWindowStyleMaskBorderless FIRST (before setFrame:display:), then setHasShadow:NO
     *   3. setFrame:display: on exact rectangle below the notch
     *   4. Force win.contentView.frame, apply_borderless_presentation_options(YES), CGL sync & focus.
     */
    apply_window_level_and_mission_control_behavior(win);

    if (inSpace) {
        gHasCompletedFirstWindowShow = YES;
        apply_borderless_presentation_options(NO);
        ensure_fullscreen_space_geometry(win, "in-native-space");
        sync_sdl_window_logical_size_to_engine_fb(win, "in-native-space");
        ensure_sdl_responder_chain(win, "in-native-space");
        apply_opengl_surface_backing_size_ex(win, isExplicitTransition);
        if (isExplicitTransition || (NSApp && [NSApp isActive] && ![win isKeyWindow])) {
            if (gOrigMakeKeyAndOrderFrontIMP) {
                typedef void (*OrderFn)(id, SEL, id);
                ((OrderFn)gOrigMakeKeyAndOrderFrontIMP)(win, @selector(makeKeyAndOrderFront:), nil);
            } else {
                [win makeKeyAndOrderFront:nil];
            }
            if (win.contentView) {
                [win makeFirstResponder:win.contentView];
            }
        }
        [win setAcceptsMouseMovedEvents:YES];
        debuglog_window_geometry("after-native-space", win);
        return;
    }

    if (gInFullscreenTransition) {
        return;
    }

    BOOL isFallbackReason = (reason &&
                             (strcmp(reason, "failEnterFullScreenFallback") == 0 ||
                              strcmp(reason, "fullscreenSettle") == 0));

    if (!gHasCompletedFirstWindowShow && !isExplicitTransition && !isFallbackReason) {
        /* Booting in Fullscreen: let SDL's own Cocoa_SetWindowFullscreenSpace enter native Space cleanly.
           Schedule a one-shot 900 ms check in case Aspyr prefs had DisplayFullScreen=false. */
        static BOOL sScheduledBootFsCheck = NO;
        if (!sScheduledBootFsCheck) {
            sScheduledBootFsCheck = YES;
            uint64_t bootGen = current_display_transition_gen();
            __weak NSWindow *weakWin = win;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(900 * NSEC_PER_MSEC)),
                           dispatch_get_main_queue(), ^{
                if (current_display_transition_gen() != bootGen || gInFullscreenTransition || gAppIsTerminating) {
                    return;
                }
                NSWindow *w = weakWin;
                if (w && !gWindowedModeActive && ((w.styleMask & NSWindowStyleMaskFullScreen) == 0)) {
                    debuglog_write("WIN", "Boot Space check: window not yet in Space after 900ms -> entering native Space");
                    enforce_primary_window_borderless_fullscreen(w, "bootEnterFullscreen");
                }
            });
        }
        apply_opengl_surface_backing_size_ex(win, NO);
        return;
    }

    if (isExplicitTransition && !isFallbackReason) {
        /* Enter real native macOS Fullscreen Space cleanly via toggleFullScreen: */
        clear_exit_fullscreen_target_screen();
        NSWindowStyleMask spaceReadyMask = (NSWindowStyleMaskTitled |
                                            NSWindowStyleMaskClosable |
                                            NSWindowStyleMaskMiniaturizable |
                                            NSWindowStyleMaskResizable);
        if ((win.styleMask & spaceReadyMask) != spaceReadyMask) {
            safe_set_sdl_window_style_mask(win, spaceReadyMask, "pre-enter-space");
        }
        apply_borderless_presentation_options(NO);
        gUserRequestedFullscreenEnter = YES;
        gInFullscreenTransition = YES;
        gAllowResizableForSpaceToggle = YES;
        uint64_t enterGen = current_display_transition_gen();
        debuglog_write("WIN", "Entering native macOS Fullscreen Space (%s) win=%p gen=%llu",
                       reason ? reason : "transition", (__bridge void *)win, (unsigned long long)enterGen);
        if (gOrigSDLToggleFullScreenIMP && gSDLWindowClass && [win isKindOfClass:gSDLWindowClass]) {
            typedef void (*ToggleFn)(id, SEL, id);
            ((ToggleFn)gOrigSDLToggleFullScreenIMP)(win, @selector(toggleFullScreen:), nil);
        } else {
            [win toggleFullScreen:nil];
        }
        /* Safety watchdog: if Space entry fails silently, gracefully fall back to borderless fullscreen */
        __weak NSWindow *weakWin = win;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2500 * NSEC_PER_MSEC)),
                       dispatch_get_main_queue(), ^{
            if (current_display_transition_gen() != enterGen || gAppIsTerminating) {
                return;
            }
            NSWindow *w = weakWin;
            if (w && !gWindowedModeActive && gInFullscreenTransition &&
                ((w.styleMask & NSWindowStyleMaskFullScreen) == 0)) {
                gInFullscreenTransition = NO;
                gAllowResizableForSpaceToggle = NO;
                gUserRequestedFullscreenEnter = NO;
                debuglog_write("WIN", "Native Space entry timeout (2.5s) -> falling back to borderless fullscreen");
                enforce_primary_window_borderless_fullscreen(w, "failEnterFullScreenFallback");
            }
        });
        return;
    }

    /* Borderless Fullscreen Fallback (strictly setStyleMask: BEFORE setFrame:display:) */
    gHasCompletedFirstWindowShow = YES;
    NSWindowStyleMask curStyle = win.styleMask;
    NSWindowStyleMask cleanStyle = sanitize_sdl_style_mask(curStyle);
    BOOL styleChanged = (cleanStyle != curStyle);
    if (styleChanged) {
        debuglog_write("WIN", "strip styleMask 0x%lx -> 0x%lx (%s) win=%p",
                       (unsigned long)curStyle, (unsigned long)cleanStyle,
                       reason ? reason : "guard", (__bridge void *)win);
        safe_set_sdl_window_style_mask(win, cleanStyle, "borderless-fallback-styleMask");
    }

    if (![win.backgroundColor isEqual:[NSColor blackColor]]) {
        [win setBackgroundColor:[NSColor blackColor]];
    }
    if (![win isOpaque]) {
        [win setOpaque:YES];
    }
    if ([win hasShadow]) {
        [win setHasShadow:NO];
    }
    [win setMovable:NO];

    NSRect fullscreenFrame = compute_primary_game_frame(win);
    if (fullscreenFrame.size.width < 640.0 || fullscreenFrame.size.height < 480.0) {
        return;
    }

    NSRect liveCurF = win.frame;
    BOOL frameMatches = (fabs(liveCurF.size.width - fullscreenFrame.size.width) <= 1.0 &&
                         fabs(liveCurF.size.height - fullscreenFrame.size.height) <= 1.0 &&
                         fabs(liveCurF.origin.x - fullscreenFrame.origin.x) <= 1.0 &&
                         fabs(liveCurF.origin.y - fullscreenFrame.origin.y) <= 1.0);

    if (!frameMatches || isExplicitTransition || styleChanged) {
        if (!isExplicitTransition && !styleChanged &&
            NSEqualRects(gNotchTargetFrame, fullscreenFrame) && gNotchClampAttempts >= 8) {
            sync_content_view_to_window_bounds(win, liveCurF);
        } else {
            if (!NSEqualRects(gNotchTargetFrame, fullscreenFrame) || isExplicitTransition) {
                gNotchTargetFrame = fullscreenFrame;
                gNotchClampAttempts = 0;
            }
            gNotchClampAttempts++;
            gSuppressSDLResizeNotification = YES;
            debuglog_write("WIN", "clamp %s #%d (fs=%d) %.0fx%.0f@(%.0f,%.0f) -> %.0fx%.0f@(%.0f,%.0f)",
                           reason ? reason : "guard", gNotchClampAttempts, inSpace ? 1 : 0,
                           liveCurF.size.width, liveCurF.size.height, liveCurF.origin.x, liveCurF.origin.y,
                           fullscreenFrame.size.width, fullscreenFrame.size.height,
                           fullscreenFrame.origin.x, fullscreenFrame.origin.y);
            if (gOrigSDLSetFrameDisplayIMP && gSDLWindowClass && [win isKindOfClass:gSDLWindowClass]) {
                typedef void (*FrameFn)(id, SEL, NSRect, BOOL);
                ((FrameFn)gOrigSDLSetFrameDisplayIMP)(win, @selector(setFrame:display:), fullscreenFrame, YES);
            } else {
                [win setFrame:fullscreenFrame display:YES];
            }
            gSuppressSDLResizeNotification = NO;
        }
    } else {
        gNotchTargetFrame = fullscreenFrame;
        gNotchClampAttempts = 0;
    }

    /* Force win.contentView.frame to exact (0, 0, fullscreenFrame.w, fullscreenFrame.h) */
    if (win.contentView) {
        NSRect exactBounds = NSMakeRect(0.0, 0.0, fullscreenFrame.size.width, fullscreenFrame.size.height);
        if (!NSEqualRects(win.contentView.frame, exactBounds)) {
            [win.contentView setFrame:exactBounds];
        }
    }

    /* HideMenuBar | HideDock exclusively via NSApplicationPresentationOptions */
    if (gAppIsActive && !gAppIsHiding && !gAppIsTerminating && !gInFullscreenTransition) {
        apply_borderless_presentation_options(YES);
    }

    /* Sync SDL_Window geometry & OpenGL surface backing size */
    sync_sdl_window_logical_size_to_engine_fb(win, "after-borderless-fallback");
    ensure_sdl_responder_chain(win, "after-borderless-fallback");
    apply_opengl_surface_backing_size_ex(win, (isExplicitTransition || styleChanged || !frameMatches));

    /* Ensure borderless fullscreen window stays key, firstResponder & accepts mouse moves */
    if (isExplicitTransition || styleChanged || (NSApp && [NSApp isActive] && ![win isKeyWindow])) {
        if (gOrigMakeKeyAndOrderFrontIMP) {
            typedef void (*OrderFn)(id, SEL, id);
            ((OrderFn)gOrigMakeKeyAndOrderFrontIMP)(win, @selector(makeKeyAndOrderFront:), nil);
        } else {
            [win makeKeyAndOrderFront:nil];
        }
        if (win.contentView) {
            [win makeFirstResponder:win.contentView];
        }
        [win display];
    }
    [win setAcceptsMouseMovedEvents:YES];
    debuglog_window_geometry("after-clamp", win);
}

static void enforce_primary_window_borderless_fullscreen(NSWindow *win, const char *reason) {
    if (!__sync_bool_compare_and_swap(&gModeTransitionInProgress, 0, 1)) {
        return;
    }
    gNotchFitInProgress = YES;
    @try {
        enforce_primary_window_borderless_fullscreen_locked(win, reason);
    } @finally {
        gSuppressSDLResizeNotification = NO;
        gNotchFitInProgress = NO;
        __sync_lock_release(&gModeTransitionInProgress);
    }
}

static void clamp_fullscreen_window_to_visible_frame(NSWindow *win) {
    enforce_primary_window_borderless_fullscreen(win, "observer");
}

static NSMenu *gSims2DisplayMenu = nil;
static NSMenuItem *gSims2ToggleModeMenuItem = nil;
static NSMenuItem *gSims2CycleResMenuItem = nil;
static NSMutableArray<NSMenuItem *> *gSims2ResolutionMenuItems = nil;

@interface Sims2DisplayMenuHandler : NSObject <NSMenuDelegate>
- (void)onToggleWindowedMode:(NSMenuItem *)sender;
- (void)onCycleResolution:(NSMenuItem *)sender;
- (void)onSelectResolution:(NSMenuItem *)sender;
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem;
@end

static Sims2DisplayMenuHandler *gSims2MenuHandler = nil;

static void select_default_windowed_resolution_if_native(NSWindow *win) {
    if (is_reduced_target_resolution()) {
        resolve_compatible_windowed_size(win, &gTargetWindowWidth, &gTargetWindowHeight);
        return;
    }
    NSInteger resWList[4];
    NSInteger resHList[4];
    size_t count = build_windowed_resolution_list(win, resWList, resHList);
    if (count > 0) {
        gTargetWindowWidth = resWList[0];
        gTargetWindowHeight = resHList[0];
    } else {
        NSInteger w = 1512, h = 982;
        resolve_compatible_windowed_size(win, &w, &h);
        gTargetWindowWidth = w;
        gTargetWindowHeight = h;
    }
}

static void apply_target_resolution(NSWindow *win, NSInteger resW, NSInteger resH, const char *reason) {
    bump_display_transition_gen();
    detect_native_screen_resolution(win);
    if (resW < 640 || resH < 480) {
        resW = gNativeScreenWidth;
        resH = gNativeScreenHeight;
    }

    BOOL isNative = (resW >= gNativeScreenWidth && resH >= gNativeScreenHeight);
    if (isNative) {
        gWindowedModeActive = NO;
    } else {
        gTargetWindowWidth = resW;
        gTargetWindowHeight = resH;
        resolve_compatible_windowed_size(win, &gTargetWindowWidth, &gTargetWindowHeight);
        gWindowedModeActive = YES;
        gForceCenterWindowedFrame = YES;
        save_windowed_size_preference();
    }
    gNotchClampAttempts = 0;
    update_sims2_display_menu_state();
    if (win) {
        enforce_primary_window_borderless_fullscreen(win, reason);
    } else {
        apply_borderless_presentation_options(NO);
    }
}

static void toggle_windowed_fullscreen_mode_ex(NSTimeInterval eventTs, const char *source) {
    if (!try_accept_shortcut_trigger("toggleMode", source ? source : "direct", eventTs, 0.45, YES)) {
        return;
    }

    bump_display_transition_gen();
    NSWindow *win = resolve_primary_game_window();
    detect_native_screen_resolution(win);

    gWindowedModeActive = !gWindowedModeActive;
    if (gWindowedModeActive) {
        select_default_windowed_resolution_if_native(win);
        gForceCenterWindowedFrame = YES;
    }
    gNotchClampAttempts = 0;
    update_sims2_display_menu_state();
    if (win) {
        enforce_primary_window_borderless_fullscreen(win, "toggleMode");
    } else {
        apply_borderless_presentation_options(NO);
    }
}

static void toggle_windowed_fullscreen_mode(void) {
    NSEvent *curEv = NSApp ? [NSApp currentEvent] : nil;
    toggle_windowed_fullscreen_mode_ex(curEv ? [curEv timestamp] : 0.0, "direct");
}

static void cycle_next_resolution_ex(NSTimeInterval eventTs, const char *source) {
    /* Command + R is strictly windowed-only: NEVER enter or exit native Fullscreen Space. */
    if (!gWindowedModeActive) {
        debuglog_write("KEY", "IGNORED cycleRes from %s (windowed-only, currently in Fullscreen)",
                       source ? source : "direct");
        return;
    }
    if (!try_accept_shortcut_trigger("cycleRes", source ? source : "direct", eventTs, 0.25, YES)) {
        return;
    }

    NSWindow *win = resolve_primary_game_window();
    NSInteger resWList[4];
    NSInteger resHList[4];
    size_t count = build_windowed_resolution_list(win, resWList, resHList);
    if (count == 0) {
        return;
    }

    NSInteger curW = gTargetWindowWidth;
    NSInteger curH = gTargetWindowHeight;
    size_t curIdx = 0;
    BOOL matched = NO;
    for (size_t i = 0; i < count; i++) {
        if (resWList[i] == curW && resHList[i] == curH) {
            curIdx = i;
            matched = YES;
            break;
        }
    }
    size_t nextIdx = matched ? ((curIdx + 1) % count) : 0;
    debuglog_write("KEY", "Command + R cycling windowed resolution %ldx%ld -> %ldx%ld",
                   (long)curW, (long)curH, (long)resWList[nextIdx], (long)resHList[nextIdx]);
    apply_target_resolution(win, resWList[nextIdx], resHList[nextIdx], "cycleResolution");
}

static void cycle_next_resolution(void) {
    NSEvent *curEv = NSApp ? [NSApp currentEvent] : nil;
    cycle_next_resolution_ex(curEv ? [curEv timestamp] : 0.0, "direct");
}

@implementation Sims2DisplayMenuHandler

- (void)menuNeedsUpdate:(NSMenu *)menu {
    (void)menu;
    NSWindow *primaryWin = resolve_primary_game_window();
    detect_native_screen_resolution(primaryWin);
    rebuild_sims2_display_menu_resolution_items(primaryWin);
    update_sims2_display_menu_state();
    debuglog_write("MENU", "menuNeedsUpdate: windowed=%d target=%ldx%ld fb=%.0fx%.0f",
                   gWindowedModeActive ? 1 : 0,
                   (long)gTargetWindowWidth, (long)gTargetWindowHeight,
                   gEngineFbW, gEngineFbH);
}

- (void)menuDidClose:(NSMenu *)menu {
    (void)menu;
    uint64_t gen = current_display_transition_gen();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(40 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), ^{
        if (current_display_transition_gen() != gen || gInFullscreenTransition || gAppIsTerminating) {
            return;
        }
        NSWindow *w = resolve_primary_game_window();
        if (w && NSApp && [NSApp isActive] && !gAppIsHiding) {
            restore_game_window_focus_and_input(w, "menuDidClose");
        }
    });
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    update_sims2_display_menu_state();
    if (menuItem && [menuItem action] == @selector(onCycleResolution:)) {
        return gWindowedModeActive;
    }
    return YES;
}

- (void)onToggleWindowedMode:(NSMenuItem *)sender {
    (void)sender;
    NSEvent *curEv = NSApp ? [NSApp currentEvent] : nil;
    NSTimeInterval evTs = curEv ? [curEv timestamp] : 0.0;
    /* Defer by one runloop turn so NSMenu fully exits tracking before toggleFullScreen:
       contacts the Dock Space daemon (prevents failedToEnterFullScreen during menu teardown). */
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gAppIsTerminating) {
            toggle_windowed_fullscreen_mode_ex(evTs, "menu");
        }
    });
}

- (void)onCycleResolution:(NSMenuItem *)sender {
    (void)sender;
    NSEvent *curEv = NSApp ? [NSApp currentEvent] : nil;
    NSTimeInterval evTs = curEv ? [curEv timestamp] : 0.0;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gAppIsTerminating) {
            cycle_next_resolution_ex(evTs, "menu");
        }
    });
}

- (void)onSelectResolution:(NSMenuItem *)sender {
    if (!sender) {
        return;
    }
    NSInteger tag = [sender tag];
    NSInteger resW = (tag >> 16) & 0xFFFF;
    NSInteger resH = tag & 0xFFFF;
    debuglog_write("MENU", "onSelectResolution: %ldx%ld", (long)resW, (long)resH);
    /* Defer by one runloop turn so NSMenu exits tracking before any Space enter/exit transition */
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gAppIsTerminating) {
            NSWindow *win = resolve_primary_game_window();
            apply_target_resolution(win, resW, resH, "selectResolution");
        }
    });
}

@end

static void rebuild_sims2_display_menu_resolution_items(NSWindow *win) {
    if (!gSims2DisplayMenu || !gSims2MenuHandler || !gSims2ResolutionMenuItems) {
        return;
    }
    detect_native_screen_resolution(win);
    NSInteger winWList[4];
    NSInteger winHList[4];
    size_t winCount = build_windowed_resolution_list(win, winWList, winHList);

    /* Skip rebuild if native resolution and windowed item list are unchanged */
    if ([gSims2ResolutionMenuItems count] == (1 + winCount)) {
        BOOL same = YES;
        NSInteger expectedNativeTag = ((gNativeScreenWidth & 0xFFFF) << 16) | (gNativeScreenHeight & 0xFFFF);
        if ([[gSims2ResolutionMenuItems objectAtIndex:0] tag] != expectedNativeTag) {
            same = NO;
        }
        for (size_t i = 0; same && i < winCount; i++) {
            NSInteger expectedTag = ((winWList[i] & 0xFFFF) << 16) | (winHList[i] & 0xFFFF);
            if ([[gSims2ResolutionMenuItems objectAtIndex:(1 + i)] tag] != expectedTag) {
                same = NO;
            }
        }
        if (same) {
            return;
        }
    }

    for (NSMenuItem *oldItem in gSims2ResolutionMenuItems) {
        if ([gSims2DisplayMenu indexOfItem:oldItem] != -1) {
            [gSims2DisplayMenu removeItem:oldItem];
        }
    }
    [gSims2ResolutionMenuItems removeAllObjects];

    NSString *nativeTitle = [NSString stringWithFormat:@"Plein écran natif (%ld×%ld)",
                             (long)gNativeScreenWidth, (long)gNativeScreenHeight];
    NSMenuItem *nativeItem = [[NSMenuItem alloc] initWithTitle:nativeTitle
                                                        action:@selector(onSelectResolution:)
                                                 keyEquivalent:@""];
    [nativeItem setTag:((gNativeScreenWidth & 0xFFFF) << 16) | (gNativeScreenHeight & 0xFFFF)];
    [nativeItem setTarget:gSims2MenuHandler];
    [nativeItem setEnabled:YES];
    [gSims2DisplayMenu addItem:nativeItem];
    [gSims2ResolutionMenuItems addObject:nativeItem];

    for (size_t i = 0; i < winCount; i++) {
        NSInteger rw = winWList[i];
        NSInteger rh = winHList[i];
        NSString *resTitle = [NSString stringWithFormat:@"%ld×%ld (Fenêtré)", (long)rw, (long)rh];
        NSMenuItem *resItem = [[NSMenuItem alloc] initWithTitle:resTitle
                                                         action:@selector(onSelectResolution:)
                                                  keyEquivalent:@""];
        [resItem setTag:((rw & 0xFFFF) << 16) | (rh & 0xFFFF)];
        [resItem setTarget:gSims2MenuHandler];
        [resItem setEnabled:YES];
        [gSims2DisplayMenu addItem:resItem];
        [gSims2ResolutionMenuItems addObject:resItem];
    }
}

static void update_sims2_display_menu_state(void) {
    if (!gSims2DisplayMenu) {
        return;
    }
    if (gSims2ToggleModeMenuItem) {
        [gSims2ToggleModeMenuItem setState:(gWindowedModeActive ? NSControlStateValueOn : NSControlStateValueOff)];
    }
    if (gSims2CycleResMenuItem) {
        [gSims2CycleResMenuItem setEnabled:gWindowedModeActive];
    }
    NSInteger activeW = gWindowedModeActive ? gTargetWindowWidth : gNativeScreenWidth;
    NSInteger activeH = gWindowedModeActive ? gTargetWindowHeight : gNativeScreenHeight;

    for (NSMenuItem *item in gSims2ResolutionMenuItems) {
        NSInteger tag = [item tag];
        NSInteger w = (tag >> 16) & 0xFFFF;
        NSInteger h = tag & 0xFFFF;
        BOOL match = (w == activeW && h == activeH);
        [item setState:(match ? NSControlStateValueOn : NSControlStateValueOff)];
    }
}

static void ensure_sims2_display_menu_installed(void) {
    if (!NSApp) {
        return;
    }
    NSMenu *mainMenu = [NSApp mainMenu];
    if (!mainMenu) {
        return;
    }
    if (gSims2DisplayMenu && [mainMenu indexOfItemWithSubmenu:gSims2DisplayMenu] != -1) {
        return;
    }

    NSWindow *primaryWin = resolve_primary_game_window();
    detect_native_screen_resolution(primaryWin);
    if (!gSims2MenuHandler) {
        gSims2MenuHandler = [[Sims2DisplayMenuHandler alloc] init];
    }
    if (!gSims2ResolutionMenuItems) {
        gSims2ResolutionMenuItems = [[NSMutableArray alloc] init];
    } else {
        [gSims2ResolutionMenuItems removeAllObjects];
    }

    NSMenuItem *containerItem = [[NSMenuItem alloc] initWithTitle:@"Affichage" action:NULL keyEquivalent:@""];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Affichage"];
    [menu setAutoenablesItems:YES];
    [menu setDelegate:gSims2MenuHandler];

    NSMenuItem *toggleItem = [[NSMenuItem alloc] initWithTitle:@"Basculer Plein écran / Fenêtré"
                                                        action:@selector(onToggleWindowedMode:)
                                                 keyEquivalent:@"\r"];
    [toggleItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [toggleItem setTarget:gSims2MenuHandler];
    [toggleItem setEnabled:YES];
    [menu addItem:toggleItem];
    gSims2ToggleModeMenuItem = toggleItem;

    NSMenuItem *cycleResItem = [[NSMenuItem alloc] initWithTitle:@"Résolution fenêtrée suivante"
                                                          action:@selector(onCycleResolution:)
                                                   keyEquivalent:@"r"];
    [cycleResItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [cycleResItem setTarget:gSims2MenuHandler];
    [cycleResItem setEnabled:gWindowedModeActive];
    [menu addItem:cycleResItem];
    gSims2CycleResMenuItem = cycleResItem;

    [menu addItem:[NSMenuItem separatorItem]];

    NSString *nativeTitle = [NSString stringWithFormat:@"Plein écran natif (%ld×%ld)",
                             (long)gNativeScreenWidth, (long)gNativeScreenHeight];
    NSMenuItem *nativeItem = [[NSMenuItem alloc] initWithTitle:nativeTitle
                                                        action:@selector(onSelectResolution:)
                                                 keyEquivalent:@""];
    [nativeItem setTag:((gNativeScreenWidth & 0xFFFF) << 16) | (gNativeScreenHeight & 0xFFFF)];
    [nativeItem setTarget:gSims2MenuHandler];
    [nativeItem setEnabled:YES];
    [menu addItem:nativeItem];
    [gSims2ResolutionMenuItems addObject:nativeItem];

    NSInteger winWList[4];
    NSInteger winHList[4];
    size_t winCount = build_windowed_resolution_list(primaryWin, winWList, winHList);
    for (size_t i = 0; i < winCount; i++) {
        NSInteger rw = winWList[i];
        NSInteger rh = winHList[i];
        NSString *resTitle = [NSString stringWithFormat:@"%ld×%ld (Fenêtré)", (long)rw, (long)rh];
        NSMenuItem *resItem = [[NSMenuItem alloc] initWithTitle:resTitle
                                                         action:@selector(onSelectResolution:)
                                                  keyEquivalent:@""];
        [resItem setTag:((rw & 0xFFFF) << 16) | (rh & 0xFFFF)];
        [resItem setTarget:gSims2MenuHandler];
        [resItem setEnabled:YES];
        [menu addItem:resItem];
        [gSims2ResolutionMenuItems addObject:resItem];
    }

    [containerItem setSubmenu:menu];
    [mainMenu addItem:containerItem];
    gSims2DisplayMenu = menu;
    update_sims2_display_menu_state();
    debuglog_write("MENU", "Installed macOS Affichage NSMenu (native=%ldx%ld items=%lu)",
                   (long)gNativeScreenWidth, (long)gNativeScreenHeight,
                   (unsigned long)[gSims2ResolutionMenuItems count]);
}

static void ensure_workspace_space_observer_registered(void) {
    static dispatch_once_t sSpaceObserverOnce;
    dispatch_once(&sSpaceObserverOnce, ^{
        NSNotificationCenter *wsNC = [[NSWorkspace sharedWorkspace] notificationCenter];
        [wsNC addObserverForName:NSWorkspaceActiveSpaceDidChangeNotification
                          object:nil
                           queue:[NSOperationQueue mainQueue]
                      usingBlock:^(NSNotification *note) {
            (void)note;
            gUserWindowMoveInProgress = NO;
            if (!gUserRequestedFullscreenExit && !gUserRequestedFullscreenEnter) {
                gInFullscreenTransition = NO;
            }
            gSuppressSDLResizeNotification = NO;
            gNotchFitInProgress = NO;
            __sync_lock_release(&gModeTransitionInProgress);
            reset_gesture_and_key_state(resolve_window_listener());
            NSWindow *primaryWin = resolve_primary_game_window();
            BOOL inSpace = (primaryWin && ((primaryWin.styleMask & NSWindowStyleMaskFullScreen) != 0));
            BOOL onActiveSpace = (primaryWin && [primaryWin isOnActiveSpace]);
            BOOL isVisible = (primaryWin && (([primaryWin occlusionState] & NSWindowOcclusionStateVisible) != 0));
            debuglog_write("SPACE", "NSWorkspaceActiveSpaceDidChangeNotification active=%d windowed=%d inSpace=%d onActiveSpace=%d visible=%d",
                           (NSApp && [NSApp isActive]) ? 1 : 0, gWindowedModeActive ? 1 : 0,
                           inSpace ? 1 : 0, onActiveSpace ? 1 : 0, isVisible ? 1 : 0);
            if (NSApp && [NSApp isActive] && !gAppIsHiding && !gAppIsTerminating) {
                __atomic_add_fetch(&gSpaceReactivateSeq, 1ULL, __ATOMIC_ACQ_REL);
                if (primaryWin) {
                    refresh_opengl_surface_for_screen_or_backing_change(primaryWin, "ActiveSpaceDidChange");
                    restore_game_window_focus_and_input(primaryWin, "ActiveSpaceDidChange");
                    uint64_t spaceGen = current_display_transition_gen();
                    __weak NSWindow *weakWin = primaryWin;
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(100 * NSEC_PER_MSEC)),
                                   dispatch_get_main_queue(), ^{
                        if (current_display_transition_gen() != spaceGen || gInFullscreenTransition || gAppIsTerminating) {
                            return;
                        }
                        NSWindow *w = weakWin;
                        if (w && NSApp && [NSApp isActive] && !gAppIsHiding) {
                            restore_game_window_focus_and_input(w, "ActiveSpaceDidChangeSettle");
                        }
                    });
                }
            } else if (primaryWin && !gAppIsHiding && !gAppIsTerminating &&
                       !gWindowedModeActive && inSpace && onActiveSpace) {
                /* Multi-screen Space return recovery WITHOUT colliding with Mission Control dismissal:
                   1. Coalesce OpenGL surface refresh (debounced 140 ms, zero synchronous setFrame:).
                   2. Defer NSApp reactivation by 150 ms via gSpaceReactivateSeq: if macOS activates
                      the app naturally (e.g. clicking the Space in Mission Control), do nothing!
                      Only reactivate if still inactive after 150 ms and cursor is on the game screen. */
                if (isVisible) {
                    refresh_opengl_surface_for_screen_or_backing_change(primaryWin, "ActiveSpaceVisibleRefresh");
                }
                uint64_t reactSeq = __atomic_add_fetch(&gSpaceReactivateSeq, 1ULL, __ATOMIC_ACQ_REL);
                uint64_t spaceGen = current_display_transition_gen();
                __weak NSWindow *weakWin = primaryWin;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(150 * NSEC_PER_MSEC)),
                               dispatch_get_main_queue(), ^{
                    if (__atomic_load_n(&gSpaceReactivateSeq, __ATOMIC_ACQUIRE) != reactSeq ||
                        current_display_transition_gen() != spaceGen ||
                        gInFullscreenTransition || gAppIsHiding || gAppIsTerminating) {
                        return;
                    }
                    if (NSApp && [NSApp isActive]) {
                        return;
                    }
                    NSWindow *w = weakWin;
                    if (!w || gWindowedModeActive) {
                        return;
                    }
                    BOOL wInSpace = ((w.styleMask & NSWindowStyleMaskFullScreen) != 0);
                    BOOL wOnActive = [w isOnActiveSpace];
                    BOOL wVisible = (([w occlusionState] & NSWindowOcclusionStateVisible) != 0);
                    NSArray<NSScreen *> *allScreens = [NSScreen screens];
                    NSPoint cursorPt = [NSEvent mouseLocation];
                    BOOL cursorOnGameScreen = (w.screen && NSPointInRect(cursorPt, w.screen.frame));
                    if (wInSpace && wOnActive && wVisible &&
                        (cursorOnGameScreen || !allScreens || [allScreens count] <= 1)) {
                        debuglog_write("SPACE", "Deferred reactivation of game Fullscreen Space (cursorOnGameScreen=%d screens=%lu)",
                                       cursorOnGameScreen ? 1 : 0, (unsigned long)(allScreens ? [allScreens count] : 0));
                        gAppIsActive = YES;
                        gLastResignTimestamp = 0.0;
                        gAllowExplicitSpaceReactivation = YES;
                        [NSApp activateIgnoringOtherApps:YES];
                        gAllowExplicitSpaceReactivation = NO;
                        restore_game_window_focus_and_input(w, "ActiveSpaceDidChangeReactivate");
                        refresh_opengl_surface_for_screen_or_backing_change(w, "ActiveSpaceDidChangeReactivate");
                    } else {
                        CGAssociateMouseAndMouseCursorPosition(true);
                        CGDisplayShowCursor(kCGDirectMainDisplay);
                    }
                });
            } else {
                __atomic_add_fetch(&gSpaceReactivateSeq, 1ULL, __ATOMIC_ACQ_REL);
                CGAssociateMouseAndMouseCursorPosition(true);
                CGDisplayShowCursor(kCGDirectMainDisplay);
                apply_borderless_presentation_options(NO);
            }
        }];
    });
}

static void register_window_geometry_observers(void) {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserverForName:NSApplicationDidFinishLaunchingNotification object:nil queue:nil
                usingBlock:^(NSNotification *note) {
        (void)note;
        NSScreen *scr = [NSScreen mainScreen];
        update_cached_screen_geometry(scr);
        load_display_preferences_from_defaults();
        ensure_workspace_space_observer_registered();
        ensure_sims2_display_menu_installed();
        update_sims2_display_menu_state();
        if (scr) {
            NSRect sf = scr.frame;
            NSRect vf = scr.visibleFrame;
            debuglog_write("SCREEN", "main frame=%.0fx%.0f visibleFrame=%.0fx%.0f@(%.0f,%.0f) notch=%ld native=%ldx%ld scale=%.1f",
                           sf.size.width, sf.size.height, vf.size.width, vf.size.height,
                           vf.origin.x, vf.origin.y, (long)gNotchTopInset,
                           (long)gNativeScreenWidth, (long)gNativeScreenHeight,
                           scr.backingScaleFactor);
        }
        debuglog_write("APP", "DidFinishLaunching");
    }];
    [nc addObserverForName:NSApplicationDidChangeScreenParametersNotification object:nil queue:nil
                usingBlock:^(NSNotification *note) {
        (void)note;
        if (gAppIsTerminating) {
            return;
        }
        NSWindow *primaryWin = resolve_primary_game_window();
        NSScreen *scr = (primaryWin && primaryWin.screen) ? primaryWin.screen : [NSScreen mainScreen];
        detect_native_screen_resolution(primaryWin);
        update_cached_screen_geometry(scr);
        rebuild_sims2_display_menu_resolution_items(primaryWin);
        update_sims2_display_menu_state();
        debuglog_write("SCREEN", "DidChangeScreenParameters native=%ldx%ld notch=%ld windowed=%d target=%ldx%ld",
                       (long)gNativeScreenWidth, (long)gNativeScreenHeight,
                       (long)gNotchTopInset, gWindowedModeActive ? 1 : 0,
                       (long)gTargetWindowWidth, (long)gTargetWindowHeight);
        if (primaryWin && is_sdl_window_fully_attached(primaryWin) && !gInFullscreenTransition) {
            sync_sdl_window_origin_to_frame(primaryWin, "screenParamsChanged");
            if (gWindowedModeActive) {
                NSInteger prevW = gTargetWindowWidth;
                NSInteger prevH = gTargetWindowHeight;
                if (gTargetWindowWidth >= 640 && gTargetWindowHeight >= 480) {
                    resolve_compatible_windowed_size(primaryWin, &gTargetWindowWidth, &gTargetWindowHeight);
                    update_sims2_display_menu_state();
                }
                NSScreen *curScr = resolve_screen_for_rect(primaryWin.frame, primaryWin.screen);
                BOOL fitsOnScreen = (curScr && NSContainsRect(curScr.visibleFrame, primaryWin.frame));
                if (!fitsOnScreen || prevW != gTargetWindowWidth || prevH != gTargetWindowHeight) {
                    gForceCenterWindowedFrame = YES;
                    enforce_primary_window_borderless_fullscreen(primaryWin, "screenParamsChanged");
                }
                refresh_opengl_surface_for_screen_or_backing_change(primaryWin, "screenParamsChanged");
            } else {
                refresh_opengl_surface_for_screen_or_backing_change(primaryWin, "screenParamsChanged");
            }
        }
    }];
    [nc addObserverForName:NSWindowDidChangeScreenNotification object:nil queue:nil
                usingBlock:^(NSNotification *note) {
        NSWindow *win = (NSWindow *)note.object;
        if (gAppIsTerminating || !win || !is_sdl_game_window(win) || is_secondary_orphan_game_window(win)) {
            return;
        }
        debuglog_window_geometry("DidChangeScreen", win);
        if (is_sdl_window_fully_attached(win) && !gInFullscreenTransition) {
            if (gWindowedModeActive && gTargetWindowWidth >= 640 && gTargetWindowHeight >= 480) {
                NSInteger prevW = gTargetWindowWidth, prevH = gTargetWindowHeight;
                resolve_compatible_windowed_size(win, &gTargetWindowWidth, &gTargetWindowHeight);
                if (prevW != gTargetWindowWidth || prevH != gTargetWindowHeight) {
                    gForceCenterWindowedFrame = YES;
                    enforce_primary_window_borderless_fullscreen(win, "didChangeScreen");
                }
            }
            refresh_opengl_surface_for_screen_or_backing_change(win, "didChangeScreen");
        }
    }];
    [nc addObserverForName:NSWindowDidChangeBackingPropertiesNotification object:nil queue:nil
                usingBlock:^(NSNotification *note) {
        NSWindow *win = (NSWindow *)note.object;
        if (gAppIsTerminating || !win || !is_sdl_game_window(win) || is_secondary_orphan_game_window(win)) {
            return;
        }
        debuglog_window_geometry("DidChangeBackingProperties", win);
        if (is_sdl_window_fully_attached(win) && !gInFullscreenTransition) {
            refresh_opengl_surface_for_screen_or_backing_change(win, "didChangeBackingProperties");
        }
    }];
    [nc addObserverForName:NSMenuDidEndTrackingNotification object:nil queue:nil
                usingBlock:^(NSNotification *note) {
        (void)note;
        uint64_t menuGen = current_display_transition_gen();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(40 * NSEC_PER_MSEC)),
                       dispatch_get_main_queue(), ^{
            if (current_display_transition_gen() != menuGen || gInFullscreenTransition || gAppIsTerminating) {
                return;
            }
            NSWindow *w = resolve_primary_game_window();
            if (w && NSApp && [NSApp isActive] && !gAppIsHiding) {
                restore_game_window_focus_and_input(w, "MenuDidEndTracking");
            }
        });
    }];
    [nc addObserverForName:NSWindowDidBecomeKeyNotification object:nil queue:nil
                usingBlock:^(NSNotification *note) {
        NSWindow *win = (NSWindow *)note.object;
        if (win && [win isKindOfClass:[NSWindow class]]) {
            update_cached_screen_geometry(win.screen ?: [NSScreen mainScreen]);
        }
        ensure_workspace_space_observer_registered();
        ensure_sims2_display_menu_installed();
        update_sims2_display_menu_state();
        debuglog_window_geometry("DidBecomeKey", win);
        if (!gModeTransitionInProgress && !gInFullscreenTransition) {
            clamp_fullscreen_window_to_visible_frame(win);
            restore_game_window_focus_and_input(win, "DidBecomeKeyObserver");
        }
    }];
    [nc addObserverForName:NSWindowDidBecomeMainNotification object:nil queue:nil
                usingBlock:^(NSNotification *note) {
        NSWindow *win = (NSWindow *)note.object;
        if (win && is_sdl_game_window(win) && !is_secondary_orphan_game_window(win)) {
            debuglog_window_geometry("DidBecomeMain", win);
            if (!gModeTransitionInProgress && !gInFullscreenTransition) {
                restore_game_window_focus_and_input(win, "DidBecomeMainObserver");
            }
        }
    }];
    [nc addObserverForName:NSWindowDidResizeNotification object:nil queue:nil
                usingBlock:^(NSNotification *note) {
        if (gModeTransitionInProgress || gNotchFitInProgress || gInFullscreenTransition) {
            return;
        }
        NSWindow *win = (NSWindow *)note.object;
        if (win && [win isKindOfClass:[NSWindow class]]) {
            update_cached_screen_geometry(win.screen ?: [NSScreen mainScreen]);
        }
        debuglog_window_geometry("DidResize", win);
        if (win && is_sdl_game_window(win) && !is_secondary_orphan_game_window(win)) {
            BOOL inSpace = ((win.styleMask & NSWindowStyleMaskFullScreen) != 0);
            if (inSpace) {
                if (NSApp && [NSApp isActive] && !gAppIsHiding) {
                    ensure_fullscreen_space_geometry(win, "didResizeSpace");
                    sync_sdl_window_logical_size_to_engine_fb(win, "didResizeSpace");
                    apply_opengl_surface_backing_size_ex(win, NO);
                } else {
                    refresh_opengl_surface_for_screen_or_backing_change(win, "didResizeSpaceInactive");
                }
                return;
            }
            clamp_fullscreen_window_to_visible_frame(win);
        }
    }];
    [nc addObserverForName:NSWindowWillMoveNotification object:nil queue:nil
                usingBlock:^(NSNotification *note) {
        NSWindow *win = (NSWindow *)note.object;
        if (gWindowedModeActive && !gModeTransitionInProgress && !gNotchFitInProgress && !gInFullscreenTransition &&
            ([NSEvent pressedMouseButtons] & 1) != 0 &&
            win && is_sdl_game_window(win) && !is_secondary_orphan_game_window(win)) {
            gUserWindowMoveInProgress = YES;
            clear_exit_fullscreen_target_screen();
        }
    }];
    [nc addObserverForName:NSWindowDidMoveNotification object:nil queue:nil
                usingBlock:^(NSNotification *note) {
        NSWindow *win = (NSWindow *)note.object;
        BOOL isPrimaryGameWin = (win && is_sdl_game_window(win) && !is_secondary_orphan_game_window(win));
        if (isPrimaryGameWin) {
            sync_sdl_window_origin_to_frame(win, "didMove");
            if (gDebugBootEnabled || gDiagLogEnabled || gDiagOsLogEnabled) {
                CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
                BOOL draggingNow = (([NSEvent pressedMouseButtons] & 1) != 0);
                if (!draggingNow || (now - gLastDidMoveDiagLogTime) >= 0.25) {
                    gLastDidMoveDiagLogTime = now;
                    NSRect wf = win.frame;
                    NSRect cs = query_window_content_screen_rect(win);
                    CGFloat sx = 0.0, sy = 0.0, sw = 0.0, sh = 0.0;
                    query_sdl_window_rect(win, &sx, &sy, &sw, &sh);
                    debuglog_write("WIN",
                                   "DidMove winFrame=%.0fx%.0f@(%.0f,%.0f) contentScreen=%.0fx%.0f@(%.0f,%.0f) "
                                   "sdl=%.0fx%.0f@(%.0f,%.0f) windowed=%d",
                                   wf.size.width, wf.size.height, wf.origin.x, wf.origin.y,
                                   cs.size.width, cs.size.height, cs.origin.x, cs.origin.y,
                                   sw, sh, sx, sy,
                                   gWindowedModeActive ? 1 : 0);
                }
            }
        }
        if (gWindowedModeActive) {
            if (([NSEvent pressedMouseButtons] & 1) == 0) {
                gUserWindowMoveInProgress = NO;
            }
            return;
        }
        if (gModeTransitionInProgress || gNotchFitInProgress || gInFullscreenTransition) {
            return;
        }
        if (isPrimaryGameWin) {
            if ((win.styleMask & NSWindowStyleMaskFullScreen) != 0) {
                return;
            }
            clamp_fullscreen_window_to_visible_frame(win);
        }
    }];
    [nc addObserverForName:NSWindowDidEnterFullScreenNotification object:nil queue:nil
                usingBlock:^(NSNotification *note) {
        NSWindow *win = (NSWindow *)note.object;
        if (win && [win isKindOfClass:[NSWindow class]]) {
            update_cached_screen_geometry(win.screen ?: [NSScreen mainScreen]);
        }
        debuglog_window_geometry("DidEnterFullScreen", win);
        if (win && is_sdl_game_window(win) && !is_secondary_orphan_game_window(win)) {
            sync_sdl_window_logical_size_to_engine_fb(win, "DidEnterFullScreenObserver");
            apply_opengl_surface_backing_size_ex(win, NO);
        }
    }];
    [nc addObserverForName:NSWindowDidExitFullScreenNotification object:nil queue:nil
                usingBlock:^(NSNotification *note) {
        gNotchClampAttempts = 0;
        NSWindow *win = (NSWindow *)note.object;
        debuglog_window_geometry("DidExitFullScreen", win);
        if (!gAppIsTerminating && gWindowedModeActive &&
            win && is_sdl_game_window(win) && !is_secondary_orphan_game_window(win)) {
            enforce_primary_window_borderless_fullscreen(win, "didExitFullScreen");
        }
    }];
}

typedef struct {
    const char *symbolName;
    void *replacement;
} Sims2SymbolHookEntry;

static const Sims2SymbolHookEntry kSims2CoreGraphicsHooks[] = {
    { "_CGDisplayCopyAllDisplayModes", (void *)hook_CGDisplayCopyAllDisplayModes },
    { "_CGDisplayCopyDisplayMode",     (void *)hook_CGDisplayCopyDisplayMode },
    { "_CGDisplayModeGetHeight",       (void *)hook_CGDisplayModeGetHeight },
    { "_CGDisplayModeGetPixelHeight",  (void *)hook_CGDisplayModeGetPixelHeight },
    { "_CGDisplayPixelsHigh",          (void *)hook_CGDisplayPixelsHigh },
    { "_CGDisplayBounds",              (void *)hook_CGDisplayBounds },
    { "_CGWarpMouseCursorPosition",    (void *)hook_CGWarpMouseCursorPosition },
    { "_CGDisplayMoveCursorToPoint",   (void *)hook_CGDisplayMoveCursorToPoint },
    { "_sscanf",                       (void *)hook_sscanf },
    { "___cxa_throw",                  (void *)hook_cxa_throw },
};

static size_t hook_coregraphics_la_symbol_ptrs(void) {
    const struct mach_header_64 *execHdr = NULL;
    intptr_t execSlide = 0;

    uint32_t imageCount = _dyld_image_count();
    for (uint32_t i = 0; i < imageCount; i++) {
        const struct mach_header *mh = _dyld_get_image_header(i);
        if (mh && mh->magic == MH_MAGIC_64 && mh->filetype == MH_EXECUTE) {
            execHdr = (const struct mach_header_64 *)mh;
            execSlide = _dyld_get_image_vmaddr_slide(i);
            gExecSlide = execSlide;
            break;
        }
    }
    if (!execHdr) {
        return 0;
    }

    const struct segment_command_64 *linkeditCmd = NULL;
    const struct symtab_command *symtabCmd = NULL;
    const struct dysymtab_command *dysymtabCmd = NULL;
    const struct section_64 *symPtrSections[8];
    size_t symPtrSectionCount = 0;

    const uint8_t *cmdPtr = (const uint8_t *)(execHdr + 1);
    for (uint32_t i = 0; i < execHdr->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)cmdPtr;
        if (lc->cmdsize < sizeof(struct load_command)) {
            break;
        }
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)cmdPtr;
            if (strcmp(seg->segname, SEG_LINKEDIT) == 0) {
                linkeditCmd = seg;
            } else if (strcmp(seg->segname, SEG_DATA) == 0 &&
                       (seg->initprot & VM_PROT_WRITE) != 0) {
                const struct section_64 *sects = (const struct section_64 *)(seg + 1);
                for (uint32_t s = 0; s < seg->nsects; s++) {
                    uint32_t stype = sects[s].flags & SECTION_TYPE;
                    if ((stype == S_LAZY_SYMBOL_POINTERS || stype == S_NON_LAZY_SYMBOL_POINTERS) &&
                        symPtrSectionCount < (sizeof(symPtrSections) / sizeof(symPtrSections[0]))) {
                        symPtrSections[symPtrSectionCount++] = &sects[s];
                    }
                }
            }
        } else if (lc->cmd == LC_SYMTAB) {
            symtabCmd = (const struct symtab_command *)cmdPtr;
        } else if (lc->cmd == LC_DYSYMTAB) {
            dysymtabCmd = (const struct dysymtab_command *)cmdPtr;
        }
        cmdPtr += lc->cmdsize;
    }

    if (!linkeditCmd || !symtabCmd || !dysymtabCmd ||
        symPtrSectionCount == 0 || dysymtabCmd->nindirectsyms == 0) {
        return 0;
    }

    uintptr_t linkeditBase =
        (uintptr_t)linkeditCmd->vmaddr + (uintptr_t)execSlide - (uintptr_t)linkeditCmd->fileoff;
    const struct nlist_64 *symtab =
        (const struct nlist_64 *)(linkeditBase + (uintptr_t)symtabCmd->symoff);
    const char *strtab =
        (const char *)(linkeditBase + (uintptr_t)symtabCmd->stroff);
    const uint32_t *indirectSymtab =
        (const uint32_t *)(linkeditBase + (uintptr_t)dysymtabCmd->indirectsymoff);

    const size_t hookTableCount =
        sizeof(kSims2CoreGraphicsHooks) / sizeof(kSims2CoreGraphicsHooks[0]);
    size_t hookedCount = 0;

    for (size_t s = 0; s < symPtrSectionCount; s++) {
        const struct section_64 *sect = symPtrSections[s];
        uint32_t indirectOff = sect->reserved1;
        size_t ptrCount = (size_t)(sect->size / sizeof(void *));
        if (indirectOff > dysymtabCmd->nindirectsyms ||
            ptrCount > (size_t)(dysymtabCmd->nindirectsyms - indirectOff)) {
            continue;
        }

        void **ptrs = (void **)((uintptr_t)sect->addr + (uintptr_t)execSlide);
        for (size_t j = 0; j < ptrCount; j++) {
            uint32_t symIdx = indirectSymtab[indirectOff + j];
            if ((symIdx & (INDIRECT_SYMBOL_ABS | INDIRECT_SYMBOL_LOCAL)) != 0 ||
                symIdx >= symtabCmd->nsyms) {
                continue;
            }
            uint32_t strx = symtab[symIdx].n_un.n_strx;
            if (strx == 0 || strx >= symtabCmd->strsize) {
                continue;
            }
            const char *symName = strtab + strx;
            for (size_t h = 0; h < hookTableCount; h++) {
                if (strcmp(symName, kSims2CoreGraphicsHooks[h].symbolName) == 0) {
                    ptrs[j] = kSims2CoreGraphicsHooks[h].replacement;
                    hookedCount++;
                    debuglog_write("HOOK", "rebound %s in %s", symName, sect->sectname);
                    break;
                }
            }
        }
    }

    return hookedCount;
}

__attribute__((constructor))
static void sims2_trackpad_init(void) {
    gBootMonotonicNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    init_log_paths_and_system_info();
    install_crash_handlers();
    debuglog_init_if_enabled();
    diaglog_init_if_enabled();

    debuglog_write("BOOT", "libsims2_trackpad v%s loaded pid=%d model=%s macOS=%s frame=%s diagLog=%s osLog=%d",
                   SIMS2_PATCH_VERSION, getpid(), gCachedHwModel, gCachedOsVersion, gCachedFrameStr,
                   (gDiagLogEnabled && gDiagLogPath[0]) ? gDiagLogPath : "disabled",
                   gDiagOsLogEnabled ? 1 : 0);

    /*
     * Override Aspyr's hardcoded SDL_SetHint(..., "0") priority-1 hints via environment
     * variables so SDL2 uses a native macOS fullscreen Space, keeps normal window level
     * (SDL_ALLOW_TOPMOST=0 matching Aspyr), and never minimizes on focus loss.
     */
    setenv("SDL_VIDEO_MAC_FULLSCREEN_SPACES", "1", 0);
    setenv("SDL_HINT_ALLOW_FULLSCREEN_NOTIFICATIONS", "1", 0);
    setenv("SDL_ALLOW_TOPMOST", "0", 1);
    setenv("SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS", "0", 1);

    const char *inv = getenv("SIMS2_ROTATE_INVERT");
    if (inv && inv[0] == '1') {
        gInvertRotation = YES;
    }
    const char *stepStr = getenv("SIMS2_ROTATE_STEP");
    if (stepStr && stepStr[0] != '\0') {
        double v = atof(stepStr);
        if (v >= 5.0 && v <= 200.0) gRotateStep = v;
    }
    const char *twistStr = getenv("SIMS2_TWIST_STEP");
    if (twistStr && twistStr[0] != '\0') {
        double v = atof(twistStr);
        if (v >= 3.0 && v <= 90.0) gTwistStep = v;
    }
    const char *pinchStr = getenv("SIMS2_PINCH_STEP");
    if (pinchStr && pinchStr[0] != '\0') {
        double v = atof(pinchStr);
        if (v >= 0.02 && v <= 0.50) gPinchStep = v;
    }
    const char *ctrlOrbitStr = getenv("SIMS2_CTRL_ORBIT");
    const char *optOrbitStr = getenv("SIMS2_OPTION_ORBIT");
    if ((ctrlOrbitStr && ctrlOrbitStr[0] == '0') ||
        (!ctrlOrbitStr && optOrbitStr && optOrbitStr[0] == '0')) {
        gEnableOptionOrbit = NO;
    }
    const char *dbg = getenv("SIMS2_TRACKPAD_DEBUG");
    if (dbg && dbg[0] == '1') {
        gDebug = YES;
    }

    Class appCls = objc_getClass("SDLApplication");
    if (!appCls) {
        appCls = [NSApplication class];
    }
    gOrigNextEventIMP = swizzle_instance_method(appCls,
                                                @selector(nextEventMatchingMask:untilDate:inMode:dequeue:),
                                                (IMP)swizzled_nextEventMatchingMask);
    gOrigActivateIgnoringOtherAppsIMP = swizzle_instance_method(appCls,
                                                                @selector(activateIgnoringOtherApps:),
                                                                (IMP)swizzled_activateIgnoringOtherApps);

    Class appDelegateCls = objc_getClass("SDLAppDelegate");
    if (appDelegateCls) {
        gOrigFocusSomeWindowIMP = swizzle_instance_method(appDelegateCls,
                                                          @selector(focusSomeWindow:),
                                                          (IMP)swizzled_focusSomeWindow);
    }

    Class evCls = [NSEvent class];
    gOrigButtonNumberIMP = swizzle_instance_method(evCls, @selector(buttonNumber), (IMP)swizzled_buttonNumber);
    gOrigEventModifierFlagsIMP = swizzle_instance_method(evCls, @selector(modifierFlags), (IMP)swizzled_eventModifierFlags);
    Method classModMethod = class_getClassMethod(evCls, @selector(modifierFlags));
    if (classModMethod) {
        gOrigClassModifierFlagsIMP = method_setImplementation(classModMethod, (IMP)swizzled_classModifierFlags);
    }
    gOrigIsDirectionInvertedIMP = swizzle_instance_method(evCls,
                                                          @selector(isDirectionInvertedFromDevice),
                                                          (IMP)swizzled_isDirectionInvertedFromDevice);
    gOrigLocationInWindowIMP = swizzle_instance_method(evCls,
                                                       @selector(locationInWindow),
                                                       (IMP)swizzled_locationInWindow);

    Class winCls = [NSWindow class];
    gOrigMiniaturizeIMP = swizzle_instance_method(winCls, @selector(miniaturize:), (IMP)swizzled_miniaturize);
    gOrigMakeKeyAndOrderFrontIMP = swizzle_instance_method(winCls, @selector(makeKeyAndOrderFront:), (IMP)swizzled_makeKeyAndOrderFront);
    gOrigOrderFrontRegardlessIMP = swizzle_instance_method(winCls, @selector(orderFrontRegardless), (IMP)swizzled_orderFrontRegardless);
    gOrigMouseLocationOutsideOfEventStreamIMP = swizzle_instance_method(winCls,
                                                                        @selector(mouseLocationOutsideOfEventStream),
                                                                        (IMP)swizzled_mouseLocationOutsideOfEventStream);

    Class sdlWinCls = objc_getClass("SDLWindow");
    gSDLWindowClass = sdlWinCls;
    if (sdlWinCls) {
        gOrigCanBecomeKeyWindowIMP = swizzle_instance_method(sdlWinCls,
                                                             @selector(canBecomeKeyWindow),
                                                             (IMP)swizzled_canBecomeKeyWindow);
        gOrigCanBecomeMainWindowIMP = swizzle_instance_method(sdlWinCls,
                                                              @selector(canBecomeMainWindow),
                                                              (IMP)swizzled_canBecomeMainWindow);
        swizzle_target_class_method(sdlWinCls, @selector(validateMenuItem:),
                                    (IMP)swizzled_sdlValidateMenuItem, &gOrigSDLValidateMenuItemIMP);
        swizzle_target_class_method(sdlWinCls, @selector(setStyleMask:),
                                    (IMP)swizzled_sdlSetStyleMask, &gOrigSDLSetStyleMaskIMP);
        swizzle_target_class_method(sdlWinCls, @selector(setLevel:),
                                    (IMP)swizzled_sdlSetLevel, &gOrigSDLSetLevelIMP);
        swizzle_target_class_method(sdlWinCls, @selector(setFrame:display:),
                                    (IMP)swizzled_sdlSetFrameDisplay, &gOrigSDLSetFrameDisplayIMP);
        swizzle_target_class_method(sdlWinCls, @selector(setFrame:display:animate:),
                                    (IMP)swizzled_sdlSetFrameDisplayAnimate, &gOrigSDLSetFrameDisplayAnimateIMP);
        swizzle_target_class_method(sdlWinCls, @selector(setContentSize:),
                                    (IMP)swizzled_sdlSetContentSize, &gOrigSDLSetContentSizeIMP);
        swizzle_target_class_method(sdlWinCls, @selector(constrainFrameRect:toScreen:),
                                    (IMP)swizzled_sdlConstrainFrameRect, &gOrigSDLConstrainFrameRectIMP);
        swizzle_target_class_method(sdlWinCls, @selector(setCollectionBehavior:),
                                    (IMP)swizzled_sdlSetCollectionBehavior, &gOrigSDLSetCollectionBehaviorIMP);
        swizzle_target_class_method(sdlWinCls, @selector(toggleFullScreen:),
                                    (IMP)swizzled_sdlToggleFullScreen, &gOrigSDLToggleFullScreenIMP);
        swizzle_target_class_method(sdlWinCls, @selector(setFrameOrigin:),
                                    (IMP)swizzled_sdlSetFrameOrigin, &gOrigSDLSetFrameOriginIMP);
        swizzle_target_class_method(sdlWinCls, @selector(setFrameTopLeftPoint:),
                                    (IMP)swizzled_sdlSetFrameTopLeftPoint, &gOrigSDLSetFrameTopLeftPointIMP);
    }

    Class sdlViewCls = objc_getClass("SDLView");
    if (sdlViewCls) {
        swizzle_target_class_method(sdlViewCls, @selector(mouseDownCanMoveWindow),
                                    (IMP)swizzled_sdlViewMouseDownCanMoveWindow, &gOrigSDLViewMouseDownCanMoveWindowIMP);
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    Class nsglCls = [NSOpenGLContext class];
    if (nsglCls) {
        gOrigNSGLSetViewIMP = swizzle_instance_method(nsglCls,
                                                      @selector(setView:),
                                                      (IMP)swizzled_nsglSetView);
        gOrigNSGLMakeCurrentContextIMP = swizzle_instance_method(nsglCls,
                                                                 @selector(makeCurrentContext),
                                                                 (IMP)swizzled_nsglMakeCurrentContext);
    }
#pragma clang diagnostic pop

    Class listenerCls = objc_getClass("Cocoa_WindowListener");
    if (listenerCls) {
        gOrigScrollWheelIMP = swizzle_instance_method(listenerCls, @selector(scrollWheel:), (IMP)swizzled_scrollWheel);
        gOrigMouseDownIMP = swizzle_instance_method(listenerCls, @selector(mouseDown:), (IMP)swizzled_mouseDown);
        gOrigMouseUpIMP = swizzle_instance_method(listenerCls, @selector(mouseUp:), (IMP)swizzled_mouseUp);
        gOrigMouseDraggedIMP = swizzle_instance_method(listenerCls, @selector(mouseDragged:), (IMP)swizzled_mouseDragged);
        gOrigRightMouseDownIMP = swizzle_instance_method(listenerCls, @selector(rightMouseDown:), (IMP)swizzled_rightMouseDown);
        gOrigRightMouseUpIMP = swizzle_instance_method(listenerCls, @selector(rightMouseUp:), (IMP)swizzled_rightMouseUp);
        gOrigRightMouseDraggedIMP = swizzle_instance_method(listenerCls, @selector(rightMouseDragged:), (IMP)swizzled_rightMouseDragged);
        gOrigOtherMouseDownIMP = swizzle_instance_method(listenerCls, @selector(otherMouseDown:), (IMP)swizzled_otherMouseDown);
        gOrigOtherMouseUpIMP = swizzle_instance_method(listenerCls, @selector(otherMouseUp:), (IMP)swizzled_otherMouseUp);
        gOrigOtherMouseDraggedIMP = swizzle_instance_method(listenerCls, @selector(otherMouseDragged:), (IMP)swizzled_otherMouseDragged);
        gOrigMouseMovedIMP = swizzle_instance_method(listenerCls, @selector(mouseMoved:), (IMP)swizzled_mouseMoved);
        gOrigWindowDidBecomeKeyIMP = swizzle_instance_method(listenerCls, @selector(windowDidBecomeKey:), (IMP)swizzled_windowDidBecomeKey);
        gOrigWindowDidResignKeyIMP = swizzle_instance_method(listenerCls, @selector(windowDidResignKey:), (IMP)swizzled_windowDidResignKey);
        gOrigWindowDidResizeIMP = swizzle_instance_method(listenerCls, @selector(windowDidResize:), (IMP)swizzled_windowDidResize);
        gOrigWindowWillEnterFullScreenIMP = swizzle_instance_method(listenerCls, @selector(windowWillEnterFullScreen:), (IMP)swizzled_windowWillEnterFullScreen);
        gOrigWindowDidEnterFullScreenIMP = swizzle_instance_method(listenerCls, @selector(windowDidEnterFullScreen:), (IMP)swizzled_windowDidEnterFullScreen);
        gOrigWindowDidFailToEnterFullScreenIMP = swizzle_instance_method(listenerCls, @selector(windowDidFailToEnterFullScreen:), (IMP)swizzled_windowDidFailToEnterFullScreen);
        gOrigWindowWillExitFullScreenIMP = swizzle_instance_method(listenerCls, @selector(windowWillExitFullScreen:), (IMP)swizzled_windowWillExitFullScreen);
        gOrigWindowDidExitFullScreenIMP = swizzle_instance_method(listenerCls, @selector(windowDidExitFullScreen:), (IMP)swizzled_windowDidExitFullScreen);
        gOrigWindowDidFailToExitFullScreenIMP = swizzle_instance_method(listenerCls, @selector(windowDidFailToExitFullScreen:), (IMP)swizzled_windowDidFailToExitFullScreen);
        gOrigSetFullscreenSpaceIMP = swizzle_instance_method(listenerCls, @selector(setFullscreenSpace:), (IMP)swizzled_setFullscreenSpace);
    }

    load_display_preferences_from_defaults();

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserverForName:NSApplicationWillResignActiveNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *note) {
        (void)note;
        gAppIsActive = NO;
        gUserWindowMoveInProgress = NO;
        gLastResignTimestamp = CFAbsoluteTimeGetCurrent();
        reset_gesture_and_key_state(resolve_window_listener());
        apply_borderless_presentation_options(NO);
        CGAssociateMouseAndMouseCursorPosition(true);
        CGDisplayShowCursor(kCGDirectMainDisplay);
        debuglog_write("APP", "WillResignActive");
        diaglog_flush();
    }];
    [nc addObserverForName:NSApplicationDidResignActiveNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *note) {
        (void)note;
        gAppIsActive = NO;
        gUserWindowMoveInProgress = NO;
        if (gLastResignTimestamp == 0.0) {
            gLastResignTimestamp = CFAbsoluteTimeGetCurrent();
        }
        debuglog_write("APP", "DidResignActive");
    }];
    [nc addObserverForName:NSApplicationWillBecomeActiveNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *note) {
        (void)note;
        gAppHasActivatedOnce = YES;
        gAppIsActive = YES;
        gAppIsHiding = NO;
        gLastResignTimestamp = 0.0;
        NSWindow *primaryWin = resolve_primary_game_window();
        BOOL inSpace = (primaryWin && ((primaryWin.styleMask & NSWindowStyleMaskFullScreen) != 0));
        if (gWindowedModeActive == NO && !inSpace && !gInFullscreenTransition && gHasCompletedFirstWindowShow) {
            apply_borderless_presentation_options(YES);
        } else {
            apply_borderless_presentation_options(NO);
        }
        neutralize_secondary_orphan_windows(primaryWin);
        if (primaryWin && !gInFullscreenTransition) {
            enforce_primary_window_borderless_fullscreen(primaryWin, "WillBecomeActive");
        }
        debuglog_write("APP", "WillBecomeActive inSpace=%d windowed=%d",
                       inSpace ? 1 : 0, gWindowedModeActive ? 1 : 0);
    }];
    [nc addObserverForName:NSApplicationDidBecomeActiveNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *note) {
        (void)note;
        gAppHasActivatedOnce = YES;
        gAppIsActive = YES;
        gAppIsHiding = NO;
        gLastResignTimestamp = 0.0;
        ensure_workspace_space_observer_registered();
        ensure_sims2_display_menu_installed();
        update_sims2_display_menu_state();
        NSWindow *primaryWin = resolve_primary_game_window();
        neutralize_secondary_orphan_windows(primaryWin);
        if (primaryWin && !gInFullscreenTransition) {
            enforce_primary_window_borderless_fullscreen(primaryWin, "DidBecomeActive");
            restore_game_window_focus_and_input(primaryWin, "DidBecomeActive");
            if (!gWindowedModeActive && ((primaryWin.styleMask & NSWindowStyleMaskFullScreen) != 0)) {
                refresh_opengl_surface_for_screen_or_backing_change(primaryWin, "DidBecomeActive");
            }
            uint64_t activeGen = current_display_transition_gen();
            __weak NSWindow *weakWin = primaryWin;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60 * NSEC_PER_MSEC)),
                           dispatch_get_main_queue(), ^{
                if (current_display_transition_gen() != activeGen || gInFullscreenTransition || gAppIsTerminating) {
                    return;
                }
                NSWindow *w = weakWin;
                if (w && NSApp && [NSApp isActive] && !gAppIsHiding) {
                    restore_game_window_focus_and_input(w, "DidBecomeActiveSettle");
                }
            });
        } else if (gWindowedModeActive) {
            apply_borderless_presentation_options(NO);
        }
        debuglog_write("APP", "DidBecomeActive");
    }];
    [nc addObserverForName:NSApplicationWillHideNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *note) {
        (void)note;
        gAppIsHiding = YES;
        apply_borderless_presentation_options(NO);
        debuglog_write("APP", "WillHide");
        diaglog_flush();
    }];
    [nc addObserverForName:NSApplicationDidUnhideNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *note) {
        (void)note;
        gAppIsHiding = NO;
        debuglog_write("APP", "DidUnhide");
    }];
    [nc addObserverForName:NSApplicationWillTerminateNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *note) {
        (void)note;
        gAppIsTerminating = YES;
        apply_borderless_presentation_options(NO);
        debuglog_write("APP", "WillTerminate");
        diaglog_flush();
    }];

    uint16_t initLeft = 43, initRight = 47;
    resolve_camera_rotate_keycodes(&initLeft, &initRight);
    register_window_geometry_observers();
    size_t cgHooks = hook_coregraphics_la_symbol_ptrs();
    record_last_hook_state("init-complete");

    NSString *bundleStr = [[NSBundle mainBundle] bundleIdentifier];
    const char *bundleId = bundleStr ? [bundleStr UTF8String] : "unknown";
    debuglog_write("INIT",
                   "pid=%d bundle=%s execSlide=0x%lx appHook=%d focusHook=%d keyWinHook=%d scrollHook=%d btnHook=%d "
                   "modHook=%d mouseMoved=%d fsSpaceHook=%d failFsHook=%d validateMenuHook=%d sdlViewHook=%d "
                   "miniHook=%d activateHook=%d cgHooks=%zu rotKeys=(%u,%u) invert=%d ctrlOrbit=%d "
                   "debugLog=%s diagLog=%s",
                   getpid(),
                   bundleId ? bundleId : "unknown",
                   (unsigned long)gExecSlide,
                   gOrigNextEventIMP != NULL,
                   gOrigFocusSomeWindowIMP != NULL,
                   gOrigCanBecomeKeyWindowIMP != NULL,
                   gOrigScrollWheelIMP != NULL,
                   gOrigButtonNumberIMP != NULL,
                   gOrigEventModifierFlagsIMP != NULL,
                   gOrigMouseMovedIMP != NULL,
                   gOrigSetFullscreenSpaceIMP != NULL,
                   gOrigWindowDidFailToEnterFullScreenIMP != NULL,
                   gOrigSDLValidateMenuItemIMP != NULL,
                   gOrigSDLViewMouseDownCanMoveWindowIMP != NULL,
                   gOrigMiniaturizeIMP != NULL,
                   gOrigActivateIgnoringOtherAppsIMP != NULL,
                   cgHooks,
                   initLeft,
                   initRight,
                   gInvertRotation,
                   gEnableOptionOrbit,
                   gDebugLogPath[0] ? gDebugLogPath : "disabled",
                   (gDiagLogEnabled && gDiagLogPath[0]) ? gDiagLogPath : "disabled");

    log_msg([NSString stringWithFormat:
             @"Loaded v%s: appHook=%d focusHook=%d keyWinHook=%d scrollHook=%d btnHook=%d modHook=%d mouseMoved=%d fsSpaceHook=%d miniHook=%d activateHook=%d cgHooks=%zu rotKeys=(%u,%u) invert=%d ctrlOrbit=%d",
             SIMS2_PATCH_VERSION,
             gOrigNextEventIMP != NULL,
             gOrigFocusSomeWindowIMP != NULL,
             gOrigCanBecomeKeyWindowIMP != NULL,
             gOrigScrollWheelIMP != NULL,
             gOrigButtonNumberIMP != NULL,
             gOrigEventModifierFlagsIMP != NULL,
             gOrigMouseMovedIMP != NULL,
             gOrigSetFullscreenSpaceIMP != NULL,
             gOrigMiniaturizeIMP != NULL,
             gOrigActivateIgnoringOtherAppsIMP != NULL,
             cgHooks,
             initLeft,
             initRight,
             gInvertRotation,
             gEnableOptionOrbit]);
}
