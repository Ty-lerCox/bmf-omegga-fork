#Requires AutoHotkey v2.0
#SingleInstance Force

SetTitleMatchMode 2
SendMode "Input"
CoordMode "Mouse", "Screen"

if !WinWait("ahk_exe BrickadiaSteam-Win64-Shipping.exe", , 10) {
  ExitApp 1
}

WinActivate "ahk_exe BrickadiaSteam-Win64-Shipping.exe"
if !WinWaitActive("ahk_exe BrickadiaSteam-Win64-Shipping.exe", , 5) {
  ExitApp 1
}

MouseMove 1800, 650, 0
Sleep 500
for point in [[1145, 270], [1195, 270], [1250, 270], [1305, 270], [1220, 252]] {
  Click point[1], point[2]
  Sleep 450
}
Sleep 2000
