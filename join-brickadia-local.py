#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ctypes
import os
import re
import subprocess
import sys
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from ctypes import wintypes


BRICKADIA_PROCESS = "BrickadiaSteam-Win64-Shipping.exe"
DEFAULT_BRICKADIA_EXE = (
    r"J:\SteamLibrary\steamapps\common\Brickadia\Brickadia\Binaries\Win64"
    rf"\{BRICKADIA_PROCESS}"
)
DEFAULT_LOG = (
    Path(os.environ.get("LOCALAPPDATA", ""))
    / "Brickadia"
    / "Saved"
    / "Logs"
    / "Brickadia.log"
)

INPUT_MOUSE = 0
INPUT_KEYBOARD = 1
KEYEVENTF_EXTENDEDKEY = 0x0001
KEYEVENTF_KEYUP = 0x0002
KEYEVENTF_UNICODE = 0x0004
KEYEVENTF_SCANCODE = 0x0008
MOUSEEVENTF_LEFTDOWN = 0x0002
MOUSEEVENTF_LEFTUP = 0x0004
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
SW_RESTORE = 9
WH_KEYBOARD_LL = 13
WH_MOUSE_LL = 14
WM_QUIT = 0x0012
PM_NOREMOVE = 0x0000
VK_A = 0x41
VK_CONTROL = 0x11
VK_LBUTTON = 0x01
VK_LWIN = 0x5B
VK_MENU = 0x12
VK_MBUTTON = 0x04
VK_RBUTTON = 0x02
VK_RWIN = 0x5C
VK_RETURN = 0x0D
VK_SHIFT = 0x10
VK_XBUTTON1 = 0x05
VK_XBUTTON2 = 0x06
MAPVK_VK_TO_VSC = 0

SCRIPT_INPUT_EXTRA_INFO = 0x0B41D1A
HOOK_READY_TIMEOUT = 2.0
HOOK_STOP_TIMEOUT = 2.0
INPUT_IDLE_TIMEOUT = 10.0
INPUT_IDLE_STABLE_TIME = 0.12
XINPUT_MAX_CONTROLLERS = 4
XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE = 7849
XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE = 8689
XINPUT_GAMEPAD_TRIGGER_THRESHOLD = 30
ERROR_SUCCESS = 0
ERROR_DEVICE_NOT_CONNECTED = 1167
ULONG_PTR = ctypes.c_ulonglong if ctypes.sizeof(ctypes.c_void_p) == 8 else ctypes.c_ulong
LRESULT = ctypes.c_ssize_t
HOOKPROC = ctypes.WINFUNCTYPE(LRESULT, ctypes.c_int, wintypes.WPARAM, wintypes.LPARAM)

user32 = ctypes.WinDLL("user32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)


class POINT(ctypes.Structure):
    _fields_ = [("x", wintypes.LONG), ("y", wintypes.LONG)]


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


class INPUT_UNION(ctypes.Union):
    _fields_ = [
        ("mi", MOUSEINPUT),
        ("ki", KEYBDINPUT),
        ("hi", HARDWAREINPUT),
    ]


class INPUT(ctypes.Structure):
    _fields_ = [("type", wintypes.DWORD), ("union", INPUT_UNION)]


class KBDLLHOOKSTRUCT(ctypes.Structure):
    _fields_ = [
        ("vkCode", wintypes.DWORD),
        ("scanCode", wintypes.DWORD),
        ("flags", wintypes.DWORD),
        ("time", wintypes.DWORD),
        ("dwExtraInfo", ULONG_PTR),
    ]


class MSLLHOOKSTRUCT(ctypes.Structure):
    _fields_ = [
        ("pt", POINT),
        ("mouseData", wintypes.DWORD),
        ("flags", wintypes.DWORD),
        ("time", wintypes.DWORD),
        ("dwExtraInfo", ULONG_PTR),
    ]


class XINPUT_GAMEPAD(ctypes.Structure):
    _fields_ = [
        ("wButtons", wintypes.WORD),
        ("bLeftTrigger", wintypes.BYTE),
        ("bRightTrigger", wintypes.BYTE),
        ("sThumbLX", wintypes.SHORT),
        ("sThumbLY", wintypes.SHORT),
        ("sThumbRX", wintypes.SHORT),
        ("sThumbRY", wintypes.SHORT),
    ]


class XINPUT_STATE(ctypes.Structure):
    _fields_ = [
        ("dwPacketNumber", wintypes.DWORD),
        ("Gamepad", XINPUT_GAMEPAD),
    ]


class WindowInfo:
    def __init__(self, hwnd: int, pid: int, title: str, image_path: str | None):
        self.hwnd = hwnd
        self.pid = pid
        self.title = title
        self.image_path = image_path

    @property
    def image_name(self) -> str:
        if not self.image_path:
            return ""
        return Path(self.image_path).name


@dataclass
class LogCheckpoint:
    path: Path
    size: int


@dataclass
class LogResult:
    connected: bool
    seen_attempt: bool
    seen_failure: bool
    reason: str
    latest_line: str | None = None


INPUT_IDLE_KEYS: tuple[tuple[int, str], ...] = (
    (VK_LBUTTON, "left mouse"),
    (VK_RBUTTON, "right mouse"),
    (VK_MBUTTON, "middle mouse"),
    (VK_XBUTTON1, "mouse button 4"),
    (VK_XBUTTON2, "mouse button 5"),
    (VK_SHIFT, "Shift"),
    (VK_CONTROL, "Ctrl"),
    (VK_MENU, "Alt"),
    (VK_LWIN, "left Windows"),
    (VK_RWIN, "right Windows"),
)

XINPUT_BUTTON_NAMES: tuple[tuple[int, str], ...] = (
    (0x0001, "dpad up"),
    (0x0002, "dpad down"),
    (0x0004, "dpad left"),
    (0x0008, "dpad right"),
    (0x0010, "start"),
    (0x0020, "back"),
    (0x0040, "left stick button"),
    (0x0080, "right stick button"),
    (0x0100, "left shoulder"),
    (0x0200, "right shoulder"),
    (0x1000, "A"),
    (0x2000, "B"),
    (0x4000, "X"),
    (0x8000, "Y"),
)


def load_xinput_get_state() -> object | None:
    for dll_name in ("xinput1_4.dll", "xinput1_3.dll", "xinput9_1_0.dll"):
        try:
            dll = ctypes.WinDLL(dll_name)
        except OSError:
            continue

        get_state = dll.XInputGetState
        get_state.argtypes = [wintypes.DWORD, ctypes.POINTER(XINPUT_STATE)]
        get_state.restype = wintypes.DWORD
        return get_state
    return None


XINPUT_GET_STATE = load_xinput_get_state()


user32.EnumWindows.argtypes = [ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM), wintypes.LPARAM]
user32.EnumWindows.restype = wintypes.BOOL
user32.IsWindowVisible.argtypes = [wintypes.HWND]
user32.IsWindowVisible.restype = wintypes.BOOL
user32.IsWindow.argtypes = [wintypes.HWND]
user32.IsWindow.restype = wintypes.BOOL
user32.GetWindowTextLengthW.argtypes = [wintypes.HWND]
user32.GetWindowTextLengthW.restype = ctypes.c_int
user32.GetWindowTextW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
user32.GetWindowTextW.restype = ctypes.c_int
user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
user32.GetWindowThreadProcessId.restype = wintypes.DWORD
user32.ShowWindow.argtypes = [wintypes.HWND, ctypes.c_int]
user32.ShowWindow.restype = wintypes.BOOL
user32.BringWindowToTop.argtypes = [wintypes.HWND]
user32.BringWindowToTop.restype = wintypes.BOOL
user32.SetForegroundWindow.argtypes = [wintypes.HWND]
user32.SetForegroundWindow.restype = wintypes.BOOL
user32.SetFocus.argtypes = [wintypes.HWND]
user32.SetFocus.restype = wintypes.HWND
user32.SetActiveWindow.argtypes = [wintypes.HWND]
user32.SetActiveWindow.restype = wintypes.HWND
user32.GetForegroundWindow.argtypes = []
user32.GetForegroundWindow.restype = wintypes.HWND
user32.AttachThreadInput.argtypes = [wintypes.DWORD, wintypes.DWORD, wintypes.BOOL]
user32.AttachThreadInput.restype = wintypes.BOOL
user32.GetClientRect.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.RECT)]
user32.GetClientRect.restype = wintypes.BOOL
user32.ClientToScreen.argtypes = [wintypes.HWND, ctypes.POINTER(POINT)]
user32.ClientToScreen.restype = wintypes.BOOL
user32.SetCursorPos.argtypes = [ctypes.c_int, ctypes.c_int]
user32.SetCursorPos.restype = wintypes.BOOL
user32.SendInput.argtypes = [ctypes.c_uint, ctypes.POINTER(INPUT), ctypes.c_int]
user32.SendInput.restype = ctypes.c_uint
user32.SetWindowsHookExW.argtypes = [ctypes.c_int, HOOKPROC, wintypes.HINSTANCE, wintypes.DWORD]
user32.SetWindowsHookExW.restype = wintypes.HHOOK
user32.CallNextHookEx.argtypes = [wintypes.HHOOK, ctypes.c_int, wintypes.WPARAM, wintypes.LPARAM]
user32.CallNextHookEx.restype = LRESULT
user32.UnhookWindowsHookEx.argtypes = [wintypes.HHOOK]
user32.UnhookWindowsHookEx.restype = wintypes.BOOL
user32.PeekMessageW.argtypes = [ctypes.POINTER(wintypes.MSG), wintypes.HWND, wintypes.UINT, wintypes.UINT, wintypes.UINT]
user32.PeekMessageW.restype = wintypes.BOOL
user32.GetMessageW.argtypes = [ctypes.POINTER(wintypes.MSG), wintypes.HWND, wintypes.UINT, wintypes.UINT]
user32.GetMessageW.restype = wintypes.BOOL
user32.PostThreadMessageW.argtypes = [wintypes.DWORD, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
user32.PostThreadMessageW.restype = wintypes.BOOL
user32.GetAsyncKeyState.argtypes = [ctypes.c_int]
user32.GetAsyncKeyState.restype = ctypes.c_short
user32.MapVirtualKeyW.argtypes = [ctypes.c_uint, ctypes.c_uint]
user32.MapVirtualKeyW.restype = ctypes.c_uint
user32.VkKeyScanW.argtypes = [ctypes.c_wchar]
user32.VkKeyScanW.restype = ctypes.c_short

kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
kernel32.OpenProcess.restype = wintypes.HANDLE
kernel32.QueryFullProcessImageNameW.argtypes = [
    wintypes.HANDLE,
    wintypes.DWORD,
    wintypes.LPWSTR,
    ctypes.POINTER(wintypes.DWORD),
]
kernel32.QueryFullProcessImageNameW.restype = wintypes.BOOL
kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
kernel32.CloseHandle.restype = wintypes.BOOL
kernel32.GetCurrentThreadId.argtypes = []
kernel32.GetCurrentThreadId.restype = wintypes.DWORD


def fail(message: str, code: int = 1) -> int:
    print(f"[join] error: {message}", file=sys.stderr)
    return code


def window_pid(hwnd: int) -> int:
    pid = wintypes.DWORD()
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    return int(pid.value)


def window_exists(hwnd: int) -> bool:
    return bool(hwnd and user32.IsWindow(hwnd))


def window_title(hwnd: int) -> str:
    length = user32.GetWindowTextLengthW(hwnd)
    if length <= 0:
        return ""
    buffer = ctypes.create_unicode_buffer(length + 1)
    user32.GetWindowTextW(hwnd, buffer, length + 1)
    return buffer.value


def process_image_path(pid: int) -> str | None:
    handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if not handle:
        return None

    try:
        size = wintypes.DWORD(32768)
        buffer = ctypes.create_unicode_buffer(size.value)
        if not kernel32.QueryFullProcessImageNameW(handle, 0, buffer, ctypes.byref(size)):
            return None
        return buffer.value
    finally:
        kernel32.CloseHandle(handle)


def describe_window(hwnd: int) -> str:
    if not window_exists(hwnd):
        return "none"

    pid = window_pid(hwnd)
    image_path = process_image_path(pid)
    title = window_title(hwnd)
    image = f" image={image_path!r}" if image_path else ""
    return f"hwnd={hwnd} pid={pid} title={title!r}{image}"


def find_brickadia_windows() -> list[WindowInfo]:
    windows: list[WindowInfo] = []

    @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    def enum_window(hwnd: int, _lparam: int) -> bool:
        if not user32.IsWindowVisible(hwnd):
            return True

        pid = window_pid(hwnd)
        image_path = process_image_path(pid)
        title = window_title(hwnd)
        image_name = Path(image_path).name if image_path else ""
        if image_name.lower() == BRICKADIA_PROCESS.lower() or "Brickadia" in title:
            windows.append(WindowInfo(hwnd, pid, title, image_path))
        return True

    user32.EnumWindows(enum_window, 0)
    windows.sort(key=lambda item: (item.image_name.lower() != BRICKADIA_PROCESS.lower(), not item.title))
    return windows


def candidate_exe_paths(configured: str | None) -> Iterable[Path]:
    seen: set[str] = set()

    def add(path: str | os.PathLike[str] | None) -> Iterable[Path]:
        if not path:
            return
        normalized = str(Path(path)).lower()
        if normalized in seen:
            return
        seen.add(normalized)
        yield Path(path)

    yield from add(configured)
    yield from add(DEFAULT_BRICKADIA_EXE)

    for library in steam_libraries():
        yield from add(library / "steamapps" / "common" / "Brickadia" / "Brickadia" / "Binaries" / "Win64" / BRICKADIA_PROCESS)


def steam_libraries() -> Iterable[Path]:
    roots: list[Path] = []
    try:
        import winreg

        registry_keys = [
            (winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam"),
            (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Valve\Steam"),
            (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Valve\Steam"),
        ]
        for hive, key_name in registry_keys:
            try:
                with winreg.OpenKey(hive, key_name) as key:
                    for value in ("SteamPath", "InstallPath"):
                        try:
                            path, _kind = winreg.QueryValueEx(key, value)
                            roots.append(Path(str(path)))
                        except OSError:
                            pass
            except OSError:
                pass
    except ImportError:
        pass

    roots.extend(
        [
            Path(r"C:\Program Files (x86)\Steam"),
            Path(r"C:\Program Files\Steam"),
            Path(r"J:\SteamLibrary"),
        ]
    )

    seen: set[str] = set()
    for root in roots:
        normalized = str(root).lower()
        if normalized in seen:
            continue
        seen.add(normalized)
        yield root

        library_file = root / "steamapps" / "libraryfolders.vdf"
        if not library_file.exists():
            continue
        try:
            text = library_file.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for match in re.finditer(r'"path"\s*"([^"]+)"', text):
            library = Path(match.group(1).replace("\\\\", "\\"))
            normalized_library = str(library).lower()
            if normalized_library not in seen:
                seen.add(normalized_library)
                yield library


def start_brickadia(configured_exe: str | None) -> bool:
    for exe in candidate_exe_paths(configured_exe):
        if exe.exists():
            print(f"[join] starting Brickadia: {exe}")
            subprocess.Popen([str(exe)], cwd=str(exe.parent))
            return True
    return False


def wait_for_window(timeout: float) -> WindowInfo | None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        windows = find_brickadia_windows()
        if windows:
            return windows[0]
        time.sleep(0.25)
    return None


def foreground_process_matches(hwnd: int) -> bool:
    if not window_exists(hwnd):
        return False

    foreground = int(user32.GetForegroundWindow() or 0)
    if not foreground:
        return False
    return foreground == hwnd or window_pid(foreground) == window_pid(hwnd)


def ensure_target_window(window: WindowInfo) -> None:
    if not window_exists(window.hwnd):
        raise RuntimeError("Brickadia client window no longer exists")

    current_pid = window_pid(window.hwnd)
    if current_pid != window.pid:
        raise RuntimeError(
            f"Brickadia client window handle changed unexpectedly: "
            f"expected pid {window.pid}, got pid {current_pid}"
        )


def ensure_brickadia_foreground(window: WindowInfo, action: str) -> None:
    ensure_target_window(window)
    if foreground_process_matches(window.hwnd):
        return

    foreground = int(user32.GetForegroundWindow() or 0)
    raise RuntimeError(
        f"Brickadia is not the foreground window before {action}; "
        f"foreground is {describe_window(foreground)}"
    )


def pressed_input_names() -> list[str]:
    pressed: list[str] = []
    for vk, name in INPUT_IDLE_KEYS:
        if int(user32.GetAsyncKeyState(vk)) & 0x8000:
            pressed.append(name)
    pressed.extend(controller_input_names())
    return pressed


def thumbstick_active(x: int, y: int, deadzone: int) -> bool:
    return (x * x) + (y * y) > deadzone * deadzone


def controller_input_names() -> list[str]:
    if XINPUT_GET_STATE is None:
        return []

    active: list[str] = []
    for user_index in range(XINPUT_MAX_CONTROLLERS):
        state = XINPUT_STATE()
        result = int(XINPUT_GET_STATE(user_index, ctypes.byref(state)))
        if result == ERROR_DEVICE_NOT_CONNECTED:
            continue
        if result != ERROR_SUCCESS:
            continue

        controller = f"controller {user_index + 1}"
        gamepad = state.Gamepad
        for mask, name in XINPUT_BUTTON_NAMES:
            if int(gamepad.wButtons) & mask:
                active.append(f"{controller} {name}")
        if int(gamepad.bLeftTrigger) > XINPUT_GAMEPAD_TRIGGER_THRESHOLD:
            active.append(f"{controller} left trigger")
        if int(gamepad.bRightTrigger) > XINPUT_GAMEPAD_TRIGGER_THRESHOLD:
            active.append(f"{controller} right trigger")
        if thumbstick_active(int(gamepad.sThumbLX), int(gamepad.sThumbLY), XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE):
            active.append(f"{controller} left stick")
        if thumbstick_active(int(gamepad.sThumbRX), int(gamepad.sThumbRY), XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE):
            active.append(f"{controller} right stick")

    return active


def wait_for_physical_input_idle(timeout: float = INPUT_IDLE_TIMEOUT) -> None:
    deadline = time.monotonic() + timeout
    stable_since: float | None = None
    last_report: tuple[str, ...] | None = None

    while time.monotonic() < deadline:
        pressed = tuple(pressed_input_names())
        if not pressed:
            if stable_since is None:
                stable_since = time.monotonic()
            if time.monotonic() - stable_since >= INPUT_IDLE_STABLE_TIME:
                return
        else:
            stable_since = None
            if pressed != last_report:
                print(f"[join] waiting for physical input to go idle: {', '.join(pressed)}")
                last_report = pressed
        time.sleep(0.02)

    pressed = pressed_input_names()
    if pressed:
        raise RuntimeError(
            f"physical input is still held after {timeout:.1f}s: {', '.join(pressed)}"
        )
    raise RuntimeError(f"physical input did not stay idle for {INPUT_IDLE_STABLE_TIME:.2f}s")


def send_inputs(inputs: list[INPUT]) -> None:
    if not inputs:
        return
    array_type = INPUT * len(inputs)
    array = array_type(*inputs)
    sent = user32.SendInput(len(inputs), array, ctypes.sizeof(INPUT))
    if sent != len(inputs):
        raise OSError(ctypes.get_last_error(), "SendInput failed")


class BlockOtherInput:
    def __init__(self, enabled: bool) -> None:
        self.enabled = enabled
        self.thread: threading.Thread | None = None
        self.ready = threading.Event()
        self.error: str | None = None
        self.thread_id = 0
        self.keyboard_hook: int | None = None
        self.mouse_hook: int | None = None
        self.keyboard_proc: HOOKPROC | None = None
        self.mouse_proc: HOOKPROC | None = None

    def __enter__(self) -> "BlockOtherInput":
        if not self.enabled:
            return self

        self.thread = threading.Thread(target=self._hook_thread, name="BrickadiaJoinInputBlock", daemon=True)
        self.thread.start()
        if not self.ready.wait(HOOK_READY_TIMEOUT):
            self._stop_hooks()
            raise RuntimeError("timed out installing keyboard/mouse input block hooks")
        if self.error:
            self._stop_hooks()
            raise RuntimeError(self.error)
        pressed = pressed_input_names()
        if pressed:
            self._stop_hooks()
            raise RuntimeError(
                f"physical input became held while arming input block: {', '.join(pressed)}"
            )
        return self

    def __exit__(self, _exc_type: object, _exc: object, _tb: object) -> None:
        self._stop_hooks()

    def _allow_or_block_keyboard(self, n_code: int, w_param: int, l_param: int) -> int:
        if n_code >= 0:
            event = ctypes.cast(l_param, ctypes.POINTER(KBDLLHOOKSTRUCT)).contents
            if int(event.dwExtraInfo) != SCRIPT_INPUT_EXTRA_INFO:
                return 1
        return int(user32.CallNextHookEx(self.keyboard_hook, n_code, w_param, l_param))

    def _allow_or_block_mouse(self, n_code: int, w_param: int, l_param: int) -> int:
        if n_code >= 0:
            event = ctypes.cast(l_param, ctypes.POINTER(MSLLHOOKSTRUCT)).contents
            if int(event.dwExtraInfo) != SCRIPT_INPUT_EXTRA_INFO:
                return 1
        return int(user32.CallNextHookEx(self.mouse_hook, n_code, w_param, l_param))

    def _hook_thread(self) -> None:
        self.thread_id = int(kernel32.GetCurrentThreadId())
        self.keyboard_proc = HOOKPROC(self._allow_or_block_keyboard)
        self.mouse_proc = HOOKPROC(self._allow_or_block_mouse)

        self.keyboard_hook = int(user32.SetWindowsHookExW(WH_KEYBOARD_LL, self.keyboard_proc, None, 0) or 0)
        self.mouse_hook = int(user32.SetWindowsHookExW(WH_MOUSE_LL, self.mouse_proc, None, 0) or 0)
        if not self.keyboard_hook or not self.mouse_hook:
            error = ctypes.get_last_error()
            detail = f"Win32 error {error}" if error else "unknown error"
            self.error = f"could not install keyboard/mouse input block hooks ({detail})"
            self._unhook()
            self.ready.set()
            return

        msg = wintypes.MSG()
        user32.PeekMessageW(ctypes.byref(msg), None, 0, 0, PM_NOREMOVE)
        self.ready.set()
        try:
            while user32.GetMessageW(ctypes.byref(msg), None, 0, 0) > 0:
                pass
        finally:
            self._unhook()

    def _unhook(self) -> None:
        if self.keyboard_hook:
            user32.UnhookWindowsHookEx(self.keyboard_hook)
            self.keyboard_hook = None
        if self.mouse_hook:
            user32.UnhookWindowsHookEx(self.mouse_hook)
            self.mouse_hook = None

    def _stop_hooks(self) -> None:
        if not self.thread:
            return
        if self.thread_id:
            user32.PostThreadMessageW(self.thread_id, WM_QUIT, 0, 0)
        self.thread.join(HOOK_STOP_TIMEOUT)
        if self.thread.is_alive():
            print("[join] warning: keyboard/mouse input block hook thread did not stop cleanly", file=sys.stderr)
        self.thread = None


def keyboard_input(vk: int = 0, scan: int = 0, flags: int = 0) -> INPUT:
    return INPUT(
        type=INPUT_KEYBOARD,
        union=INPUT_UNION(
            ki=KEYBDINPUT(
                wVk=vk,
                wScan=scan,
                dwFlags=flags,
                time=0,
                dwExtraInfo=ULONG_PTR(SCRIPT_INPUT_EXTRA_INFO),
            )
        ),
    )


def mouse_input(flags: int) -> INPUT:
    return INPUT(
        type=INPUT_MOUSE,
        union=INPUT_UNION(
            mi=MOUSEINPUT(
                dx=0,
                dy=0,
                mouseData=0,
                dwFlags=flags,
                time=0,
                dwExtraInfo=ULONG_PTR(SCRIPT_INPUT_EXTRA_INFO),
            )
        ),
    )


def send_vk(vk: int, key_delay: float = 0.0) -> None:
    scan = int(user32.MapVirtualKeyW(vk, MAPVK_VK_TO_VSC))
    send_inputs(
        [
            keyboard_input(vk=vk, scan=scan),
            keyboard_input(vk=vk, scan=scan, flags=KEYEVENTF_KEYUP),
        ]
    )
    if key_delay:
        time.sleep(key_delay)


def send_scancode(scan: int, key_delay: float = 0.0) -> None:
    send_inputs(
        [
            keyboard_input(scan=scan, flags=KEYEVENTF_SCANCODE),
            keyboard_input(scan=scan, flags=KEYEVENTF_SCANCODE | KEYEVENTF_KEYUP),
        ]
    )
    if key_delay:
        time.sleep(key_delay)


def send_chord(modifiers: list[int], key: int, key_delay: float = 0.0) -> None:
    inputs: list[INPUT] = []
    for modifier in modifiers:
        inputs.append(keyboard_input(vk=modifier, scan=int(user32.MapVirtualKeyW(modifier, MAPVK_VK_TO_VSC))))
    key_scan = int(user32.MapVirtualKeyW(key, MAPVK_VK_TO_VSC))
    inputs.append(keyboard_input(vk=key, scan=key_scan))
    inputs.append(keyboard_input(vk=key, scan=key_scan, flags=KEYEVENTF_KEYUP))
    for modifier in reversed(modifiers):
        modifier_scan = int(user32.MapVirtualKeyW(modifier, MAPVK_VK_TO_VSC))
        inputs.append(keyboard_input(vk=modifier, scan=modifier_scan, flags=KEYEVENTF_KEYUP))
    send_inputs(inputs)
    if key_delay:
        time.sleep(key_delay)


def send_unicode_char(char: str) -> None:
    codepoint = ord(char)
    send_inputs(
        [
            keyboard_input(scan=codepoint, flags=KEYEVENTF_UNICODE),
            keyboard_input(scan=codepoint, flags=KEYEVENTF_UNICODE | KEYEVENTF_KEYUP),
        ]
    )


def send_text(text: str, key_delay: float) -> None:
    for char in text:
        scan = int(user32.VkKeyScanW(char))
        if scan == -1:
            send_unicode_char(char)
            time.sleep(key_delay)
            continue

        vk = scan & 0xFF
        shift_state = (scan >> 8) & 0xFF
        modifiers: list[int] = []
        if shift_state & 1:
            modifiers.append(VK_SHIFT)
        if shift_state & 2:
            modifiers.append(VK_CONTROL)
        if shift_state & 4:
            modifiers.append(VK_MENU)

        if modifiers:
            send_chord(modifiers, vk)
        else:
            send_vk(vk)
        time.sleep(key_delay)


def attach_thread_input(source: int, target: int, attach: bool) -> None:
    if source and target and source != target:
        user32.AttachThreadInput(source, target, attach)


def activate_window(hwnd: int, timeout: float) -> bool:
    if not window_exists(hwnd):
        return False

    deadline = time.monotonic() + timeout
    current_thread = int(kernel32.GetCurrentThreadId())

    while time.monotonic() < deadline:
        target_thread = int(user32.GetWindowThreadProcessId(hwnd, None))
        foreground = int(user32.GetForegroundWindow() or 0)
        foreground_thread = int(user32.GetWindowThreadProcessId(foreground, None)) if foreground else 0

        attach_thread_input(current_thread, target_thread, True)
        attach_thread_input(current_thread, foreground_thread, True)
        try:
            user32.ShowWindow(hwnd, SW_RESTORE)
            user32.BringWindowToTop(hwnd)
            user32.SetActiveWindow(hwnd)
            user32.SetFocus(hwnd)
            user32.SetForegroundWindow(hwnd)
        finally:
            attach_thread_input(current_thread, foreground_thread, False)
            attach_thread_input(current_thread, target_thread, False)

        if foreground_process_matches(hwnd):
            return True

        # Tapping Alt is a standard SetForegroundWindow workaround.
        send_vk(VK_MENU)
        user32.SetForegroundWindow(hwnd)
        if foreground_process_matches(hwnd):
            return True
        time.sleep(0.15)

    return False


def return_focus_to_window(hwnd: int, timeout: float) -> bool:
    if not window_exists(hwnd):
        return False

    deadline = time.monotonic() + timeout
    current_thread = int(kernel32.GetCurrentThreadId())

    while time.monotonic() < deadline:
        target_thread = int(user32.GetWindowThreadProcessId(hwnd, None))
        foreground = int(user32.GetForegroundWindow() or 0)
        foreground_thread = int(user32.GetWindowThreadProcessId(foreground, None)) if foreground else 0

        attach_thread_input(current_thread, target_thread, True)
        attach_thread_input(current_thread, foreground_thread, True)
        try:
            user32.BringWindowToTop(hwnd)
            user32.SetActiveWindow(hwnd)
            user32.SetFocus(hwnd)
            user32.SetForegroundWindow(hwnd)
        finally:
            attach_thread_input(current_thread, foreground_thread, False)
            attach_thread_input(current_thread, target_thread, False)

        if int(user32.GetForegroundWindow() or 0) == hwnd:
            return True

        # Tapping Alt is a standard SetForegroundWindow workaround.
        send_vk(VK_MENU)
        user32.SetForegroundWindow(hwnd)
        if int(user32.GetForegroundWindow() or 0) == hwnd:
            return True
        time.sleep(0.15)

    return False


def click_window_center(hwnd: int) -> None:
    rect = wintypes.RECT()
    if not user32.GetClientRect(hwnd, ctypes.byref(rect)):
        return
    width = int(rect.right - rect.left)
    height = int(rect.bottom - rect.top)
    if width <= 0 or height <= 0:
        return

    point = POINT(width // 2, height // 2)
    if not user32.ClientToScreen(hwnd, ctypes.byref(point)):
        return
    user32.SetCursorPos(point.x, point.y)
    send_inputs([mouse_input(MOUSEEVENTF_LEFTDOWN), mouse_input(MOUSEEVENTF_LEFTUP)])


def checkpoint_log(path: Path) -> LogCheckpoint:
    try:
        return LogCheckpoint(path=path, size=path.stat().st_size)
    except OSError:
        return LogCheckpoint(path=path, size=0)


def read_log_since(checkpoint: LogCheckpoint, max_bytes: int = 200_000) -> str:
    path = checkpoint.path
    try:
        size = path.stat().st_size
    except OSError:
        return ""

    start = checkpoint.size if size >= checkpoint.size else 0
    start = max(start, size - max_bytes)
    try:
        with path.open("rb") as handle:
            handle.seek(start)
            return handle.read(max_bytes).decode("utf-8", errors="replace")
    except OSError:
        return ""


def tail_log(path: Path, max_bytes: int = 200_000) -> str:
    try:
        size = path.stat().st_size
    except OSError:
        return ""
    try:
        with path.open("rb") as handle:
            handle.seek(max(0, size - max_bytes))
            return handle.read(max_bytes).decode("utf-8", errors="replace")
    except OSError:
        return ""


def host_for_log(address: str) -> str:
    if address.startswith("["):
        end = address.find("]")
        return address[1:end] if end > 0 else address
    if ":" in address and address.count(":") == 1:
        return address.split(":", 1)[0]
    return address


def classify_log(text: str, address: str) -> LogResult:
    host = re.escape(host_for_log(address))
    attempt_patterns = [
        re.compile(rf"Browse:\s*{host}(?::\d+)?", re.IGNORECASE),
        re.compile(rf"RemoteAddr:\s*{host}(?::\d+)?", re.IGNORECASE),
        re.compile(r"Attempting to connect", re.IGNORECASE),
    ]
    connected_patterns = [
        re.compile(r"Welcomed by server", re.IGNORECASE),
        re.compile(rf"LoadMap:\s*{host}(?::\d+)?//Game/Maps/", re.IGNORECASE),
        re.compile(r"Ty joined the game\.", re.IGNORECASE),
    ]
    failure_patterns = [
        re.compile(r"NetworkFailure", re.IGNORECASE),
        re.compile(r"Connection TIMED OUT", re.IGNORECASE),
        re.compile(rf"UNetConnection::Close:.*RemoteAddr:\s*{host}(?::\d+)?", re.IGNORECASE),
    ]

    seen_attempt = False
    seen_failure = False
    latest_line: str | None = None
    for line in text.splitlines():
        if any(pattern.search(line) for pattern in attempt_patterns):
            seen_attempt = True
            latest_line = line.strip()
        if any(pattern.search(line) for pattern in failure_patterns):
            seen_failure = True
            latest_line = line.strip()
        if any(pattern.search(line) for pattern in connected_patterns):
            return LogResult(
                connected=True,
                seen_attempt=True,
                seen_failure=seen_failure,
                reason="connected",
                latest_line=line.strip(),
            )

    if seen_attempt and seen_failure:
        reason = "connection attempt ended with a failure line"
    elif seen_attempt:
        reason = "connection attempt was logged, but no successful load/join line appeared"
    else:
        reason = "no fresh connection attempt appeared in the log"

    return LogResult(False, seen_attempt, seen_failure, reason, latest_line)


def wait_for_log_result(checkpoint: LogCheckpoint, address: str, timeout: float) -> LogResult:
    deadline = time.monotonic() + timeout
    best = LogResult(False, False, False, "no fresh connection attempt appeared in the log")
    while time.monotonic() < deadline:
        current = classify_log(read_log_since(checkpoint), address)
        if current.connected:
            return current
        if current.seen_attempt or current.seen_failure:
            best = current
        time.sleep(0.5)
    return best


def latest_known_state(log_path: Path, address: str) -> LogResult:
    return classify_log(tail_log(log_path), address)


def send_join_command(window: WindowInfo, address: str, args: argparse.Namespace) -> None:
    ensure_target_window(window)
    if not activate_window(window.hwnd, args.focus_timeout):
        raise RuntimeError("could not activate the Brickadia client window")

    time.sleep(args.focus_delay)
    ensure_brickadia_foreground(window, "clicking the client")
    if not args.no_click:
        click_window_center(window.hwnd)
        time.sleep(args.click_delay)

    ensure_brickadia_foreground(window, "opening the console")
    # Brickadia console opener: grave-accent key scancode 0x29.
    send_scancode(0x29)
    time.sleep(args.console_delay)
    ensure_brickadia_foreground(window, "selecting console text")
    send_chord([VK_CONTROL], VK_A)
    time.sleep(args.select_delay)
    ensure_brickadia_foreground(window, "typing the open command")
    send_text(f"open {address}", args.key_delay)
    time.sleep(args.enter_delay)
    ensure_brickadia_foreground(window, "submitting the open command")
    send_vk(VK_RETURN)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Focus Brickadia, send the local open command, and verify the client log."
    )
    parser.add_argument("address", nargs="?", default="127.0.0.1", help="server address passed to Brickadia's open command")
    parser.add_argument("--exe", default=os.environ.get("BRICKADIA_EXE"), help="Brickadia executable path to launch if needed")
    parser.add_argument("--log", default=str(DEFAULT_LOG), help="Brickadia client log path used for validation")
    parser.add_argument("--no-start", action="store_true", help="do not launch Brickadia when no window is found")
    parser.add_argument("--no-validate", action="store_true", help="send input only; do not wait for log confirmation")
    parser.add_argument("--dry-run", action="store_true", help="report the detected window/log state without sending input")
    parser.add_argument("--retries", type=int, default=2, help="number of input attempts when no fresh log attempt appears")
    parser.add_argument("--window-timeout", type=float, default=30.0, help="seconds to wait for a Brickadia window")
    parser.add_argument("--focus-timeout", type=float, default=5.0, help="seconds to try activating the Brickadia window")
    parser.add_argument("--validate-timeout", type=float, default=25.0, help="seconds to wait for fresh connection log lines")
    parser.add_argument("--focus-delay", type=float, default=0.08, help="pause after focus, in seconds")
    parser.add_argument("--click-delay", type=float, default=0.04, help="pause after the viewport click, in seconds")
    parser.add_argument("--console-delay", type=float, default=0.18, help="pause after opening the console, in seconds")
    parser.add_argument("--select-delay", type=float, default=0.02, help="pause after Ctrl+A, in seconds")
    parser.add_argument("--enter-delay", type=float, default=0.04, help="pause before pressing Enter, in seconds")
    parser.add_argument("--key-delay", type=float, default=0.005, help="delay between typed characters, in seconds")
    parser.add_argument("--no-click", action="store_true", help="skip clicking the center of the Brickadia client area")
    parser.add_argument(
        "--no-block-input",
        action="store_true",
        help="do not block other keyboard/mouse input while sending the join command",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    log_path = Path(args.log)
    previous_hwnd = int(user32.GetForegroundWindow() or 0)

    windows = find_brickadia_windows()
    if args.dry_run:
        if windows:
            window = windows[0]
            print(f"[join] window: hwnd={window.hwnd} pid={window.pid} title={window.title!r}")
        else:
            print("[join] window: not found")
        state = latest_known_state(log_path, args.address)
        print(f"[join] latest log state: {state.reason}")
        if state.latest_line:
            print(f"[join] latest line: {state.latest_line}")
        return 0 if windows else 2

    if not windows:
        if args.no_start:
            return fail("Brickadia is not running and --no-start was used")
        if not start_brickadia(args.exe):
            return fail("Brickadia is not running and no executable path was found")
        window = wait_for_window(args.window_timeout)
    else:
        window = windows[0]

    if not window:
        return fail("timed out waiting for the Brickadia client window")

    print(f"[join] using window: hwnd={window.hwnd} pid={window.pid} title={window.title!r}")

    try:
        attempts = max(1, args.retries)
        final_result = LogResult(False, False, False, "validation was not run")
        for attempt in range(1, attempts + 1):
            checkpoint = checkpoint_log(log_path)
            print(f"[join] sending console command ({attempt}/{attempts}): open {args.address}")
            try:
                if not args.no_block_input:
                    wait_for_physical_input_idle()
                with BlockOtherInput(not args.no_block_input):
                    send_join_command(window, args.address, args)
            except Exception as exc:
                return fail(str(exc))

            if args.no_validate:
                print("[join] input sent; validation skipped")
                return 0

            result = wait_for_log_result(checkpoint, args.address, args.validate_timeout)
            final_result = result
            if result.connected:
                print(f"[join] connected: {result.latest_line or result.reason}")
                return 0

            print(f"[join] validation: {result.reason}")
            if result.latest_line:
                print(f"[join] latest line: {result.latest_line}")

            if result.seen_attempt:
                break
            if attempt < attempts:
                print("[join] retrying because no fresh log attempt appeared")

        return fail(final_result.reason)
    finally:
        if previous_hwnd and previous_hwnd != window.hwnd and window_exists(previous_hwnd):
            if return_focus_to_window(previous_hwnd, 2.0):
                print(f"[join] returned focus to previous window: {describe_window(previous_hwnd)}")
            else:
                print(f"[join] warning: could not return focus to previous window: {describe_window(previous_hwnd)}", file=sys.stderr)


if __name__ == "__main__":
    if os.name != "nt":
        sys.exit(fail("this script only supports Windows"))
    sys.exit(main())
