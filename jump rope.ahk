; ==================================================
; FF9 Jump Rope Bot — Steam Stable + Attempt Logging
; ==================================================

#SingleInstance Force
#NoEnv
SetBatchLines -1
SendMode Input
CoordMode, Pixel, Window

; ---------------- CONFIG ----------------
bubbleColor  := 0xF8E8E0
variation    := 15

; YOUR detection box
searchLeft   := 600
searchTop    := 530
searchRight  := 625
searchBottom := 560

pollRate     := 2
lockoutMs    := 90

earlyGap     := 180
normalGap    := 240

missTimeout  := 1400
; --------------------------------------

toggle := false
running := false

lastJump := 0
lastSeen := 0
jumps := 0
attempt := 0

bubbleWasVisible := false
armed := false

; ---------------- LOG FILE ----------------
logFile := A_ScriptDir . "\ff9_jump_log.txt"
FormatTime, nowTime,, yyyy-MM-dd HH:mm:ss
FileAppend, `n=== FF9 Jump Rope Session Started: %nowTime% ===`n, %logFile%
; ------------------------------------------

; ---------------- OVERLAY ----------------
Gui, Overlay:New, +AlwaysOnTop -Caption +ToolWindow +E0x20
Gui, Overlay:Color, 000000
Gui, Overlay:Font, s16 cFFFFFF Bold, Arial
Gui, Overlay:Add, Text, vJumpText w260 Center, FF9 Jumps: 0
Gui, Overlay:Show, x20 y20 NoActivate
WinSet, Transparent, 180, FF9 Jumps
Gui, Overlay:Hide
; ----------------------------------------

; ---------- START ----------
F8::
if (running)
    return

toggle := true
running := true
Gosub, StartSequence
return

; ---------- STOP ----------
F9::
toggle := false
running := false
Gui, Overlay:Hide
return

; ==================================================
StartSequence:
while (toggle)
{
    attempt++

    ; ---------- HARD RESET ----------
    jumps := 0
    lastJump := 0
    lastSeen := A_TickCount
    bubbleWasVisible := false
    armed := false

    Gui, Overlay:Show, NoActivate
    GuiControl, Overlay:, JumpText, Initiating...

    ; Initiate rope (you start facing girls)
    Send, {Enter}
    Sleep, 2000
    Send, {Enter}
    Sleep, 2500

    ; Allow characters to settle
    GuiControl, Overlay:, JumpText, Arming...
    Sleep, 500

    armed := true
    GuiControl, Overlay:, JumpText, FF9 Jumps: 0

    ; ---------- MAIN LOOP ----------
    Loop
    {
        if (!toggle)
            break

        now := A_TickCount

        PixelSearch, px, py
            , searchLeft, searchTop
            , searchRight, searchBottom
            , bubbleColor
            , variation
            , Fast RGB

        bubbleVisible := (ErrorLevel = 0)

        ; ---------- JUMP ----------
        if (armed && bubbleVisible && !bubbleWasVisible)
        {
            lastSeen := now
            minGap := (jumps < 8) ? earlyGap : normalGap

            if (now - lastJump >= minGap)
            {
                SendInput, {Enter}
                lastJump := now
                jumps++
                GuiControl, Overlay:, JumpText, FF9 Jumps: %jumps%
                Sleep, lockoutMs
            }
        }

        bubbleWasVisible := bubbleVisible

        ; ---------- MISS ----------
        if (armed && (now - lastSeen > missTimeout))
        {
            FormatTime, endTime,, yyyy-MM-dd HH:mm:ss
            ;FileAppend, [%endTime%] Attempt %attempt% — %jumps% jumps`n, %logFile%

            GuiControl, Overlay:, JumpText, Missed — Resetting
            armed := false
            Sleep, 300

            ; Exit rope / dialogue cleanly
            Send, {Enter}
            Sleep, 300
            Send, {Enter}
            Sleep, 200
            Send, {Enter}
            Sleep, 3000

            break
        }

        Sleep, pollRate
    }
}
Gui, Overlay:Hide
running := false
return
