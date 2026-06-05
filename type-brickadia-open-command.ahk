#Requires AutoHotkey v2.0
#SingleInstance Force

SetTitleMatchMode 2
SendMode "Event"
SetKeyDelay 80, 80

target := "ahk_exe BrickadiaSteam-Win64-Shipping.exe"
if !WinWait(target, , 10) {
  ExitApp 1
}

WinActivate target
if !WinWaitActive(target, , 5) {
  ExitApp 1
}

Sleep 300
SendEvent "open 127.0.0.1"
Sleep 250
SendEvent "{Enter}"
