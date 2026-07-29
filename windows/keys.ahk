#Requires AutoHotkey v2.0
#SingleInstance Force
; ============================================================
; Windows key remaps — replaces PowerToys Keyboard Manager.
;
; Caps Lock -> Esc is deliberately NOT here: it's a Scancode Map registry
; value written by setup.ps1, so the keyboard driver does it — no process to
; crash, and it works at the login screen too.
;
; setup.ps1 runs this as a logon scheduled task with highest privileges.
; That matters: an unelevated keyboard hook is ignored while an admin window
; has focus, which is the usual reason PowerToys "randomly stops working".
;
; Left-Ctrl-only (<^) where the PowerToys entries said "Ctrl (Left)".
; ============================================================

F3::Send "#{Tab}"            ; Task View
<^Left::Send  "#^{Left}"     ; previous virtual desktop
<^Right::Send "#^{Right}"    ; next virtual desktop
<^q::Send "!{F4}"            ; close app (Cmd+Q muscle memory)

; --- Ctrl+Tab -> Alt+Tab ------------------------------------
; Alt must stay down for as long as Ctrl is held, otherwise this flips to the
; last window instead of opening a switcher you can tab through. Wildcard
; prefix (*) because our own {Alt down} would stop a plain ^Tab from matching.
altHeld := false

*^Tab:: {
    global altHeld
    if !altHeld {
        Send "{Alt down}"
        altHeld := true
        SetTimer ReleaseAlt, 50
    }
    Send GetKeyState("Shift", "P") ? "+{Tab}" : "{Tab}"
}

; ponytail: 50ms poll for the Ctrl release. A ~^Ctrl up:: hotkey would be
; event-driven but fires for chords we don't own; swap it in if 50ms lags.
ReleaseAlt() {
    global altHeld
    if GetKeyState("Ctrl", "P")
        return
    Send "{Alt up}"
    altHeld := false
    SetTimer , 0
}

; If the Alt-Tab switcher never renders (SendInput can outrun the shell on
; some machines), add `SendMode "Event"` above the hotkeys.
