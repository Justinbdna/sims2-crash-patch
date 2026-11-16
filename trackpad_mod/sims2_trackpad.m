#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dlfcn.h>
#import <execinfo.h>
#import <fcntl.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
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
 * libsims2_trackpad.dylib (v1.4.0)
 * Free & open-source Trackpad, Display & Stability helper for The Sims 2: Super Collection (macOS).
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
 *      and on-demand debug_boot.log when SIMS2_DEBUG=1 or ~/.debug_enabled is present.
 *
 * Env config (optional overrides):
 *   SIMS2_ROTATE_INVERT=0|1      (default 0)
 *   SIMS2_ROTATE_STEP=<float>    (default 28.0 trackpad points per rotation step)
 *   SIMS2_TWIST_STEP=<float>     (default 12.0 degrees per rotation step)
 *   SIMS2_PINCH_STEP=<float>     (default 0.08 magnification units per zoom step)
 *   SIMS2_CTRL_ORBIT=0|1         (default 1, Control+drag emulates middle mouse button)
 *   SIMS2_OPTION_ORBIT=0|1       (legacy fallback alias if SIMS2_CTRL_ORBIT is unset)
 *   SIMS2_DEBUG=0|1              (default 0, writes ~/Library/Logs/Sims2-Crash-Patch/debug_boot.log)
 *   SIMS2_TRACKPAD_DEBUG=0|1     (default 0, logs via NSLog)
 */

#define SIMS2_PATCH_VERSION "1.4.0"

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
static IMP gOrigMouseMovedIMP = NULL;
static IMP gOrigWindowDidBecomeKeyIMP = NULL;
static IMP gOrigWindowDidResignKeyIMP = NULL;
static IMP gOrigWindowWillEnterFullScreenIMP = NULL;
static IMP gOrigWindowDidEnterFullScreenIMP = NULL;
static IMP gOrigWindowWillExitFullScreenIMP = NULL;
static IMP gOrigWindowDidExitFullScreenIMP = NULL;
static IMP gOrigSetFullscreenSpaceIMP = NULL;
static IMP gOrigMiniaturizeIMP = NULL;
static IMP gOrigMakeKeyAndOrderFrontIMP = NULL;
static IMP gOrigOrderFrontRegardlessIMP = NULL;
static IMP gOrigActivateIgnoringOtherAppsIMP = NULL;
static IMP gOrigFocusSomeWindowIMP = NULL;
static IMP gOrigCanBecomeKeyWindowIMP = NULL;
static IMP gOrigCanBecomeMainWindowIMP = NULL;

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
static __weak NSWindow *gLastMouseDownWindow = nil;
static __weak NSWindow *gPrimaryFullscreenWindow = nil;
static __weak id gWindowListener = nil;

static BOOL gAppHasActivatedOnce = NO;
static BOOL gAppIsActive = YES;
static BOOL gAppIsHiding = NO;
static BOOL gInFullscreenTransition = NO;
static CFAbsoluteTime gLastResignTimestamp = 0.0;

static BOOL gDebugBootEnabled = NO;
static FILE *gDebugLogFile = NULL;
static pthread_mutex_t gDebugLogMutex = PTHREAD_MUTEX_INITIALIZER;

static char gLibDir[512] = {0};
static char gLogsRootDir[512] = {0};
static char gLogsDir[512] = {0};
static char gCrashLogPath[600] = {0};
static char gDebugLogPath[600] = {0};
static char gDebugPrevLogPath[600] = {0};
static char gDebugFlagPath[600] = {0};

static char gCachedHwModel[128] = "unknown";
static char gCachedOsVersion[128] = "unknown";
static char gCachedFrameStr[128] = "unknown";
static char gCachedVisibleFrameStr[128] = "unknown";
static char gLastCxaThrowInfo[384] = "none";
static volatile int gCrashReportWritten = 0;

static struct sigaction gPrevSigActions[32];
typedef void (*Sims2TerminateHandler)(void);
static Sims2TerminateHandler gPrevTerminateHandler = NULL;

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

static void debuglog_write(const char *category, const char *fmt, ...) {
    if (!gDebugBootEnabled || !gDebugLogFile || !fmt) {
        return;
    }
    struct timeval tv;
    gettimeofday(&tv, NULL);
    time_t sec = tv.tv_sec;
    struct tm tm_info;
    localtime_r(&sec, &tm_info);

    char msgBuf[1536];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(msgBuf, sizeof(msgBuf), fmt, ap);
    va_end(ap);

    pthread_mutex_lock(&gDebugLogMutex);
    if (gDebugLogFile) {
        fprintf(gDebugLogFile, "[%02d:%02d:%02d.%03d] [%s] %s\n",
                tm_info.tm_hour, tm_info.tm_min, tm_info.tm_sec, (int)(tv.tv_usec / 1000),
                category ? category : "LOG", msgBuf);
        fflush(gDebugLogFile);
    }
    pthread_mutex_unlock(&gDebugLogMutex);
}

static void init_log_paths_and_system_info(void) {
    const char *home = getenv("HOME");
    if (!home || home[0] == '\0') {
        NSString *nsHome = NSHomeDirectory();
        home = nsHome ? [nsHome UTF8String] : NULL;
    }
    if (home && home[0] != '\0') {
        snprintf(gLibDir, sizeof(gLibDir), "%s/Library", home);
        snprintf(gLogsRootDir, sizeof(gLogsRootDir), "%s/Library/Logs", home);
        snprintf(gLogsDir, sizeof(gLogsDir), "%s/Library/Logs/Sims2-Crash-Patch", home);
        snprintf(gCrashLogPath, sizeof(gCrashLogPath), "%s/crash_report.log", gLogsDir);
        snprintf(gDebugLogPath, sizeof(gDebugLogPath), "%s/debug_boot.log", gLogsDir);
        snprintf(gDebugPrevLogPath, sizeof(gDebugPrevLogPath), "%s/debug_boot.previous.log", gLogsDir);
        snprintf(gDebugFlagPath, sizeof(gDebugFlagPath), "%s/.debug_enabled", gLogsDir);
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

static void write_crash_report_async_safe(const char *reason, int sig, siginfo_t *info) {
    if (!__sync_bool_compare_and_swap(&gCrashReportWritten, 0, 1)) {
        return;
    }
    if (gCrashLogPath[0] == '\0') {
        return;
    }
    mkdir(gLibDir, 0755);
    mkdir(gLogsRootDir, 0755);
    mkdir(gLogsDir, 0755);

    int fd = open(gCrashLogPath, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0644);
    if (fd < 0) {
        return;
    }

    write_cstr_fd(fd, "=== Sims 2 Crash Patch — Automatic Crash Report ===\n");
    write_cstr_fd(fd, "Patch Version : " SIMS2_PATCH_VERSION "\n");
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
    if (info && info->si_addr != NULL) {
        write_cstr_fd(fd, "\nFault Address : ");
        write_hex_fd(fd, (uintptr_t)info->si_addr);
    }
    write_cstr_fd(fd, "\nLast C++ Throw: ");
    write_cstr_fd(fd, gLastCxaThrowInfo);
    write_cstr_fd(fd, "\n\n--- Backtrace ---\n");

    void *frames[64];
    int nframes = backtrace(frames, 64);
    if (nframes > 0) {
        backtrace_symbols_fd(frames, nframes, fd);
    } else {
        write_cstr_fd(fd, "(unavailable)\n");
    }
    close(fd);
}

static void sims2_crash_signal_handler(int sig, siginfo_t *info, void *uap) {
    (void)uap;
    write_crash_report_async_safe("Fatal Signal", sig, info);
    if (sig > 0 && sig < 32) {
        sigaction(sig, &gPrevSigActions[sig], NULL);
        raise(sig);
    }
    _exit(128 + sig);
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
    static const int kCrashSignals[] = { SIGSEGV, SIGABRT, SIGBUS, SIGILL, SIGFPE };
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = sims2_crash_signal_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_SIGINFO;

    for (size_t i = 0; i < sizeof(kCrashSignals) / sizeof(kCrashSignals[0]); i++) {
        int sig = kCrashSignals[i];
        if (sig > 0 && sig < 32) {
            sigaction(sig, &sa, &gPrevSigActions[sig]);
        }
    }

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
                debuglog_write("GESTURE", "SCROLL_LOCK axis=RotateX dx=%.2f dy=%.2f", fingerRightDx, dy);
            } else {
                gScrollAxis = Sims2ScrollAxisZoomY;
                debuglog_write("GESTURE", "SCROLL_LOCK axis=ZoomY dx=%.2f dy=%.2f", fingerRightDx, dy);
            }
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
    if (phase == NSEventPhaseBegan || phase == NSEventPhaseMayBegin ||
        phase == NSEventPhaseEnded || phase == NSEventPhaseCancelled) {
        gPinchAccum = 0.0;
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
    NSWindow *win = gLastMouseDownWindow;
    IMP upIMP = gCtrlDragWasRight ? gOrigRightMouseUpIMP : gOrigMouseUpIMP;
    SEL upSEL = gCtrlDragWasRight ? @selector(rightMouseUp:) : @selector(mouseUp:);
    NSEventType upType = gCtrlDragWasRight ? NSEventTypeRightMouseUp : NSEventTypeLeftMouseUp;

    debuglog_write("CAM", "CTRL_ORBIT_END_SYNTH btn=%s", gCtrlDragWasRight ? "right" : "left");

    if (win && upIMP) {
        NSTimeInterval ts = [[NSProcessInfo processInfo] systemUptime];
        NSEvent *synthUp = [NSEvent mouseEventWithType:upType
                                              location:NSZeroPoint
                                         modifierFlags:0
                                             timestamp:ts
                                          windowNumber:[win windowNumber]
                                               context:nil
                                           eventNumber:0
                                            clickCount:1
                                              pressure:0.0];
        if (synthUp && listener) {
            typedef void (*MouseUpFn)(id, SEL, NSEvent *);
            gSpoofMiddleButton = YES;
            gMaskControlModifier = YES;
            ((MouseUpFn)upIMP)(listener, upSEL, synthUp);
            gSpoofMiddleButton = NO;
            gMaskControlModifier = NO;
        }
    }
    gCtrlMiddleDragActive = NO;
    gCtrlDragWasRight = NO;
    gLastMouseDownWindow = nil;
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
        case 123: snprintf(outBuf, outBufSize, "Left"); return;
        case 124: snprintf(outBuf, outBufSize, "Right"); return;
        case 125: snprintf(outBuf, outBufSize, "Down"); return;
        case 126: snprintf(outBuf, outBufSize, "Up"); return;
        default: break;
    }
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
    snprintf(outBuf, outBufSize, "kc=%u", (unsigned int)kc);
}

static NSEvent *swizzled_nextEventMatchingMask(id self, SEL _cmd, NSEventMask mask,
                                               NSDate *expiration, NSRunLoopMode mode, BOOL dequeue) {
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
            if (![ev isARepeat] && gDebugBootEnabled) {
                NSEventModifierFlags rawFlags = raw_event_modifier_flags(ev);
                BOOL isSynth = ([ev CGEvent] == NULL);
                char keyLabel[32];
                format_key_label(ev, keyLabel, sizeof(keyLabel));
                debuglog_write("KEY", "%s keyCode=%u key=%s synth=%d ctrl=%d opt=%d shift=%d cmd=%d",
                               (t == NSEventTypeKeyDown) ? "keyDown" : "keyUp",
                               (unsigned int)[ev keyCode],
                               keyLabel,
                               isSynth ? 1 : 0,
                               (rawFlags & NSEventModifierFlagControl) ? 1 : 0,
                               (rawFlags & NSEventModifierFlagOption) ? 1 : 0,
                               (rawFlags & NSEventModifierFlagShift) ? 1 : 0,
                               (rawFlags & NSEventModifierFlagCommand) ? 1 : 0);
            }
        } else if (t == NSEventTypeFlagsChanged) {
            NSEventModifierFlags rawFlags = raw_event_modifier_flags(ev);
            if (gCtrlMiddleDragActive && ((rawFlags & NSEventModifierFlagControl) == 0)) {
                release_ctrl_middle_drag(resolve_window_listener());
            }
            if (gDebugBootEnabled) {
                NSUInteger trackedMods = rawFlags & (NSEventModifierFlagControl |
                                                     NSEventModifierFlagOption |
                                                     NSEventModifierFlagShift |
                                                     NSEventModifierFlagCommand);
                if (trackedMods != gLastLoggedModifierMask) {
                    gLastLoggedModifierMask = trackedMods;
                    debuglog_write("MOD", "flags ctrl=%d opt=%d shift=%d cmd=%d (raw=0x%lx)",
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
        ((Fn)gOrigScrollWheelIMP)(self, _cmd, event);
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

static void handle_camera_mouse_down(id self, SEL _cmd, NSEvent *event, IMP origIMP, BOOL isRight) {
    gWindowListener = self;
    typedef void (*Fn)(id, SEL, NSEvent *);
    if (!origIMP) {
        return;
    }
    if (gSpoofMiddleButton) {
        ((Fn)origIMP)(self, _cmd, event);
        return;
    }
    NSEventModifierFlags rawFlags = raw_event_modifier_flags(event);
    BOOL ctrlHeld = (rawFlags & NSEventModifierFlagControl) != 0;
    BOOL cmdHeld = (rawFlags & NSEventModifierFlagCommand) != 0;

    if (gEnableOptionOrbit && !gCtrlMiddleDragActive && ctrlHeld && !cmdHeld) {
        gCtrlMiddleDragActive = YES;
        gCtrlDragWasRight = isRight;
        gLastMouseDownWindow = [event window];
        debuglog_write("CAM", "CTRL_ORBIT_START btn=%s win=%p",
                       isRight ? "right" : "left", (__bridge void *)gLastMouseDownWindow);
        gSpoofMiddleButton = YES;
        gMaskControlModifier = YES;
        ((Fn)origIMP)(self, _cmd, event);
        gSpoofMiddleButton = NO;
        gMaskControlModifier = NO;
        return;
    }
    if (gCtrlMiddleDragActive) {
        return;
    }
    if (isRight && [event type] == NSEventTypeRightMouseDown) {
        BOOL optHeld = (rawFlags & NSEventModifierFlagOption) != 0;
        debuglog_write("CAM", "NATIVE_RIGHT_CLICK_DOWN opt=%d win=%p",
                       optHeld ? 1 : 0, (__bridge void *)[event window]);
    } else if (!isRight && [event type] == NSEventTypeLeftMouseDown &&
               (rawFlags & NSEventModifierFlagOption) != 0) {
        debuglog_write("CAM", "NATIVE_OPTION_LEFT_CLICK_DOWN win=%p",
                       (__bridge void *)[event window]);
    }
    ((Fn)origIMP)(self, _cmd, event);
}

static void handle_camera_mouse_drag(id self, SEL _cmd, NSEvent *event, IMP origIMP, BOOL isRight) {
    gWindowListener = self;
    typedef void (*Fn)(id, SEL, NSEvent *);
    if (!origIMP) {
        return;
    }
    if (gCtrlMiddleDragActive) {
        NSEventModifierFlags rawFlags = raw_event_modifier_flags(event);
        if ((rawFlags & NSEventModifierFlagControl) == 0) {
            release_ctrl_middle_drag(self);
            return;
        }
        if (isRight == gCtrlDragWasRight) {
            gSpoofMiddleButton = YES;
            gMaskControlModifier = YES;
            ((Fn)origIMP)(self, _cmd, event);
            gSpoofMiddleButton = NO;
            gMaskControlModifier = NO;
        }
        return;
    }
    ((Fn)origIMP)(self, _cmd, event);
}

static void handle_camera_mouse_up(id self, SEL _cmd, NSEvent *event, IMP origIMP, BOOL isRight) {
    gWindowListener = self;
    typedef void (*Fn)(id, SEL, NSEvent *);
    if (!origIMP) {
        return;
    }
    if (gSpoofMiddleButton) {
        ((Fn)origIMP)(self, _cmd, event);
        return;
    }
    if (gCtrlMiddleDragActive) {
        if (isRight == gCtrlDragWasRight) {
            debuglog_write("CAM", "CTRL_ORBIT_END btn=%s", isRight ? "right" : "left");
            gCtrlMiddleDragActive = NO;
            gCtrlDragWasRight = NO;
            gLastMouseDownWindow = nil;
            gSpoofMiddleButton = YES;
            gMaskControlModifier = YES;
            ((Fn)origIMP)(self, _cmd, event);
            gSpoofMiddleButton = NO;
            gMaskControlModifier = NO;
        }
        return;
    }
    if (isRight && [event type] == NSEventTypeRightMouseUp) {
        debuglog_write("CAM", "NATIVE_RIGHT_CLICK_UP win=%p", (__bridge void *)[event window]);
    }
    ((Fn)origIMP)(self, _cmd, event);
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

/*
 * Prevent SDL2 Cocoa_WindowListener::mouseMoved: from calling CGDisplayMoveCursorToPoint
 * when the game window is inactive or not key (Space transitions / Cmd+Tab / Dock clicks).
 */
static void swizzled_mouseMoved(id self, SEL _cmd, NSEvent *event) {
    gWindowListener = self;
    NSWindow *win = [event window] ?: [NSApp keyWindow];
    if (!gAppIsActive || ![NSApp isActive] || !win || ![win isKeyWindow]) {
        return;
    }
    if (gDebugBootEnabled && event && [event type] == NSEventTypeMouseMoved) {
        NSEventModifierFlags rawFlags = raw_event_modifier_flags(event);
        if ((rawFlags & NSEventModifierFlagOption) != 0) {
            CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
            if ((now - gLastOptionHoverLogTime) >= 0.5) {
                gLastOptionHoverLogTime = now;
                NSPoint pt = [event locationInWindow];
                debuglog_write("CAM", "NATIVE_OPTION_HOVER_MOVE loc=(%.1f,%.1f) delta=(%.1f,%.1f)",
                               pt.x, pt.y, [event deltaX], [event deltaY]);
            }
        }
    }
    if (gOrigMouseMovedIMP) {
        typedef void (*Fn)(id, SEL, NSEvent *);
        ((Fn)gOrigMouseMovedIMP)(self, _cmd, event);
    }
}

static void reset_gesture_and_key_state(id listener) {
    release_ctrl_middle_drag(listener);
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
    NSWindow *win = (NSWindow *)winObj;
    id delegate = [win delegate];
    Class listenerCls = objc_getClass("Cocoa_WindowListener");
    if (delegate && listenerCls && [delegate isKindOfClass:listenerCls]) {
        return YES;
    }
    return NO;
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

static void swizzled_windowDidBecomeKey(id self, SEL _cmd, NSNotification *notification) {
    gWindowListener = self;
    id obj = [notification object];
    BOOL isWin = [obj isKindOfClass:[NSWindow class]];
    NSRect frame = isWin ? [(NSWindow *)obj frame] : NSZeroRect;
    BOOL isFS = isWin ? (([(NSWindow *)obj styleMask] & NSWindowStyleMaskFullScreen) != 0) : NO;

    if (isFS && isWin) {
        neutralize_secondary_orphan_windows((NSWindow *)obj);
    } else if (is_secondary_orphan_game_window(obj)) {
        neutralize_single_orphan_window((NSWindow *)obj);
        debuglog_write("WIN", "SUPPRESSED orphan windowDidBecomeKey win=%p -> restoring primary=%p",
                       (__bridge void *)obj, (__bridge void *)gPrimaryFullscreenWindow);
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
                   (__bridge void *)obj, (NSApp && [NSApp isActive]) ? 1 : 0, isFS ? 1 : 0,
                   frame.size.width, frame.size.height);

    if (gOrigWindowDidBecomeKeyIMP) {
        typedef void (*BecomeFn)(id, SEL, NSNotification *);
        ((BecomeFn)gOrigWindowDidBecomeKeyIMP)(self, _cmd, notification);
    }
}

static void swizzled_windowDidResignKey(id self, SEL _cmd, NSNotification *notification) {
    id obj = [notification object];
    if (is_secondary_orphan_game_window(obj)) {
        debuglog_write("WIN", "IGNORED orphan windowDidResignKey win=%p", (__bridge void *)obj);
        return;
    }
    gWindowListener = self;
    gLastResignTimestamp = CFAbsoluteTimeGetCurrent();
    reset_gesture_and_key_state(self);
    CGAssociateMouseAndMouseCursorPosition(true);
    CGDisplayShowCursor(kCGDirectMainDisplay);
    debuglog_write("WIN", "windowDidResignKey win=%p active=%d",
                   (__bridge void *)obj, (NSApp && [NSApp isActive]) ? 1 : 0);

    if (gOrigWindowDidResignKeyIMP) {
        typedef void (*ResignFn)(id, SEL, NSNotification *);
        ((ResignFn)gOrigWindowDidResignKeyIMP)(self, _cmd, notification);
    }
}

static void swizzled_windowWillEnterFullScreen(id self, SEL _cmd, NSNotification *notification) {
    gWindowListener = self;
    gInFullscreenTransition = YES;
    id obj = [notification object];
    if ([obj isKindOfClass:[NSWindow class]]) {
        neutralize_secondary_orphan_windows((NSWindow *)obj);
    }
    debuglog_write("WIN", "windowWillEnterFullScreen win=%p", (__bridge void *)obj);

    if (gOrigWindowWillEnterFullScreenIMP) {
        typedef void (*EnterFSFn)(id, SEL, NSNotification *);
        ((EnterFSFn)gOrigWindowWillEnterFullScreenIMP)(self, _cmd, notification);
    }
}

static void swizzled_windowDidEnterFullScreen(id self, SEL _cmd, NSNotification *notification) {
    gWindowListener = self;
    gInFullscreenTransition = NO;
    id obj = [notification object];
    if ([obj isKindOfClass:[NSWindow class]]) {
        neutralize_secondary_orphan_windows((NSWindow *)obj);
    }
    debuglog_write("WIN", "windowDidEnterFullScreen win=%p", (__bridge void *)obj);

    if (gOrigWindowDidEnterFullScreenIMP) {
        typedef void (*DidEnterFSFn)(id, SEL, NSNotification *);
        ((DidEnterFSFn)gOrigWindowDidEnterFullScreenIMP)(self, _cmd, notification);
    }
}

static void swizzled_windowWillExitFullScreen(id self, SEL _cmd, NSNotification *notification) {
    gWindowListener = self;
    gInFullscreenTransition = YES;
    reset_gesture_and_key_state(self);
    debuglog_write("WIN", "windowWillExitFullScreen win=%p active=%d",
                   (__bridge void *)[notification object], (NSApp && [NSApp isActive]) ? 1 : 0);

    if (gOrigWindowWillExitFullScreenIMP) {
        typedef void (*ExitFSFn)(id, SEL, NSNotification *);
        ((ExitFSFn)gOrigWindowWillExitFullScreenIMP)(self, _cmd, notification);
    }
}

static void swizzled_windowDidExitFullScreen(id self, SEL _cmd, NSNotification *notification) {
    gWindowListener = self;
    gInFullscreenTransition = NO;
    if ([notification object] == gPrimaryFullscreenWindow) {
        gPrimaryFullscreenWindow = nil;
    }
    debuglog_write("WIN", "windowDidExitFullScreen win=%p active=%d",
                   (__bridge void *)[notification object], (NSApp && [NSApp isActive]) ? 1 : 0);

    if (gOrigWindowDidExitFullScreenIMP) {
        typedef void (*DidExitFSFn)(id, SEL, NSNotification *);
        ((DidExitFSFn)gOrigWindowDidExitFullScreenIMP)(self, _cmd, notification);
    }
}

static BOOL swizzled_setFullscreenSpace(id self, SEL _cmd, BOOL state) {
    gWindowListener = self;
    if (!state && !gAppIsHiding && !(NSApp && [NSApp isHidden]) &&
        should_suppress_focus_steal_or_fullscreen_exit()) {
        CFAbsoluteTime dt = (gLastResignTimestamp > 0.0) ? (CFAbsoluteTimeGetCurrent() - gLastResignTimestamp) : -1.0;
        debuglog_write("WIN", "SUPPRESSED setFullscreenSpace:NO (active=%d nsActive=%d dt=%.3fs)",
                       gAppIsActive ? 1 : 0, (NSApp && [NSApp isActive]) ? 1 : 0, dt);
        return YES;
    }
    debuglog_write("WIN", "setFullscreenSpace:%d (active=%d hiding=%d)",
                   state ? 1 : 0, gAppIsActive ? 1 : 0, gAppIsHiding ? 1 : 0);
    if (gOrigSetFullscreenSpaceIMP) {
        typedef BOOL (*Fn)(id, SEL, BOOL);
        return ((Fn)gOrigSetFullscreenSpaceIMP)(self, _cmd, state);
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
    if (flag && gAppHasActivatedOnce &&
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

/*
 * Real hardware display-mode filter (CGDisplayCopyAllDisplayModes) + dynamic
 * NSScreen.visibleFrame fullscreen clamping (no synthetic modes).
 */
typedef struct {
    size_t width;
    size_t height;
} Sims2CatalogResolution;

static const Sims2CatalogResolution kSims2ResolutionWhitelist[] = {
    { 1280,  800 }, { 1440,  900 }, { 1470,  956 }, { 1512,  982 },
    { 1680, 1050 }, { 1728, 1080 }, { 1728, 1117 }, { 1800, 1169 },
    { 1920, 1080 }, { 1920, 1200 }, { 2048, 1280 }, { 2056, 1329 },
    { 2560, 1440 }, { 2560, 1600 },
};
static const size_t kSims2WhitelistCount =
    sizeof(kSims2ResolutionWhitelist) / sizeof(kSims2ResolutionWhitelist[0]);

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

static BOOL is_whitelisted_or_desktop(size_t w, size_t h, size_t curW, size_t curH) {
    if (w < 800 || h < 600 || w <= h || w > 2560 || h > 1600) {
        return NO;
    }
    if (w == curW && h == curH) {
        return YES;
    }
    for (size_t i = 0; i < kSims2WhitelistCount; i++) {
        if (kSims2ResolutionWhitelist[i].width == w && kSims2ResolutionWhitelist[i].height == h) {
            return YES;
        }
    }
    return NO;
}

static CFArrayRef hook_CGDisplayCopyAllDisplayModes(CGDirectDisplayID display,
                                                    CFDictionaryRef options) {
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

    CFIndex realCount = CFArrayGetCount(realModes);
    CFMutableArrayRef result = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    if (!result) {
        return realModes;
    }

    /* Keep one genuine macOS mode per WxH (closest to 60 Hz, then 1x backing). */
    for (CFIndex i = 0; i < realCount; i++) {
        CGDisplayModeRef m = (CGDisplayModeRef)CFArrayGetValueAtIndex(realModes, i);
        if (!m) {
            continue;
        }
        size_t w = CGDisplayModeGetWidth(m);
        size_t h = CGDisplayModeGetHeight(m);
        if (!is_whitelisted_or_desktop(w, h, curW, curH) || !is_32bit_argb_pixel_encoding(m)) {
            continue;
        }
        double hz = CGDisplayModeGetRefreshRate(m);
        double delta = fabs((hz > 0.1 ? hz : 60.0) - 60.0);
        BOOL is1x = (CGDisplayModeGetPixelWidth(m) == w && CGDisplayModeGetPixelHeight(m) == h);

        CFIndex existing = -1;
        CFIndex resCount = CFArrayGetCount(result);
        for (CFIndex r = 0; r < resCount; r++) {
            CGDisplayModeRef e = (CGDisplayModeRef)CFArrayGetValueAtIndex(result, r);
            if (CGDisplayModeGetWidth(e) == w && CGDisplayModeGetHeight(e) == h) {
                existing = r;
                break;
            }
        }
        if (existing < 0) {
            CFArrayAppendValue(result, m);
            continue;
        }
        CGDisplayModeRef e = (CGDisplayModeRef)CFArrayGetValueAtIndex(result, existing);
        double eHz = CGDisplayModeGetRefreshRate(e);
        double eDelta = fabs((eHz > 0.1 ? eHz : 60.0) - 60.0);
        BOOL e1x = (CGDisplayModeGetPixelWidth(e) == w && CGDisplayModeGetPixelHeight(e) == h);
        if (delta < eDelta - 0.5 || (fabs(delta - eDelta) <= 0.5 && is1x && !e1x)) {
            CFArraySetValueAtIndex(result, existing, m);
        }
    }

    CFIndex keptCount = CFArrayGetCount(result);
    if (keptCount == 0) {
        CFRelease(result);
        debuglog_write("DISPLAY", "filter kept 0/%ld modes -> returning unfiltered macOS list", (long)realCount);
        return realModes;
    }

    if (gDebugBootEnabled) {
        static int sLoggedEnum = 0;
        if (sLoggedEnum < 4) {
            sLoggedEnum++;
            char listBuf[1024];
            size_t off = 0;
            listBuf[0] = '\0';
            for (CFIndex r = 0; r < keptCount && off < sizeof(listBuf) - 32; r++) {
                CGDisplayModeRef e = (CGDisplayModeRef)CFArrayGetValueAtIndex(result, r);
                off += (size_t)snprintf(listBuf + off, sizeof(listBuf) - off, "%s%zux%zu@%.0f",
                                        r ? "," : "",
                                        CGDisplayModeGetWidth(e), CGDisplayModeGetHeight(e),
                                        CGDisplayModeGetRefreshRate(e));
            }
            debuglog_write("DISPLAY", "CGDisplayCopyAllDisplayModes(display=%u) real=%ld kept=%ld desktop=%zux%zu modes=[%s]",
                           (unsigned)display, (long)realCount, (long)keptCount, curW, curH, listBuf);
        }
    }

    CFRelease(realModes);
    return (CFArrayRef)result;
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

static void debuglog_window_geometry(const char *reason, NSWindow *win) {
    if (!gDebugBootEnabled || !win) {
        return;
    }
    NSScreen *scr = win.screen ?: [NSScreen mainScreen];
    NSRect f = win.frame;
    NSRect cb = win.contentView ? win.contentView.bounds : NSZeroRect;
    NSRect sf = scr ? scr.frame : NSZeroRect;
    NSRect vf = scr ? scr.visibleFrame : NSZeroRect;
    BOOL fs = (win.styleMask & NSWindowStyleMaskFullScreen) != 0;
    debuglog_write("WIN", "%s win=%p class=%s fs=%d frame=%.0fx%.0f@(%.0f,%.0f) content=%.0fx%.0f "
                   "screen=%.0fx%.0f visible=%.0fx%.0f@(%.0f,%.0f) scale=%.1f",
                   reason, (__bridge void *)win, object_getClassName(win), fs,
                   f.size.width, f.size.height, f.origin.x, f.origin.y,
                   cb.size.width, cb.size.height,
                   sf.size.width, sf.size.height,
                   vf.size.width, vf.size.height, vf.origin.x, vf.origin.y,
                   scr ? scr.backingScaleFactor : 0.0);
}

static void clamp_fullscreen_window_to_visible_frame(NSWindow *win) {
    if (gNotchFitInProgress || !win || !is_sdl_game_window(win) ||
        !(win.styleMask & NSWindowStyleMaskFullScreen)) {
        return;
    }
    NSScreen *scr = win.screen ?: [NSScreen mainScreen];
    if (!scr) {
        return;
    }
    update_cached_screen_geometry(scr);
    NSRect vf = scr.visibleFrame;
    NSRect f = win.frame;
    if (vf.size.width < 640.0 || vf.size.height < 480.0) {
        return;
    }
    if (fabs(f.size.width - vf.size.width) <= 1.0 && fabs(f.size.height - vf.size.height) <= 1.0 &&
        fabs(f.origin.x - vf.origin.x) <= 1.0 && fabs(f.origin.y - vf.origin.y) <= 1.0) {
        gNotchTargetFrame = vf;
        gNotchClampAttempts = 0;
        return;
    }
    if (NSEqualRects(gNotchTargetFrame, vf) && gNotchClampAttempts >= 8) {
        return;
    }
    if (!NSEqualRects(gNotchTargetFrame, vf)) {
        gNotchTargetFrame = vf;
        gNotchClampAttempts = 0;
    }
    gNotchClampAttempts++;
    gNotchFitInProgress = YES;
    debuglog_write("WIN", "clamp fs #%d %.0fx%.0f@(%.0f,%.0f) -> visibleFrame %.0fx%.0f@(%.0f,%.0f)",
                   gNotchClampAttempts,
                   f.size.width, f.size.height, f.origin.x, f.origin.y,
                   vf.size.width, vf.size.height, vf.origin.x, vf.origin.y);
    [win setFrame:vf display:YES];
    if (win.contentView) {
        NSRect bounds = NSMakeRect(0.0, 0.0, vf.size.width, vf.size.height);
        if (!NSEqualRects(win.contentView.frame, bounds)) {
            [win.contentView setFrame:bounds];
        }
    }
    gNotchFitInProgress = NO;
    debuglog_window_geometry("after-clamp", win);
}

static void register_window_geometry_observers(void) {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserverForName:NSApplicationDidFinishLaunchingNotification object:nil queue:nil
                usingBlock:^(NSNotification *note) {
        (void)note;
        NSScreen *scr = [NSScreen mainScreen];
        update_cached_screen_geometry(scr);
        if (scr) {
            NSRect sf = scr.frame;
            NSRect vf = scr.visibleFrame;
            debuglog_write("SCREEN", "main frame=%.0fx%.0f visibleFrame=%.0fx%.0f@(%.0f,%.0f) scale=%.1f",
                           sf.size.width, sf.size.height, vf.size.width, vf.size.height,
                           vf.origin.x, vf.origin.y, scr.backingScaleFactor);
        }
        debuglog_write("APP", "DidFinishLaunching");
    }];
    [nc addObserverForName:NSWindowDidBecomeKeyNotification object:nil queue:nil
                usingBlock:^(NSNotification *note) {
        NSWindow *win = (NSWindow *)note.object;
        if (win && [win isKindOfClass:[NSWindow class]]) {
            update_cached_screen_geometry(win.screen ?: [NSScreen mainScreen]);
        }
        debuglog_window_geometry("DidBecomeKey", win);
        clamp_fullscreen_window_to_visible_frame(win);
    }];
    [nc addObserverForName:NSWindowDidResizeNotification object:nil queue:nil
                usingBlock:^(NSNotification *note) {
        NSWindow *win = (NSWindow *)note.object;
        if (win && [win isKindOfClass:[NSWindow class]]) {
            update_cached_screen_geometry(win.screen ?: [NSScreen mainScreen]);
        }
        debuglog_window_geometry("DidResize", win);
        clamp_fullscreen_window_to_visible_frame(win);
    }];
    [nc addObserverForName:NSWindowDidEnterFullScreenNotification object:nil queue:nil
                usingBlock:^(NSNotification *note) {
        NSWindow *win = (NSWindow *)note.object;
        if (win && [win isKindOfClass:[NSWindow class]]) {
            update_cached_screen_geometry(win.screen ?: [NSScreen mainScreen]);
        }
        debuglog_window_geometry("DidEnterFullScreen", win);
        clamp_fullscreen_window_to_visible_frame(win);
    }];
    [nc addObserverForName:NSWindowDidExitFullScreenNotification object:nil queue:nil
                usingBlock:^(NSNotification *note) {
        gNotchClampAttempts = 0;
        debuglog_window_geometry("DidExitFullScreen", (NSWindow *)note.object);
    }];
}

typedef struct {
    const char *symbolName;
    void *replacement;
} Sims2SymbolHookEntry;

static const Sims2SymbolHookEntry kSims2CoreGraphicsHooks[] = {
    { "_CGDisplayCopyAllDisplayModes", (void *)hook_CGDisplayCopyAllDisplayModes },
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
    init_log_paths_and_system_info();
    install_crash_handlers();
    debuglog_init_if_enabled();

    debuglog_write("BOOT", "libsims2_trackpad v%s loaded pid=%d model=%s macOS=%s frame=%s",
                   SIMS2_PATCH_VERSION, getpid(), gCachedHwModel, gCachedOsVersion, gCachedFrameStr);

    /*
     * Override Aspyr's hardcoded SDL_SetHint(..., "0") priority-1 hints via environment
     * variables so SDL2 uses a native macOS fullscreen Space and properly hides the Dock.
     */
    setenv("SDL_VIDEO_MAC_FULLSCREEN_SPACES", "1", 0);
    setenv("SDL_HINT_ALLOW_FULLSCREEN_NOTIFICATIONS", "1", 0);
    setenv("SDL_ALLOW_TOPMOST", "1", 0);
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

    Class winCls = [NSWindow class];
    gOrigMiniaturizeIMP = swizzle_instance_method(winCls, @selector(miniaturize:), (IMP)swizzled_miniaturize);
    gOrigMakeKeyAndOrderFrontIMP = swizzle_instance_method(winCls, @selector(makeKeyAndOrderFront:), (IMP)swizzled_makeKeyAndOrderFront);
    gOrigOrderFrontRegardlessIMP = swizzle_instance_method(winCls, @selector(orderFrontRegardless), (IMP)swizzled_orderFrontRegardless);

    Class sdlWinCls = objc_getClass("SDLWindow");
    if (sdlWinCls) {
        gOrigCanBecomeKeyWindowIMP = swizzle_instance_method(sdlWinCls,
                                                             @selector(canBecomeKeyWindow),
                                                             (IMP)swizzled_canBecomeKeyWindow);
        gOrigCanBecomeMainWindowIMP = swizzle_instance_method(sdlWinCls,
                                                              @selector(canBecomeMainWindow),
                                                              (IMP)swizzled_canBecomeMainWindow);
    }

    Class listenerCls = objc_getClass("Cocoa_WindowListener");
    if (listenerCls) {
        gOrigScrollWheelIMP = swizzle_instance_method(listenerCls, @selector(scrollWheel:), (IMP)swizzled_scrollWheel);
        gOrigMouseDownIMP = swizzle_instance_method(listenerCls, @selector(mouseDown:), (IMP)swizzled_mouseDown);
        gOrigMouseUpIMP = swizzle_instance_method(listenerCls, @selector(mouseUp:), (IMP)swizzled_mouseUp);
        gOrigMouseDraggedIMP = swizzle_instance_method(listenerCls, @selector(mouseDragged:), (IMP)swizzled_mouseDragged);
        gOrigRightMouseDownIMP = swizzle_instance_method(listenerCls, @selector(rightMouseDown:), (IMP)swizzled_rightMouseDown);
        gOrigRightMouseUpIMP = swizzle_instance_method(listenerCls, @selector(rightMouseUp:), (IMP)swizzled_rightMouseUp);
        gOrigRightMouseDraggedIMP = swizzle_instance_method(listenerCls, @selector(rightMouseDragged:), (IMP)swizzled_rightMouseDragged);
        gOrigMouseMovedIMP = swizzle_instance_method(listenerCls, @selector(mouseMoved:), (IMP)swizzled_mouseMoved);
        gOrigWindowDidBecomeKeyIMP = swizzle_instance_method(listenerCls, @selector(windowDidBecomeKey:), (IMP)swizzled_windowDidBecomeKey);
        gOrigWindowDidResignKeyIMP = swizzle_instance_method(listenerCls, @selector(windowDidResignKey:), (IMP)swizzled_windowDidResignKey);
        gOrigWindowWillEnterFullScreenIMP = swizzle_instance_method(listenerCls, @selector(windowWillEnterFullScreen:), (IMP)swizzled_windowWillEnterFullScreen);
        gOrigWindowDidEnterFullScreenIMP = swizzle_instance_method(listenerCls, @selector(windowDidEnterFullScreen:), (IMP)swizzled_windowDidEnterFullScreen);
        gOrigWindowWillExitFullScreenIMP = swizzle_instance_method(listenerCls, @selector(windowWillExitFullScreen:), (IMP)swizzled_windowWillExitFullScreen);
        gOrigWindowDidExitFullScreenIMP = swizzle_instance_method(listenerCls, @selector(windowDidExitFullScreen:), (IMP)swizzled_windowDidExitFullScreen);
        gOrigSetFullscreenSpaceIMP = swizzle_instance_method(listenerCls, @selector(setFullscreenSpace:), (IMP)swizzled_setFullscreenSpace);
    }

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserverForName:NSApplicationWillResignActiveNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *note) {
        (void)note;
        gAppIsActive = NO;
        gLastResignTimestamp = CFAbsoluteTimeGetCurrent();
        reset_gesture_and_key_state(resolve_window_listener());
        CGAssociateMouseAndMouseCursorPosition(true);
        CGDisplayShowCursor(kCGDirectMainDisplay);
        debuglog_write("APP", "WillResignActive");
    }];
    [nc addObserverForName:NSApplicationDidResignActiveNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *note) {
        (void)note;
        gAppIsActive = NO;
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
        neutralize_secondary_orphan_windows(gPrimaryFullscreenWindow);
        debuglog_write("APP", "WillBecomeActive");
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
        neutralize_secondary_orphan_windows(gPrimaryFullscreenWindow);
        debuglog_write("APP", "DidBecomeActive");
    }];
    [nc addObserverForName:NSApplicationWillHideNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *note) {
        (void)note;
        gAppIsHiding = YES;
        debuglog_write("APP", "WillHide");
    }];
    [nc addObserverForName:NSApplicationDidUnhideNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *note) {
        (void)note;
        gAppIsHiding = NO;
        debuglog_write("APP", "DidUnhide");
    }];

    uint16_t initLeft = 43, initRight = 47;
    resolve_camera_rotate_keycodes(&initLeft, &initRight);
    register_window_geometry_observers();
    size_t cgHooks = hook_coregraphics_la_symbol_ptrs();

    NSString *bundleStr = [[NSBundle mainBundle] bundleIdentifier];
    const char *bundleId = bundleStr ? [bundleStr UTF8String] : "unknown";
    debuglog_write("INIT",
                   "pid=%d bundle=%s execSlide=0x%lx appHook=%d focusHook=%d keyWinHook=%d scrollHook=%d btnHook=%d "
                   "modHook=%d mouseMoved=%d fsSpaceHook=%d miniHook=%d activateHook=%d cgHooks=%zu "
                   "rotKeys=(%u,%u) invert=%d ctrlOrbit=%d log=%s",
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
                   gOrigMiniaturizeIMP != NULL,
                   gOrigActivateIgnoringOtherAppsIMP != NULL,
                   cgHooks,
                   initLeft,
                   initRight,
                   gInvertRotation,
                   gEnableOptionOrbit,
                   gDebugLogPath[0] ? gDebugLogPath : "disabled");

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
