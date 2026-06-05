#Requires AutoHotkey v2.0
#SingleInstance Force

SetTitleMatchMode 2
SendMode "Event"
SetKeyDelay 80, 80
CoordMode "Mouse", "Screen"

target := "ahk_exe BrickadiaSteam-Win64-Shipping.exe"
if !WinWait(target, , 10) {
  ExitApp 1
}

WinActivate target
if !WinWaitActive(target, , 5) {
  ExitApp 1
}

Click 1000, 500
Sleep 500

SendEvent "``"
Sleep 5000
