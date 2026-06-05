#Requires AutoHotkey v2.0
#SingleInstance Force

SetTitleMatchMode 2
SendMode "Event"
SetWinDelay 0
SetMouseDelay 0
SetKeyDelay 5, 5
CoordMode "Mouse", "Screen"

FocusBrickadia(attempts := 3) {
  Loop attempts {
    WinShow "ahk_exe BrickadiaSteam-Win64-Shipping.exe"
    WinRestore "ahk_exe BrickadiaSteam-Win64-Shipping.exe"
    WinActivate "ahk_exe BrickadiaSteam-Win64-Shipping.exe"
    WinWaitActive "ahk_exe BrickadiaSteam-Win64-Shipping.exe", , 0.5
    Sleep 10
  }

  return WinActive("ahk_exe BrickadiaSteam-Win64-Shipping.exe")
}

address := A_Args.Length >= 1 ? A_Args[1] : "127.0.0.1"
brickadiaExe := A_Args.Length >= 2
  ? A_Args[2]
  : "J:\SteamLibrary\steamapps\common\Brickadia\Brickadia\Binaries\Win64\BrickadiaSteam-Win64-Shipping.exe"

if !ProcessExist("BrickadiaSteam-Win64-Shipping.exe") {
  if !FileExist(brickadiaExe) {
    MsgBox "Brickadia is not running, and the configured executable was not found:`n`n" brickadiaExe
    ExitApp 1
  }

  Run '"' brickadiaExe '"'
}

if !WinWait("ahk_exe BrickadiaSteam-Win64-Shipping.exe", , 30) {
  MsgBox "Timed out waiting for the Brickadia client window."
  ExitApp 1
}

if !FocusBrickadia(3) {
  MsgBox "Could not activate the Brickadia client window."
  ExitApp 1
}

; Use Brickadia's console command path.
Click 1000, 500
Sleep 8
SendEvent "{vkC0sc029 down}"
Sleep 13
SendEvent "{vkC0sc029 up}"
Sleep 175
SendEvent "^a"
Sleep 8
SendEvent "open " address
Sleep 38
DllCall("user32\keybd_event", "UChar", 0x0D, "UChar", 0x1C, "UInt", 0, "UPtr", 0)
Sleep 18
DllCall("user32\keybd_event", "UChar", 0x0D, "UChar", 0x1C, "UInt", 0x2, "UPtr", 0)
