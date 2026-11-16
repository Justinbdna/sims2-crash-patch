#!/usr/bin/env python3
"""
Sims 2 Crash Patch — Windows Trackpad & Camera Rotation Helper (Standalone, v1.4.0)

Solves the classic Sims 2 trackpad limitation (no physical Middle Mouse Button
drag for 3D camera orbit & tilt) cleanly in user space without touching game files
or macOS code:
  1. Two-finger horizontal trackpad swipe (WM_MOUSEHWHEEL) -> smooth camera orbit
  2. Modifier + 1-finger trackpad drag (default: Right Alt / AltGr) -> full 360 orbit + pitch
  3. One-key Camera Orbit Latch (default: F8) -> toggle 1-finger drag orbit on/off
  4. Automatic focus guard -> activates ONLY inside Sims 2 and releases MMB on Alt-Tab

Zero external dependencies (Python 3 standard library + Win32 user32/kernel32).
"""

from __future__ import annotations

import argparse
import atexit
import ctypes
from dataclasses import dataclass, field
import os
from pathlib import Path
import signal
import sys
import time

# Windows message & hook constants
WH_KEYBOARD_LL = 13
WH_MOUSE_LL = 14

WM_KEYDOWN = 0x0100
WM_KEYUP = 0x0101
WM_SYSKEYDOWN = 0x0104
WM_SYSKEYUP = 0x0105

WM_MOUSEMOVE = 0x0200
WM_LBUTTONDOWN = 0x0201
WM_LBUTTONUP = 0x0202
WM_RBUTTONDOWN = 0x0204
WM_RBUTTONUP = 0x0205
WM_MBUTTONDOWN = 0x0207
WM_MBUTTONUP = 0x0208
WM_MOUSEWHEEL = 0x020A
WM_MOUSEHWHEEL = 0x020E
WM_TIMER = 0x0113

INPUT_MOUSE = 0
INPUT_KEYBOARD = 1

MOUSEEVENTF_MOVE = 0x0001
MOUSEEVENTF_MIDDLEDOWN = 0x0020
MOUSEEVENTF_MIDDLEUP = 0x0040

KEYEVENTF_KEYUP = 0x0002

VK_SHIFT = 0x10
VK_CONTROL = 0x11
VK_MENU = 0x12
VK_LSHIFT = 0xA0
VK_RSHIFT = 0xA1
VK_LCONTROL = 0xA2
VK_RCONTROL = 0xA3
VK_LMENU = 0xA4
VK_RMENU = 0xA5
VK_F8 = 0x77
VK_F9 = 0x78
VK_F10 = 0x79
VK_ESCAPE = 0x1B
VK_OEM_COMMA = 0xBC
VK_OEM_PERIOD = 0xBE

# Unique tag ("S2TP") stamped on synthetic inputs so our hooks never recurse
SYNTHETIC_EXTRA_INFO = 0x53325450

DEFAULT_TARGET_EXES = frozenset({
    "sims2ep9.exe",
    "sims2ep9rpc.exe",
    "sims2rpc.exe",
    "sims2sc.exe",
    "sims2lc.exe",
    "sims2.exe",
    "sims2ep8.exe",
    "sims2sp8.exe",
    "sims2ep7.exe",
    "sims2ep6.exe",
    "sims2ep5.exe",
    "sims2ep4.exe",
    "sims2ep3.exe",
    "sims2ep2.exe",
    "sims2ep1.exe",
})

MODIFIER_VKS: dict[str, tuple[int, ...]] = {
    "ralt": (VK_RMENU,),
    "lalt": (VK_LMENU,),
    "alt": (VK_LMENU, VK_RMENU, VK_MENU),
    "rctrl": (VK_RCONTROL,),
    "lctrl": (VK_LCONTROL,),
    "ctrl": (VK_LCONTROL, VK_RCONTROL, VK_CONTROL),
    "none": (),
}

LATCH_VKS: dict[str, int] = {
    "f8": VK_F8,
    "f9": VK_F9,
    "f10": VK_F10,
    "none": 0,
}


@dataclass
class HookActions:
    """Outputs produced by TrackpadCameraState for a single input or timer event."""

    swallow: bool = False
    inject_mmb_down: bool = False
    inject_mmb_up: bool = False
    inject_move_dx: int = 0
    inject_key_tap: int | None = None


@dataclass
class TrackpadConfig:
    modifier_mode: str = "ralt"
    latch_key: str = "f8"
    hscroll_mode: str = "mmb-drag"  # "mmb-drag" | "keys" | "off"
    sensitivity: float = 18.0
    invert_hscroll: bool = False
    swipe_release_sec: float = 0.18
    target_exes: frozenset[str] = DEFAULT_TARGET_EXES
    any_window: bool = False


@dataclass
class TrackpadCameraState:
    """Pure-Python state machine governing trackpad-to-camera translation."""

    config: TrackpadConfig = field(default_factory=TrackpadConfig)
    modifier_down: bool = False
    latch_armed: bool = False
    drag_mmb_active: bool = False
    swipe_mmb_active: bool = False
    last_swipe_ts: float = 0.0

    @property
    def mmb_virtually_held(self) -> bool:
        return self.drag_mmb_active or self.swipe_mmb_active

    def on_key_event(self, vk_code: int, is_down: bool, is_target_focused: bool) -> HookActions:
        actions = HookActions()

        target_mods = MODIFIER_VKS.get(self.config.modifier_mode, ())
        if vk_code in target_mods:
            self.modifier_down = is_down

        latch_vk = LATCH_VKS.get(self.config.latch_key, 0)
        if is_target_focused and is_down and latch_vk and vk_code == latch_vk:
            self.latch_armed = not self.latch_armed
            actions.swallow = True
            if not self.latch_armed and self.drag_mmb_active:
                self.drag_mmb_active = False
                if not self.swipe_mmb_active:
                    actions.inject_mmb_up = True
            return actions

        if is_target_focused and is_down and vk_code == VK_ESCAPE and self.latch_armed:
            self.latch_armed = False
            if self.drag_mmb_active:
                self.drag_mmb_active = False
                if not self.swipe_mmb_active:
                    actions.inject_mmb_up = True

        return actions

    def on_mouse_event(
        self,
        msg: int,
        wheel_delta: int,
        is_target_focused: bool,
        now: float,
    ) -> HookActions:
        actions = HookActions()

        if not is_target_focused:
            return self.on_focus_lost()

        if msg == WM_LBUTTONDOWN:
            if self.modifier_down or self.latch_armed:
                was_held = self.mmb_virtually_held
                self.drag_mmb_active = True
                actions.swallow = True
                if not was_held:
                    actions.inject_mmb_down = True
            return actions

        if msg == WM_LBUTTONUP:
            if self.drag_mmb_active:
                self.drag_mmb_active = False
                actions.swallow = True
                if not self.swipe_mmb_active:
                    actions.inject_mmb_up = True
            return actions

        if msg == WM_MOUSEHWHEEL and self.config.hscroll_mode != "off" and wheel_delta != 0:
            signed_delta = -wheel_delta if self.config.invert_hscroll else wheel_delta
            actions.swallow = True

            if self.config.hscroll_mode == "keys":
                actions.inject_key_tap = VK_OEM_PERIOD if signed_delta > 0 else VK_OEM_COMMA
                return actions

            # Smooth analog horizontal MMB drag
            was_held = self.mmb_virtually_held
            self.swipe_mmb_active = True
            self.last_swipe_ts = now
            if not was_held:
                actions.inject_mmb_down = True

            step = int(round((signed_delta / 120.0) * self.config.sensitivity))
            if step == 0:
                step = 1 if signed_delta > 0 else -1
            actions.inject_move_dx = step
            return actions

        return actions

    def on_tick(self, now: float, is_target_focused: bool) -> HookActions:
        if not is_target_focused:
            return self.on_focus_lost()

        actions = HookActions()
        if self.swipe_mmb_active and (now - self.last_swipe_ts) >= self.config.swipe_release_sec:
            self.swipe_mmb_active = False
            if not self.drag_mmb_active:
                actions.inject_mmb_up = True
        return actions

    def on_focus_lost(self) -> HookActions:
        actions = HookActions()
        was_held = self.mmb_virtually_held
        self.modifier_down = False
        self.latch_armed = False
        self.drag_mmb_active = False
        self.swipe_mmb_active = False
        if was_held:
            actions.inject_mmb_up = True
        return actions


# ---------------------------------------------------------------------------
# Win32 x64-safe structures & ctypes bindings
# ---------------------------------------------------------------------------

if sys.platform == "win32":
    from ctypes import wintypes

    LRESULT = ctypes.c_ssize_t
    ULONG_PTR = ctypes.c_size_t
    HHOOK = wintypes.HANDLE

    class POINT(ctypes.Structure):
        _fields_ = [("x", wintypes.LONG), ("y", wintypes.LONG)]

    class MSLLHOOKSTRUCT(ctypes.Structure):
        _fields_ = [
            ("pt", POINT),
            ("mouseData", wintypes.DWORD),
            ("flags", wintypes.DWORD),
            ("time", wintypes.DWORD),
            ("dwExtraInfo", ULONG_PTR),
        ]

    class KBDLLHOOKSTRUCT(ctypes.Structure):
        _fields_ = [
            ("vkCode", wintypes.DWORD),
            ("scanCode", wintypes.DWORD),
            ("flags", wintypes.DWORD),
            ("time", wintypes.DWORD),
            ("dwExtraInfo", ULONG_PTR),
        ]

    class MOUSEINPUT(ctypes.Structure):
        _fields_ = [
            ("dx", wintypes.LONG),
            ("dy", wintypes.LONG),
            ("mouseData", wintypes.DWORD),
            ("dwFlags", wintypes.DWORD),
            ("time", wintypes.DWORD),
            ("dwExtraInfo", ULONG_PTR),
        ]

    class KEYBDINPUT(ctypes.Structure):
        _fields_ = [
            ("wVk", wintypes.WORD),
            ("wScan", wintypes.WORD),
            ("dwFlags", wintypes.DWORD),
            ("time", wintypes.DWORD),
            ("dwExtraInfo", ULONG_PTR),
        ]

    class HARDWAREINPUT(ctypes.Structure):
        _fields_ = [
            ("uMsg", wintypes.DWORD),
            ("wParamL", wintypes.WORD),
            ("wParamH", wintypes.WORD),
        ]

    class _INPUT_UNION(ctypes.Union):
        _fields_ = [
            ("mi", MOUSEINPUT),
            ("ki", KEYBDINPUT),
            ("hi", HARDWAREINPUT),
        ]

    class INPUT(ctypes.Structure):
        _anonymous_ = ("_u",)
        _fields_ = [
            ("type", wintypes.DWORD),
            ("_u", _INPUT_UNION),
        ]

    HOOKPROC = ctypes.WINFUNCTYPE(LRESULT, ctypes.c_int, wintypes.WPARAM, wintypes.LPARAM)

    _user32 = ctypes.windll.user32
    _kernel32 = ctypes.windll.kernel32

    _user32.SetWindowsHookExW.argtypes = [ctypes.c_int, HOOKPROC, wintypes.HINSTANCE, wintypes.DWORD]
    _user32.SetWindowsHookExW.restype = HHOOK
    _user32.CallNextHookEx.argtypes = [HHOOK, ctypes.c_int, wintypes.WPARAM, wintypes.LPARAM]
    _user32.CallNextHookEx.restype = LRESULT
    _user32.UnhookWindowsHookEx.argtypes = [HHOOK]
    _user32.UnhookWindowsHookEx.restype = wintypes.BOOL
    _user32.SendInput.argtypes = [wintypes.UINT, ctypes.POINTER(INPUT), ctypes.c_int]
    _user32.SendInput.restype = wintypes.UINT
    _user32.GetMessageW.argtypes = [ctypes.POINTER(wintypes.MSG), wintypes.HWND, wintypes.UINT, wintypes.UINT]
    _user32.GetMessageW.restype = wintypes.BOOL
    _user32.SetTimer.argtypes = [wintypes.HWND, ULONG_PTR, wintypes.UINT, ctypes.c_void_p]
    _user32.SetTimer.restype = ULONG_PTR
    _user32.KillTimer.argtypes = [wintypes.HWND, ULONG_PTR]
    _user32.KillTimer.restype = wintypes.BOOL
    _user32.GetForegroundWindow.argtypes = []
    _user32.GetForegroundWindow.restype = wintypes.HWND
    _user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    _user32.GetWindowThreadProcessId.restype = wintypes.DWORD
    _user32.PostThreadMessageW.argtypes = [wintypes.DWORD, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
    _user32.PostThreadMessageW.restype = wintypes.BOOL
    _user32.MapVirtualKeyW.argtypes = [wintypes.UINT, wintypes.UINT]
    _user32.MapVirtualKeyW.restype = wintypes.UINT

    _kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    _kernel32.OpenProcess.restype = wintypes.HANDLE
    _kernel32.QueryFullProcessImageNameW.argtypes = [
        wintypes.HANDLE,
        wintypes.DWORD,
        wintypes.LPWSTR,
        ctypes.POINTER(wintypes.DWORD),
    ]
    _kernel32.QueryFullProcessImageNameW.restype = wintypes.BOOL
    _kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    _kernel32.CloseHandle.restype = wintypes.BOOL
    _kernel32.GetCurrentThreadId.argtypes = []
    _kernel32.GetCurrentThreadId.restype = wintypes.DWORD

    PROCESS_QUERY_LIMITED_INFORMATION = 0x1000

    def get_foreground_process_name() -> str | None:
        hwnd = _user32.GetForegroundWindow()
        if not hwnd:
            return None
        pid = wintypes.DWORD(0)
        _user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        if not pid.value:
            return None
        handle = _kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid.value)
        if not handle:
            return None
        try:
            buf_len = wintypes.DWORD(512)
            buf = ctypes.create_unicode_buffer(buf_len.value)
            if _kernel32.QueryFullProcessImageNameW(handle, 0, buf, ctypes.byref(buf_len)):
                return Path(buf.value).name.lower()
            return None
        finally:
            _kernel32.CloseHandle(handle)

    def _send_mouse_input(flags: int, dx: int = 0, dy: int = 0) -> None:
        inp = INPUT()
        inp.type = INPUT_MOUSE
        inp.mi = MOUSEINPUT(
            dx=dx,
            dy=dy,
            mouseData=0,
            dwFlags=flags,
            time=0,
            dwExtraInfo=SYNTHETIC_EXTRA_INFO,
        )
        _user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(INPUT))

    def _send_key_tap(vk_code: int) -> None:
        scan = _user32.MapVirtualKeyW(vk_code, 0)
        pair = (INPUT * 2)()
        pair[0].type = INPUT_KEYBOARD
        pair[0].ki = KEYBDINPUT(wVk=vk_code, wScan=scan, dwFlags=0, time=0, dwExtraInfo=SYNTHETIC_EXTRA_INFO)
        pair[1].type = INPUT_KEYBOARD
        pair[1].ki = KEYBDINPUT(
            wVk=vk_code,
            wScan=scan,
            dwFlags=KEYEVENTF_KEYUP,
            time=0,
            dwExtraInfo=SYNTHETIC_EXTRA_INFO,
        )
        _user32.SendInput(2, pair, ctypes.sizeof(INPUT))

    def _execute_actions(actions: HookActions) -> None:
        if actions.inject_mmb_down:
            _send_mouse_input(MOUSEEVENTF_MIDDLEDOWN)
        if actions.inject_move_dx != 0:
            _send_mouse_input(MOUSEEVENTF_MOVE, dx=actions.inject_move_dx, dy=0)
        if actions.inject_key_tap is not None:
            _send_key_tap(actions.inject_key_tap)
        if actions.inject_mmb_up:
            _send_mouse_input(MOUSEEVENTF_MIDDLEUP)

    def run_hook_loop(config: TrackpadConfig) -> int:
        state = TrackpadCameraState(config=config)
        mouse_hook: HHOOK | None = None
        kbd_hook: HHOOK | None = None
        main_tid = _kernel32.GetCurrentThreadId()
        last_fg_check = 0.0
        cached_focused = False

        def check_target_focused(now: float) -> bool:
            nonlocal last_fg_check, cached_focused
            if config.any_window:
                return True
            if (now - last_fg_check) >= 0.08:
                proc = get_foreground_process_name()
                cached_focused = bool(proc and proc in config.target_exes)
                last_fg_check = now
            return cached_focused

        def cleanup() -> None:
            nonlocal mouse_hook, kbd_hook
            if state.mmb_virtually_held:
                state.on_focus_lost()
                _send_mouse_input(MOUSEEVENTF_MIDDLEUP)
            if mouse_hook:
                _user32.UnhookWindowsHookEx(mouse_hook)
                mouse_hook = None
            if kbd_hook:
                _user32.UnhookWindowsHookEx(kbd_hook)
                kbd_hook = None

        atexit.register(cleanup)

        @HOOKPROC
        def mouse_proc(nCode: int, wParam: wintypes.WPARAM, lParam: wintypes.LPARAM) -> LRESULT:
            if nCode >= 0:
                info = ctypes.cast(lParam, ctypes.POINTER(MSLLHOOKSTRUCT)).contents
                if info.dwExtraInfo != SYNTHETIC_EXTRA_INFO:
                    now = time.monotonic()
                    wheel_delta = ctypes.c_short((info.mouseData >> 16) & 0xFFFF).value
                    prev_latch = state.latch_armed
                    actions = state.on_mouse_event(int(wParam), wheel_delta, check_target_focused(now), now)
                    _execute_actions(actions)
                    if prev_latch != state.latch_armed:
                        print(f"[Orbit Latch] {'ACTIVE' if state.latch_armed else 'OFF'}", flush=True)
                    if actions.swallow:
                        return 1
            return _user32.CallNextHookEx(mouse_hook, nCode, wParam, lParam)

        @HOOKPROC
        def kbd_proc(nCode: int, wParam: wintypes.WPARAM, lParam: wintypes.LPARAM) -> LRESULT:
            if nCode >= 0:
                info = ctypes.cast(lParam, ctypes.POINTER(KBDLLHOOKSTRUCT)).contents
                if info.dwExtraInfo != SYNTHETIC_EXTRA_INFO:
                    msg = int(wParam)
                    is_down = msg in (WM_KEYDOWN, WM_SYSKEYDOWN)
                    if msg in (WM_KEYDOWN, WM_SYSKEYDOWN, WM_KEYUP, WM_SYSKEYUP):
                        now = time.monotonic()
                        prev_latch = state.latch_armed
                        actions = state.on_key_event(int(info.vkCode), is_down, check_target_focused(now))
                        _execute_actions(actions)
                        if prev_latch != state.latch_armed:
                            print(f"[Orbit Latch] {'ACTIVE (1-finger drag orbits camera)' if state.latch_armed else 'OFF'}", flush=True)
                        if actions.swallow:
                            return 1
            return _user32.CallNextHookEx(kbd_hook, nCode, wParam, lParam)

        mouse_hook = _user32.SetWindowsHookExW(WH_MOUSE_LL, mouse_proc, None, 0)
        kbd_hook = _user32.SetWindowsHookExW(WH_KEYBOARD_LL, kbd_proc, None, 0)
        if not mouse_hook or not kbd_hook:
            cleanup()
            print("[-] Echec d'installation des hooks Win32 SetWindowsHookExW.", file=sys.stderr)
            return 1

        timer_id = _user32.SetTimer(None, 0, 50, None)

        def on_sigint(_sig: int, _frame: object) -> None:
            _user32.PostThreadMessageW(main_tid, 0x0012, 0, 0)  # WM_QUIT

        signal.signal(signal.SIGINT, on_sigint)

        print("========================================================================")
        print("  Sims 2 Crash Patch — Windows Trackpad & Camera Rotation Helper        ")
        print("========================================================================")
        print(f"  * Swipe horizontal 2 doigts : mode='{config.hscroll_mode}', sens={config.sensitivity}")
        print(f"  * Modificateur + Glisser    : '{config.modifier_mode}' + clic gauche -> Orbite 360")
        print(f"  * Bascule Orbite (1 doigt)  : touche '{config.latch_key.upper()}' (Esc pour quitter)")
        scope = "TOUTES fenetres (--any-window)" if config.any_window else "Sims 2 uniquement (auto-detecte)"
        print(f"  * Portee                    : {scope}")
        print("  Appuyez sur Ctrl+C pour quitter proprement.")
        print("========================================================================")

        msg = wintypes.MSG()
        try:
            while _user32.GetMessageW(ctypes.byref(msg), None, 0, 0) > 0:
                if msg.message == WM_TIMER:
                    now = time.monotonic()
                    actions = state.on_tick(now, check_target_focused(now))
                    _execute_actions(actions)
        finally:
            if timer_id:
                _user32.KillTimer(None, timer_id)
            cleanup()

        return 0
else:

    def run_hook_loop(config: TrackpadConfig) -> int:
        print("[-] Le hook Win32 fonctionne uniquement sous Windows.", file=sys.stderr)
        return 1


def run_self_test() -> int:
    """Verify Win32 structure layout, hook registration, and foreground process lookup."""
    if sys.platform != "win32":
        print("Self-test non-Windows: state machine loaded cleanly.")
        return 0

    expected_input_size = 40 if ctypes.sizeof(ctypes.c_void_p) == 8 else 28
    actual_input_size = ctypes.sizeof(INPUT)
    assert actual_input_size == expected_input_size, f"INPUT size {actual_input_size} != {expected_input_size}"
    fg = get_foreground_process_name()

    @HOOKPROC
    def noop_proc(nCode: int, wParam: wintypes.WPARAM, lParam: wintypes.LPARAM) -> LRESULT:
        return _user32.CallNextHookEx(None, nCode, wParam, lParam)

    test_hook = _user32.SetWindowsHookExW(WH_MOUSE_LL, noop_proc, None, 0)
    if test_hook:
        _user32.UnhookWindowsHookEx(test_hook)
        hook_msg = "WH_MOUSE_LL hook OK"
    elif os.environ.get("CI") == "true":
        hook_msg = "WH_MOUSE_LL skipped (headless CI session)"
    else:
        raise AssertionError("SetWindowsHookExW(WH_MOUSE_LL) failed")

    print(f"[+] Win32 INPUT sizeof = {actual_input_size} bytes, {hook_msg}, foreground proc = {fg}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Sims 2 Windows Trackpad & Camera Rotation Helper"
    )
    parser.add_argument(
        "--modifier",
        choices=sorted(MODIFIER_VKS.keys()),
        default="ralt",
        help="Modifier key + Left-Drag to orbit camera (default: ralt / AltGr)",
    )
    parser.add_argument(
        "--latch-key",
        choices=sorted(LATCH_VKS.keys()),
        default="f8",
        help="Toggle 1-finger drag camera orbit mode (default: f8)",
    )
    parser.add_argument(
        "--hscroll",
        choices=["mmb-drag", "keys", "off"],
        default="mmb-drag",
        help="2-finger horizontal swipe translation mode (default: mmb-drag)",
    )
    parser.add_argument(
        "--sensitivity",
        type=float,
        default=18.0,
        help="Horizontal swipe drag pixels per wheel notch (default: 18.0)",
    )
    parser.add_argument(
        "--invert-hscroll",
        action="store_true",
        help="Invert 2-finger horizontal swipe camera rotation direction",
    )
    parser.add_argument(
        "--any-window",
        action="store_true",
        help="Apply hooks globally (testing only)",
    )
    parser.add_argument(
        "--extra-exe",
        action="append",
        default=[],
        help="Additional target executable name (e.g. Sims2Custom.exe)",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Validate Win32 ctypes structures and exit",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.self_test:
        return run_self_test()

    exes = frozenset(set(DEFAULT_TARGET_EXES) | {name.lower() for name in args.extra_exe})
    cfg = TrackpadConfig(
        modifier_mode=args.modifier,
        latch_key=args.latch_key,
        hscroll_mode=args.hscroll,
        sensitivity=args.sensitivity,
        invert_hscroll=args.invert_hscroll,
        target_exes=exes,
        any_window=args.any_window,
    )
    return run_hook_loop(cfg)


if __name__ == "__main__":
    raise SystemExit(main())
