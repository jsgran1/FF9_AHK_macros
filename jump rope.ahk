; ==================================================
; FF9 Jump Rope Bot — STABLE + LOGGING + SCALING
; ==================================================

#SingleInstance Force
#NoEnv
SetBatchLines -1
SendMode Input
CoordMode, Pixel, Window

; ---------------- CONFIG ----------------
bubbleColor  := 0xF8E8E0
variation    := 15

; Jump bubble detection
jumpLeft   := 600
jumpTop    := 530
jumpRight  := 625
jumpBottom := 560

; Zidane initiation bubble
initLeft   := 650
initTop    := 515
initRight  := 660
initBottom := 560

pollRate  := 1

earlyGap  := 150      ; jumps < 8
midGap    := 215      ; jumps 8–50
lateGap   := 200      ; jumps > 50

lockoutEarly := 90
lockoutLate  := 70

missTimeout := 1400

restartEnterInterval := 500
restartTimeout       := 20000

; ---------- LEARNING (PHASE 1) ----------
learnWindowSize := 5
attemptHistory := []        ; stores jump counts
prevMedian := ""

; --------------------------------------

toggle := false
running := false

; State machine
STATE_INIT := 1
STATE_ARM := 2
STATE_RHYTHM := 3
STATE_RESTART := 4
state := STATE_INIT

; Runtime vars
jumps := 0
attempt := 0
bestJump := 0
lastJump := 0
lastSeen := 0
bubbleWasVisible := false
restartStart := 0
lastRestartEnter := 0

; Logging
logFile := A_ScriptDir . "\ff9_jump_log.txt"

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
Gosub, StartLog
Gosub, MainLoop
return

; ---------- STOP ----------
F9::
toggle := false
running := false
Gui, Overlay:Hide
Gosub, EndLog
return

; ==================================================
MainLoop:
while (toggle)
{
    attempt++
    jumps := 0
    bubbleWasVisible := false
    state := STATE_INIT

    Gui, Overlay:Show, NoActivate
    GuiControl, Overlay:, JumpText, Initiating...

    ; -------- INIT --------
    Send, {Enter}
    Sleep, 2000
    Send, {Enter}
    Sleep, 2500

    state := STATE_ARM
    GuiControl, Overlay:, JumpText, Waiting...

    Loop
    {
        if (!toggle)
            break

        now := A_TickCount

        ; -------- ARM --------
        if (state = STATE_ARM)
        {
            PixelSearch, x, y, jumpLeft, jumpTop, jumpRight, jumpBottom, bubbleColor, variation, Fast RGB
            bubbleVisible := (ErrorLevel = 0)

            if (bubbleVisible && !bubbleWasVisible)
            {
                SendInput, {Enter}
                jumps := 1
                lastJump := now
                lastSeen := now
                bubbleWasVisible := true
                GuiControl, Overlay:, JumpText, FF9 Jumps: 1
                Sleep, lockoutEarly
                state := STATE_RHYTHM
            }
            else
                bubbleWasVisible := bubbleVisible
        }

        ; -------- RHYTHM --------
        else if (state = STATE_RHYTHM)
        {
            PixelSearch, x, y, jumpLeft, jumpTop, jumpRight, jumpBottom, bubbleColor, variation, Fast RGB
            bubbleVisible := (ErrorLevel = 0)

            if (bubbleVisible && !bubbleWasVisible)
            {
                lastSeen := now

                if (jumps < 8)
                {
                    minGap := earlyGap
                    lockout := lockoutEarly
                }
                else if (jumps <= 50)
                {
                    minGap := midGap
                    lockout := lockoutEarly
                }
                else
                {
                    minGap := lateGap
                    lockout := lockoutLate
                }

                if (now - lastJump >= minGap)
                {
                    SendInput, {Enter}
                    jumps++
                    lastJump := now
                    GuiControl, Overlay:, JumpText, FF9 Jumps: %jumps%
                    Sleep, lockout
                }
            }

            bubbleWasVisible := bubbleVisible

            if (now - lastSeen > missTimeout)
            {
				jumps -= 1 ;remove missed jump
                if (jumps > bestJump)
                    bestJump := jumps

                FormatTime, t,, yyyy-MM-dd HH:mm:ss
                FileAppend, [%t%] Attempt %attempt% — %jumps% jumps (BEST: %bestJump%)`n, %logFile%

				; ---------- LEARNING DATA ----------
				attemptHistory.Push(jumps)

				if (attemptHistory.Length() >= learnWindowSize)
				{
					; Keep window trimmed BEFORE analysis
					while (attemptHistory.Length() > learnWindowSize)
						attemptHistory.RemoveAt(1)

					currMedian := GetMedian(attemptHistory)

					if (prevMedian = "")
					{
						FileAppend, [LEARN] Baseline median established: %currMedian%`n, %logFile%
					}
					else
					{
						if (currMedian > prevMedian + 2)
							FileAppend, [LEARN] Median improved (%prevMedian% → %currMedian%). Consider slightly faster timing`n, %logFile%
						else if (currMedian < prevMedian - 2)
							FileAppend, [LEARN] Median dropped (%prevMedian% → %currMedian%). Consider slightly slower timing`n, %logFile%
						else
							FileAppend, [LEARN] Median stable (%prevMedian% → %currMedian%). No change suggested`n, %logFile%
					}
					prevMedian := currMedian
				}

                GuiControl, Overlay:, JumpText, Missed — Restarting
                state := STATE_RESTART
                restartStart := now
                lastRestartEnter := 0
                Sleep, 5000
            }
        }

        ; -------- RESTART --------
        else if (state = STATE_RESTART)
        {
            if (now - restartStart > restartTimeout)
                break

            if (now - lastRestartEnter >= restartEnterInterval)
            {
                Send, {Enter}
                lastRestartEnter := now
            }

            PixelSearch, x, y, initLeft, initTop, initRight, initBottom, bubbleColor, variation, Fast RGB
            if (ErrorLevel = 0)
            {
                Sleep, 150
                Send, {Enter}
                Sleep, 800
                break
            }
        }

        Sleep, pollRate
    }
}
Gui, Overlay:Hide
running := false
return

GetMedian(arr)
{
    list := ""

    ; Convert array to newline-delimited string
	for k, v in arr
		list .= v . "`n"

	StringTrimRight, list, list, 1  ; remove trailing newline

    ; Numeric sort
    Sort, list, N

    ; Split back into array
    StringSplit, sorted, list, `n
    count := sorted0

    if (count = 0)
        return ""

    if (Mod(count, 2) = 1)
        return sorted[(count + 1) // 2]
    else
        return (sorted[count // 2] + sorted[count // 2 + 1]) / 2
}

StartLog:
	startTime := A_TickCount

	FormatTime, nowTime,, yyyy-MM-dd HH:mm:ss
	FileAppend, `n=========== Session Start: %nowTime% ===========`n, %logFile%
	return

EndLog:
	if (startTime > 0)
	{
		Seconds := Round((A_TickCount - startTime)/1000,2)
		Hours := Floor(Seconds / 3600)
		Minutes := Floor(Mod(Seconds,3600)/60)
		Secs := Round(Mod(Seconds,60),0)
		runDuration := Format("{:02}:{:02}:{:02}", Hours, Minutes, Secs)
		FileAppend,    Runtime: %runDuration%`n, %logFile%
		FileAppend,==========================================================`n, %logFile%
		startTime := 0
	}
	return
