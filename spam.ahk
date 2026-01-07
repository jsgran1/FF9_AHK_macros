#SingleInstance Force
SetBatchLines -1
SendMode Input

running := false

; F8 = start
F8::
running := true
while (running) {
    Send, {B}
    Sleep, 100
}
return

; F9 = stop
F9::
running := false
return
