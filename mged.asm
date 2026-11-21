;  MGED  -  the built-in text editor of MG.COM, and other rarely used parts:
;           delete, rename, running a .COM so that MG comes back  (MG 1.5)
;
;  Not a program of its own: assembled to run at OVB (the start of MG's
;  list memory) and appended to MG.COM by BUILD.PY. MG reads it from its
;  own file into the list memory when a .TXT / .CFG is opened and no
;  EDITOR is set, so the editor needs no memory while MG shows the list.
;  The symbols of MG come from build/mgsyms.inc (made by BUILD.PY).

include "build/mgsyms.inc"

        org OVB
        jp ed_dos               ; OVB+0: a file of the directory (selname)
        jp ed_zip               ; OVB+3: a file extracted from a ZIP (tmppath)
        dm "MGED"               ; OVB+6: checked by MG before jumping here
        jp ov_del               ; OVB+10: DEL, delete the selection
        jp ov_ren               ; OVB+13: F2, rename it
        jp ov_com               ; OVB+16: run a .COM from MGRUNn.BAT and come back

; ==========================================================================
;  Built-in text editor: .TXT / .CFG when no EDITOR is set in the .CFG
; ==========================================================================
; A window over the list. The text is kept in the list memory as a gap
; buffer: [ED_TXT, ed_gs) is before the cursor, [ed_ge, ed_bend) after it.
; Lines end with LF inside; CR LF and a final ^Z are put back when saving.
; The window is drawn band by band over the list read back from VRAM
; (like the dialogs); typing redraws the cursor row and the title only.
ED_X0:      equ 13
ED_X1:      equ 238
ED_Y0:      equ 18
ED_TX:      equ ED_X0+5          ; text: first pixel column
ED_TY:      equ ED_Y0+19         ;       first pixel row
ED_ROWS:    equ 14
ED_COLS:    equ 36
ED_KY:      equ ED_TY+ED_ROWS*8+2  ; line above the keys (151)
ED_KT:      equ ED_KY+2          ; key caps (153..160)
ED_Y1:      equ ED_KY+14         ; bottom edge (165), shadow to 168
ED_B0:      equ 2                ; bands 2..21
ED_B1:      equ 21
ED_RL:      equ 38               ; ED_LB row: "more" flag, 36 characters, 0
ED_PX0:     equ ED_X1-4-6*11     ; title: "line:column" from here (name before it)
ED_MINGAP:  equ 0x400            ; room kept for typing
KEY_CTLS:   equ 0x13
KEY_INS:    equ 0x12
KEY_DEL:    equ 0x7F
KEY_CLS:    equ 0x0C
KEY_TAB:    equ 0x09

; ---- open --------------------------------------------------------------------------
; a file of the directory (selname)
ed_dos:
        ld hl,(selname)
        ld de,lastname          ; (selected again when the editor closes)
        call strcpy
        ld hl,lastname
        ld de,ED_FILE
        call strcpy
        xor a
        jr ed_open
; a file extracted from the ZIP (tmppath, name in lastname): read only
ed_zip:
        ld hl,tmppath
        ld de,ED_FILE
        call strcpy
        ld a,1
ed_open:
        ld (ed_ro),a
        ld hl,lastname          ; name for the title, at most 20 characters
        ld de,ED_NAME
        call strcpy
        ld hl,ED_NAME
        call strlen
        ld hl,20
        or a
        sbc hl,bc
        jr nc,eo_nm
        ld hl,str_dots
        ld de,ED_NAME+17
        call strcpy
eo_nm:  ld a,1
        ld (listbad),a          ; the list memory holds the text now
        call ed_load
        jr nc,eo_ok
        ld (errmsg),hl
        jp reload_err
eo_ok:  ld hl,0
        ld (ed_line),hl
        ld (ed_top),hl
        ld (ed_col),hl
        ld (ed_want),hl
        ld (ed_hs),hl
        xor a
        ld (ed_mod),a
        inc a
        ld (ed_ins),a
        ld (ed_act),a
        ld (kinact),a
        call titoff             ; the list window loses the focus
        call helpline
        call ed_full
        jp ed_loop

; ED_FILE -> gap buffer. C and HL = message on an error
ed_load:
        ld hl,(TPATOP)
        ld de,0x200             ; stack
        or a
        sbc hl,de
        ld (ed_bend),hl
        ld de,ED_FILE
        ld a,1                  ; read only
        ld c,F_OPEN
        call BDOS
        or a
        ld hl,msg_openerr
        scf
        ret nz
        ld a,b
        ld (ed_fh),a
        ld hl,(ed_bend)         ; read one byte more than fits
        ld de,ED_TXT+ED_MINGAP
        or a
        sbc hl,de
        inc hl
        ld de,ED_TXT
        ld c,F_READ
        call BDOS               ; HL = bytes read
        push hl
        ld a,(ed_fh)
        ld b,a
        ld c,F_CLOSE
        call BDOS
        pop bc                  ; BC = length
        ld hl,(ed_bend)
        ld de,ED_TXT+ED_MINGAP
        or a
        sbc hl,de
        or a
        sbc hl,bc
        ld hl,msg_edbig
        ret c
        ; CR LF -> LF, a lone CR -> LF, stop at ^Z
        xor a
        ld (ed_eofz),a
        ld (ed_crlf),a
        ld (ed_lfonly),a
        ld hl,ED_TXT            ; HL = from, DE = to, BC = bytes left
        ld d,h
        ld e,l
ldx_lp: ld a,b
        or c
        jr z,ldx_end
        ld a,(hl)
        inc hl
        dec bc
        cp 0x1A
        jr z,ldx_eof
        cp 0x0D
        jr nz,ldx_ncr
        ld a,b
        or c
        jr z,ldx_lone
        ld a,(hl)
        cp 0x0A
        jr nz,ldx_lone
        inc hl                  ; CR LF
        dec bc
        ld a,1
        ld (ed_crlf),a
        jr ldx_lf
ldx_lone:
        ld a,0x0A
        jr ldx_put
ldx_ncr:cp 0x0A
        jr nz,ldx_put
        ld a,1
        ld (ed_lfonly),a
ldx_lf: ld a,0x0A
ldx_put:ld (de),a
        inc de
        jr ldx_lp
ldx_eof:ld a,1
        ld (ed_eofz),a
ldx_end:ld a,(ed_lfonly)        ; saved with CR LF unless only LF was seen
        or a
        jr nz,ldx_k
        ld a,1
        ld (ed_crlf),a
ldx_k:  ld hl,ED_TXT            ; cursor at the start: the text to the top
        ld (ed_gs),hl
        ex de,hl
        ld de,ED_TXT
        or a
        sbc hl,de
        ld b,h
        ld c,l                  ; BC = length
        ld hl,(ed_bend)
        or a
        sbc hl,bc
        ld (ed_ge),hl
        ld a,b
        or c
        ret z                   ; (NC) empty
        ld hl,ED_TXT-1
        add hl,bc
        ld de,(ed_bend)
        dec de
        lddr
        or a
        ret

; ---- text helpers --------------------------------------------------------------------
; HL + 1, over the gap (ed_norm: HL at the gap -> after it); A changed
ed_inc: inc hl
ed_norm:ld a,(ed_gs)
        cp l
        ret nz
        ld a,(ed_gs+1)
        cp h
        ret nz
        ld hl,(ed_ge)
        ret
; Z if HL is the end of the text; A changed
ed_end: ld a,(ed_bend)
        cp l
        ret nz
        ld a,(ed_bend+1)
        cp h
        ret
; HL = start of the cursor line (before the gap), BC = column
ed_lstart:
        ld hl,(ed_gs)
        ld bc,0
        ld de,ED_TXT
els_lp: ld a,l
        cp e
        jr nz,els_c
        ld a,h
        cp d
        ret z
els_c:  dec hl
        ld a,(hl)
        cp 0x0A
        jr z,els_lf
        inc bc
        jr els_lp
els_lf: inc hl
        ret
; HL = start of a line before the gap (not the first) -> start of the line above
ed_prevl:
        dec hl                  ; its LF
        ld de,ED_TXT
epl_lp: ld a,l
        cp e
        jr nz,epl_c
        ld a,h
        cp d
        ret z
epl_c:  dec hl
        ld a,(hl)
        cp 0x0A
        jr nz,epl_lp
        inc hl
        ret
; move the gap left / right by BC bytes
ed_gl:  ld a,b
        or c
        ret z
        ld hl,(ed_gs)
        dec hl
        ld de,(ed_ge)
        dec de
        lddr
        inc hl
        ld (ed_gs),hl
        inc de
        ld (ed_ge),de
        ret
ed_gr:  ld a,b
        or c
        ret z
        ld hl,(ed_ge)
        ld de,(ed_gs)
        ldir
        ld (ed_ge),hl
        ld (ed_gs),de
        ret
; C if there is no room for one more character (B kept)
ed_room:ld hl,(ed_ge)
        ld de,(ed_gs)
        or a
        sbc hl,de
        ld de,2
        sbc hl,de
        ret

; ---- rows as shown -------------------------------------------------------------------
; row DE (in ED_LB) from the line at HL: columns ed_hs .. ed_hs+35, "more"
; if it goes on; HL = start of the next line (or the end of the text)
ed_mkline:
        xor a
        ld (de),a
        inc de
        push de
        ld bc,(ed_hs)
ml_skip:ld a,b
        or c
        jr z,ml_show
        call ed_end
        jr z,ml_done
        ld a,(hl)
        cp 0x0A
        jr z,ml_lf
        call ed_inc
        dec bc
        jr ml_skip
ml_show:ld b,ED_COLS
ml_sh:  call ed_end
        jr z,ml_done
        ld a,(hl)
        cp 0x0A
        jr z,ml_lf
        cp 0x20
        jr nc,ml_ch
        ld a,0x20               ; tab and other control characters
ml_ch:  ld (de),a
        inc de
        call ed_inc
        djnz ml_sh
        call ed_end
        jr z,ml_done
        ld a,(hl)
        cp 0x0A
        jr z,ml_lf
        pop bc                  ; more on this line
        push bc
        dec bc
        ld a,1
        ld (bc),a
ml_rest:call ed_inc
        call ed_end
        jr z,ml_done
        ld a,(hl)
        cp 0x0A
        jr nz,ml_rest
ml_lf:  call ed_inc
ml_done:xor a
        ld (de),a
        pop bc
        ret
; A = row -> HL = its place in ED_LB
ed_rowptr:
        ld l,a
        ld h,0
        add hl,hl
        ld d,h
        ld e,l                  ; 2
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl               ; 32
        add hl,de
        add hl,de
        add hl,de               ; 38
        ld de,ED_LB
        add hl,de
        ret
; HL = line -> A = its row in the window, 0xFF if not shown
ed_rowof:
        ld de,(ed_top)
        or a
        sbc hl,de
        ld a,0xFF
        ret c
        inc h
        dec h
        ret nz
        ld a,l
        cp ED_ROWS
        ret c
        ld a,0xFF
        ret

; title text and "line:column"
ed_mktitle:
        ld hl,ED_NAME
        ld de,ED_TBUF
        call strcpy
        ld hl,str_ro
        ld a,(ed_ro)
        or a
        jr nz,emt_s
        ld hl,str_mod
        ld a,(ed_mod)
        or a
        jr nz,emt_s
        ld hl,str_none
emt_s:  call strcpy
        ld hl,(ed_line)
        inc hl
        call ed_num
        ld de,ED_POS
        call strcpy
        ld a,0x3A
        ld (de),a
        inc de
        push de
        ld hl,(ed_col)
        inc hl
        call ed_num
        pop de
        jp strcpy
ed_num: ld (numtmp),hl
        ld hl,0
        ld (numtmp+2),hl
        ld hl,numtmp
        jp u32txt

; ---- drawing ---------------------------------------------------------------------------
; everything: the rows from the top line, then all bands of the window
ed_full:
        call ed_rebuild
        call ed_mktitle
        ld a,ED_B0
efu_b:  push af
        call ed_band
        pop af
        inc a
        cp ED_B1+1
        jr c,efu_b
        ret
; all rows of ED_LB from the top line
ed_rebuild:
        call ed_lstart          ; HL = start of the cursor line
        push hl
        ld hl,(ed_line)
        ld de,(ed_top)
        or a
        sbc hl,de
        ld b,l                  ; lines above it in the window (0..13)
        inc b
        pop hl
        jr efu_n
efu_up: push bc
        call ed_prevl
        pop bc
efu_n:  djnz efu_up
        call ed_norm
        ld de,ED_LB
        ld b,ED_ROWS
efu_r:  push bc
        push de
        call ed_mkline
        pop de
        ex de,hl
        ld bc,ED_RL
        add hl,bc
        ex de,hl
        pop bc
        djnz efu_r
        ret

; bands of row A (if shown)
ed_drawrow:
        cp ED_ROWS
        ret nc
        add a,4                 ; row j is in bands 4+j and 5+j
        push af
        call ed_band
        pop af
        inc a
        jp ed_band

; band A of the window (over what VRAM shows there)
ed_band:
        ld (ed_b),a
        add a,a
        add a,a
        add a,a
        ld (dy0),a
        ld a,(ed_b)
        call bget
        ld a,(ed_b)
        cp ED_B0
        jr nz,ebd_1
        ld de,0x01F5            ; the 2 list rows above the window: blank
        ld hl,0x1011
        ld a,1
        call crect
        ld de,0xF7FE
        ld hl,0x1011
        ld a,1
        call crect
ebd_1:  ld de,ED_X0*256+ED_X1   ; inside
        ld hl,ED_Y0*256+ED_Y1
        ld a,1
        call crect
        ld de,(ED_X1+1)*256+ED_X1+3     ; the corners left by the shadow: blank
        ld hl,ED_Y0*256+ED_Y0+2
        ld a,1
        call crect
        ld de,ED_X0*256+ED_X0+2
        ld hl,(ED_Y1+1)*256+ED_Y1+3
        ld a,1
        call crect
        ld de,(ED_X1+1)*256+ED_X1+3     ; shadow
        ld hl,(ED_Y0+3)*256+ED_Y1+3
        xor a
        call crect
        ld de,(ED_X0+3)*256+ED_X1+3
        ld hl,(ED_Y1+1)*256+ED_Y1+3
        xor a
        call crect
        ld de,ED_X0*256+ED_X0   ; frame
        ld hl,ED_Y0*256+ED_Y1
        xor a
        call crect
        ld de,ED_X1*256+ED_X1
        ld hl,ED_Y0*256+ED_Y1
        xor a
        call crect
        ld de,ED_X0*256+ED_X1
        ld hl,ED_Y1*256+ED_Y1
        xor a
        call crect
        ld de,ED_X0*256+ED_X1   ; line above the keys
        ld hl,ED_KY*256+ED_KY
        xor a
        call crect
        ld a,(ed_b)             ; title bar: bands 2..4
        cp 5
        jr nc,ebd_txt
        ld hl,ED_TBUF
        ld a,ED_X0+6
        ld d,ED_Y0+4
        ld b,30
        call ctext
        ld hl,ED_POS
        ld a,ED_X1-4
        ld d,ED_Y0+4
        call ctextr
        ld de,ED_X0*256+ED_X1
        ld a,(ed_act)
        or a
        jr z,ebd_ina
        ld de,(ED_X0+1)*256+ED_X1-1 ; (inside the frame, which stays black)
        ld hl,ED_Y0*256+ED_Y0+14
        ld a,2
        call crect
        jr ebd_txt
ebd_ina:ld hl,ED_Y0*256+ED_Y0   ; not active: white, lines above and below
        xor a
        call crect
        ld de,ED_X0*256+ED_X1
        ld hl,(ED_Y0+14)*256+ED_Y0+14
        xor a
        call crect
ebd_txt:ld a,(ed_b)             ; text rows b-5 and b-4
        sub 5
        call ed_trow
        ld a,(ed_b)
        sub 4
        call ed_trow
        ld a,(ed_b)             ; key caps: bands 19 and 20
        cp ED_KT>>3
        jr c,ebd_put
        cp ((ED_KT+7)>>3)+1
        jr nc,ebd_put
        ld a,ED_KT
        ld (kc_y),a
        ld a,4
        ld (kc_gap),a
        ld a,(ed_act)
        or a
        ld a,2
        jr nz,ebd_k
        ld a,0xFF
ebd_k:  ld (kc_op),a
        ld hl,edcaps
        ld a,(ed_ro)
        or a
        jr z,ebd_k2
        ld hl,edcaps_ro
ebd_k2: ld a,ED_X0+4
        call capsrow
ebd_put:ld a,(ed_b)
        jp bput

; text row A (ignored if not 0..13), with the "more" mark and the cursor
ed_trow:
        cp ED_ROWS
        ret nc
        ld (ed_j),a
        call ed_rowptr
        ld a,(hl)
        ld (ed_more),a
        inc hl
        ld a,(ed_c0)            ; from column ed_c0 on (0: all)
        ld e,a
        ld d,0
        add hl,de
        ld a,(ed_j)
        add a,a
        add a,a
        add a,a
        add a,ED_TY
        ld (ed_y),a
        ld d,a
        ld a,(ed_c0)
        ld b,a
        add a,a
        add a,b
        add a,a
        add a,ED_TX
        push af
        ld a,ED_COLS
        sub b
        ld b,a
        pop af
        call ctext
        ld a,(ed_more)          ; the line goes on: small arrow on the right
        or a
        jr z,etr_cur
        ld a,(ed_y)
        add a,2
        ld h,a
        add a,2
        ld l,a
        ld de,(ED_X1-3)*256+ED_X1-3
        xor a
        call crect
        ld a,(ed_y)
        add a,3
        ld h,a
        ld l,a
        ld de,(ED_X1-2)*256+ED_X1-2
        xor a
        call crect
etr_cur:ld hl,(ed_line)         ; the cursor on this row?
        call ed_rowof
        ld hl,ed_j
        cp (hl)
        ret nz
        ld hl,(ed_line)
        ld de,(ed_col)
        ld a,(ed_ins)
        call ed_currect
        ret c
        ld a,2
        jp crect

; cursor of line HL, column DE, insert flag A -> rect D..E x H..L, C if not shown
ed_currect:
        ld (ecr_i),a
        push de
        call ed_rowof
        pop de
        cp ED_ROWS
        ccf
        ret c
        ld (ecr_r),a
        ld hl,(ed_hs)
        ex de,hl
        or a
        sbc hl,de
        ret c
        inc h
        dec h
        scf
        ret nz
        ld a,l
        cp ED_COLS
        ccf
        ret c
        ld b,a                  ; x = ED_TX - 1 + 6 * column
        add a,a
        add a,b
        add a,a
        add a,ED_TX-1
        ld d,a
        add a,5
        ld e,a
        ld a,(ecr_r)
        add a,a
        add a,a
        add a,a
        add a,ED_TY
        ld h,a
        add a,7
        ld l,a
        ld a,(ecr_i)
        or a
        ret nz
        ld a,h                  ; overwrite: lower half
        add a,4
        ld h,a
        or a
        ret

; invert the cursor of line HL, column DE, insert flag A on the screen
ed_curxor:
        call ed_currect
        ret c
        ld (ecx_de),de
        ld (ecx_hl),hl
        ld a,h
        rrca
        rrca
        rrca
        and 0x1F
        push af
        call ecx_band
        pop bc
        ld a,(ecx_hl)           ; (L) last row
        rrca
        rrca
        rrca
        and 0x1F
        cp b
        ret z
ecx_band:
        ld (ed_b),a
        add a,a
        add a,a
        add a,a
        ld (dy0),a
        ld a,(ed_b)
        call bget
        ld de,(ecx_de)
        ld hl,(ecx_hl)
        ld a,2
        call crect
        ld a,(ed_b)
        jp bput

; row A again from window column C on (over what VRAM shows)
ed_rowfrom:
        ld (erf_j),a
        ld a,c
        ld (ed_c0),a
        ld a,(erf_j)
        add a,4
        call erf_band
        ld a,(erf_j)
        add a,5
        call erf_band
        xor a
        ld (ed_c0),a
        ret
erf_band:
        ld (ed_b),a
        add a,a
        add a,a
        add a,a
        ld (dy0),a
        ld a,(ed_b)
        call bget
        ld a,(ed_c0)            ; clear the row from that column
        ld b,a
        add a,a
        add a,b
        add a,a
        add a,ED_TX-1
        ld d,a
        ld e,ED_X1-1
        ld a,(erf_j)
        add a,a
        add a,a
        add a,a
        add a,ED_TY
        ld h,a
        add a,7
        ld l,a
        ld a,1
        call crect
        ld a,(erf_j)
        call ed_trow
        ld a,(ed_b)
        jp bput

; "line:column" in the title again (bands 2 and 3, title active)
ed_postitle:
        ld a,ED_B0
        call ept_band
        ld a,ED_B0+1
ept_band:
        ld (ed_b),a
        add a,a
        add a,a
        add a,a
        ld (dy0),a
        ld a,(ed_b)
        call bget
        ld de,ED_PX0*256+ED_X1-1
        ld hl,(ED_Y0+1)*256+ED_Y0+13
        ld a,1
        call crect
        ld hl,ED_POS
        ld a,ED_X1-4
        ld d,ED_Y0+4
        call ctextr
        ld de,ED_PX0*256+ED_X1-1
        ld hl,(ED_Y0+1)*256+ED_Y0+13
        ld a,2
        call crect
        ld a,(ed_b)
        jp bput

; title bar of the list: not active (white with black text, frame kept)
titoff:
        xor a
        call bget
        ld de,0x01FE
        ld hl,0x0007
        ld a,2
        call rect
        ld de,0x00FF
        ld hl,0x0000
        xor a
        call rect
        xor a
        call bput
        ld a,1
        call bget
        ld de,0x01FE
        ld hl,0x0006
        ld a,2
        call rect
        ld de,0x00FF
        ld hl,0x0707
        xor a
        call rect
        ld a,1
        jp bput

; ---- keys ----------------------------------------------------------------------------
; a key, without dropping what was typed ahead
ed_key: ld hl,(GETPNT)
        ld de,(PUTPNT)
        or a
        sbc hl,de
        jr z,ed_key
        ld c,F_DIRIN
        jp BDOS
; Z if SHIFT is held (keyboard matrix row 6, bit 0)
shiftdown:
        di
        in a,(0xAA)
        and 0xF0
        or 6
        out (0xAA),a
        in a,(0xA9)
        ei
        and 0x01
        ret

ed_loop:
        ld hl,(ed_line)
        ld (ed_oline),hl
        ld hl,(ed_col)
        ld (ed_ocol),hl
        ld a,(ed_ins)
        ld (ed_oins),a
        ld a,(ed_mod)
        ld (ed_omod),a
        xor a
        ld (ed_fullf),a
        ld (ed_linef),a
        call ed_key
        cp KEY_ESC
        jp z,ed_esc
        cp KEY_RIGHT
        jp z,ed_right
        cp KEY_LEFT
        jp z,ed_left
        cp KEY_UP
        jp z,ed_up
        cp KEY_DOWN
        jp z,ed_down
        cp KEY_HOME
        jp z,ed_home
        cp KEY_CLS
        jp z,ed_eol
        ld b,a
        ld a,(ed_ro)
        or a
        jr nz,ed_loop           ; read only: no changes
        ld a,b
        cp KEY_CTLS
        jp z,ed_ctls
        cp KEY_INS
        jp z,ed_tins
        cp KEY_RET
        jp z,ed_ret
        cp KEY_BS
        jp z,ed_bs
        cp KEY_DEL
        jp z,ed_del
        cp KEY_TAB
        jr z,ed_char
        cp 0x20
        jr c,ed_loop
; ---- changes ---------------------------------------------------------------------------
ed_char:ld b,a
        ld a,(ed_ins)
        or a
        jr nz,ec_ins
        ld hl,(ed_ge)           ; overwrite: drop the character under the cursor
        call ed_end
        jr z,ec_ins
        ld a,(hl)
        cp 0x0A
        jr z,ec_ins
        inc hl
        ld (ed_ge),hl
ec_ins: call ed_room
        jp c,ed_loop            ; full
        ld hl,(ed_gs)
        ld (hl),b
        inc hl
        ld (ed_gs),hl
        ld hl,(ed_col)
        inc hl
        ld (ed_col),hl
        ld (ed_want),hl
ec_mod: ld a,1
        ld (ed_linef),a
ec_modf:ld a,1
        ld (ed_mod),a
        jp ed_upd
ec_full:ld a,2                   ; lines added / removed: rows from here on
        ld (ed_fullf),a
        jr ec_modf

ed_ret: call ed_room
        jp c,ed_loop
        ld hl,(ed_gs)
        ld (hl),0x0A
        inc hl
        ld (ed_gs),hl
        ld hl,(ed_line)
        inc hl
        ld (ed_line),hl
        ld hl,0
        ld (ed_col),hl
        ld (ed_want),hl
        jr ec_full

ed_bs:  ld hl,(ed_gs)
        ld de,ED_TXT
        or a
        sbc hl,de
        jp z,ed_loop
        ld hl,(ed_gs)
        dec hl
        ld (ed_gs),hl
        ld a,(hl)
        cp 0x0A
        jr z,ebs_nl
        ld hl,(ed_col)
        dec hl
        ld (ed_col),hl
        ld (ed_want),hl
        jr ec_mod
ebs_nl: ld hl,(ed_line)         ; joined with the line above
        dec hl
        ld (ed_line),hl
        call ed_lstart
        ld (ed_col),bc
        ld (ed_want),bc
        jr ec_full

ed_del: ld hl,(ed_ge)
        call ed_end
        jp z,ed_loop
        ld a,(hl)
        inc hl
        ld (ed_ge),hl
        cp 0x0A
        jr z,ec_full
        jp ec_mod

ed_tins:ld a,(ed_ins)
        xor 1
        ld (ed_ins),a
        jp ed_upd

; ---- cursor ---------------------------------------------------------------------------
ed_right:
        ld hl,(ed_ge)
        call ed_end
        jp z,ed_mv
        ld a,(hl)
        push af
        ld bc,1
        call ed_gr
        pop af
        cp 0x0A
        jr z,ert_nl
        ld hl,(ed_col)
        inc hl
        jr elt_c
ert_nl: ld hl,(ed_line)
        inc hl
        ld (ed_line),hl
        ld hl,0
        jr elt_c

ed_left:ld hl,(ed_gs)
        ld de,ED_TXT
        or a
        sbc hl,de
        jp z,ed_mv
        ld bc,1
        call ed_gl
        ld hl,(ed_ge)
        ld a,(hl)
        cp 0x0A
        jr z,elt_nl
        ld hl,(ed_col)
        dec hl
        jr elt_c
elt_nl: ld hl,(ed_line)
        dec hl
        ld (ed_line),hl
        call ed_lstart
        ld h,b
        ld l,c
elt_c:  ld (ed_col),hl
        ld (ed_want),hl
        jp ed_mv

ed_home:ld bc,(ed_col)
        call ed_gl
        ld hl,0
        jr elt_c

ed_eol: ld hl,(ed_ge)           ; CLS (SHIFT+HOME): end of the line
        ld bc,0
eeo_lp: call ed_end
        jr z,eeo_go
        ld a,(hl)
        cp 0x0A
        jr z,eeo_go
        inc hl
        inc bc
        jr eeo_lp
eeo_go: push bc
        call ed_gr
        pop bc
        ld hl,(ed_col)
        add hl,bc
        jr elt_c

ed_up:  call shiftdown
        jr z,ed_pgup
        call ed_up1
        jp ed_mv
ed_down:call shiftdown
        jr z,ed_pgdn
        call ed_dn1
        jp ed_mv

ed_pgup:ld b,ED_ROWS
epu_lp: push bc
        call ed_up1
        pop bc
        jr c,epu_e
        djnz epu_lp
epu_e:  ld a,ED_ROWS            ; the window moves as far as the cursor did
        sub b
        ld e,a
        ld d,0
        ld hl,(ed_top)
        or a
        sbc hl,de
        jr nc,epu_s
        ld hl,0
epu_s:  ld (ed_top),hl
        jr epg_f
ed_pgdn:ld b,ED_ROWS
epd_lp: push bc
        call ed_dn1
        pop bc
        jr c,epd_e
        djnz epd_lp
epd_e:  ld a,ED_ROWS
        sub b
        ld e,a
        ld d,0
        ld hl,(ed_top)
        add hl,de
        ld (ed_top),hl
        ld hl,(ed_ge)           ; keep the window full: lines below the cursor
        ld b,ED_ROWS-1          ; (at most 13)
epd_c:  call ed_end
        jr z,epd_m
        ld a,(hl)
        inc hl
        cp 0x0A
        jr nz,epd_c
        djnz epd_c
epd_m:  ld a,ED_ROWS-1          ; top <= line + below - 13
        sub b
        ld e,a
        ld d,0
        ld hl,(ed_line)
        add hl,de
        ld de,ED_ROWS-1
        or a
        sbc hl,de
        jr nc,epd_t
        ld hl,0
epd_t:  ld de,(ed_top)
        ex de,hl
        or a
        sbc hl,de
        jr c,epg_f
        ld (ed_top),de
epg_f:  ld a,1
        ld (ed_fullf),a
        jp ed_mv

; one line up / down, at the wanted column; C if there is none
ed_up1: ld hl,(ed_line)
        ld a,h
        or l
        scf
        ret z
        call ed_lstart          ; HL = start of this line
        push hl
        call ed_prevl           ; HL = start of the line above
        pop de
        push hl
        ex de,hl
        or a
        sbc hl,de
        dec hl
        ld b,h
        ld c,l                  ; BC = length of the line above
        ld hl,(ed_want)
        or a
        sbc hl,bc
        ld hl,(ed_want)
        jr c,eu1_s
        ld h,b
        ld l,c
eu1_s:  ld (ed_col),hl
        pop de
        add hl,de               ; the new place
        ex de,hl
        ld hl,(ed_gs)
        or a
        sbc hl,de
        ld b,h
        ld c,l
        call ed_gl
        ld hl,(ed_line)
        dec hl
        ld (ed_line),hl
        or a
        ret
ed_dn1: ld hl,(ed_ge)           ; to the end of this line
edn_lp: call ed_end
        scf
        ret z
        ld a,(hl)
        inc hl
        cp 0x0A
        jr nz,edn_lp
        ld bc,0                 ; along the next line up to the wanted column
        ld de,(ed_want)
edn_l2: ld a,b
        cp d
        jr nz,edn_c
        ld a,c
        cp e
        jr z,edn_go
edn_c:  call ed_end
        jr z,edn_go
        ld a,(hl)
        cp 0x0A
        jr z,edn_go
        inc hl
        inc bc
        jr edn_l2
edn_go: ld (ed_col),bc
        ld de,(ed_ge)
        or a
        sbc hl,de
        ld b,h
        ld c,l
        call ed_gr
        ld hl,(ed_line)
        inc hl
        ld (ed_line),hl
        or a
        ret

; ---- after a key: keep the cursor in the window, redraw what changed -----------------------
ed_mv:  di                      ; cursor keys: drop the ones typed while drawing
        ld hl,(PUTPNT)
        ld (GETPNT),hl
        ei
ed_upd: call ed_fit
        ld a,(ed_fullf)
        cp 1
        jr nz,eup_1
        call ed_full            ; the window moved: everything
        jp ed_loop
eup_1:  or a
        jr z,eup_2
        call ed_rebuild         ; lines added / removed: rows from the upper
        ld hl,(ed_oline)        ; of the old and new cursor row on
        call ed_rowof
        push af
        ld hl,(ed_line)
        call ed_rowof
        pop bc
        cp b
        jr c,eup_f
        ld a,b
eup_f:  add a,4
eup_fb: push af
        call ed_band
        pop af
        inc a
        cp 4+ED_ROWS+1
        jr c,eup_fb
        jr eup_t
eup_2:  ld a,(ed_linef)
        or a
        jr z,eup_3
        ld hl,(ed_line)         ; this row changed: build it, draw it from the
        call ed_rowof           ; first column that changed
        call ed_rowptr
        push hl
        call ed_lstart
        call ed_norm
        pop de
        call ed_mkline
        ld hl,(ed_ocol)
        ld de,(ed_col)
        or a
        sbc hl,de
        add hl,de
        jr c,eup_c
        ex de,hl
eup_c:  ld de,(ed_hs)           ; HL = the smaller column
        or a
        sbc hl,de
        ld c,l
        ld hl,(ed_line)
        call ed_rowof
        call ed_rowfrom
        jr eup_t
eup_3:  ld hl,(ed_oline)        ; only the cursor moved
        ld de,(ed_ocol)
        ld a,(ed_oins)
        call ed_curxor
        ld hl,(ed_line)
        ld de,(ed_col)
        ld a,(ed_ins)
        call ed_curxor
eup_t:  call ed_mktitle
        ld a,(ed_omod)
        ld b,a
        ld a,(ed_mod)
        cp b
        jr z,eup_p
        ld a,ED_B0              ; "*" came or went: the whole title
        call ed_band
        ld a,ED_B0+1
        call ed_band
        jp ed_loop
eup_p:  call ed_postitle
        jp ed_loop

; top line and first column so that the cursor is shown (ed_fullf if moved)
ed_fit: ld hl,(ed_line)
        ld de,(ed_top)
        or a
        sbc hl,de
        jr nc,efi_1
        ld hl,(ed_line)         ; above the window
        ld (ed_top),hl
        jr efi_v
efi_1:  ld de,ED_ROWS
        or a
        sbc hl,de
        jr c,efi_h
        ld hl,(ed_line)         ; below it
        ld de,ED_ROWS-1
        or a
        sbc hl,de
        ld (ed_top),hl
efi_v:  ld a,1
        ld (ed_fullf),a
efi_h:  ld hl,(ed_col)
        ld de,(ed_hs)
        or a
        sbc hl,de
        jr nc,efi_h1
        ld hl,(ed_col)          ; left of it: 8 columns of context
        ld de,8
        or a
        sbc hl,de
        jr nc,efi_hs
        ld hl,0
        jr efi_hs
efi_h1: ld de,ED_COLS
        or a
        sbc hl,de
        ret c
        ld hl,(ed_col)          ; right of it
        ld de,ED_COLS-8
        or a
        sbc hl,de
efi_hs: ld (ed_hs),hl
        ld a,1
        ld (ed_fullf),a
        ret

; ---- save / close ------------------------------------------------------------------------
ed_ctls:call ed_save
        jr c,ed_serr
        ld a,1                  ; (a disk error box may have been shown)
        ld (ed_fullf),a
        jp ed_upd
; HL = message: box until a key is pressed
ed_serr:push hl
        xor a
        ld (ed_act),a
        call ed_full
        pop de
        ld hl,ED_NAME
        ld bc,str_anykey
        call dlg_msg
        call ed_key
        ld a,1
        ld (ed_act),a
        call ed_full
        jp ed_loop

ed_esc: ld a,(ed_mod)
        or a
        jr z,ed_close
        xor a                   ; changed: ask
        ld (ed_act),a
        call ed_full
        ld hl,ED_NAME
        ld de,str_savech
        ld bc,yncaps
        call dlg_ask
eq_key: call ed_key
        call toupper
        cp "Y"
        jr z,eq_yes
        cp "N"
        jr z,ed_close
        cp KEY_ESC
        jr nz,eq_key
        ld a,1
        ld (ed_act),a
        call ed_full
        jp ed_loop
eq_yes: call ed_save
        jr c,ed_serr
ed_close:
        xor a
        ld (kinact),a
        jp reload               ; the list again, with the file selected

; ED_FILE <- the text. C and HL = message on an error
ed_save:
        ld de,ED_FILE
        xor a
        ld b,a
        ld c,F_CREATE
        call BDOS
        or a
        ld hl,msg_edsave
        scf
        ret nz
        ld a,b
        ld (ed_fh),a
        ld de,iobuf             ; DE = output (iobuf is page aligned)
        ld hl,ED_TXT
        call ed_norm
esv_lp: call ed_end
        jr z,esv_end
        ld a,(hl)
        push af
        call ed_inc
        pop af
        cp 0x0A
        jr nz,esv_put
        ld a,(ed_crlf)
        or a
        ld a,0x0A
        jr z,esv_put
        ld a,0x0D
        call esv_out
        jr c,esv_fail
        ld a,0x0A
esv_put:call esv_out
        jr nc,esv_lp
        jr esv_fail
esv_end:ld a,(ed_eofz)
        or a
        jr z,esv_fl
        ld a,0x1A
        call esv_out
        jr c,esv_fail
esv_fl: call esv_flush
        jr c,esv_fail
        call esv_close
        xor a
        ld (ed_mod),a
        ld hl,ED_FILE           ; MG's own .CFG: read it again
        call mkfull
        ld hl,pathbuf
        ld de,cfgpath
        call strcmpi
        jr nz,esv_ok
        call loadcfg
        call settmp
esv_ok: or a
        ret
esv_fail:
        call esv_close
        ld hl,msg_wrerr
        scf
        ret
esv_close:
        ld a,(ed_fh)
        ld b,a
        ld c,F_CLOSE
        jp BDOS
; A -> output; written when 256 bytes are there. C on an error (HL kept)
esv_out:ld (de),a
        inc de
        ld a,e
        or a
        ret nz
        push hl
        call esv_flush
        pop hl
        ret
esv_flush:
        ex de,hl
        ld de,iobuf
        or a
        sbc hl,de               ; HL = bytes
        ret z
        push hl
        ld a,(ed_fh)
        ld b,a
        ld c,F_WRITE
        call BDOS
        pop de
        ld b,a
        ld a,h                  ; (HL = bytes written)
        cp d
        jr nz,esf_err
        ld a,l
        cp e
        jr nz,esf_err
        ld a,b
        or a
        jr nz,esf_err
        ld de,iobuf
        ret
esf_err:ld de,iobuf
        scf
        ret



; ==========================================================================
;  DEL: delete the selection (lastname = what to select afterwards)
; ==========================================================================
ov_del: ld hl,str_delt
        ld de,(selname)
        ld bc,yn2caps
        call dlg_ask
odl_k:  call ed_key
        call toupper
        cp "Y"
        jr z,odl_y
        cp "N"
        jr z,odl_n
        cp KEY_ESC
        jr nz,odl_k
odl_n:  ld hl,(selname)         ; not deleted: it stays selected
        ld de,lastname
        call strcpy
        jp reload
odl_y:  ld de,(selname)         ; (an empty directory can be deleted too)
        ld c,F_DELETE
        call BDOS
        or a
        jp z,reload
        ld hl,(selname)
        ld de,lastname
        call strcpy
        ld hl,msg_nodel
        ld (errmsg),hl
        jp reload_err

; ==========================================================================
;  F2: rename the selection, the new name typed in a box
; ==========================================================================
ORN_MAX:    equ 12
ov_ren: ld hl,(selname)
        ld de,orn_buf
        call strcpy
        call orn_show
        ld hl,str_rent
        ld de,orn_txt
        ld bc,okcaps
        call dlg_ask
orn_k:  call ed_key
        cp KEY_ESC
        jp z,orn_no
        cp KEY_RET
        jr z,orn_do
        cp KEY_BS
        jr z,orn_bs
        call toupper            ; (DOS keeps names in capitals)
        cp 0x21
        jr c,orn_k
        cp 0x7F
        jr nc,orn_k
        ld hl,str_badch         ; characters a name cannot have
        ld b,a
orn_ck: ld a,(hl)
        or a
        jr z,orn_add
        cp b
        jr z,orn_k
        inc hl
        jr orn_ck
orn_add:ld a,b
        ld (orn_ch),a
        ld hl,orn_buf
        call strlen             ; (HL at the end)
        ld a,c
        cp ORN_MAX
        jr nc,orn_k
        ld a,(orn_ch)
        ld (hl),a
        inc hl
        ld (hl),0
        jr orn_upd
orn_bs: ld hl,orn_buf
        call strend
        ld de,orn_buf
        or a
        sbc hl,de
        jr z,orn_k
        add hl,de
        dec hl
        ld (hl),0
orn_upd:call orn_show
        ld a,2                  ; the line with the name: bands 2 and 3 of the box
        call dlg_band
        ld a,3
        call dlg_band
        jr orn_k
orn_do: ld a,(orn_buf)
        or a
        jr z,orn_k
        ld hl,(selname)
        ld de,orn_buf
        call strcmp
        jr z,orn_no             ; the same name
        ld de,(selname)
        ld hl,orn_buf
        ld c,F_RENAME
        call BDOS
        or a
        jr nz,orn_err
        ld hl,orn_buf
        ld de,lastname
        call strcpy
        jp reload
orn_no: ld hl,(selname)
        ld de,lastname
        call strcpy
        jp reload
orn_err:ld hl,(selname)
        ld de,lastname
        call strcpy
        ld hl,msg_noren
        ld (errmsg),hl
        jp reload_err
; orn_txt = the name and "_" as the cursor
orn_show:
        ld hl,orn_buf
        ld de,orn_txt
        call strcpy
        ld a,"_"
        ld (de),a
        inc de
        xor a
        ld (de),a
        ret

; ==========================================================================
;  .COM: write MGRUNn.BAT in TMPDIR and let COMMAND2 run it:
;      <the program>
;      <MG.COM> /Rn <the program, or its ZIP> <directory MG was started in>
;  so that MG starts again where it was. MGRUN1 and MGRUN2 are used in
;  turn: the one MG was started from may still be read by COMMAND2.
;  Anything wrong: the program is run directly (rc_direct), as before.
; ==========================================================================
ov_com: ld hl,env_program       ; the path of MG.COM
        ld de,progpath
        ld b,128
        ld c,F_GENV
        call BDOS
        or a
        jp nz,rc_direct
        ld a,(progpath)
        or a
        jp z,rc_direct
        ld hl,(selname)         ; the program (current directory)
        call mkfull
        ld hl,tmpdir            ; TMPDIR\MGRUNn.BAT
        ld de,oc_bat
        call strcpy
        dec de
        ld a,(de)
        inc de
        cp 0x5C
        jr z,oc_sl
        ld a,0x5C
        ld (de),a
        inc de
oc_sl:  ld hl,str_mgrun
        call strcpy
        ld a,(rbatch)
        cp 1
        ld a,"2"
        jr z,oc_n
        ld a,"1"
oc_n:   ld (oc_num),a
        ld (de),a
        inc de
        ld hl,str_batext
        call strcpy
        ld hl,oc_bat            ; it is typed into the keyboard buffer
        call strlen
        ld a,c
        cp 33
        jp nc,rc_direct
        ld de,ED_LB             ; the two lines
        ld hl,pathbuf
        call strcpy
        ld hl,str_crlf
        call strcpy
        ld (oc_l2),de
        ld hl,progpath
        call strcpy
        ld hl,str_rarg
        call strcpy
        ld a,(oc_num)
        ld (de),a
        inc de
        ld a,0x20
        ld (de),a
        inc de
        ld hl,pathbuf
        ld a,(zipmode)
        or a
        jr z,oc_b
        ld hl,zipfile
oc_b:   call strcpy
        ld a,0x20
        ld (de),a
        inc de
        ld a,(origdrv)
        add a,"A"
        ld (de),a
        inc de
        ld a,0x3A
        ld (de),a
        inc de
        ld a,0x5C
        ld (de),a
        inc de
        ld hl,origcwd
        call strcpy
        ex de,hl                ; a command line is at most 127 characters
        ld de,(oc_l2)
        or a
        sbc hl,de
        ld bc,120
        or a
        sbc hl,bc
        jp nc,rc_direct
        add hl,bc
        add hl,de
        ex de,hl
        ld hl,str_crlf
        call strcpy
        ld hl,ED_LB+0           ; bytes
        ex de,hl
        or a
        sbc hl,de
        ld (oc_len),hl
        ld de,oc_bat
        xor a
        ld b,a
        ld c,F_CREATE
        call BDOS
        or a
        jp nz,rc_direct
        ld a,b
        ld (oc_fh),a
        ld de,ED_LB
        ld hl,(oc_len)
        ld c,F_WRITE
        call BDOS
        push af
        ld a,(oc_fh)
        ld b,a
        ld c,F_CLOSE
        call BDOS
        pop af
        or a
        jp nz,rc_direct
        ld hl,oc_bat            ; type its name (as for a .BAT) and end MG
        ld (selname),hl
        jp run_bat

; ---- titles, messages, keys ----------------------------------------------------------
str_delt:    dm "Delete"
             db 0
str_rent:    dm "Rename to"
             db 0
msg_nodel:   dm "Cannot delete it"
             db 0
msg_noren:   dm "Cannot rename it"
             db 0
str_badch:   db 0x22,0x2A,0x2B,0x2C,0x2F,0x3A,0x3B,0x3C,0x3D,0x3E,0x3F,0x5B,0x5D,0x7C,0x5C,0
str_mgrun:   dm "MGRUN"
             db 0
str_batext:  dm ".BAT"
             db 0
str_rarg:    dm " /R"
             db 0
yn2caps:     dm "Y"
             db 0
             dm "Yes"
             db 0
             dm "N"
             db 0
             dm "No"
             db 0,0
okcaps:      dm "RET"
             db 0
             dm "OK"
             db 0
             dm "ESC"
             db 0
             dm "Cancel"
             db 0,0
msg_edbig:   dm "Too big for the editor"
             db 0
msg_edsave:  dm "Cannot create the file"
             db 0
str_savech:  dm "Save the changes?"
             db 0
str_anykey:  dm "Press a key"
             db 0
str_ro:      dm " R/O"
             db 0
str_mod:     dm " *"
             db 0
edcaps:      dm "^S"
             db 0
             dm "Save"
             db 0
             dm "ESC"
             db 0
             dm "Close"
             db 0
             dm "INS"
             db 0
             dm "Insert"
             db 0,0
edcaps_ro:   dm "ESC"
             db 0
             dm "Close"
             db 0,0
yncaps:      dm "Y"
             db 0
             dm "Yes"
             db 0
             dm "N"
             db 0
             dm "No"
             db 0
             dm "ESC"
             db 0
             dm "Back"
             db 0,0

; ---- variables ------------------------------------------------------------------------
ed_gs:       dw 0               ; gap: [ed_gs, ed_ge)
ed_ge:       dw 0
ed_bend:     dw 0               ; end of the text
ed_line:     dw 0               ; cursor line (0 = first)
ed_oline:    dw 0
ed_top:      dw 0               ; first line in the window
ed_col:      dw 0               ; cursor column
ed_want:     dw 0               ; column kept for up / down
ed_hs:       dw 0               ; first column in the window
ed_fh:       db 0
ed_mod:      db 0               ; changed since loaded / saved
ed_ins:      db 0               ; 1 insert, 0 overwrite
ed_ro:       db 0               ; read only (a file from a ZIP)
ed_act:      db 0               ; the window has the focus
ed_crlf:     db 0               ; save line ends as CR LF
ed_lfonly:   db 0
ed_eofz:     db 0               ; ^Z at the end
ed_fullf:    db 0
ed_linef:    db 0
ed_b:        db 0
ed_j:        db 0
ed_y:        db 0
ed_more:     db 0
orn_buf:     ds 16
orn_ch:      db 0
orn_txt:     ds 16
oc_bat:      ds 48
oc_num:      db 0
oc_l2:       dw 0
oc_len:      dw 0
oc_fh:       db 0
ed_ocol:     dw 0
ed_oins:     db 0
ed_omod:     db 0
ed_c0:       db 0
ecr_i:       db 0
ecr_r:       db 0
ecx_de:      dw 0
ecx_hl:      dw 0
erf_j:       db 0
ed_cend:

; ---- buffers after the code (not in the file) --------------------------------------------
ED_LB:       equ (ed_cend+255)&0xFF00  ; 14 rows of ED_RL bytes: the rows as shown
ED_NAME:     equ ED_LB+0x240    ; 64   name in the title
ED_FILE:     equ ED_LB+0x280    ; 128  file loaded / saved
ED_TBUF:     equ ED_LB+0x300    ; 64   title text
ED_POS:      equ ED_LB+0x340    ; 16   "line:column"
ED_TXT:      equ ED_LB+0x400    ; the text, up to the stack
