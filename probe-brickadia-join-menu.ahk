#Requires AutoHotkey v2.0
#SingleInstance Force

SetTitleMatchMode 2
SendMode "Input"

if !WinWait("ahk_exe BrickadiaSteam-Win64-Shipping.exe", , 10) {
  ExitApp 1
}

WinActivate "ahk_exe BrickadiaSteam-Win64-Shipping.exe"
if !WinWaitActive("ahk_exe BrickadiaSteam-Win64-Shipping.exe", , 5) {
  ExitApp 1
}

Sleep 500
Click 300, 845
Sleep 2500
