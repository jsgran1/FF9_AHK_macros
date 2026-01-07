#SingleInstance Force
SetBatchLines -1
SendMode Input

running := false

; F8 = start
F8::
running := true
while (running) {
    ; Move up
    Send, {Up down}
    Sleep, 50
    Send, {Enter}
    Sleep, 50
    Send, {Enter}
    Sleep, 50
    Send, {Enter}
    Sleep, 50
    Send, {Enter}
    Sleep, 50
    Send, {Enter}
    Sleep, 50
    Send, {Enter}
    Send, {Up up}

    ; Move down
    Send, {Down down}
    Sleep, 50
    Send, {Enter}
    Send, {Down up}
}
return

; F9 = stop
F9::
running := false
return
