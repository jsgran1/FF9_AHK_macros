#SingleInstance Force
SetBatchLines -1
SendMode Input

; ----- tuning values -----
baseDelay := 20    ; ms
jitter    := 5     ; ms

running := false
delayStart := false

; F8 = start
F8::
running := true
delayStart := false
while (running) {
    while (delayStart) {
		Sleep, 20000
		delayStart := false
	}
    Send, {Left down}
	Sleep, 30
	Send, {Left up}
    Sleep, 200
    Send, {Right down}
	Sleep, 30
	Send, {Right up}
    Sleep, 200
}
return

; F9 = stop
F9::
running := false
return

Rand(min, max) {
    Random, r, min, max
    return r
}
