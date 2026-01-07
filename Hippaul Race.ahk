#SingleInstance Force
SetBatchLines -1
SendMode Input

; ----- tuning values -----
baseDelay := 19    ; ms
jitter    := 3     ; ms

toggle := false

; F8 = toggle ON / OFF
F8::
toggle := !toggle
while (toggle) {
    Send, c
    Sleep, baseDelay + Rand(0, jitter)
    Send, b
    Sleep, baseDelay + Rand(0, jitter)
}
return

; F9 = hard stop
F9::
toggle := false
return

Rand(min, max) {
    Random, r, min, max
    return r
}
