#Requires AutoHotkey v2.0
#SingleInstance Force

SetTitleMatchMode 2
SendMode "Event"
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
Sleep 400

; Try common console-opening keys. Stop manually if one opens the console.
for key in ["{F1}", "{vkC0}", "{SC029}", "{F2}", "{Tab}"] {
  SendEvent key
  Sleep 1200
}

ControlSend "{F1}", , target
Sleep 1200
ControlSend "{vkC0}", , target
Sleep 5000
