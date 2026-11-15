#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <errno.h>
#import <math.h>
#import <pthread.h>
#import <stdarg.h>
#import <stdio.h>
#import <stdlib.h>
#import <sys/stat.h>
#import <sys/time.h>
#import <time.h>
#import <unistd.h>

/*
 * libsims2_trackpad.dylib
 * Free & open-source Trackpad & macOS SDL2 helper for The Sims 2: Super Collection (macOS).
 *
 * Adds:
 *   1. SDL2 macOS Fullscreen Space & Dock fix (SDL_VIDEO_MAC_FULLSCREEN_SPACES, etc.)
 *   2. Out-of-focus cursor grab/warp protection & Command+Tab fullscreen bounce-back suppression
 *   3. Two-finger pinch gesture (NSEventTypeMagnify) -> native scrollWheel zoom (layout-independent, non-inverted)
 *   4. Two-finger horizontal slide (scrollWheel X) & twist (NSEventTypeRotate) -> dynamic Carbon AZERTY/QWERTY camera rotation (, / .)
 *   5. Control (^) + left or right click-drag -> SDL_BUTTON_MIDDLE emulation (360° orbit & pitch)
 *   6. Native Option (⌥) camera hand-drag left untouched for the base game
 *   7. Axis lock & momentum suppression on horizontal swipes + developer event log (trackpad_events.log)
 *
 * Env config (optional overrides):
 *   SIMS2_ROTATE_INVERT=0|1      (default 0)
 *   SIMS2_ROTATE_STEP=<float>    (default 28.0 trackpad points per rotation step)
 *   SIMS2_TWIST_STEP=<float>     (default 12.0 degrees per rotation step)
 *   SIMS2_PINCH_STEP=<float>     (default 0.08 magnification units per zoom step)
 *   SIMS2_CTRL_ORBIT=0|1         (default 1, Control+drag emulates middle mouse button)
 *   SIMS2_OPTION_ORBIT=0|1       (legacy fallback alias if SIMS2_CTRL_ORBIT is unset)
 *   SIMS2_TRACKPAD_DEBUG=0|1     (default 0, logs via NSLog)
 *   SIMS2_TRACKPAD_DEVLOG=0|1    (default 1, writes ~/Library/Logs/Sims2-Crash-Patch/trackpad_events.log)
 */

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
static __weak id gWindowListener = nil;

static BOOL gAppHasActivatedOnce = NO;
static BOOL gAppIsActive = YES;
static BOOL gInFullscreenTransition = NO;
static CFAbsoluteTime gLastResignTimestamp = 0.0;

static FILE *gDevLogFile = NULL;
static BOOL gDevLogEnabled = YES;
static pthread_mutex_t gDevLogMutex = PTHREAD_MUTEX_INITIALIZER;
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

static void devlog_write(const char *category, const char *fmt, ...) __attribute__((format(printf, 2, 3)));

static void devlog_write(const char *category, const char *fmt, ...) {
    if (!gDevLogEnabled || !gDevLogFile || !fmt) {
        return;
    }
    struct timeval tv;
    gettimeofday(&tv, NULL);
    time_t sec = tv.tv_sec;
    struct tm tm_info;
    localtime_r(&sec, &tm_info);

    char tsBuf[32];
    snprintf(tsBuf, sizeof(tsBuf), "%02d:%02d:%02d.%03d",
             tm_info.tm_hour, tm_info.tm_min, tm_info.tm_sec, (int)(tv.tv_usec / 1000));

    char msgBuf[1024];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(msgBuf, sizeof(msgBuf), fmt, ap);
    va_end(ap);

    pthread_mutex_lock(&gDevLogMutex);
    if (gDevLogFile) {
        fprintf(gDevLogFile, "[%s] [%s] %s\n", tsBuf, category ? category : "LOG", msgBuf);
        fflush(gDevLogFile);
    }
    pthread_mutex_unlock(&gDevLogMutex);
}

static void devlog_init(char *outLogPath, size_t outLogPathSize) {
    if (outLogPath && outLogPathSize > 0) {
        outLogPath[0] = '\0';
    }
    const char *env = getenv("SIMS2_TRACKPAD_DEVLOG");
    if (env && env[0] == '0') {
        gDevLogEnabled = NO;
        return;
    }
    const char *home = getenv("HOME");
    if (!home || home[0] == '\0') {
        NSString *nsHome = NSHomeDirectory();
        home = nsHome ? [nsHome UTF8String] : NULL;
    }
    if (!home || home[0] == '\0') {
        return;
    }

    char libDir[512];
    char logsRoot[512];
    char appLogDir[512];
    char logPath[600];
    char prevPath[600];

    snprintf(libDir, sizeof(libDir), "%s/Library", home);
    snprintf(logsRoot, sizeof(logsRoot), "%s/Library/Logs", home);
    snprintf(appLogDir, sizeof(appLogDir), "%s/Library/Logs/Sims2-Crash-Patch", home);
    ensure_dir_exists(libDir);
    ensure_dir_exists(logsRoot);
    ensure_dir_exists(appLogDir);

    snprintf(logPath, sizeof(logPath), "%s/trackpad_events.log", appLogDir);
    snprintf(prevPath, sizeof(prevPath), "%s/trackpad_events.previous.log", appLogDir);

    struct stat st;
    if (stat(logPath, &st) == 0) {
        rename(logPath, prevPath);
    }

    FILE *fp = fopen(logPath, "w");
    if (!fp) {
        return;
    }
    pthread_mutex_lock(&gDevLogMutex);
    gDevLogFile = fp;
    pthread_mutex_unlock(&gDevLogMutex);

    if (outLogPath && outLogPathSize > 0) {
        snprintf(outLogPath, outLogPathSize, "%s", logPath);
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
 * On ABC-AZERTY, ',' is keyCode 46 (WinVK 0xBC) while '.' requires Shift on keyCode 43
 * (Wait: unshifted 43 is ';', WinVK 0xBA), whereas unshifted keyCode 47 falls through
 * SDL2 Pass 2 (darwin_scancode_table[47] -> SDL_SCANCODE_PERIOD -> WinVK 0xBE).
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
            /* Skip numeric keypad keycodes (e.g. kc=65 KP_DECIMAL -> VK_DECIMAL, not VK_OEM_COMMA/PERIOD) */
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
        return; // External mouse wheel or synthetic pinch line scroll: keep native behavior
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
    // Normalize horizontal finger direction so sliding fingers right is positive regardless of Natural Scrolling
    double fingerRightDx = [event isDirectionInvertedFromDevice] ? -dx : dx;

    if (gScrollAxis == Sims2ScrollAxisNone) {
        double adx = fabs(fingerRightDx);
        double ady = fabs(dy);
        if (adx > 1.5 || ady > 1.5) {
            if (adx > ady * 1.35) {
                gScrollAxis = Sims2ScrollAxisRotateX;
                devlog_write("GESTURE", "SCROLL_LOCK axis=RotateX dx=%.2f dy=%.2f", fingerRightDx, dy);
            } else {
                gScrollAxis = Sims2ScrollAxisZoomY;
                devlog_write("GESTURE", "SCROLL_LOCK axis=ZoomY dx=%.2f dy=%.2f", fingerRightDx, dy);
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
                devlog_write("GESTURE", "SCROLL_ROTATE dir=%s steps=%d dx=%.2f",
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
        devlog_write("GESTURE", "TWIST_BEGIN");
        return;
    }
    if (phase == NSEventPhaseEnded || phase == NSEventPhaseCancelled) {
        gIsTwisting = NO;
        gTwistAccum = 0.0;
        devlog_write("GESTURE", "TWIST_END");
        return;
    }

    gIsTwisting = YES;
    // In AppKit, clockwise (turning right) has negative rotation degrees
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
            devlog_write("GESTURE", "TWIST_ROTATE dir=%s steps=%d deg=%.2f keys=(%u,%u)",
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
            devlog_write("GESTURE", "PINCH_ZOOM dir=%d steps=%d mag=%.3f", lastDir, steps, mag);
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

    devlog_write("CAM", "CTRL_ORBIT_END_SYNTH btn=%s", gCtrlDragWasRight ? "right" : "left");

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
        } else if (t == NSEventTypeFlagsChanged) {
            NSEventModifierFlags rawFlags = raw_event_modifier_flags(ev);
            if (gCtrlMiddleDragActive && ((rawFlags & NSEventModifierFlagControl) == 0)) {
                release_ctrl_middle_drag(resolve_window_listener());
            }
            NSUInteger trackedMods = rawFlags & (NSEventModifierFlagControl |
                                                 NSEventModifierFlagOption |
                                                 NSEventModifierFlagShift |
                                                 NSEventModifierFlagCommand);
            if (trackedMods != gLastLoggedModifierMask) {
                gLastLoggedModifierMask = trackedMods;
                devlog_write("MOD", "flags ctrl=%d opt=%d shift=%d cmd=%d (raw=0x%lx)",
                             (trackedMods & NSEventModifierFlagControl) ? 1 : 0,
                             (trackedMods & NSEventModifierFlagOption) ? 1 : 0,
                             (trackedMods & NSEventModifierFlagShift) ? 1 : 0,
                             (trackedMods & NSEventModifierFlagCommand) ? 1 : 0,
                             (unsigned long)rawFlags);
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
        devlog_write("CAM", "CTRL_ORBIT_START btn=%s win=%p",
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
        devlog_write("CAM", "NATIVE_RIGHT_CLICK_DOWN opt=%d win=%p",
                     optHeld ? 1 : 0, (__bridge void *)[event window]);
    } else if (!isRight && [event type] == NSEventTypeLeftMouseDown &&
               (rawFlags & NSEventModifierFlagOption) != 0) {
        devlog_write("CAM", "NATIVE_OPTION_LEFT_CLICK_DOWN win=%p",
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
            devlog_write("CAM", "CTRL_ORBIT_END btn=%s", isRight ? "right" : "left");
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
        devlog_write("CAM", "NATIVE_RIGHT_CLICK_UP win=%p", (__bridge void *)[event window]);
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
    if (event && [event type] == NSEventTypeMouseMoved) {
        NSEventModifierFlags rawFlags = raw_event_modifier_flags(event);
        if ((rawFlags & NSEventModifierFlagOption) != 0) {
            CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
            if ((now - gLastOptionHoverLogTime) >= 0.5) {
                gLastOptionHoverLogTime = now;
                NSPoint pt = [event locationInWindow];
                devlog_write("CAM", "NATIVE_OPTION_HOVER_MOVE loc=(%.1f,%.1f) delta=(%.1f,%.1f)",
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

static void swizzled_windowDidBecomeKey(id self, SEL _cmd, NSNotification *notification) {
    gWindowListener = self;
    if (!NSApp || [NSApp isActive]) {
        gAppHasActivatedOnce = YES;
        gAppIsActive = YES;
        gLastResignTimestamp = 0.0;
    }
    id obj = [notification object];
    BOOL isWin = [obj isKindOfClass:[NSWindow class]];
    NSRect frame = isWin ? [(NSWindow *)obj frame] : NSZeroRect;
    BOOL isFS = isWin ? (([(NSWindow *)obj styleMask] & NSWindowStyleMaskFullScreen) != 0) : NO;
    devlog_write("WIN", "windowDidBecomeKey win=%p active=%d fs=%d frame=%.0fx%.0f",
                 (__bridge void *)obj, (NSApp && [NSApp isActive]) ? 1 : 0, isFS ? 1 : 0,
                 frame.size.width, frame.size.height);

    if (gOrigWindowDidBecomeKeyIMP) {
        typedef void (*BecomeFn)(id, SEL, NSNotification *);
        ((BecomeFn)gOrigWindowDidBecomeKeyIMP)(self, _cmd, notification);
    }
}

static void swizzled_windowDidResignKey(id self, SEL _cmd, NSNotification *notification) {
    gWindowListener = self;
    gLastResignTimestamp = CFAbsoluteTimeGetCurrent();
    reset_gesture_and_key_state(self);
    CGAssociateMouseAndMouseCursorPosition(true);
    CGDisplayShowCursor(kCGDirectMainDisplay);
    devlog_write("WIN", "windowDidResignKey win=%p active=%d",
                 (__bridge void *)[notification object], (NSApp && [NSApp isActive]) ? 1 : 0);

    if (gOrigWindowDidResignKeyIMP) {
        typedef void (*ResignFn)(id, SEL, NSNotification *);
        ((ResignFn)gOrigWindowDidResignKeyIMP)(self, _cmd, notification);
    }
}

static void swizzled_windowWillEnterFullScreen(id self, SEL _cmd, NSNotification *notification) {
    gWindowListener = self;
    gInFullscreenTransition = YES;
    devlog_write("WIN", "windowWillEnterFullScreen win=%p", (__bridge void *)[notification object]);

    if (gOrigWindowWillEnterFullScreenIMP) {
        typedef void (*EnterFSFn)(id, SEL, NSNotification *);
        ((EnterFSFn)gOrigWindowWillEnterFullScreenIMP)(self, _cmd, notification);
    }
}

static void swizzled_windowDidEnterFullScreen(id self, SEL _cmd, NSNotification *notification) {
    gWindowListener = self;
    gInFullscreenTransition = NO;
    devlog_write("WIN", "windowDidEnterFullScreen win=%p", (__bridge void *)[notification object]);

    if (gOrigWindowDidEnterFullScreenIMP) {
        typedef void (*DidEnterFSFn)(id, SEL, NSNotification *);
        ((DidEnterFSFn)gOrigWindowDidEnterFullScreenIMP)(self, _cmd, notification);
    }
}

static void swizzled_windowWillExitFullScreen(id self, SEL _cmd, NSNotification *notification) {
    gWindowListener = self;
    gInFullscreenTransition = YES;
    reset_gesture_and_key_state(self);
    devlog_write("WIN", "windowWillExitFullScreen win=%p active=%d",
                 (__bridge void *)[notification object], (NSApp && [NSApp isActive]) ? 1 : 0);

    if (gOrigWindowWillExitFullScreenIMP) {
        typedef void (*ExitFSFn)(id, SEL, NSNotification *);
        ((ExitFSFn)gOrigWindowWillExitFullScreenIMP)(self, _cmd, notification);
    }
}

static void swizzled_windowDidExitFullScreen(id self, SEL _cmd, NSNotification *notification) {
    gWindowListener = self;
    gInFullscreenTransition = NO;
    devlog_write("WIN", "windowDidExitFullScreen win=%p active=%d",
                 (__bridge void *)[notification object], (NSApp && [NSApp isActive]) ? 1 : 0);

    if (gOrigWindowDidExitFullScreenIMP) {
        typedef void (*DidExitFSFn)(id, SEL, NSNotification *);
        ((DidExitFSFn)gOrigWindowDidExitFullScreenIMP)(self, _cmd, notification);
    }
}

static BOOL swizzled_setFullscreenSpace(id self, SEL _cmd, BOOL state) {
    gWindowListener = self;
    if (!state && should_suppress_focus_steal_or_fullscreen_exit()) {
        CFAbsoluteTime dt = (gLastResignTimestamp > 0.0) ? (CFAbsoluteTimeGetCurrent() - gLastResignTimestamp) : -1.0;
        devlog_write("WIN", "SUPPRESSED setFullscreenSpace:NO (active=%d nsActive=%d dt=%.3fs)",
                     gAppIsActive ? 1 : 0, (NSApp && [NSApp isActive]) ? 1 : 0, dt);
        return YES;
    }
    devlog_write("WIN", "setFullscreenSpace:%d (active=%d)", state ? 1 : 0, gAppIsActive ? 1 : 0);
    if (gOrigSetFullscreenSpaceIMP) {
        typedef BOOL (*Fn)(id, SEL, BOOL);
        return ((Fn)gOrigSetFullscreenSpaceIMP)(self, _cmd, state);
    }
    return NO;
}

static void swizzled_miniaturize(id self, SEL _cmd, id sender) {
    NSWindow *win = (NSWindow *)self;
    BOOL isFullscreen = (([win styleMask] & NSWindowStyleMaskFullScreen) != 0);
    if (isFullscreen || gInFullscreenTransition || should_suppress_focus_steal_or_fullscreen_exit()) {
        devlog_write("WIN", "SUPPRESSED miniaturize: (fs=%d trans=%d active=%d) win=%p",
                     isFullscreen ? 1 : 0, gInFullscreenTransition ? 1 : 0,
                     gAppIsActive ? 1 : 0, (__bridge void *)win);
        return;
    }
    devlog_write("WIN", "miniaturize: win=%p", (__bridge void *)win);
    if (gOrigMiniaturizeIMP) {
        typedef void (*Fn)(id, SEL, id);
        ((Fn)gOrigMiniaturizeIMP)(self, _cmd, sender);
    }
}

static void swizzled_makeKeyAndOrderFront(id self, SEL _cmd, id sender) {
    if (should_suppress_focus_steal_or_fullscreen_exit()) {
        devlog_write("WIN", "SUPPRESSED makeKeyAndOrderFront: (active=%d nsActive=%d) win=%p",
                     gAppIsActive ? 1 : 0, (NSApp && [NSApp isActive]) ? 1 : 0, (__bridge void *)self);
        return;
    }
    if (gOrigMakeKeyAndOrderFrontIMP) {
        typedef void (*Fn)(id, SEL, id);
        ((Fn)gOrigMakeKeyAndOrderFrontIMP)(self, _cmd, sender);
    }
}

static void swizzled_orderFrontRegardless(id self, SEL _cmd) {
    if (should_suppress_focus_steal_or_fullscreen_exit()) {
        devlog_write("WIN", "SUPPRESSED orderFrontRegardless (active=%d nsActive=%d) win=%p",
                     gAppIsActive ? 1 : 0, (NSApp && [NSApp isActive]) ? 1 : 0, (__bridge void *)self);
        return;
    }
    if (gOrigOrderFrontRegardlessIMP) {
        typedef void (*Fn)(id, SEL);
        ((Fn)gOrigOrderFrontRegardlessIMP)(self, _cmd);
    }
}

static void swizzled_activateIgnoringOtherApps(id self, SEL _cmd, BOOL flag) {
    if (flag && gAppHasActivatedOnce &&
        (!gAppIsActive || (gLastResignTimestamp > 0.0 && (CFAbsoluteTimeGetCurrent() - gLastResignTimestamp) < 2.0))) {
        CFAbsoluteTime dt = (gLastResignTimestamp > 0.0) ? (CFAbsoluteTimeGetCurrent() - gLastResignTimestamp) : -1.0;
        devlog_write("WIN", "SUPPRESSED activateIgnoringOtherApps:YES (active=%d dt=%.3fs)",
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

__attribute__((constructor))
static void sims2_trackpad_init(void) {
    char devLogPath[600];
    devlog_init(devLogPath, sizeof(devLogPath));

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
        devlog_write("APP", "WillResignActive");
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
        devlog_write("APP", "DidResignActive");
    }];
    [nc addObserverForName:NSApplicationWillBecomeActiveNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *note) {
        (void)note;
        gAppHasActivatedOnce = YES;
        gAppIsActive = YES;
        gLastResignTimestamp = 0.0;
        devlog_write("APP", "WillBecomeActive");
    }];
    [nc addObserverForName:NSApplicationDidBecomeActiveNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *note) {
        (void)note;
        gAppHasActivatedOnce = YES;
        gAppIsActive = YES;
        gLastResignTimestamp = 0.0;
        devlog_write("APP", "DidBecomeActive");
    }];

    uint16_t initLeft = 43, initRight = 47;
    resolve_camera_rotate_keycodes(&initLeft, &initRight);

    NSString *bundleStr = [[NSBundle mainBundle] bundleIdentifier];
    const char *bundleId = bundleStr ? [bundleStr UTF8String] : "unknown";
    devlog_write("INIT",
                 "pid=%d bundle=%s appHook=%d scrollHook=%d btnHook=%d modHook=%d mouseMoved=%d "
                 "fsSpaceHook=%d miniHook=%d activateHook=%d rotKeys=(%u,%u) invert=%d ctrlOrbit=%d log=%s",
                 getpid(),
                 bundleId ? bundleId : "unknown",
                 gOrigNextEventIMP != NULL,
                 gOrigScrollWheelIMP != NULL,
                 gOrigButtonNumberIMP != NULL,
                 gOrigEventModifierFlagsIMP != NULL,
                 gOrigMouseMovedIMP != NULL,
                 gOrigSetFullscreenSpaceIMP != NULL,
                 gOrigMiniaturizeIMP != NULL,
                 gOrigActivateIgnoringOtherAppsIMP != NULL,
                 initLeft,
                 initRight,
                 gInvertRotation,
                 gEnableOptionOrbit,
                 devLogPath[0] ? devLogPath : "disabled");

    log_msg([NSString stringWithFormat:
             @"Loaded: appHook=%d scrollHook=%d btnHook=%d modHook=%d mouseMoved=%d fsSpaceHook=%d miniHook=%d activateHook=%d rotKeys=(%u,%u) invert=%d ctrlOrbit=%d",
             gOrigNextEventIMP != NULL,
             gOrigScrollWheelIMP != NULL,
             gOrigButtonNumberIMP != NULL,
             gOrigEventModifierFlagsIMP != NULL,
             gOrigMouseMovedIMP != NULL,
             gOrigSetFullscreenSpaceIMP != NULL,
             gOrigMiniaturizeIMP != NULL,
             gOrigActivateIgnoringOtherAppsIMP != NULL,
             initLeft,
             initRight,
             gInvertRotation,
             gEnableOptionOrbit]);
}
