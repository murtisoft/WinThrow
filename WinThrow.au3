#cs ----------------------------------------------------------------------------

	 AutoIt Version: 3.3.18.0
	 Author:         Claude

	 Script Function:
		A script for throwing windows around.

#ce ----------------------------------------------------------------------------

#include <WinAPI.au3>
#include <WindowsConstants.au3>
#include <Misc.au3>
#include <SendMessage.au3>

Global Const $DROP_SPEED   = 400    ; px/s: below this it's a normal drop, nothing happens
Global Const $MIN_SPEED    = 1500   ; px/s: below this (but above DROP_SPEED) the window falls and minimizes
Global Const $MAX_SPEED    = 6000   ; px/s: cap so a throw stays sane
Global Const $GRAVITY      = 1000    ; px/s^2 while flying to a side/top edge (0 = none)
Global Const $FALL_GRAVITY = 3000   ; px/s^2 when a window drops to be minimized
Global Const $TITLE_H      = 40     ; title bar stays at least this far above the bottom edge

While 1
	If _IsPressed("71") Then ;F2
		While _IsPressed("71")
			Sleep(250)
		WEnd
		Exit
	EndIf
    If _IsPressed("01") Then
        Local $h = _CaptionWindowUnderMouse()
        If $h Then _TrackAndThrow($h)
        While _IsPressed("01")
            Sleep(10)
        WEnd
    EndIf
    Sleep(10)
WEnd

Func _CaptionWindowUnderMouse()
    Local $m = MouseGetPos()
    Local $pt = DllStructCreate("long x;long y")
    DllStructSetData($pt, 1, $m[0])
    DllStructSetData($pt, 2, $m[1])
    Local $hChild = _WinAPI_WindowFromPoint($pt)
    If Not $hChild Then Return 0
    Local $lp = BitOR(BitAND($m[0], 0xFFFF), BitShift(BitAND($m[1], 0xFFFF), -16))
    If _SendMessage($hChild, $WM_NCHITTEST, 0, $lp) <> 2 Then Return 0 ; HTCAPTION
    Return _WinAPI_GetAncestor($hChild, 2)
EndFunc

Func _TrackAndThrow($h)
    Local $s[8][3], $n = 0, $start = WinGetPos($h)
    While _IsPressed("01")
        Local $m = MouseGetPos()
        For $i = 0 To 6
            For $j = 0 To 2
                $s[$i][$j] = $s[$i + 1][$j]
            Next
        Next
        $s[7][0] = $m[0]
        $s[7][1] = $m[1]
        $s[7][2] = TimerInit()
        $n += 1
        Sleep(10)
    WEnd
    If $n < 8 Then Return
    Local $end = WinGetPos($h)
    If Not IsArray($start) Or Not IsArray($end) Then Return
    If $start[0] = $end[0] And $start[1] = $end[1] Then Return ; not dragged

    ; velocity over the last ~70ms (oldest sample is the larger TimerDiff)
    Local $dt = (TimerDiff($s[0][2]) - TimerDiff($s[7][2])) / 1000
    If $dt <= 0.02 Then Return
    Local $vx = ($s[7][0] - $s[0][0]) / $dt
    Local $vy = ($s[7][1] - $s[0][1]) / $dt
    Local $sp = Sqrt($vx ^ 2 + $vy ^ 2)
    If $sp < $DROP_SPEED Then Return ; just placed it, leave it alone

    If $sp > $MAX_SPEED Then
        $vx *= $MAX_SPEED / $sp
        $vy *= $MAX_SPEED / $sp
        $sp = $MAX_SPEED
    EndIf

    ; too weak to reach an edge, or thrown downwards: fall and minimize
    If $sp < $MIN_SPEED Or (Abs($vy) > Abs($vx) And $vy > 0) Then
        _FallAndMinimize($h, $vx, $vy, $end)
        Return
    EndIf

    ; grab point = last cursor position, relative to the window
    Local $offX = $s[7][0] - $end[0]
    Local $offY = $s[7][1] - $end[1]
    _Fly($h, $vx, $vy, $s[7][0], $s[7][1], $offX, $offY)
EndFunc

Func _Fly($h, $vx, $vy, $ax, $ay, $offX, $offY)
    ; 2 = MONITOR_DEFAULTTONEAREST
    Local $mi = _WinAPI_GetMonitorInfo(_WinAPI_MonitorFromWindow($h, 2))
    If Not IsArray($mi) Then Return
    Local $mL = DllStructGetData($mi[1], "Left"), $mR = DllStructGetData($mi[1], "Right")
    Local $mT = DllStructGetData($mi[1], "Top"), $mB = DllStructGetData($mi[1], "Bottom")

    Local $key = ""
    If Abs($vx) >= Abs($vy) Then
        $key = ($vx > 0) ? "#{RIGHT}" : "#{LEFT}"
    ElseIf $vy < 0 Then
        $key = "#{UP}"
    EndIf

    ; $ax/$ay is the grab point. The window follows it, so the rest of the
    ; window may hang off-screen, like a manual drag to the edge.
    Local $tStart = TimerInit(), $last = 0, $wy
    While TimerDiff($tStart) < 1500
        Local $now = TimerDiff($tStart) / 1000, $d = $now - $last
        If $d > 0.03 Then $d = 0.03
        $last = $now
        $ax += $vx * $d
        $ay += $vy * $d
        $vy += $GRAVITY * $d

        ; horizontally the grab point stays on screen
        If $ax < $mL Then $ax = $mL
        If $ax > $mR - 1 Then $ax = $mR - 1

        ; vertically the window top stays between the top edge and the bottom
        ; edge minus the title bar, so the window can never sink out of reach
        $wy = $ay - $offY
        If $wy < $mT Then $wy = $mT
        If $wy > $mB - $TITLE_H Then $wy = $mB - $TITLE_H
        $ay = $wy + $offY

        WinMove($h, "", Round($ax - $offX), Round($wy))

        If $key = "#{LEFT}" And $ax <= $mL Then ExitLoop
        If $key = "#{RIGHT}" And $ax >= $mR - 1 Then ExitLoop
        If $key = "#{UP}" And $wy <= $mT Then ExitLoop
        Sleep(8)
    WEnd

    WinActivate($h)
    If $key <> "" Then Send($key)
EndFunc

Func _FallAndMinimize($h, $vx, $vy, $orig)
    ; only windows that have a minimize button
    Local $r = DllCall("user32.dll", "long", "GetWindowLongW", "hwnd", $h, "int", -16)
    If @error Or Not BitAND($r[0], $WS_MINIMIZEBOX) Then Return

    Local $mi = _WinAPI_GetMonitorInfo(_WinAPI_MonitorFromWindow($h, 2))
    If Not IsArray($mi) Then Return
    Local $mB = DllStructGetData($mi[1], "Bottom")

    Local $x = $orig[0], $y = $orig[1], $w = $orig[2], $hh = $orig[3]
    Local $tStart = TimerInit(), $last = 0
    While TimerDiff($tStart) < 2500
        Local $now = TimerDiff($tStart) / 1000, $d = $now - $last
        If $d > 0.03 Then $d = 0.03
        $last = $now
        $x += $vx * $d
        $y += $vy * $d
        $vy += $FALL_GRAVITY * $d
        WinMove($h, "", Round($x), Round($y))
        If $y >= $mB Then ExitLoop ; fully fallen out of view
        Sleep(8)
    WEnd

    WinSetState($h, "", @SW_MINIMIZE)
    Sleep(50)

    ; make the window come back where it was dropped, not where it fell to
    Local $tWP = DllStructCreate("uint length;uint flags;uint showCmd;long ptMinPosition[2];long ptMaxPosition[2];long rcNormalPosition[4]")
    DllStructSetData($tWP, "length", DllStructGetSize($tWP))
    DllCall("user32.dll", "bool", "GetWindowPlacement", "hwnd", $h, "struct*", $tWP)
    DllStructSetData($tWP, "rcNormalPosition", $orig[0], 1)
    DllStructSetData($tWP, "rcNormalPosition", $orig[1], 2)
    DllStructSetData($tWP, "rcNormalPosition", $orig[0] + $orig[2], 3)
    DllStructSetData($tWP, "rcNormalPosition", $orig[1] + $orig[3], 4)
    DllCall("user32.dll", "bool", "SetWindowPlacement", "hwnd", $h, "struct*", $tWP)
EndFunc
