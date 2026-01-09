; ==================================================
; FF9 Jump Rope Bot — v1.0
; Stable core + logging + overlay + zone monitoring
; + INI persistence: per-zone Gap + per-zone Lockout + JumpKey
; + Auto-adjust when zone fails 3 times in a row within 10 jumps
; ==================================================

#SingleInstance Force
#NoEnv
SetBatchLines -1
SendMode Input
CoordMode, Pixel, Window

; ---------------- CONFIG ----------------
bubbleColor  := 0xF8E8E0
variation    := 15

; Jump bubble detection (YOUR BOX)
jumpLeft   := 550
jumpTop    := 530
jumpRight  := 610
jumpBottom := 575

; Zidane initiation bubble (YOUR BOX)
initLeft   := 650
initTop    := 515
initRight  := 660
initBottom := 560

pollRate := 1

; Base timing defaults (used to seed INI)
earlyGap_default := 150        ; jumps < 8 (irregular start)
gapZ0A_default   := 215        ; Z0A (8–50)
gapZ0B_default   := 200        ; Z0B (51–100)
gapZ_default     := 200        ; Z1+ default

lockEarly_default := 90
lockZ0A_default   := 90
lockZ0B_default   := 70
lockZ_default     := 70

missTimeout := 1400

restartEnterInterval := 500
restartTimeout       := 20000
restartAnimWait      := 5000

; Auto-tune behavior
failStreakNeeded := 3
failWithinJumps  := 10   ; "within 10 jumps"
tuneGapStep      := 1    ; ms
tuneLockStep     := 2    ; ms
minGapClamp      := 80
maxGapClamp      := 350
minLockClamp     := 20
maxLockClamp     := 200

; Files
configFile := A_ScriptDir . "\ff9_jump_config.ini"
logFile := A_ScriptDir . "\ff9_jump_log.txt"
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
startTime := 0

; Input
jumpKey := "{Enter}"   ; loaded from INI, default Enter

; ---------------- ZONES + TUNING ----------------
zoneStats := {}        ; zoneStats["Z0A"] := {pass:0, fail:0}
zoneGap   := {}        ; zoneGap["Z0B"] := 200
zoneLock  := {}        ; zoneLock["Z0B"] := 70

; streak tracking per zone
zoneFailStreak := {}   ; zoneFailStreak["Z0B"] := 0
zoneLastFailJump := {} ; last fail jump count for zone
zoneTuneDir := {}      ; -1 = faster (gap down), +1 = slower (gap up)

InitZones()
LoadConfigFromINI()

; ---------------- OVERLAY ----------------
overlayTitle := "FF9 Jump Rope v1.0"
Gui, Overlay:New, +AlwaysOnTop -Caption +ToolWindow +E0x20 +LastFound
Gui, Overlay:Color, 000000
Gui, Overlay:Font, s14 cFFFFFF Bold, Arial
Gui, Overlay:Add, Text, vJumpText w380 h190 Center, %overlayTitle%
Gui, Overlay:Show, x20 y20 NoActivate, %overlayTitle%
WinSet, Transparent, 180, %overlayTitle%
Gui, Overlay:Hide
; ----------------------------------------

OnExit, HandleExit

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

; ---------- CONFIG HOTKEYS (optional) ----------
; F6 reloads INI values (if you edit INI manually)
F6::
LoadConfigFromINI()
UpdateOverlay("Config reloaded")
return

; Numpad +/- adjust current zone gap (manual tuning still available)
NumpadAdd::AdjustCurrentZoneGap(1)
NumpadSub::AdjustCurrentZoneGap(-1)
+NumpadAdd::AdjustCurrentZoneGap(5)
+NumpadSub::AdjustCurrentZoneGap(-5)

; ==================================================
MainLoop:
while (toggle)
{
    attempt++
    jumps := 0
    bubbleWasVisible := false
    state := STATE_INIT

    Gui, Overlay:Show, NoActivate, %overlayTitle%
    UpdateOverlay("Initiating")

    ; -------- INIT --------
    Send, %jumpKey%
    Sleep, 2000
    Send, %jumpKey%
    Sleep, 2500

    state := STATE_ARM
    UpdateOverlay("Waiting")

    Loop
    {
        if (!toggle)
            break

        now := A_TickCount

        ; -------- ARM --------
        if (state = STATE_ARM)
        {
            DetectJumpBubble(bubbleVisible)

            if (bubbleVisible && !bubbleWasVisible)
            {
                SendInput, %jumpKey%
                jumps := 1
                lastJump := now
                lastSeen := now
                bubbleWasVisible := true

                UpdateOverlay("")
                Sleep, lockEarly_default

                state := STATE_RHYTHM
            }
            else
                bubbleWasVisible := bubbleVisible
        }

        ; -------- RHYTHM --------
        else if (state = STATE_RHYTHM)
        {
            DetectJumpBubble(bubbleVisible)

            if (bubbleVisible && !bubbleWasVisible)
            {
                lastSeen := now

                ; --- choose per-zone gap/lockout ---
                if (jumps < 8)
                {
                    minGap := earlyGap_default
                    lockout := lockEarly_default
                }
                else
                {
                    zid := GetZoneId(jumps)
                    minGap := GetZoneGap(zid)
                    lockout := GetZoneLock(zid)
                }

                if (now - lastJump >= minGap)
                {
                    SendInput, %jumpKey%
                    jumps++
                    lastJump := now

                    HandleZonePass(jumps)
                    UpdateOverlay("")
                    Sleep, lockout
                }
            }

            bubbleWasVisible := bubbleVisible

            ; MISS
            if (now - lastSeen > missTimeout)
            {
                if (jumps > bestJump)
                    bestJump := jumps

                zoneId := GetZoneId(jumps)
                IncrementZoneFail(zoneId)

                ; update streak tracking and maybe auto-tune
                UpdateFailStreakAndMaybeTune(zoneId, jumps)

                LogAttemptFailure(attempt, jumps, zoneId)

                UpdateOverlay("Missed — Restarting")
                state := STATE_RESTART
                restartStart := now
                lastRestartEnter := 0

                Sleep, restartAnimWait
            }
        }

        ; -------- RESTART --------
        else if (state = STATE_RESTART)
        {
            now := A_TickCount

            if (now - restartStart > restartTimeout)
            {
                UpdateOverlay("Restart Timeout")
                break
            }

            if (now - lastRestartEnter >= restartEnterInterval)
            {
                Send, %jumpKey%
                lastRestartEnter := now
            }

            PixelSearch, x, y, initLeft, initTop, initRight, initBottom, bubbleColor, variation, Fast RGB
            if (ErrorLevel = 0)
            {
                Sleep, 150
                Send, %jumpKey%
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

; ==================================================
; ---------------- HELPERS ----------------
; ==================================================

DetectJumpBubble(ByRef visible)
{
    global jumpLeft, jumpTop, jumpRight, jumpBottom, bubbleColor, variation
    PixelSearch, x, y, jumpLeft, jumpTop, jumpRight, jumpBottom, bubbleColor, variation, Fast RGB
    visible := (ErrorLevel = 0)
}

UpdateOverlay(status)
{
    global attempt, jumps, bestJump, zoneStats, zoneGap, zoneLock

    zoneId := GetZoneId(jumps)
    if (!zoneStats.HasKey(zoneId))
        zoneStats[zoneId] := {pass: 0, fail: 0}
    if (!zoneGap.HasKey(zoneId))
        zoneGap[zoneId] := 200
    if (!zoneLock.HasKey(zoneId))
        zoneLock[zoneId] := 70

    zPass := zoneStats[zoneId].pass
    zFail := zoneStats[zoneId].fail
    zGap  := zoneGap[zoneId]
    zLock := zoneLock[zoneId]

    txt := ""
    txt .= "FF9 Jump Rope v1.0`n"
    txt .= "Attempt: " attempt "`n"
    txt .= "Jumps:   " jumps "`n"
    txt .= "Best:    " bestJump "`n"
    txt .= "Zone:    " zoneId " (P:" zPass " F:" zFail ")`n"
    txt .= "Gap/Lock: " zGap " / " zLock " ms"

    if (status != "")
        txt .= "`n" status

    GuiControl, Overlay:, JumpText, %txt%
}

; -------- ZONES --------

InitZones()
{
    global zoneStats, zoneGap, zoneLock, zoneFailStreak, zoneLastFailJump, zoneTuneDir
    global gapZ0A_default, gapZ0B_default, gapZ_default
    global lockZ0A_default, lockZ0B_default, lockZ_default

    zoneStats["Z0A"] := {pass: 0, fail: 0}
    zoneStats["Z0B"] := {pass: 0, fail: 0}

    zoneGap["Z0A"] := gapZ0A_default
    zoneGap["Z0B"] := gapZ0B_default
    zoneLock["Z0A"] := lockZ0A_default
    zoneLock["Z0B"] := lockZ0B_default

    zoneFailStreak["Z0A"] := 0, zoneLastFailJump["Z0A"] := -9999, zoneTuneDir["Z0A"] := -1
    zoneFailStreak["Z0B"] := 0, zoneLastFailJump["Z0B"] := -9999, zoneTuneDir["Z0B"] := -1

    ; Pre-create Z1..Z9
    Loop, 9
    {
        zid := "Z" . A_Index
        zoneStats[zid] := {pass: 0, fail: 0}
        zoneGap[zid] := gapZ_default
        zoneLock[zid] := lockZ_default
        zoneFailStreak[zid] := 0
        zoneLastFailJump[zid] := -9999
        zoneTuneDir[zid] := -1
    }
}

GetZoneId(j)
{
    if (j <= 50)
        return "Z0A"
    else if (j <= 100)
        return "Z0B"
    else
    {
        idx := Floor((j - 101) / 100) + 1
        return "Z" idx
    }
}

HandleZonePass(j)
{
    if (j = 51)
    {
        IncrementZonePass("Z0A")
        LogZonePass("Z0A", j)
        return
    }

    if (j = 101)
    {
        IncrementZonePass("Z0B")
        LogZonePass("Z0B", j)
        return
    }

    if (j > 101)
    {
        if (Mod(j - 1, 100) = 0)
        {
            idx := Floor((j - 101) / 100)
            zid := "Z" idx
            IncrementZonePass(zid)
            LogZonePass(zid, j)
        }
    }
}

IncrementZonePass(zoneId)
{
    global zoneStats
    if (!zoneStats.HasKey(zoneId))
        zoneStats[zoneId] := {pass: 0, fail: 0}
    zoneStats[zoneId].pass++
}

IncrementZoneFail(zoneId)
{
    global zoneStats
    if (!zoneStats.HasKey(zoneId))
        zoneStats[zoneId] := {pass: 0, fail: 0}
    zoneStats[zoneId].fail++
}

GetZoneGap(zoneId)
{
    global zoneGap, gapZ_default
    if (!zoneGap.HasKey(zoneId))
        zoneGap[zoneId] := gapZ_default
    return zoneGap[zoneId]
}

GetZoneLock(zoneId)
{
    global zoneLock, lockZ_default
    if (!zoneLock.HasKey(zoneId))
        zoneLock[zoneId] := lockZ_default
    return zoneLock[zoneId]
}

; -------- CONFIG PERSISTENCE (INI) --------

LoadConfigFromINI()
{
    global configFile, jumpKey
    global zoneGap, zoneLock
    global gapZ0A_default, gapZ0B_default, gapZ_default
    global lockZ0A_default, lockZ0B_default, lockZ_default

    ; Ensure file has at least defaults
    if (!FileExist(configFile))
    {
        IniWrite, {Enter}, %configFile%, Input, JumpKey

        IniWrite, %gapZ0A_default%, %configFile%, Gaps, Z0A
        IniWrite, %gapZ0B_default%, %configFile%, Gaps, Z0B
        IniWrite, %lockZ0A_default%, %configFile%, Lockouts, Z0A
        IniWrite, %lockZ0B_default%, %configFile%, Lockouts, Z0B

        Loop, 9
        {
            zid := "Z" . A_Index
            IniWrite, %gapZ_default%, %configFile%, Gaps, %zid%
            IniWrite, %lockZ_default%, %configFile%, Lockouts, %zid%
        }
    }

    IniRead, jumpKey, %configFile%, Input, JumpKey, {Enter}

    ; Load zones we know
    IniRead, v, %configFile%, Gaps, Z0A, %gapZ0A_default%
    zoneGap["Z0A"] := v
    IniRead, v, %configFile%, Gaps, Z0B, %gapZ0B_default%
    zoneGap["Z0B"] := v

    IniRead, v, %configFile%, Lockouts, Z0A, %lockZ0A_default%
    zoneLock["Z0A"] := v
    IniRead, v, %configFile%, Lockouts, Z0B, %lockZ0B_default%
    zoneLock["Z0B"] := v

    Loop, 9
    {
        zid := "Z" . A_Index
        IniRead, v, %configFile%, Gaps, %zid%, %gapZ_default%
        zoneGap[zid] := v
        IniRead, v, %configFile%, Lockouts, %zid%, %lockZ_default%
        zoneLock[zid] := v
    }
}

SaveZoneGap(zoneId, val)
{
    global configFile, zoneGap
    zoneGap[zoneId] := val
    IniWrite, %val%, %configFile%, Gaps, %zoneId%
}

SaveZoneLock(zoneId, val)
{
    global configFile, zoneLock
    zoneLock[zoneId] := val
    IniWrite, %val%, %configFile%, Lockouts, %zoneId%
}

AdjustCurrentZoneGap(delta)
{
    global jumps, minGapClamp, maxGapClamp
    zoneId := GetZoneId(jumps)
    g := GetZoneGap(zoneId) + delta
    if (g < minGapClamp)
        g := minGapClamp
    if (g > maxGapClamp)
        g := maxGapClamp
    SaveZoneGap(zoneId, g)
    LogTuning("MANUAL", zoneId, "Gap", g, delta)
    UpdateOverlay("Gap " zoneId " = " g)
}

; -------- AUTO-TUNE --------
UpdateFailStreakAndMaybeTune(zoneId, jumpCount)
{
    global zoneFailStreak, zoneLastFailJump, zoneTuneDir
    global failWithinJumps, failStreakNeeded
    global tuneGapStep, tuneLockStep
    global minGapClamp, maxGapClamp, minLockClamp, maxLockClamp

    if (!zoneFailStreak.HasKey(zoneId))
    {
        zoneFailStreak[zoneId] := 0
        zoneLastFailJump[zoneId] := -9999
        zoneTuneDir[zoneId] := -1
    }

    lastJ := zoneLastFailJump[zoneId]

    ; streak counts only if failures are clustered
    if (Abs(jumpCount - lastJ) <= failWithinJumps)
        zoneFailStreak[zoneId]++
    else
        zoneFailStreak[zoneId] := 1

    zoneLastFailJump[zoneId] := jumpCount

    if (zoneFailStreak[zoneId] < failStreakNeeded)
        return

    ; --- Apply tune ---
    ; 1) Reduce lockout slightly first (most common cause of missing edges at higher tempo)
    lock := GetZoneLock(zoneId)
    newLock := lock - tuneLockStep
    if (newLock < minLockClamp)
        newLock := minLockClamp
    if (newLock > maxLockClamp)
        newLock := maxLockClamp

    if (newLock != lock)
    {
        SaveZoneLock(zoneId, newLock)
        LogTuning("AUTO", zoneId, "Lockout", newLock, -tuneLockStep)
    }

    ; 2) Nudge gap in current direction (starts "faster")
    dir := zoneTuneDir[zoneId]  ; -1 faster, +1 slower
    gap := GetZoneGap(zoneId)
    newGap := gap + (dir * tuneGapStep)

    if (newGap < minGapClamp)
        newGap := minGapClamp
    if (newGap > maxGapClamp)
        newGap := maxGapClamp

    if (newGap != gap)
    {
        SaveZoneGap(zoneId, newGap)
        LogTuning("AUTO", zoneId, "Gap", newGap, (dir * tuneGapStep))
    }

    ; flip direction next time (prevents getting stuck pushing only faster when it’s wrong)
    zoneTuneDir[zoneId] := -dir

    ; reset streak so it needs 3 clustered fails again before next adjustment
    zoneFailStreak[zoneId] := 0

    UpdateOverlay("Auto-tune " zoneId ": gap=" newGap " lock=" newLock)
}

; -------- LOGGING --------

StartLog:
startTime := A_TickCount
FormatTime, nowTime,, yyyy-MM-dd HH:mm:ss
FileAppend, `n=========== Session Start (v1.0): %nowTime% ===========`n, %logFile%
FileAppend, Config: %configFile%`n, %logFile%
FileAppend, JumpKey: %jumpKey%`n`n, %logFile%
return

EndLog:
if (startTime > 0)
{
    Seconds := Round((A_TickCount - startTime)/1000,2)
    Hours := Floor(Seconds / 3600)
    Minutes := Floor(Mod(Seconds,3600)/60)
    Secs := Round(Mod(Seconds,60),0)
    runDuration := Format("{:02}:{:02}:{:02}", Hours, Minutes, Secs)

    FileAppend, Runtime: %runDuration%`n, %logFile%
    FileAppend,==========================================================`n, %logFile%
    startTime := 0
}
return

LogAttemptFailure(attemptNum, jumpCount, zoneId)
{
    global logFile, bestJump, jumpKey
    global earlyGap_default, missTimeout
    global restartEnterInterval, restartTimeout, restartAnimWait
    global zoneStats, zoneGap, zoneLock

    FormatTime, t,, yyyy-MM-dd HH:mm:ss

    zPass := zoneStats[zoneId].pass
    zFail := zoneStats[zoneId].fail
    zGap  := GetZoneGap(zoneId)
    zLock := GetZoneLock(zoneId)

    line := ""
    line .= "[" t "] Attempt " attemptNum " — " jumpCount " jumps (BEST: " bestJump ")`n"
    line .= "  FailZone: " zoneId " (P:" zPass " F:" zFail ")`n"
    line .= "  ZoneGap/Lock(ms): " zGap " / " zLock " | earlyGap=" earlyGap_default "`n"
    line .= "  missTimeout=" missTimeout " | JumpKey=" jumpKey "`n"
    line .= "  Restart: enterEvery=" restartEnterInterval " timeout=" restartTimeout " animWait=" restartAnimWait "`n`n"

    FileAppend, %line%, %logFile%
}

LogZonePass(zoneId, atJump)
{
    global logFile, zoneStats
    FormatTime, t,, yyyy-MM-dd HH:mm:ss
    zPass := zoneStats[zoneId].pass
    zFail := zoneStats[zoneId].fail
    line := "[" t "] ZONE PASS: " zoneId " at jump " atJump " (P:" zPass " F:" zFail ")`n"
    FileAppend, %line%, %logFile%
}

LogTuning(kind, zoneId, field, newVal, delta)
{
    global logFile
    FormatTime, t,, yyyy-MM-dd HH:mm:ss
    line := "[" t "] [TUNE-" kind "] " zoneId " " field " => " newVal " (delta " delta ")`n"
    FileAppend, %line%, %logFile%
}

HandleExit:
; Nothing needed—INI writes happen immediately
ExitApp
return
