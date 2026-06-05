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

Sleep 300
MouseMove 1800, 650, 0
Sleep 800
Click 1220, 270
Sleep 2500
