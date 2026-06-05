#Requires AutoHotkey v2.0
#SingleInstance Force

SetTitleMatchMode 2
SendMode "Event"
CoordMode "Mouse", "Screen"

if !WinWait("ahk_exe BrickadiaSteam-Win64-Shipping.exe", , 10) {
  ExitApp 1
}

WinActivate "ahk_exe BrickadiaSteam-Win64-Shipping.exe"
if !WinWaitActive("ahk_exe BrickadiaSteam-Win64-Shipping.exe", , 5) {
  ExitApp 1
}

Click 1000, 500
Sleep 500
DllCall("user32\keybd_event", "UChar", 0x70, "UChar", 0x3B, "UInt", 0, "UPtr", 0)
Sleep 120
DllCall("user32\keybd_event", "UChar", 0x70, "UChar", 0x3B, "UInt", 0x2, "UPtr", 0)
Sleep 10000
