#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <math.h>
#import <stdlib.h>

/*
 * libsims2_trackpad.dylib
 * Free & open-source Trackpad & macOS SDL2 helper for The Sims 2: Super Collection (macOS).
 *
 * Adds:
 *   1. SDL2 macOS Fullscreen Space & Dock fix (SDL_VIDEO_MAC_FULLSCREEN_SPACES, etc.)
 *   2. Out-of-focus cursor grab/warp protection in Cocoa_WindowListener::mouseMoved:
 *   3. Two-finger pinch gesture (NSEventTypeMagnify) -> native scrollWheel zoom (layout-independent, non-inverted)
 *   4. Two-finger horizontal slide (scrollWheel X) & twist (NSEventTypeRotate) -> dynamic Carbon AZERTY/QWERTY camera rotation (, / .)
 *   5. Option (⌥) + left or right click-drag -> SDL_BUTTON_MIDDLE emulation (360° orbit & pitch) with Option flag stripped
 *   6. Axis lock & momentum suppression on horizontal swipes so zoom and rotation don't fight.
 *
 * Env config (optional overrides):
 *   SIMS2_ROTATE_INVERT=0|1      (default 0)
 *   SIMS2_ROTATE_STEP=<float>    (default 28.0 trackpad points per rotation step)
 *   SIMS2_TWIST_STEP=<float>     (default 12.0 degrees per rotation step)
 *   SIMS2_PINCH_STEP=<float>     (default 0.08 magnification units per zoom step)
 *   SIMS2_OPTION_ORBIT=0|1       (default 1, Option+drag emulates middle mouse button)
 *   SIMS2_TRACKPAD_DEBUG=0|1     (default 0, logs via NSLog)
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
static IMP gOrigFlagsChangedIMP = NULL;
static IMP gOrigWindowDidResignKeyIMP = NULL;
static IMP gOrigWindowWillExitFullScreenIMP = NULL;

static Sims2ScrollAxis gScrollAxis = Sims2ScrollAxisNone;
static double gScrollAccumX = 0.0;
static double gTwistAccum = 0.0;
static double gPinchAccum = 0.0;
static BOOL gIsTwisting = NO;
static __weak NSEvent *gSuppressedScrollEvent = nil;
static __weak NSEvent *gForcedNonInvertedEvent = nil;
static BOOL gForceScrollNonInverted = NO;

static BOOL gSpoofMiddleButton = NO;
static BOOL gMaskOptionModifier = NO;
static BOOL gOptionMiddleDragActive = NO;
static BOOL gOptionDragWasRight = NO;
static BOOL gSendingSyntheticFlags = NO;
static __weak NSWindow *gLastMouseDownWindow = nil;
static __weak id gWindowListener = nil;

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
            } else {
                gScrollAxis = Sims2ScrollAxisZoomY;
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
        while (gScrollAccumX >= gRotateStep && steps < 3) {
            gScrollAccumX -= gRotateStep;
            post_rotation_key(YES);
            steps++;
        }
        while (gScrollAccumX <= -gRotateStep && steps < 3) {
            gScrollAccumX += gRotateStep;
            post_rotation_key(NO);
            steps++;
        }
    }
}

static void handle_rotate_event(NSEvent *event) {
    NSEventPhase phase = [event phase];
    if (phase == NSEventPhaseBegan || phase == NSEventPhaseMayBegin) {
        gIsTwisting = YES;
        gTwistAccum = 0.0;
        return;
    }
    if (phase == NSEventPhaseEnded || phase == NSEventPhaseCancelled) {
        gIsTwisting = NO;
        gTwistAccum = 0.0;
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
    while (gTwistAccum >= gTwistStep && steps < 3) {
        gTwistAccum -= gTwistStep;
        post_rotation_key(YES);
        steps++;
    }
    while (gTwistAccum <= -gTwistStep && steps < 3) {
        gTwistAccum += gTwistStep;
        post_rotation_key(NO);
        steps++;
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
    while (gPinchAccum >= gPinchStep && steps < 4) {
        gPinchAccum -= gPinchStep;
        post_pinch_zoom_scroll(1);
        steps++;
    }
    while (gPinchAccum <= -gPinchStep && steps < 4) {
        gPinchAccum += gPinchStep;
        post_pinch_zoom_scroll(-1);
        steps++;
    }
}

static void clear_sdl_option_modifier_state(id listener, NSEvent *baseEvent) {
    if (gSendingSyntheticFlags) {
        return;
    }
    NSEventModifierFlags cleanFlags = ([baseEvent modifierFlags] & ~NSEventModifierFlagOption);
    NSTimeInterval ts = [[NSProcessInfo processInfo] systemUptime];
    NSWindow *win = [baseEvent window] ?: [NSApp keyWindow];
    NSInteger winNum = win ? [win windowNumber] : 0;
    NSEvent *flagsEv = [NSEvent keyEventWithType:NSEventTypeFlagsChanged
                                        location:[baseEvent locationInWindow]
                                   modifierFlags:cleanFlags
                                       timestamp:ts
                                    windowNumber:winNum
                                         context:nil
                                      characters:@""
                     charactersIgnoringModifiers:@""
                                       isARepeat:NO
                                         keyCode:(uint16_t)kVK_Option];
    if (!flagsEv) {
        return;
    }

    gSendingSyntheticFlags = YES;
    if (listener && gOrigFlagsChangedIMP) {
        typedef void (*FlagsFn)(id, SEL, NSEvent *);
        ((FlagsFn)gOrigFlagsChangedIMP)(listener, @selector(flagsChanged:), flagsEv);
    } else if (NSApp) {
        [NSApp sendEvent:flagsEv];
    }
    gSendingSyntheticFlags = NO;
}

static void release_option_middle_drag(id listener) {
    if (!gOptionMiddleDragActive) {
        return;
    }
    NSWindow *win = gLastMouseDownWindow;
    IMP upIMP = gOptionDragWasRight ? gOrigRightMouseUpIMP : gOrigMouseUpIMP;
    SEL upSEL = gOptionDragWasRight ? @selector(rightMouseUp:) : @selector(mouseUp:);
    NSEventType upType = gOptionDragWasRight ? NSEventTypeRightMouseUp : NSEventTypeLeftMouseUp;

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
            gMaskOptionModifier = YES;
            ((MouseUpFn)upIMP)(listener, upSEL, synthUp);
            gSpoofMiddleButton = NO;
            gMaskOptionModifier = NO;
        }
    }
    gOptionMiddleDragActive = NO;
    gOptionDragWasRight = NO;
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
    if (gMaskOptionModifier || gOptionMiddleDragActive) {
        flags &= ~NSEventModifierFlagOption;
    }
    return flags;
}

static NSEventModifierFlags swizzled_classModifierFlags(id self, SEL _cmd) {
    typedef NSEventModifierFlags (*Fn)(id, SEL);
    NSEventModifierFlags flags = gOrigClassModifierFlagsIMP ? ((Fn)gOrigClassModifierFlagsIMP)(self, _cmd) : 0;
    if (gMaskOptionModifier || gOptionMiddleDragActive) {
        flags &= ~NSEventModifierFlagOption;
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

static void handle_option_mouse_down(id self, SEL _cmd, NSEvent *event, IMP origIMP, BOOL isRight) {
    gWindowListener = self;
    typedef void (*Fn)(id, SEL, NSEvent *);
    if (!origIMP) {
        return;
    }
    if (gEnableOptionOrbit && !gOptionMiddleDragActive && (([event modifierFlags] & NSEventModifierFlagOption) != 0)) {
        clear_sdl_option_modifier_state(self, event);
        gOptionMiddleDragActive = YES;
        gOptionDragWasRight = isRight;
        gLastMouseDownWindow = [event window];
        gSpoofMiddleButton = YES;
        gMaskOptionModifier = YES;
        ((Fn)origIMP)(self, _cmd, event);
        gSpoofMiddleButton = NO;
        gMaskOptionModifier = NO;
        return;
    }
    ((Fn)origIMP)(self, _cmd, event);
}

static void handle_option_mouse_drag(id self, SEL _cmd, NSEvent *event, IMP origIMP, BOOL isRight) {
    gWindowListener = self;
    typedef void (*Fn)(id, SEL, NSEvent *);
    if (!origIMP) {
        return;
    }
    if (gOptionMiddleDragActive && (isRight == gOptionDragWasRight)) {
        gSpoofMiddleButton = YES;
        gMaskOptionModifier = YES;
        ((Fn)origIMP)(self, _cmd, event);
        gSpoofMiddleButton = NO;
        gMaskOptionModifier = NO;
        return;
    }
    ((Fn)origIMP)(self, _cmd, event);
}

static void handle_option_mouse_up(id self, SEL _cmd, NSEvent *event, IMP origIMP, BOOL isRight) {
    gWindowListener = self;
    typedef void (*Fn)(id, SEL, NSEvent *);
    if (!origIMP) {
        return;
    }
    if (gOptionMiddleDragActive && (isRight == gOptionDragWasRight)) {
        gOptionMiddleDragActive = NO;
        gOptionDragWasRight = NO;
        gLastMouseDownWindow = nil;
        gSpoofMiddleButton = YES;
        gMaskOptionModifier = YES;
        ((Fn)origIMP)(self, _cmd, event);
        gSpoofMiddleButton = NO;
        gMaskOptionModifier = NO;
        return;
    }
    ((Fn)origIMP)(self, _cmd, event);
}

static void swizzled_mouseDown(id self, SEL _cmd, NSEvent *event) {
    handle_option_mouse_down(self, _cmd, event, gOrigMouseDownIMP, NO);
}

static void swizzled_mouseUp(id self, SEL _cmd, NSEvent *event) {
    handle_option_mouse_up(self, _cmd, event, gOrigMouseUpIMP, NO);
}

static void swizzled_mouseDragged(id self, SEL _cmd, NSEvent *event) {
    handle_option_mouse_drag(self, _cmd, event, gOrigMouseDraggedIMP, NO);
}

static void swizzled_rightMouseDown(id self, SEL _cmd, NSEvent *event) {
    handle_option_mouse_down(self, _cmd, event, gOrigRightMouseDownIMP, YES);
}

static void swizzled_rightMouseUp(id self, SEL _cmd, NSEvent *event) {
    handle_option_mouse_up(self, _cmd, event, gOrigRightMouseUpIMP, YES);
}

static void swizzled_rightMouseDragged(id self, SEL _cmd, NSEvent *event) {
    handle_option_mouse_drag(self, _cmd, event, gOrigRightMouseDraggedIMP, YES);
}

/*
 * Prevent SDL2 Cocoa_WindowListener::mouseMoved: from calling CGDisplayMoveCursorToPoint
 * when the game window is inactive or not key (Space transitions / Cmd+Tab / Dock clicks).
 */
static void swizzled_mouseMoved(id self, SEL _cmd, NSEvent *event) {
    gWindowListener = self;
    NSWindow *win = [event window] ?: [NSApp keyWindow];
    if (![NSApp isActive] || !win || ![win isKeyWindow]) {
        return;
    }
    if (gOrigMouseMovedIMP) {
        typedef void (*Fn)(id, SEL, NSEvent *);
        ((Fn)gOrigMouseMovedIMP)(self, _cmd, event);
    }
}

static void reset_gesture_and_key_state(id listener) {
    release_option_middle_drag(listener);
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

static void swizzled_windowDidResignKey(id self, SEL _cmd, NSNotification *notification) {
    gWindowListener = self;
    reset_gesture_and_key_state(self);

    if (gOrigWindowDidResignKeyIMP) {
        typedef void (*ResignFn)(id, SEL, NSNotification *);
        ((ResignFn)gOrigWindowDidResignKeyIMP)(self, _cmd, notification);
    }
}

static void swizzled_windowWillExitFullScreen(id self, SEL _cmd, NSNotification *notification) {
    gWindowListener = self;
    reset_gesture_and_key_state(self);

    if (gOrigWindowWillExitFullScreenIMP) {
        typedef void (*ExitFSFn)(id, SEL, NSNotification *);
        ((ExitFSFn)gOrigWindowWillExitFullScreenIMP)(self, _cmd, notification);
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
    /*
     * Override Aspyr's hardcoded SDL_SetHint(..., "0") priority-1 hints via environment
     * variables so SDL2 uses a native macOS fullscreen Space and properly hides the Dock.
     */
    setenv("SDL_VIDEO_MAC_FULLSCREEN_SPACES", "1", 0);
    setenv("SDL_HINT_ALLOW_FULLSCREEN_NOTIFICATIONS", "1", 0);
    setenv("SDL_ALLOW_TOPMOST", "1", 0);
    setenv("SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS", "1", 0);

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
    const char *optOrbitStr = getenv("SIMS2_OPTION_ORBIT");
    if (optOrbitStr && optOrbitStr[0] == '0') {
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
        Method flagsMethod = class_getInstanceMethod(listenerCls, @selector(flagsChanged:));
        if (flagsMethod) {
            gOrigFlagsChangedIMP = method_getImplementation(flagsMethod);
        }
        gOrigWindowDidResignKeyIMP = swizzle_instance_method(listenerCls, @selector(windowDidResignKey:), (IMP)swizzled_windowDidResignKey);
        gOrigWindowWillExitFullScreenIMP = swizzle_instance_method(listenerCls, @selector(windowWillExitFullScreen:), (IMP)swizzled_windowWillExitFullScreen);
    }

    uint16_t initLeft = 43, initRight = 47;
    resolve_camera_rotate_keycodes(&initLeft, &initRight);

    log_msg([NSString stringWithFormat:
             @"Loaded: appHook=%d scrollHook=%d btnHook=%d modHook=%d mouseMoved=%d rotKeys=(%u,%u) invert=%d optOrbit=%d",
             gOrigNextEventIMP != NULL,
             gOrigScrollWheelIMP != NULL,
             gOrigButtonNumberIMP != NULL,
             gOrigEventModifierFlagsIMP != NULL,
             gOrigMouseMovedIMP != NULL,
             initLeft,
             initRight,
             gInvertRotation,
             gEnableOptionOrbit]);
}
