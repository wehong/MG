; ==========================================================================
;  MG.COM 1.5  -  MSX-DOS2 File Browser & Launcher, SCREEN 2 (graphic) version
;               (same functions as MB.COM, drawn as a 256 x 192 bitmap)
; --------------------------------------------------------------------------
;  * Lists directories / files of the current directory (dirs first, sorted)
;  * UP/DOWN    : move selection        LEFT/RIGHT : page up / page down
;  * RETURN     : directory -> enter it
;                 .COM      -> load & run it (with PROGRAM/PARAMETERS env)
;                 .BAT      -> asks: run it through COMMAND2 (keyboard buffer),
;                              or edit it (like a .TXT)
;                 .ROM      -> run the configured ROM loader with the ROM path
;                 .DSK      -> run the disk image launcher (DSKLDR) with its path
;                 .BAS      -> leave to COMMAND2 typing  BASIC NAME.BAS
;                 .TXT .CFG .INI -> the built-in editor (MGED.ASM, read from the end of
;                              MG.COM), or EDITOR from the .CFG if set
;                 .ZIP      -> browse the archive like a directory (long
;                              names are shown as stored in the archive);
;                              .ROM/.DSK/.COM/.BAS/.TXT/.CFG inside are extracted
;                              (stored or deflate) to TMPDIR and run
;  * BS         : parent directory      HOME : first entry
;  * D          : change drive
;  Memory       : TPA top (0006h) C6F0h or higher, extraction CE00h
;  * F1         : box with the version
;  * ESC        : quit (restore the directory MB was started in)
;  * Q          : quit and stay in the current directory
;
;  Config file  : MG.CFG next to MG.COM (located via the PROGRAM env item)
;      ROMLDR=A:\UTILS\SOFAROM.COM
;      ROMARG=%F
;      DSKLDR=A:\TOOLS\EMUFILE.COM   (optional: launcher for .DSK images)
;      DSKARG=%F                    (its arguments, same % codes as ROMARG)
;      EDITOR=A:\TOOLS\TED.COM      (optional: other editor for .TXT / .CFG)
;      EDITARG=%F                   (its arguments, same % codes as ROMARG)
;      TMPDIR=H:\              (optional, default: the directory of MB.CFG)
;      STARTDIR=A:\GAMES        (optional, directory to start browsing in)
;    ROMARG template: %F = full path of the ROM, %N = file name only, %% = %
;
;  Build        : python3 build.py  (pyz80: mg.asm, then mged.asm with the
;                 symbols of mg.asm; MG.COM = both, the editor at the end)
;  Syntax note  : hex as 0x.., strings via DM, labels with ':' so that the
;                 source assembles unchanged with both assemblers.
;
;  Version      : 1.5  (see CHANGELOG.md)
; ==========================================================================

BDOS:       equ 0x0005
TPATOP:     equ 0x0006

; ---- BDOS function numbers ------------------------------------------------
F_TERM0:    equ 0x00
F_CONOUT:   equ 0x02
F_DIRIN:    equ 0x07
F_STROUT:   equ 0x09
F_SELDSK:   equ 0x0E
F_LOGIN:    equ 0x18
F_CURDRV:   equ 0x19
F_FFIRST:   equ 0x40
F_FNEXT:    equ 0x41
F_OPEN:     equ 0x43
F_CREATE:   equ 0x44
F_CLOSE:    equ 0x45
F_READ:     equ 0x48
F_WRITE:    equ 0x49
F_SEEK:     equ 0x4A
F_DELETE:   equ 0x4D
F_RENAME:   equ 0x4E
F_GETCD:    equ 0x59
F_CHDIR:    equ 0x5A
F_DEFAB:    equ 0x63
F_TERM:     equ 0x62
F_GENV:     equ 0x6B
F_SENV:     equ 0x6C
F_DOSVER:   equ 0x6F

; ---- MSX system area --------------------------------------------------------
LINLEN:     equ 0xF3B0          ; current screen width
CRTCNT:     equ 0xF3B1          ; number of screen lines
PUTPNT:     equ 0xF3F8          ; keyboard buffer write pointer
GETPNT:     equ 0xF3FA          ; keyboard buffer read pointer
KEYBUF:     equ 0xFBF0          ; keyboard buffer (40 bytes)
NAMBAS:     equ 0xF922          ; name table of the current screen
EXPTBL:     equ 0xFCC1          ; slot of the main ROM
RDSLT:      equ 0x000C          ; read a byte from a slot (DOS page 0 entry)
JIFFY:      equ 0xFC9E          ; counts interrupts (50 / 60 per second)
CGPBAS:     equ 0xF924          ; pattern generator table of the current screen
INVOFS:     equ 0x60            ; inverted copy of character c is c + INVOFS
MSGTIME:    equ 120             ; how long a message stays (about 2 s)

; ---- keys -----------------------------------------------------------------
KEY_BS:       equ 0x08
KEY_HOME:     equ 0x0B
KEY_RET:      equ 0x0D
KEY_ESC:      equ 0x1B
KEY_F1:       equ 0x0E          ; what F1 types while MG runs (its FNKSTR entry)
KEY_F2:       equ 0x0F          ; F2 (rename)
KEY_F5:       equ 0x11          ; F5 (version)
KEY_DEL:      equ 0x7F
FNKSTR:       equ 0xF87F        ; function key strings, 10 x 16 bytes
KEY_RIGHT:    equ 0x1C
KEY_LEFT:     equ 0x1D
KEY_UP:       equ 0x1E
KEY_DOWN:     equ 0x1F

; ---- entry types (also the primary sort key) ------------------------------
T_PARENT:   equ 1
T_DIR:      equ 2
T_FILE:     equ 3

; ---- list entry record (24 bytes) ---------------------------------------------
E_TYPE:     equ 0               ; T_PARENT / T_DIR / T_FILE
E_ATTR:     equ 1               ; attributes
E_SIZE:     equ 2               ; size, 32 bit little endian
E_NAMEP:    equ 6               ; pointer to the ASCIIZ name in the name pool
E_ZOFS:     equ 8               ; ZIP: offset of the local header (4 bytes)
E_ZMETH:    equ 12              ; ZIP: compression method (2 bytes)
E_ZFLAG:    equ 14              ; ZIP: general purpose flags (2 bytes)
E_ZCRC:     equ 16              ; ZIP: CRC32 of the contents (4 bytes)
RECSZ:      equ 24

MAXENT:     equ 640             ; entries per directory
NAMECAP:    equ 254             ; longest name kept
POOLSZ:     equ 0x4000          ; name pool
ZBUFSZ:     equ 1024            ; ZIP read buffer
ZDIRMAX:    equ 256             ; longest path inside a ZIP
STUBSPC:    equ 64              ; bytes reserved below TPA top for the loader

        org 0x0100

; ==========================================================================
;  Start-up
; ==========================================================================
start:
        ld c,F_DOSVER
        call BDOS
        ld a,b
        cp 2
        jr nc,dos2ok
        ld de,msg_nodos2
        ld c,F_STROUT
        call BDOS
        jp 0

dos2ok:
        ld hl,(TPATOP)          ; room for the list buffers and the stack?
        ld de,mem_end+0x0300
        or a
        sbc hl,de
        jr nc,mem_ok
        ld de,msg_lowmem
        ld c,F_STROUT
        call BDOS
        jp 0
mem_ok:
        ; remember where we were started
        ld c,F_CURDRV
        call BDOS
        ld (origdrv),a
        ld b,0
        ld de,origcwd
        ld c,F_GETCD
        call BDOS
        call rargs              ; started again from MGRUNn.BAT?

        ; screen geometry
        ld a,(LINLEN)
        cp 20
        jr nc,w_ok
        ld a,40
w_ok:   ld (scrw),a
        ld a,(CRTCNT)
        cp 8
        jr nc,h_ok
        ld a,24
h_ok:   ld (scrh),a

        call findcfg
        call loadcfg
        call settmp
        call gostart

        call ginit              ; SCREEN 2
        ld a,LISTN
        ld (lrows),a

        xor a
        ld (lastname),a
        ld a,(rbatch)           ; back from a program: its directory, selected
        or a
        call nz,rback

; ---- (re)load the directory --------------------------------------------------
reload:
        ld hl,0
        ld (errmsg),hl
reload_err:                     ; (errmsg already set)
        xor a
        ld (listbad),a
        ld a,(zipmode)
        or a
        jr z,rl_dos
        call loadzip
        jr nc,rl_loaded
        ; not a usable ZIP: show the directory again with the ZIP selected
        ld (errmsg),hl
        xor a
        ld (zipmode),a
        ld hl,zipdos
        ld de,lastname
        call strcpy
rl_dos:
        call loaddir
rl_loaded:
        ld hl,0
        ld (sel),hl
        ld (top),hl
        call findlast
        call fixtop
        call updstat0
        ld hl,(errmsg)
        ld a,h
        or l
        jr nz,rl_msg
        ld a,(truncflg)
        or a
        jr z,redraw
        ld hl,msg_trunc
rl_msg: ld (pendmsg),hl
redraw:
        call drawall
        ld hl,(pendmsg)         ; message waiting to be shown
        ld a,h
        or l
        jr z,mainloop
        call msgshow
        ld hl,0
        ld (pendmsg),hl

; ==========================================================================
;  Main loop
; ==========================================================================
mainloop:
        call getkey
        cp KEY_DOWN
        jp z,k_down
        cp KEY_UP
        jp z,k_up
        cp KEY_RIGHT
        jp z,k_pgdn
        cp KEY_LEFT
        jp z,k_pgup
        cp KEY_HOME
        jp z,k_home
        cp KEY_RET
        jp z,k_enter
        cp KEY_BS
        jp z,k_parent
        cp KEY_ESC
        jp z,k_esc
        cp KEY_F1
        jp z,k_help
        cp KEY_F5
        jp z,k_about
        cp KEY_F2
        jp z,k_ren
        cp KEY_DEL
        jp z,k_del
        call toupper
        cp "D"
        jp z,k_drive
        cp "Q"
        jp z,k_quit
        jr mainloop

; ---- F1: box with the version ------------------------------------------------
k_about:
        ld hl,str_about
        ld de,str_ver
        ld bc,str_desc
        call dlg_msg
        call getkey             ; any key closes it (and is not used further)
        call drawlist
        jp mainloop

; ---- back from a program run by MGRUNn.BAT -------------------------------------------
; the command tail is  /Rn <program> <directory MG was started in>
rargs:  ld hl,0x0080
        ld e,(hl)
        ld d,0
        inc hl
        push hl
        add hl,de
        ld (hl),0               ; (ASCIIZ)
        pop hl
        call skipsp
        ld a,(hl)
        cp "/"
        ret nz
        inc hl
        ld a,(hl)
        call toupper
        cp "R"
        ret nz
        inc hl
        ld a,(hl)
        sub "0"
        cp 1
        jr z,ra_n
        cp 2
        ret nz
ra_n:   ld c,a
        inc hl
        call skipsp
        ld de,tailbuf           ; the program
        call ra_word
        call skipsp
        ld de,progpath          ; the start directory
        call ra_word
        ld a,(tailbuf)
        or a
        ret z
        ld a,(progpath+1)
        cp 0x3A
        ret nz
        ld a,c
        ld (rbatch),a
        ld a,(progpath)         ; ESC goes back there, as at the first start
        call toupper
        sub "A"
        ld (origdrv),a
        ld hl,progpath+3
        ld de,origcwd
        jp strcpy
; word at HL -> DE (ASCIIZ), HL after it
ra_word:ld a,(hl)
        or a
        jr z,raw_e
        cp 0x21
        jr c,raw_e
        ld (de),a
        inc hl
        inc de
        jr ra_word
raw_e:  xor a
        ld (de),a
        ret
; directory of the program (tailbuf) current, its name in lastname
rback:  ld hl,tailbuf
        call strend             ; the last backslash
rbk_lp: dec hl
        ld a,(hl)
        cp 0x5C
        jr nz,rbk_lp
        push hl
        inc hl
        ld de,lastname
        call strcpy
        pop hl
        ld de,tailbuf+2         ; "A:\" stays "A:\" (root)
        or a
        sbc hl,de
        add hl,de
        jr nz,rbk_c
        inc hl
rbk_c:  ld (hl),0
        ld hl,tailbuf
        jp godir

; ---- F1: the keys, in a box ------------------------------------------------------------
HLP_X0:     equ 30
HLP_X1:     equ 225
HLP_Y0:     equ 24
HLP_N:      equ 11               ; lines in helptab
HLP_Y1:     equ HLP_Y0+20+HLP_N*10+3
k_help:
        call f1down             ; wait until F1 is released
        jr z,k_help
        ld a,HLP_Y0>>3
khl_b:  push af
        call hlp_band
        pop af
        inc a
        cp ((HLP_Y1+3)>>3)+1
        jr c,khl_b
        call getkey             ; any key closes it (and is not used further)
khl_r:  call f1down
        jr z,khl_r
        call drawall
        jp mainloop
hlp_band:
        ld (dlg_b),a
        add a,a
        add a,a
        add a,a
        ld (dy0),a
        ld a,(dlg_b)
        call bget
        ld de,HLP_X0*256+HLP_X1         ; inside
        ld hl,HLP_Y0*256+HLP_Y1
        ld a,1
        call crect
        ld de,(HLP_X1+1)*256+HLP_X1+3   ; shadow
        ld hl,(HLP_Y0+3)*256+HLP_Y1+3
        xor a
        call crect
        ld de,(HLP_X0+3)*256+HLP_X1+3
        ld hl,(HLP_Y1+1)*256+HLP_Y1+3
        xor a
        call crect
        ld hl,str_keys                  ; title bar
        ld a,HLP_X0+6
        ld d,HLP_Y0+4
        ld b,30
        call ctext
        ld de,HLP_X0*256+HLP_X1
        ld hl,HLP_Y0*256+HLP_Y0+14
        ld a,2
        call crect
        ld de,HLP_X0*256+HLP_X0         ; sides and bottom edge
        ld hl,(HLP_Y0+15)*256+HLP_Y1
        xor a
        call crect
        ld de,HLP_X1*256+HLP_X1
        ld hl,(HLP_Y0+15)*256+HLP_Y1
        xor a
        call crect
        ld de,HLP_X0*256+HLP_X1
        ld hl,HLP_Y1*256+HLP_Y1
        xor a
        call crect
        ld hl,helptab                   ; key (as a cap) and what it does
        ld a,HLP_Y0+20
hb_lp:  ld (hb_y),a
        ld (hb_p),hl
        ld a,(hl)
        or a
        jr z,hb_put
        call strlen                     ; C = length of the key
        ld a,c
        add a,a
        add a,c
        add a,a
        add a,HLP_X0+10-1
        ld (hb_x1),a                    ; cap: x0+8 .. x0+10+6*len-1
        ld hl,(hb_p)
        ld b,c
        ld a,(hb_y)
        ld d,a
        ld a,HLP_X0+10
        call ctext
        ld a,(hb_x1)
        ld e,a
        ld d,HLP_X0+8
        ld a,(hb_y)
        ld h,a
        add a,7
        ld l,a
        ld a,2
        call crect
        ld hl,(hb_p)                    ; (ctext does not move HL outside the band)
        call strend
        inc hl
        ld (hb_p),hl
        ld a,(hb_y)
        ld d,a
        ld a,HLP_X0+80
        ld b,255
        call ctext
        ld hl,(hb_p)
        call strend
        inc hl
        ld a,(hb_y)
        add a,10
        jr hb_lp
hb_put: ld a,(dlg_b)
        jp bput

; ---- RETURN on a .BAT: run it or edit it? ---------------------------------------------
k_bat:  ld hl,(selname)
        ld de,str_batq
        ld bc,recaps
        call dlg_ask
kbt_k:  call getkey
        call toupper
        cp "R"
        jp z,run_bat
        cp "E"
        jp z,run_txt
        cp KEY_ESC
        jr nz,kbt_k
        call drawlist
        jp mainloop

; ---- DEL / F2: delete / rename the selection (in the overlay, see mged.asm) ------------------
k_del:  call kdr_ok
        ld hl,(sel)             ; selected afterwards: the next entry, else the one before
        inc hl
        ld de,(count)
        or a
        sbc hl,de
        add hl,de
        jr c,kdl_n
        dec hl
        ld a,h
        or l
        jr z,kdl_0
        dec hl
kdl_n:  call getent
        call entname
        ld de,lastname
        call strcpy
        ld a,10
        jp edl_go
kdl_0:  xor a
        ld (lastname),a
        ld a,10
        jp edl_go
k_ren:  call kdr_ok
        ld a,13
        jp edl_go
; not in a ZIP, not ".." (returns to the main loop if so)
kdr_ok: ld a,(zipmode)
        or a
        jr nz,kdr_zip
        ld hl,(count)
        ld a,h
        or l
        jr z,kdr_no
        ld hl,(sel)
        call getent
        ld a,(hl)
        cp T_PARENT
        jr z,kdr_no
        call entname            ; selname = the selection
        ld (selname),hl
        ret
kdr_no: pop hl
        jp mainloop
kdr_zip:pop hl
        ld hl,msg_inzip
        jp status_loop

; Z if HL is MB.COM or MG.COM (these are not run from here)
isself: push hl
        ld de,str_mbcom
        call strcmpi
        pop hl
        ret z
        ld de,str_mgcom
        jp strcmpi

; ---- cursor movement ------------------------------------------------------
k_down:
        ld hl,(sel)
        inc hl
        ld de,(count)
        or a
        sbc hl,de
        jp nc,mainloop          ; already last
        add hl,de
        jr setsel

k_up:
        ld hl,(sel)
        ld a,h
        or l
        jp z,mainloop
        dec hl
        jr setsel

k_home:
        ld hl,0
        jr setsel

k_pgdn:
        ld hl,(count)
        ld a,h
        or l
        jp z,mainloop
        dec hl
        ex de,hl                ; DE = last index
        ld hl,(sel)
        ld a,(lrows)
        ld c,a
        ld b,0
        add hl,bc
        push hl
        or a
        sbc hl,de
        pop hl
        jr c,setsel
        ex de,hl
        jr setsel

k_pgup:
        ld hl,(sel)
        ld a,(lrows)
        ld c,a
        ld b,0
        or a
        sbc hl,bc
        jr nc,setsel
        ld hl,0
        jr setsel

; HL = new selection index
setsel:
        ld de,(sel)
        ld (oldsel),de
        ld (sel),hl
        ld hl,(top)
        push hl
        call fixtop
        pop de
        ld hl,(top)
        or a
        sbc hl,de
        jr nz,ss_full
        ld hl,(oldsel)
        call drawline
        ld hl,(sel)
        call drawline
        jr ss_stat
ss_full:
        call drawlist
ss_stat:
        call updstat0           ; details of the new selection
        call drawstat
        jp mainloop

; ---- RETURN -----------------------------------------------------------------
k_enter:
        ld hl,(count)
        ld a,h
        or l
        jp z,mainloop
        ld hl,(sel)
        call getent             ; HL = record
        ld a,(hl)
        push af
        call entname
        ld (selname),hl
        pop af
        cp T_PARENT
        jp z,k_parent
        cp T_DIR
        jr nz,ke_file
        ld a,(zipmode)
        or a
        jr nz,ke_zipdir
        ex de,hl                ; DE = directory name
        ld c,F_CHDIR
        call BDOS
        or a
        jr nz,ke_err
        xor a
        ld (lastname),a
        jp reload
ke_err:
        ld hl,msg_cderr
        jp status_loop

ke_zipdir:
        ; zipdir = zipdir + name + "/"
        ld hl,zipdir
        call strlen
        push bc
        ld hl,(selname)
        call strlen
        pop hl
        add hl,bc
        ld de,ZDIRMAX-2
        or a
        sbc hl,de
        jr nc,ke_deep
        ld hl,zipdir
        call strend
        ex de,hl
        ld hl,(selname)
        call strcpy
        ld a,"/"
        ld (de),a
        inc de
        xor a
        ld (de),a
        ld (lastname),a
        jp reload
ke_deep:
        ld hl,msg_deep
        jp status_loop

ke_file:
        ld a,(zipmode)
        or a
        jp nz,ke_zipfile
ke_dosfile:
        ld hl,(selname)
        call getext             ; A = 1 COM / 2 BAT / 3 ROM / 4 ZIP / 5 DSK / 6 BAS / 7 TXT / 8 CFG / 9 INI
        cp 1
        jp z,k_com
        cp 2
        jp z,k_bat
        cp 3
        jp z,run_rom
        cp 4
        jp z,run_zip
        cp 5
        jp z,run_dsk
        cp 6
        jp z,run_bas
        cp 7
        jp z,run_txt
        cp 8
        jp z,run_txt
        cp 9
        jp z,run_txt
        ld hl,msg_notexe
        jp status_loop

; ---- BS : parent directory ------------------------------------------------------
k_parent:
        ld a,(zipmode)
        or a
        jr nz,kp_zip
        ld a,(cwdbuf)
        or a
        jp z,mainloop           ; already at root
        ; lastname = last component of cwdbuf
        ld hl,cwdbuf
        ld de,cwdbuf
kp_scan:
        ld a,(hl)
        or a
        jr z,kp_found
        inc hl
        cp 0x5C
        jr nz,kp_scan
        ld d,h
        ld e,l
        jr kp_scan
kp_found:
        ex de,hl
        ld de,lastname
        call strcpy
        ld de,str_dotdot
        ld c,F_CHDIR
        call BDOS
        jp reload

kp_zip:
        ld a,(zipdir)
        or a
        jr nz,kp_zsub
        ; at the top of the ZIP: leave it, select the ZIP file
        xor a
        ld (zipmode),a
        ld hl,zipdos
        ld de,lastname
        call strcpy
        jp reload
kp_zsub:
        ; "A/B/C/" -> lastname = "C", zipdir = "A/B/"
        ld hl,zipdir
        call strend
        dec hl
        ld (hl),0
        ld hl,zipdir
        ld de,zipdir
kpz_scan:
        ld a,(hl)
        or a
        jr z,kpz_found
        inc hl
        cp "/"
        jr nz,kpz_scan
        ld d,h
        ld e,l
        jr kpz_scan
kpz_found:
        push de
        ex de,hl
        ld de,lastname
        call strcpy
        pop hl
        ld (hl),0
        jp reload

; ---- D : change drive -----------------------------------------------------------
k_drive:
        ld hl,msg_drive
        call msgprompt
        call getkey
        call toupper
        sub "A"
        jr c,kd_bad
        cp 8
        jr nc,kd_bad
        ld b,a
        push bc
        ld c,F_LOGIN
        call BDOS               ; HL = login vector
        pop bc
        push bc
        inc b
kd_shift:
        dec b
        jr z,kd_test
        srl h
        rr l
        jr kd_shift
kd_test:
        pop bc
        bit 0,l
        jr z,kd_bad
        ld e,b
        ld c,F_SELDSK
        call BDOS
        xor a
        ld (lastname),a
        ld (zipmode),a
        jp reload
kd_bad:
        ld hl,msg_baddrv
        jp status_loop

; ---- ESC / Q : quit ---------------------------------------------------------------
k_esc:
        ; restore the start drive and directory
        ld a,(origdrv)
        ld e,a
        ld c,F_SELDSK
        call BDOS
        ld hl,pathbuf
        ld a,(origdrv)
        add a,"A"
        ld (hl),a
        inc hl
        ld (hl),0x3A
        inc hl
        ld (hl),0x5C
        inc hl
        ex de,hl
        ld hl,origcwd
        call strcpy
        ld de,pathbuf
        ld c,F_CHDIR
        call BDOS
k_quit:
        call scrreset
        ld c,F_TERM0
        jp BDOS

; show a message in the status line and go back to the main loop
status_loop:
        ld a,(listbad)
        or a
        jr nz,sl_reload
        call msgshow
        jp mainloop
sl_reload:                      ; the list was overwritten by an extraction
        ld (errmsg),hl
        call gozipdir
        jp reload_err

; ==========================================================================
;  Launchers
; ==========================================================================

; ---- .ZIP : browse the archive like a directory ----------------------------------
run_zip:
        ld hl,(selname)
        call mkfull
        ld hl,pathbuf
        ld de,zipfile
        call strcpy
        ld hl,(selname)
        ld de,zipdos
        call strcpy
        xor a
        ld (zipdir),a
        ld (lastname),a
        inc a
        ld (zipmode),a
        jp reload

; ---- RETURN on a file inside a ZIP: extract it, then run it --------------------
ke_zipfile:
        ld hl,(selname)
        call getext
        ld (xtype),a
        cp 1
        jr z,kz_com
        cp 3
        jr z,kz_rom
        cp 5
        jr z,kz_dsk
        cp 6
        jr z,kz_ok
        cp 7
        jr z,kz_txt
        cp 8
        jr z,kz_txt
        cp 9
        jr z,kz_txt
        ld hl,msg_zipexe
        jp status_loop
kz_txt: jr kz_ok                 ; (EDITOR, or the built-in viewer)
kz_com: ld hl,(selname)
        call isself
        ld hl,msg_self
        jp z,status_loop
        jr kz_ok
kz_dsk: ld a,(dskpath)
        or a
        jr nz,kz_ok
        ld hl,msg_nodsk
        jp status_loop
kz_rom:
        ld a,(ldrpath)
        or a
        jr nz,kz_ok
        ld hl,msg_noldr
        jp status_loop
kz_ok:
        ld hl,(sel)
        call getent             ; copy what extract needs out of the list
        push hl
        ld de,E_SIZE
        add hl,de
        ld de,xsize
        ld bc,4
        ldir
        pop hl
        ld de,E_ZOFS
        add hl,de
        ld de,xofs
        ld bc,4
        ldir
        ld de,xmeth
        ld bc,2
        ldir
        ld de,xflags
        ld bc,2
        ldir
        ld de,xcrc
        ld bc,4
        ldir
        ld hl,(selname)         ; select this entry again after a failure
        ld de,lastname
        call strcpy
        call mktmp
        ld a,1
        ld (listbad),a          ; the list memory is used by inflate
        call cachechk           ; already extracted earlier?
        jr nc,kz_cached
        call prog_init
        call extract
        jr nc,kz_go
        ld (errmsg),hl
        jp reload_err
kz_cached:
        ld de,statbuf
        ld hl,str_reuse
        call strcpy
        ld hl,tmppath
        call strcpy
        ld hl,statbuf
        call msgshow
kz_go:
        ld a,(xtype)            ; .TXT / .CFG without EDITOR: view it here
        cp 7
        jr c,kz_go2
        ld a,(edpath)
        or a
        jp z,edl_zip
kz_go2: ld hl,tmpdir
        call godir              ; the extracted file's directory is current
        ld hl,tmpname
        ld (selname),hl
        ld a,(xtype)
        cp 1
        jp z,run_com
        cp 5
        jp z,run_dsk
        cp 6
        jp z,run_bas
        cp 7
        jp nc,run_txt
        jp run_rom

; tmpname = CRC32 of the entry in hex + .ROM/.COM/.DSK/.BAS/.TXT/.CFG, tmppath = tmpdir\tmpname
mktmp:
        ld hl,tmpdir
        ld de,tmppath
        call strcpy
        dec de
        ld a,(de)
        inc de
        cp 0x5C
        jr z,mt_sl
        ld a,0x5C
        ld (de),a
        inc de
mt_sl:
        push de
        ld de,tmpname           ; name = CRC32 as 8 hex digits
        ld hl,xcrc+3
        ld b,4
mt_hx:  ld a,(hl)
        call puthex
        dec hl
        djnz mt_hx
        ld a,"."
        ld (de),a
        inc de
        ld a,(xtype)
        cp 1
        ld hl,ext_com
        jr z,mt_e2
        cp 5
        ld hl,ext_dsk
        jr z,mt_e2
        cp 6
        ld hl,ext_bas
        jr z,mt_e2
        cp 7
        ld hl,ext_txt
        jr z,mt_e2
        cp 8
        ld hl,ext_cfg
        jr z,mt_e2
        cp 9
        ld hl,ext_ini
        jr z,mt_e2
        ld hl,ext_rom
mt_e2:  call strcpy
        pop de
        ld hl,tmpname
        jp strcpy

; A -> two hex digits at DE
puthex:
        push af
        rrca
        rrca
        rrca
        rrca
        call hexdig
        pop af
hexdig: and 0x0F
        add a,"0"
        cp "9"+1
        jr c,hd_put
        add a,7
hd_put: ld (de),a
        inc de
        ret

; Carry clear if tmppath already exists with the size of the entry, so it
; can be used instead of extracting again (the name is the CRC32).
cachechk:
        ld de,tmppath
        ld a,1
        ld c,F_OPEN
        call BDOS
        or a
        jr nz,cc_no
        ld a,b
        ld (chandle),a
        ld de,0
        ld hl,0
        ld a,2
        ld c,F_SEEK
        call BDOS               ; DE:HL = file size
        ld c,a
        xor a
        ld (ccok),a
        ld a,c
        or a
        jr nz,cc_close
        push de
        ld de,(xsize)
        or a
        sbc hl,de
        pop hl
        jr nz,cc_close
        ld de,(xsize+2)
        or a
        sbc hl,de
        jr nz,cc_close
        ld a,1
        ld (ccok),a
cc_close:
        ld a,(chandle)
        ld b,a
        ld c,F_CLOSE
        call BDOS
        ld a,(ccok)
        or a
        ret nz
cc_no:  scf
        ret

; HL = "X:\path": make X: the current drive and path its current directory
godir:
        push hl
        inc hl
        ld a,(hl)
        dec hl
        cp 0x3A
        jr nz,gd_nodrv
        ld a,(hl)
        call toupper
        sub "A"
        ld e,a
        ld c,F_SELDSK
        call BDOS
gd_nodrv:
        pop de
        ld c,F_CHDIR
        call BDOS
        ld b,0
        ld de,cwdbuf
        ld c,F_GETCD
        jp BDOS

; back to the directory that holds the ZIP
gozipdir:
        ld hl,zipfile
        ld de,pathbuf
        call pathdir
        ld hl,pathbuf
        jp godir

; copy path HL to DE without its last component ("A:\X\Y" -> "A:\X",
; "A:\Y" -> "A:\")
pathdir:
        push de
        call strcpy
        pop hl
        push hl
        ld de,0
pd_s:   ld a,(hl)
        or a
        jr z,pd_e
        cp 0x5C
        jr nz,pd_n
        ld d,h
        ld e,l
pd_n:   inc hl
        jr pd_s
pd_e:   pop hl
        ld a,d
        or e
        ret z
        inc hl
        inc hl
        or a
        sbc hl,de
        ex de,hl
        jr nz,pd_cut
        inc hl
pd_cut: ld (hl),0
        ret

; STARTDIR from MB.CFG: start browsing there (ESC still returns to the
; directory MB was started in)
gostart:
        ld a,(startcfg)
        or a
        ret z
        ld a,(startcfg+1)
        cp 0x3A
        jr nz,gs_dir
        ld a,(startcfg)
        call toupper
        sub "A"
        cp 8
        jr nc,gs_bad
        ld e,a
        ld c,F_SELDSK
        call BDOS
gs_dir: ld de,startcfg
        ld c,F_CHDIR
        call BDOS
        or a
        ret z
gs_bad: ld a,(origdrv)          ; not found: stay where we are
        ld e,a
        ld c,F_SELDSK
        call BDOS
        ld hl,msg_nostart
        ld (pendmsg),hl
        ret

; tmpdir = TMPDIR from MB.CFG, or the directory of MB.CFG
settmp:
        ld hl,tmpcfg
        ld a,(hl)
        or a
        jr nz,stt_cfg
        ld hl,cfgpath
        ld de,tmpdir
        jp pathdir
stt_cfg:
        ld de,tmpdir
        call strcpy
        ; drop a trailing '\' unless it is "X:\"
        ld hl,tmpdir
        call strlen
        ld a,c
        cp 4
        ret c
        ld hl,tmpdir-1
        add hl,bc
        ld a,(hl)
        cp 0x5C
        ret nz
        ld (hl),0
        ret

; ---- .COM : load directly ------------------------------------------------------
k_com:  ld hl,(selname)
        call isself
        ld hl,msg_self
        jp z,status_loop
; run it from MGRUNn.BAT, which starts MG again afterwards (in the overlay);
; directly if that is not possible
run_com:
        call edl_load
        jp nc,OVB+16
rc_direct:
        ld hl,(selname)
        call mkfull             ; pathbuf = full path
        ld hl,pathbuf
        ld de,progpath
        ld bc,128
        ldir
        xor a
        ld (tailbuf),a          ; no parameters
        jp execprog

; ---- .ROM : run the configured loader ------------------------------------------
run_rom:
        ld hl,ldrpath
        ld de,ldrargs
        ld bc,msg_noldr
        jr run_ldr
; ---- .DSK : run the disk image launcher (DSKLDR / DSKARG in the .CFG) ------------
run_dsk:
        ld hl,dskpath
        ld de,dskargs
        ld bc,msg_nodsk
        jr run_ldr
; ---- .TXT / .CFG : open in the text editor (EDITOR / EDITARG in the .CFG) ------------
run_txt:
        ld a,(edpath)           ; no EDITOR in the .CFG: the built-in one
        or a
        jp z,edl_dos
        ld hl,edpath
        ld de,edargs
        ld bc,msg_notexe        ; (not used: EDITOR is set here)
; HL = launcher path, DE = argument template, BC = message if not set
run_ldr:
        ld a,(hl)
        or a
        jr nz,rr_ok
        ld h,b
        ld l,c
        jp status_loop
rr_ok:
        ld (rr_ldr),hl
        push de
        ld hl,(selname)
        call mkfull             ; pathbuf = full path of the file
        pop hl                  ; expand the argument template into tailbuf
        ld de,tailbuf
        ld b,125                ; room left
rr_loop:
        ld a,(hl)
        inc hl
        or a
        jr z,rr_end
        cp "%"
        jr nz,rr_put
        ld a,(hl)
        inc hl
        call toupper
        cp "F"
        jr z,rr_full
        cp "N"
        jr z,rr_name
        cp "%"
        jr z,rr_put
        or a
        jr z,rr_end
        jr rr_loop              ; unknown %x : drop
rr_full:
        push hl
        ld hl,pathbuf
        call rr_cat
        pop hl
        jr rr_loop
rr_name:
        push hl
        ld hl,(selname)
        call rr_cat
        pop hl
        jr rr_loop
rr_put:
        call rr_char
        jr rr_loop
rr_end:
        xor a
        ld (de),a
        ld hl,(rr_ldr)
        ld de,progpath
        ld bc,80
        ldir
        jp execprog

; append ASCIIZ (HL) to (DE) with limit B
rr_cat:
        ld a,(hl)
        or a
        ret z
        inc hl
        call rr_char
        jr rr_cat
rr_char:
        inc b
        dec b
        ret z
        ld (de),a
        inc de
        dec b
        ret

; ---- .BAT : let COMMAND2 run it via the keyboard buffer -------------------------
; ---- .BAS : leave to MSX-DOS and type  BASIC NAME.BAS  (COMMAND2 loads and RUNs it)
run_bas:
        ld hl,str_basic
        jr rb_go
run_bat:
        ld hl,str_none
rb_go:
        ld (rb_pfx),hl
        ld hl,(selname)
        call strlen             ; BC = length
        ld a,c
        cp 33
        jr c,rb_ok
        ld hl,msg_notexe
        jp status_loop
rb_ok:
        call scrreset
        di
        ld de,KEYBUF            ; keyboard buffer: [BASIC ]name RETURN
        ld hl,(rb_pfx)
        call rb_copy
        ld hl,(selname)
        call rb_copy
        jr rb_eol
rb_copy:
        ld a,(hl)
        or a
        ret z
        ld (de),a
        inc hl
        inc de
        jr rb_copy
rb_eol:
        ld a,KEY_RET
        ld (de),a
        inc de
        ld (PUTPNT),de
        ld hl,KEYBUF
        ld (GETPNT),hl
        ei
        ld c,F_TERM0
        jp BDOS

; --------------------------------------------------------------------------
;  execprog : load the program in progpath at 0100h and run it.
;             tailbuf = ASCIIZ parameters (without leading space)
;  Does not return on success.
; --------------------------------------------------------------------------
execprog:
        ld de,progpath
        ld a,1                  ; open mode: no write
        ld c,F_OPEN
        call BDOS
        or a
        jr z,ex_opened
        ld hl,msg_openerr
        jp status_loop
ex_opened:
        ld a,b
        ld (fhandle),a

        ; environment items like COMMAND2 sets them
        ld hl,env_program
        ld de,progpath
        ld c,F_SENV
        call BDOS
        ld hl,env_params
        ld de,tailbuf
        ld c,F_SENV
        call BDOS

        call scrreset

        ; command tail at 0080h: length, " params", 0
        ld hl,tailbuf
        call strlen
        ld a,c
        cp 125
        jr c,ex_lenok
        ld a,125
ex_lenok:
        ld de,0x0081
        or a
        jr z,ex_notail          ; no parameters: length 0
        ld c,a
        ld b,0
        inc a
        push af                 ; length incl. the leading space
        ld a,0x20
        ld (de),a
        inc de
        ld hl,tailbuf
        ldir
        pop af
ex_notail:
        ld (0x0080),a
        xor a
        ld (de),a

        ; default FCBs at 005Ch / 006Ch
        ld hl,0x005C
        ld b,0x80-0x5C
ex_clr: ld (hl),0
        inc hl
        djnz ex_clr
        ld hl,0x005D
        call fcbblank
        ld hl,0x006D
        call fcbblank
        ld hl,tailbuf
        ld de,0x005C
        call mkfcb
        ld de,0x006C
        call mkfcb

        ; copy the loader stub just below the top of the TPA and jump to it
        ld hl,(TPATOP)
        ld de,0-STUBSPC
        add hl,de
        push hl
        ex de,hl
        ld hl,stub
        ld bc,stub_end-stub
        ldir
        pop hl
        ld sp,hl                ; stack grows down below the stub
        ld a,(fhandle)
        ld b,a
        jp (hl)

; position independent loader stub (B = file handle, SP = stub address)
stub:
        ld hl,0
        add hl,sp
        ld de,0-0x0200
        add hl,de               ; bytes to read = stub - 0100h - 0100h (stack)
        ld de,0x0100
        push bc
        ld c,F_READ
        call BDOS
        pop bc
        push af
        ld c,F_CLOSE
        call BDOS
        pop af
        or a
        jr nz,stub_fail
        ld hl,(TPATOP)
        ld sp,hl
        ld hl,0
        push hl                 ; RET from the program -> warm boot
        jp 0x0100
stub_fail:
        ld b,a
        ld c,F_TERM
        call BDOS
        jp 0
        db 0,0,0,0
stub_end:

; blank 11 name bytes at HL with spaces
fcbblank:
        ld b,11
fb_lp:  ld (hl),0x20
        inc hl
        djnz fb_lp
        ret

; --------------------------------------------------------------------------
;  mkfcb : parse one parameter at HL into the FCB at DE (drive + name.ext)
;          returns HL after the parameter
; --------------------------------------------------------------------------
mkfcb:
        ld a,(hl)
        cp 0x20
        jr nz,mf_nosp
        inc hl
        jr mkfcb
mf_nosp:
        or a
        ret z
        push de
        ; drive?
        inc hl
        ld a,(hl)
        dec hl
        cp 0x3A
        jr nz,mf_nodrv
        ld a,(hl)
        call toupper
        sub "A"-1
        ld (de),a
        inc hl
        inc hl
mf_nodrv:
        ; skip to the last path component
        ld (mf_start),hl
mf_scan:
        ld a,(hl)
        or a
        jr z,mf_scanned
        cp 0x20
        jr z,mf_scanned
        inc hl
        cp 0x5C
        jr nz,mf_scan
        ld (mf_start),hl
        jr mf_scan
mf_scanned:
        ld (mf_end),hl
        ld hl,(mf_start)
        pop de
        inc de                  ; name field
        ld b,8
        call mf_field
        ld a,(hl)
        cp "."
        jr nz,mf_noext
        inc hl
mf_noext:
        ld a,b                  ; skip rest of the name field
        or a
        jr z,mf_ext
mf_adv: inc de
        djnz mf_adv
mf_ext:
        ld b,3
        call mf_field
        ld hl,(mf_end)
        ret

; copy up to B chars of a name part from HL to DE (stops at . space 0 \),
; '*' fills the rest with '?'. On exit B = unused positions.
mf_field:
        ld a,b
        or a
        ret z
        ld a,(hl)
        or a
        ret z
        cp 0x20
        ret z
        cp "."
        ret z
        cp "*"
        jr z,mf_star
        call toupper
        ld (de),a
        inc hl
        inc de
        dec b
        jr mf_field
mf_star:
        inc hl
mf_starlp:
        ld a,"?"
        ld (de),a
        inc de
        djnz mf_starlp
        ret

; ==========================================================================
;  Directory handling
; ==========================================================================

; loaddir : read the current directory into the entry table and sort it
loaddir:
        ld b,0
        ld de,cwdbuf
        ld c,F_GETCD
        call BDOS
        or a
        jr z,ld_cdok
        xor a
        ld (cwdbuf),a
ld_cdok:
        call listinit
        ld a,(cwdbuf)           ; below the root: add a ".." entry
        or a
        call nz,addparent
        ld de,str_wild
        ld b,0x10               ; include sub-directories
        ld ix,fib
        ld c,F_FFIRST
        call BDOS
        or a
        jr nz,ld_done
ld_loop:
        call addfib
        ld ix,fib
        ld c,F_FNEXT
        call BDOS
        or a
        jr z,ld_loop
ld_done:
        jp sortent

; empty the entry table
listinit:
        ld hl,0
        ld (count),hl
        ld hl,pool
        ld (poolptr),hl
        xor a
        ld (truncflg),a
        ret

; add the ".." entry
addparent:
        ld a,T_PARENT
        ld (ae_type),a
        ld a,0x10
        ld (ae_attr),a
        ld hl,str_dotdot
        ld (ae_name),hl
        ld hl,zero4
        ld (ae_size),hl
        jp addent

; add the entry in fib to the table
addfib:
        ld a,(fib+1)
        cp "."
        jr nz,af_normal
        ld a,(fib+2)
        or a
        ret z                   ; "."  -> skip
        cp "."
        jr nz,af_normal
        ld a,(fib+3)
        or a
        ret z                   ; ".." -> skip (added by loaddir)
af_normal:
        ld a,(fib+14)
        ld (ae_attr),a
        bit 3,a                 ; volume label
        ret nz
        ld b,T_FILE
        bit 4,a
        jr z,af_store
        ld b,T_DIR
af_store:
        ld a,b
        ld (ae_type),a
        ld hl,fib+1
        ld (ae_name),hl
        ld hl,fib+21
        ld (ae_size),hl
        jp addent

; --------------------------------------------------------------------------
;  addent : append a record. In: ae_type, ae_attr, ae_name (-> ASCIIZ),
;           ae_size (-> 4 bytes). ZIP fields are taken from zhdr.
;           Carry set when the table or the name pool is full.
; --------------------------------------------------------------------------
addent:
        ld hl,(count)
        ld de,MAXENT
        or a
        sbc hl,de
        jp nc,ae_full
        ld hl,(poolptr)
        ld de,NAMECAP+1
        add hl,de
        ld de,poolend
        or a
        sbc hl,de
        jr nc,ae_full
        ld hl,(count)
        add hl,hl
        add hl,hl
        add hl,hl               ; * 8
        ld d,h
        ld e,l
        add hl,hl               ; * 16
        add hl,de               ; * 24
        ld de,entries
        add hl,de               ; HL = record
        push hl
        ld a,(ae_type)
        ld (hl),a
        inc hl
        ld a,(ae_attr)
        ld (hl),a
        inc hl
        ex de,hl
        ld hl,(ae_size)
        ld bc,4
        ldir                    ; DE = record + E_NAMEP
        ld hl,(poolptr)
        ex de,hl
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        push hl                 ; record + E_ZOFS
        ld hl,(ae_name)
        ld b,NAMECAP
ae_cp:  ld a,(hl)
        or a
        jr z,ae_cpe
        ld (de),a
        inc hl
        inc de
        djnz ae_cp
ae_cpe: xor a
        ld (de),a
        inc de
        ld (poolptr),de
        pop de
        ld hl,zhdr+42
        ld bc,4
        ldir                    ; local header offset
        ld hl,zhdr+10
        ld bc,2
        ldir                    ; compression method
        ld hl,zhdr+8
        ld bc,2
        ldir                    ; general purpose flags
        ld hl,zhdr+16
        ld bc,4
        ldir                    ; CRC32 of the contents
        ld hl,(count)
        call idxptr
        pop de
        ld (hl),e
        inc hl
        ld (hl),d
        ld hl,(count)
        inc hl
        ld (count),hl
        or a
        ret
ae_full:
        ld a,1
        ld (truncflg),a
        scf
        ret

; HL = index -> HL = address of idx[index]
idxptr:
        add hl,hl
        ld de,idx
        add hl,de
        ret

; HL = index -> HL = entry record
getent:
        call idxptr
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ret

; HL = record -> HL = name
entname:
        ld de,E_NAMEP
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ret

; ---- Shell sort of the index table ------------------------------------------------
sortent:
        ld hl,gaps
so_next:
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,d
        or e
        ret z
        ld (gap),de
        push hl
        call shpass
        pop hl
        jr so_next

shpass:
        ld hl,(gap)
        ld (si),hl
sp_outer:
        ld hl,(si)
        ld de,(count)
        or a
        sbc hl,de
        ret nc
        ld hl,(si)
        call idxptr
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld (stmp),de
        ld hl,(si)
        ld (sj),hl
sp_inner:
        ld hl,(sj)
        ld de,(gap)
        or a
        sbc hl,de
        jr c,sp_place
        ld (sjg),hl
        call idxptr
        ld e,(hl)
        inc hl
        ld d,(hl)               ; DE = idx[sj-gap]
        ld hl,(stmp)
        call cmpent
        jr nc,sp_place
        ld hl,(sjg)
        call idxptr
        ld e,(hl)
        inc hl
        ld d,(hl)
        push de
        ld hl,(sj)
        call idxptr
        pop de
        ld (hl),e
        inc hl
        ld (hl),d
        ld hl,(sjg)
        ld (sj),hl
        jr sp_inner
sp_place:
        ld hl,(sj)
        call idxptr
        ld de,(stmp)
        ld (hl),e
        inc hl
        ld (hl),d
        ld hl,(si)
        inc hl
        ld (si),hl
        jr sp_outer

; compare records DE (a) and HL (b): carry set if a > b
; (type first, then the name without regard to case)
cmpent:
        ld a,(de)
        cp (hl)
        jr nz,ce_diff
        ld bc,E_NAMEP
        add hl,bc
        ld c,(hl)
        inc hl
        ld b,(hl)               ; BC = name b
        ex de,hl
        ld de,E_NAMEP
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)               ; DE = name a
        ld h,b
        ld l,c
ce_lp:  ld a,(de)
        cp (hl)
        jr nz,ce_case
        or a
        ret z                   ; equal (no carry)
        inc de
        inc hl
        jr ce_lp
ce_case:
        call toupper            ; differ: compare ignoring case
        ld c,a
        ld a,(hl)
        call toupper
        cp c                    ; carry if b < a
        ret nz
        inc de
        inc hl
        jr ce_lp
ce_diff:
        ccf
        ret

; select the entry named in lastname (after going to the parent)
findlast:
        ld a,(lastname)
        or a
        ret z
        ld hl,0
fl_loop:
        push hl
        ld de,(count)
        or a
        sbc hl,de
        pop hl
        ret nc
        push hl
        call getent
        call entname
        ld de,lastname
        call strcmp
        pop hl
        jr z,fl_found
        inc hl
        jr fl_loop
fl_found:
        ld (sel),hl
        ret

; keep the selection inside the visible window
fixtop:
        ld hl,(sel)
        ld de,(top)
        or a
        sbc hl,de
        jr nc,ft_below
        ld hl,(sel)
        ld (top),hl
        ret
ft_below:
        ; sel - top >= lrows ?  -> top = sel - lrows + 1
        ld a,(lrows)
        ld e,a
        ld d,0
        or a
        sbc hl,de
        ret c
        ld hl,(sel)
        or a
        sbc hl,de
        inc hl
        ld (top),hl
        ret

; HL = name -> A = 1 COM, 2 BAT, 3 ROM, 4 ZIP, 5 DSK, 6 BAS, 7 TXT, 8 CFG, 9 INI, 0 other
getext:
        ld de,0
ge_scan:
        ld a,(hl)
        or a
        jr z,ge_end
        cp "."
        jr nz,ge_nxt
        ld d,h
        ld e,l
ge_nxt: inc hl
        jr ge_scan
ge_end:
        ld a,d
        or e
        ret z
        ex de,hl
        inc hl                  ; HL = extension
        ld de,ext_com
        ld b,1
ge_try:
        push hl
        push de
        call strcmpi
        pop de
        pop hl
        ld a,b
        ret z
        inc de
        inc de
        inc de
        inc de
        inc b
        ld a,b
        cp 10
        jr c,ge_try
        xor a
        ret

; HL = name -> pathbuf = "D:\cwd\name"   (HL = 0 : without name)
mkfull:
        push hl
        ld c,F_CURDRV
        call BDOS
        ld de,pathbuf
        add a,"A"
        ld (de),a
        inc de
        ld a,0x3A
        ld (de),a
        inc de
        ld a,0x5C
        ld (de),a
        inc de
        ld hl,cwdbuf
        call strcpy             ; DE -> terminating 0
        pop hl
        ld a,h
        or l
        ret z
        ld a,(cwdbuf)
        or a
        jr z,mk_root
        ld a,0x5C
        ld (de),a
        inc de
mk_root:
        jp strcpy

; ==========================================================================
;  ZIP archive browsing (central directory only, nothing is extracted)
; ==========================================================================

; loadzip : list the entries of zipfile below zipdir.
;           carry set + HL = message when the file is not a usable ZIP
loadzip:
        call listinit
        call addparent          ; ".." = up one level / leave the ZIP
        ld de,zipfile
        ld a,1
        ld c,F_OPEN
        call BDOS
        or a
        jr z,lz_open
        ld hl,msg_openerr
        scf
        ret
lz_open:
        ld a,b
        ld (zhandle),a
        ; DE:HL = file size
        ld de,0
        ld hl,0
        ld a,2
        call zseek
        jp c,lz_bad
        ld (zsize),hl
        ld (zsize+2),de
        ; tail = min(size, ZBUFSZ)
        ld bc,ZBUFSZ
        ld a,d
        or e
        jr nz,lz_tail
        push hl
        or a
        sbc hl,bc
        pop hl
        jr nc,lz_tail
        ld b,h
        ld c,l
lz_tail:
        ld (ztail),bc
        ld h,b
        ld l,c
        ld de,22
        or a
        sbc hl,de
        jp c,lz_bad             ; smaller than an end record
        ; seek to size - tail and read the tail
        ld hl,(zsize)
        or a
        sbc hl,bc
        ex de,hl
        ld hl,(zsize+2)
        ld bc,0
        sbc hl,bc
        ex de,hl                ; DE:HL = size - tail
        xor a
        call zseek
        jp c,lz_bad
        ld de,zipbuf
        ld hl,(ztail)
        call zread
        jp c,lz_bad
        ; search the end of central directory record backwards
        ld hl,(ztail)
        ld de,zipbuf-22
        add hl,de
lz_scan:
        ld de,sig_eocd
        call issig
        jr z,lz_eocd
        ld de,zipbuf
        or a
        sbc hl,de
        jp z,lz_bad
        add hl,de
        dec hl
        jr lz_scan
lz_eocd:
        ld de,10
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld (zleft),de           ; number of entries
        ld (ztotal),de
        xor a
        ld (zshow),a
        push hl
        ld hl,ZIPDLG_MIN-1      ; big ZIP: "Reading" box with a bar
        or a
        sbc hl,de
        call c,zread_box
        pop hl
        ld de,5
        add hl,de               ; -> offset of the central directory
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ex de,hl                ; DE:HL = offset
        xor a
        call zseek
        jp c,lz_bad
        ld hl,0
        ld (zr_pos),hl
        ld (zr_len),hl
lz_loop:
        ld hl,(zleft)
        ld a,h
        or l
        jr z,lz_done
        dec hl
        ld (zleft),hl
        ld a,(zshow)            ; every 32 entries: the bar
        or a
        jr z,lz_nob
        ld a,l
        and 31
        call z,zread_pct
lz_nob:
        ld de,zhdr
        ld bc,46
        call zr_read
        jr c,lz_done
        ld hl,zhdr
        ld de,sig_cdir
        call issig
        jr nz,lz_done
        ; file name: keep at most 255 bytes
        ld hl,(zhdr+28)
        ld bc,0
        ld a,h
        or a
        jr z,lz_nlen
        ld de,255
        or a
        sbc hl,de
        ld b,h
        ld c,l                  ; BC = bytes to skip
        ld hl,255
lz_nlen:
        push bc
        push hl
        ld b,h
        ld c,l
        ld de,namebuf
        call zr_read
        pop hl
        pop bc
        jr c,lz_done
        ld (znlen),hl
        ld de,namebuf
        add hl,de
        ld (hl),0
        call zr_skip            ; rest of a very long name
        ld bc,(zhdr+30)
        call zr_skip            ; extra field
        ld bc,(zhdr+32)
        call zr_skip            ; comment
        call zentry
        jr nc,lz_loop
lz_done:
        call zclose
        call sortent
        or a
        ret
lz_bad:
        call zclose
        ld hl,msg_badzip
        scf
        ret

; zentry : add the central directory entry in namebuf if it lies in zipdir.
;          carry set when the table is full.
zentry:
        ld hl,namebuf           ; '\' -> '/'
        ld bc,(znlen)
ze_norm:
        ld a,b
        or c
        jr z,ze_normd
        ld a,0x5C
        cpir
        jr nz,ze_normd
        dec hl
        ld (hl),"/"
        inc hl
        jr ze_norm
ze_normd:
        ld hl,namebuf
        ld de,zipdir
ze_pre:
        ld a,(de)
        or a
        jr z,ze_rem
        cp (hl)
        jr nz,ze_skip           ; not below zipdir
        inc hl
        inc de
        jr ze_pre
ze_rem:
        ld a,(hl)
        or a
        jr z,ze_skip            ; the directory itself
        ld (ae_name),hl
        ld b,T_FILE
ze_scan:
        ld a,(hl)
        or a
        jr z,ze_add
        cp "/"
        jr z,ze_dir
        inc hl
        jr ze_scan
ze_dir:
        ld (hl),0               ; first path component = sub directory
        ld b,T_DIR
        call zdirseen
        jr z,ze_skip
ze_add:
        ld a,b
        ld (ae_type),a
        cp T_DIR
        ld a,0x10
        ld hl,zero4
        jr z,ze_set
        ld a,0x20
        ld hl,zhdr+24           ; uncompressed size
ze_set:
        ld (ae_attr),a
        ld (ae_size),hl
        jp addent
ze_skip:
        or a
        ret

; Z if a directory named (ae_name) is already in the table (B preserved)
zdirseen:
        push bc
        ld hl,(count)
zs_lp:
        ld a,h
        or l
        jr z,zs_no
        dec hl
        push hl
        call getent
        ld a,(hl)
        cp T_DIR
        jr nz,zs_next
        call entname
        ld de,(ae_name)
        call strcmp
        jr z,zs_yes
zs_next:
        pop hl
        jr zs_lp
zs_yes:
        pop hl
        pop bc
        xor a
        ret
zs_no:
        pop bc
        ld a,1
        or a
        ret

; Z if the 4 bytes at HL equal the 4 bytes at DE (HL preserved)
issig:
        push hl
        ld b,4
is_lp:  ld a,(de)
        cp (hl)
        jr nz,is_end
        inc hl
        inc de
        djnz is_lp
is_end: pop hl
        ret

; seek in the ZIP: A = method (0 start / 2 end), DE:HL = offset
zseek:
        push af
        ld a,(zhandle)
        ld b,a
        pop af
        ld c,F_SEEK
        call BDOS
        or a
        ret z
        scf
        ret

; read HL bytes of the ZIP to DE
zread:
        ld a,(zhandle)
        ld b,a
        ld c,F_READ
        call BDOS
        or a
        ret z
        scf
        ret

zclose:
        ld a,(zhandle)
        ld b,a
        ld c,F_CLOSE
        jp BDOS

; buffered reading of the central directory --------------------------------
; read BC bytes to DE (DE = 0: just skip them), carry at end of file
zr_read:
        ld a,b
        or c
        ret z
        ld hl,(zr_len)
        push de
        ld de,(zr_pos)
        or a
        sbc hl,de               ; HL = bytes left in the buffer
        pop de
        jr nz,zrr_have
        push bc
        push de
        ld de,zipbuf
        ld hl,ZBUFSZ
        call zread
        pop de
        pop bc
        ret c
        ld (zr_len),hl
        ld hl,0
        ld (zr_pos),hl
        ld hl,(zr_len)
zrr_have:
        push hl                 ; n = min(left, BC)
        or a
        sbc hl,bc
        pop hl
        jr c,zrr_n
        ld h,b
        ld l,c
zrr_n:
        push bc                 ; count
        push hl                 ; n
        ld a,d
        or e
        jr z,zrr_adv            ; skipping: no copy
        push hl
        ld hl,(zr_pos)
        ld bc,zipbuf
        add hl,bc
        pop bc
        ldir
zrr_adv:
        pop hl                  ; n
        push de
        ld de,(zr_pos)
        add hl,de
        ld (zr_pos),hl
        or a
        sbc hl,de               ; n again
        ex de,hl                ; DE = n
        pop hl                  ; HL = destination
        pop bc                  ; BC = count
        push hl
        ld h,b
        ld l,c
        or a
        sbc hl,de
        ld b,h
        ld c,l                  ; count -= n
        pop de
        jr zr_read

; skip BC bytes
zr_skip:
        ld de,0
        jr zr_read

; ==========================================================================
;  Extraction of one ZIP entry (stored or deflated) to tmppath
; --------------------------------------------------------------------------
;  The 32 KB inflate window and the Huffman tables reuse the memory of the
;  directory list (idx / entries / pool), so the list is re-read afterwards.
;  In : xofs (local header offset), xmeth, xflags, xsize (uncompressed size)
;  Out: carry + HL = message on error (the partial temp file is deleted)
; ==========================================================================
extract:
        ld (infl_sp),sp
        xor a
        ld (zhopen),a
        ld (ohopen),a
        ; enough memory between the window/tables and the top of the TPA?
        ld hl,(TPATOP)
        ld de,INFL_END+0x0200
        or a
        sbc hl,de
        ld hl,msg_nomem
        jp c,ix_fail
        ld a,(xflags)
        bit 0,a
        ld hl,msg_crypt
        jp nz,ix_fail
        ld hl,(xmeth)
        ld a,h
        or a
        jr nz,x_unsup
        ld a,l
        or a
        jr z,x_methok
        cp 8
        jr z,x_methok
x_unsup:
        ld hl,msg_method
        jp ix_fail
x_methok:
        ; open the ZIP and find the data behind the local header
        ld de,zipfile
        ld a,1
        ld c,F_OPEN
        call BDOS
        or a
        ld hl,msg_openerr
        jp nz,ix_fail
        ld a,b
        ld (zhandle),a
        ld a,1
        ld (zhopen),a
        ld hl,(xofs)
        ld de,(xofs+2)
        xor a
        call zseek
        jp c,ix_data
        ld de,zhdr
        ld hl,30
        call zread
        jp c,ix_data
        ld hl,zhdr
        ld de,sig_local
        call issig
        jp nz,ix_data
        ld hl,(zhdr+26)
        ld de,(zhdr+28)
        add hl,de
        ld de,30
        add hl,de               ; length of the local header
        ld de,(xofs)
        add hl,de
        ex de,hl                ; DE = low word
        ld hl,(xofs+2)
        ld bc,0
        adc hl,bc
        ex de,hl                ; DE:HL = start of the data
        xor a
        call zseek
        jp c,ix_data
        ; create the temporary file
        ld de,tmppath
        xor a
        ld b,0
        ld c,F_CREATE
        call BDOS
        or a
        ld hl,msg_tmperr
        jp nz,ix_fail
        ld a,b
        ld (ohandle),a
        ld a,1
        ld (ohopen),a
        ld hl,0
        ld (outtot),hl
        ld (outtot+2),hl
        ld hl,WIN
        ld (outptr),hl
        ld a,(xmeth)
        or a
        jr z,x_stored
        call inflate
        call flush
        jr x_check
x_stored:
        call stored
x_check:
        ; the output must have exactly the size given in the directory
        ld hl,(outtot)
        ld de,(xsize)
        or a
        sbc hl,de
        jp nz,ix_data
        ld hl,(outtot+2)
        ld de,(xsize+2)
        or a
        sbc hl,de
        jp nz,ix_data
        call progress           ; 100%
        call xcloseall
        or a
        ret

ix_data:
        ld hl,msg_zdata
        jr ix_fail
ix_write:
        ld hl,msg_wrerr
ix_fail:
        ld sp,(infl_sp)
        push hl
        ld a,(ohopen)
        push af
        call xcloseall
        pop af
        or a
        jr z,ixf_nodel
        ld de,tmppath           ; remove the incomplete file
        ld c,F_DELETE
        call BDOS
ixf_nodel:
        pop hl
        scf
        ret

xcloseall:
        ld a,(zhopen)
        or a
        call nz,zclose
        ld a,(ohopen)
        or a
        jr z,xc_done
        ld a,(ohandle)
        ld b,a
        ld c,F_CLOSE
        call BDOS
xc_done:
        xor a
        ld (zhopen),a
        ld (ohopen),a
        ret

; ---- progress display during extraction ---------------------------------------
; status line 1: "Extracting to <tmppath>", line 2: "  0%" .. "100%"
prog_init:
        ld hl,0
        ld (outtot),hl
        ld (outtot+2),hl
        ld hl,WIN
        ld (outptr),hl
        call prog_box           ; box with "Extracting", path, bar at 0 %
        ; fall through: show 0%

; show written / xsize in percent if it changed (A BC DE HL changed)
progress:
        ld hl,(outptr)          ; done = outtot + bytes waiting in the window
        ld de,WIN
        or a
        sbc hl,de
        ld de,(outtot)
        add hl,de
        ld (pdone),hl
        ld hl,(outtot+2)
        ld de,0
        adc hl,de
        ld (pdone+2),hl
        ld hl,(xsize)
        ld (ptot),hl
        ld hl,(xsize+2)
        ld (ptot+2),hl
pr_scale:                       ; scale both down until total < 656,
        ld hl,(ptot+2)          ; so that done * 100 fits in 16 bits
        ld a,h
        or l
        jr nz,pr_shift
        ld hl,(ptot)
        ld de,656
        or a
        sbc hl,de
        jr c,pr_calc
pr_shift:
        ld hl,ptot+3
        srl (hl)
        dec hl
        rr (hl)
        dec hl
        rr (hl)
        dec hl
        rr (hl)
        ld hl,pdone+3
        srl (hl)
        dec hl
        rr (hl)
        dec hl
        rr (hl)
        dec hl
        rr (hl)
        jr pr_scale
pr_calc:
        ld hl,(ptot)
        ld a,h
        or l
        ld a,100
        jr z,pr_have            ; empty file
        ld hl,(pdone)
        add hl,hl
        add hl,hl               ; * 4
        push hl
        add hl,hl
        add hl,hl
        add hl,hl               ; * 32
        push hl
        add hl,hl               ; * 64
        pop de
        add hl,de
        pop de
        add hl,de               ; * 100
        ld de,(ptot)
        ld b,0
pr_div: or a
        sbc hl,de
        jr c,pr_dd
        inc b
        jr pr_div
pr_dd:  ld a,b
        cp 101
        jr c,pr_have
        ld a,100
pr_have:
        ld hl,lastpct
        cp (hl)
        ret z
        jp prog_bar

; ---- method 0: copy in 32 KB pieces -------------------------------------------
stored:
        ld hl,(xsize)
        ld de,(xsize+2)
        ld (remain),hl
        ld (remain+2),de
st_lp:
        ld hl,(remain)
        ld de,(remain+2)
        ld a,h
        or l
        or d
        or e
        ret z
        ld bc,0x2000            ; 8 KB pieces (progress steps)
        ld a,d
        or e
        jr nz,st_big
        push hl
        or a
        sbc hl,bc
        pop hl
        jr nc,st_big
        ld b,h
        ld c,l
st_big:
        push bc
        ld de,WIN
        ld h,b
        ld l,c
        call zread
        pop bc
        jp c,ix_data
        push hl
        or a
        sbc hl,bc
        pop hl
        jp nz,ix_data
        ld hl,WIN
        add hl,bc
        ld (outptr),hl
        push bc
        call flush
        call progress
        pop bc
        ld hl,(remain)
        or a
        sbc hl,bc
        ld (remain),hl
        ld hl,(remain+2)
        ld bc,0
        sbc hl,bc
        ld (remain+2),hl
        jr st_lp

; ---- output -----------------------------------------------------------------
; A -> window, flushes when the window is full (BC DE HL preserved)
outbyte:
        push hl
        ld hl,(outptr)
        ld (hl),a
        inc hl
        ld (outptr),hl
        ld a,l
        or a
        jr nz,ob_ret
        ld a,h
        cp WENDH
        call z,flush
ob_ret: pop hl
        ret

; write WIN..outptr to the temporary file (BC DE HL IX IY preserved)
flush:
        push hl
        push bc
        push de
        push ix
        push iy
        ld hl,(outptr)
        ld de,WIN
        or a
        sbc hl,de
        jr z,fl_done
        push hl
        ld a,(ohandle)
        ld b,a
        ld c,F_WRITE
        call BDOS
        pop de
        or a
        jp nz,ix_write
        sbc hl,de
        jp nz,ix_write          ; disk full
        ld hl,(outtot)
        add hl,de
        ld (outtot),hl
        jr nc,fl_nc
        ld hl,(outtot+2)
        inc hl
        ld (outtot+2),hl
fl_nc:
        ld hl,WIN
        ld (outptr),hl
fl_done:
        pop iy
        pop ix
        pop de
        pop bc
        pop hl
        ret

; copy BC bytes from distance DE back in the window
lzcopy:
        ld hl,(outptr)
        push de
        ld de,WIN
        or a
        sbc hl,de               ; position in the window
        pop de
        or a
        sbc hl,de               ; - distance
        jr nc,lc_nw
        ld de,0x8000            ; wrap around the circular window
        add hl,de
lc_nw:  ld de,WIN
        add hl,de               ; HL = source
lc_src:
        ; fast path: neither source nor destination reaches the window end
        push hl
        add hl,bc
        ld de,WEND+1
        or a
        sbc hl,de
        pop hl
        jr nc,lc_slow
        push hl
        ld hl,(outptr)
        add hl,bc
        ld de,WEND+1
        or a
        sbc hl,de
        pop hl
        jr nc,lc_slow
        ld de,(outptr)
        ldir                    ; byte by byte: overlapping copies repeat
        ld (outptr),de
        ld a,e
        or a
        ret nz
        ld a,d
        cp WENDH
        ret nz
        jp flush
lc_slow:
        ld a,(hl)
        call outbyte
        inc hl
        ld a,l
        or a
        jr nz,lcs_nw
        ld a,h
        cp WENDH
        jr nz,lcs_nw
        ld hl,WIN
lcs_nw:
        dec bc
        ld a,b
        or c
        jr nz,lc_slow
        ret

; ---- compressed input ----------------------------------------------------------
; The stream position is ip (byte in zipbuf) + ik (bit 0..7, LSB first).
; Before reading, ip < ilim guarantees 4 readable bytes.
in_init:
        ld hl,zipbuf
        ld (ip),hl
        ld (iend),hl
        xor a
        ld (ik),a
        ld (ieof),a
; move the unread bytes to the start of zipbuf and read more behind them
; (all registers except A preserved)
in_fill:
        push bc
        push de
        push hl
        push ix
        push iy
        call progress           ; about every 1 KB of compressed input
        ld hl,(iend)
        ld de,(ip)
        or a
        sbc hl,de
        ld b,h
        ld c,l
        ex de,hl
        ld de,zipbuf
        ld a,b
        or c
        jr z,if_nomv
        ldir
if_nomv:
        ld hl,zipbuf
        ld (ip),hl
        ld a,(ieof)
        or a
        jr nz,if_eof
        push de
        ld hl,zipbuf+ZBUFSZ
        or a
        sbc hl,de
        call zread
        pop de
        jr c,if_eof
        add hl,de
        jr if_end
if_eof:                         ; end of the file: pad once with zeros
        ld a,(ieof)
        or a
        jp nz,ix_data
        inc a
        ld (ieof),a
        ex de,hl
        ld b,8
ife_z:  ld (hl),0
        inc hl
        djnz ife_z
if_end: ld (iend),hl
        ld de,4
        or a
        sbc hl,de
        ld (ilim),hl
        pop iy
        pop ix
        pop hl
        pop de
        pop bc
        ret

; A = next whole byte (ik = 0), BC DE HL IX IY preserved
inbyte:
        push hl
        push de
        ld hl,(ip)
        ld de,(ilim)
        or a
        sbc hl,de
        call nc,in_fill
        ld hl,(ip)
        ld a,(hl)
        inc hl
        ld (ip),hl
        pop de
        pop hl
        ret

; advance by B bits (A B DE HL changed)
consume:
        ld a,(ik)
        add a,b
        ld b,a
        and 7
        ld (ik),a
        ld a,b
        rrca
        rrca
        rrca
        and 0x1F
        ld e,a
        ld d,0
        ld hl,(ip)
        add hl,de
        ld (ip),hl
        ret

; HL = next B bits (0..13), least significant first (C DE IX IY preserved)
getbits:
        ld hl,0
        ld a,b
        or a
        ret z
        push de
        push bc
        ld hl,(ip)
        ld de,(ilim)
        or a
        sbc hl,de
        call nc,in_fill
        ld hl,(ip)
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld c,(hl)
        ld a,(ik)
        or a
        jr z,gb_0
        ld b,a
gb_sh:  srl c
        rr d
        rr e
        djnz gb_sh
gb_0:   pop bc
        push bc
        ld a,b
        add a,a
        ld l,a
        ld h,0
        push de
        ld de,mask16
        add hl,de
        pop de
        ld a,(hl)
        and e
        ld e,a
        inc hl
        ld a,(hl)
        and d
        ld d,a
        pop bc
        push bc
        push de
        call consume
        pop hl
        pop bc
        pop de
        ret
mask16: dw 0,1,3,7,15,31,63,127,255,511,1023,2047,4095,8191

; carry = next bit (BC DE HL IX IY preserved)
getbit1:
        push hl
        push de
        push bc
        ld b,1
        call getbits
        ld a,l
        rra
        pop bc
        pop de
        pop hl
        ret

; ---- Huffman decoding ----------------------------------------------------------------
; Table layout (IX, 256-byte aligned): +0 / +256 low / high bytes of
; lookup[256] (len<<12 | symbol for codes of up to 8 bits, the 8-bit code
; prefix for longer codes, 0xF000 = invalid),
; +512 limit[16], +544 base[16], +576 count[16], +608 symbols[]
T_LIMIT:    equ 512
T_BASE:     equ 544
T_COUNT:    equ 576
T_SYM:      equ 608

; IX = table, C = its page (high byte) -> HL = symbol
decodeT:
        ld hl,(ip)
        ld de,(ilim)
        or a
        sbc hl,de
        call nc,in_fill
        ld hl,(ip)
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld a,(ik)
        or a
        jr z,dt_0
        ld b,a
dt_pk:  srl d
        rr e
        djnz dt_pk
dt_0:   ld l,e                  ; next 8 bits -> lookup entry
        ld h,c                  ; (low bytes in page C, high bytes in C+1)
        ld a,(hl)
        inc h
        ld h,(hl)
        ld l,a
        ld a,h
        and 0xF0
        jr z,dt_long
        cp 0xF0
        jp z,ix_data
        rrca
        rrca
        rrca
        rrca
        ld b,a                  ; code length
        ld a,h
        and 1
        ld h,a
        ld a,(ik)               ; consume the code
        add a,b
        ld b,a
        and 7
        ld (ik),a
        ld a,b
        rrca
        rrca
        rrca
        and 0x1F
        ld de,(ip)
        add a,e
        ld e,a
        jr nc,dt_nc
        inc d
dt_nc:  ld (ip),de
        ret
dt_long:                        ; longer than 8 bits: continue bit by bit
        push hl
        ld b,8
        call consume
        pop hl
        push ix
        pop iy
        ld de,T_LIMIT+18
        add iy,de               ; IY = limit[9]
        ld a,9
        ld (dc_len),a
dtl_lp: call getbit1
        adc hl,hl               ; code = code * 2 + bit
        ld a,l
        sub (iy+0)
        ld a,h
        sbc a,(iy+1)
        jr c,dtl_hit
        inc iy
        inc iy
        ld a,(dc_len)
        inc a
        ld (dc_len),a
        cp 16
        jr c,dtl_lp
        jp ix_data
dtl_hit:
        ld e,(iy+T_BASE-T_LIMIT)
        ld d,(iy+T_BASE-T_LIMIT+1)
        add hl,de
        add hl,hl
        push ix
        pop de
        add hl,de
        ld de,T_SYM
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ret

; fill the lookup / limit / base parts of table IX from count[] and symbols[]
mktable:
        push ix
        pop hl
        ld b,0
mk_f:   ld (hl),0
        inc h
        ld (hl),0xF0
        dec h
        inc l
        djnz mk_f
        ld hl,0
        ld (k_first),hl
        ld (k_index),hl
        ld a,1
        ld (k_len),a
        push ix
        pop iy
        ld de,T_LIMIT+2
        add iy,de               ; IY = limit[1]
mk_len:
        ld l,(iy+T_COUNT-T_LIMIT)
        ld h,(iy+T_COUNT-T_LIMIT+1)
        ld (k_cnt),hl
        ld de,(k_first)
        add hl,de
        ld (iy+0),l             ; limit = first + count
        ld (iy+1),h
        ld hl,(k_index)
        or a
        sbc hl,de
        ld (iy+T_BASE-T_LIMIT),l        ; base = index - first
        ld (iy+T_BASE-T_LIMIT+1),h
        ld hl,(k_cnt)
        ld a,h
        or l
        jp z,mk_nosym
        ld (k_k),hl
        ld hl,(k_first)
        ld (k_code),hl
        ld hl,(k_index)
        ld (k_si),hl
mk_sym:
        ld hl,(k_si)
        add hl,hl
        push ix
        pop de
        add hl,de
        ld de,T_SYM
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld (k_sym),hl
        ld a,(k_len)
        cp 9
        jr nc,mk_long
        ld b,a                  ; short code: all 2^(8-L) slots
        ld a,(k_code)
        ld c,a
        xor a
mk_rev: srl c
        rla
        djnz mk_rev
        ld e,a                  ; E = bit reversed code
        ld a,(k_len)
        add a,a
        add a,a
        add a,a
        add a,a
        ld hl,(k_sym)
        or h
        ld d,a                  ; D = entry high
        ld c,l                  ; C = entry low
        ld a,(k_len)
        ld b,a
        ld a,1
mk_st:  add a,a
        djnz mk_st
        ld (k_step),a           ; 1 << L  (0 for L = 8)
        ld a,e
mk_put: push af
        ld l,a
        ld h,0
        push de
        push ix
        pop de
        add hl,de
        pop de
        ld (hl),c
        inc h
        ld (hl),d
        pop af
        ld hl,k_step
        ld b,(hl)
        inc b
        dec b
        jr z,mk_next
        add a,b
        jr nc,mk_put
        jr mk_next
mk_long:                        ; long code: slot of its first 8 bits
        sub 8
        ld b,a
        ld hl,(k_code)
mk_sr:  srl h
        rr l
        djnz mk_sr
        ld c,l
        ld b,8
        xor a
mk_rv8: srl c
        rla
        djnz mk_rv8
        push hl
        ld l,a
        ld h,0
        push ix
        pop de
        add hl,de
        pop de
        ld (hl),e
        inc h
        ld (hl),0
mk_next:
        ld hl,(k_code)
        inc hl
        ld (k_code),hl
        ld hl,(k_si)
        inc hl
        ld (k_si),hl
        ld hl,(k_k)
        dec hl
        ld (k_k),hl
        ld a,h
        or l
        jp nz,mk_sym
mk_nosym:
        ld hl,(k_index)
        ld de,(k_cnt)
        add hl,de
        ld (k_index),hl
        ld hl,(k_first)
        add hl,de
        add hl,hl
        ld (k_first),hl
        inc iy
        inc iy
        ld a,(k_len)
        inc a
        ld (k_len),a
        cp 16
        jp c,mk_len
        ret

; build a decoding table: c_len (code lengths), c_n (count), c_cnt, c_sym
construct:
        ld hl,(c_cnt)
        ld b,32
cs_z:   ld (hl),0
        inc hl
        djnz cs_z
        ld hl,(c_len)
        ld bc,(c_n)
cs_cnt: ld a,b
        or c
        jr z,cs_offs
        ld a,(hl)
        inc hl
        push hl
        add a,a
        ld e,a
        ld d,0
        ld hl,(c_cnt)
        add hl,de
        inc (hl)
        jr nz,cs_c1
        inc hl
        inc (hl)
cs_c1:  pop hl
        dec bc
        jr cs_cnt
cs_offs:
        ld hl,0
        ld (offs+2),hl          ; offs[1] = 0
        ld de,(c_cnt)
        inc de
        inc de
        ld hl,offs+2
        ld b,14
cs_o:   ld a,(de)               ; offs[l+1] = offs[l] + count[l]
        add a,(hl)
        ld c,a
        inc de
        inc hl
        ld a,(de)
        adc a,(hl)
        inc de
        inc hl
        ld (hl),c
        inc hl
        ld (hl),a
        dec hl
        djnz cs_o
        ld hl,(c_len)
        ld de,0                 ; symbol
cs_sym:
        push hl
        ld hl,(c_n)
        or a
        sbc hl,de
        pop hl
        ret z
        ld a,(hl)
        inc hl
        or a
        jr z,cs_snext
        push hl
        add a,a
        ld l,a
        ld h,0
        ld bc,offs
        add hl,bc
        ld c,(hl)
        inc hl
        ld b,(hl)               ; BC = offs[len]
        push bc
        inc bc
        ld (hl),b
        dec hl
        ld (hl),c
        pop bc
        ld h,b
        ld l,c
        add hl,hl
        ld bc,(c_sym)
        add hl,bc
        ld (hl),e
        inc hl
        ld (hl),d
        pop hl
cs_snext:
        inc de
        jr cs_sym

; ---- inflate ----------------------------------------------------------------------
inflate:
        call in_init
ifl_blk:
        ld b,1
        call getbits
        ld a,l
        ld (lastblk),a
        ld b,2
        call getbits
        ld a,l
        or a
        jr z,ifl_stored
        dec a
        jr z,ifl_fixed
        dec a
        jp z,ifl_dyn
        jp ix_data
ifl_next:
        ld a,(lastblk)
        or a
        jr z,ifl_blk
        ret

ifl_stored:
        ld a,(ik)               ; continue at a byte boundary
        or a
        jr z,ifs_al
        xor a
        ld (ik),a
        ld hl,(ip)
        inc hl
        ld (ip),hl
ifs_al: call inbyte
        ld c,a
        call inbyte
        ld b,a
        call inbyte
        call inbyte             ; NLEN (ignored)
ifs_lp: ld a,b
        or c
        jp z,ifl_next
        call inbyte
        call outbyte
        dec bc
        jr ifs_lp

ifl_fixed:
        ld hl,lens
        ld a,8
        ld b,144
        call fillb
        ld a,9
        ld b,112
        call fillb
        ld a,7
        ld b,24
        call fillb
        ld a,8
        ld b,8
        call fillb
        ld hl,lens
        ld de,288
        call mklit
        ld hl,lens
        ld a,5
        ld b,30
        call fillb
        ld hl,lens
        ld de,30
        call mkdist
        call codes
        jp ifl_next

; HL = lengths, DE = count -> literal/length table / distance table
mklit:
        ld ix,LTAB
        jr mktab
mkdist:
        ld ix,DTAB
mktab:
        ld (c_len),hl
        ld (c_n),de
        push ix
        pop hl
        ld de,T_COUNT
        add hl,de
        ld (c_cnt),hl
        ld de,T_SYM-T_COUNT
        add hl,de
        ld (c_sym),hl
        call construct
        jp mktable

fillb:  ld (hl),a
        inc hl
        djnz fillb
        ret

ifl_dyn:
        ld b,5
        call getbits
        ld de,257
        add hl,de
        ld (nlen),hl
        ld b,5
        call getbits
        inc hl
        ld (ndist),hl
        ld b,4
        call getbits
        ld a,l
        add a,4
        ld c,a                  ; number of code length codes
        ld hl,(nlen)
        ld de,287
        or a
        sbc hl,de
        jp nc,ix_data
        ld a,(ndist)
        cp 31
        jp nc,ix_data
        ld hl,lens
        xor a
        ld b,19
        call fillb
        ld hl,clorder
dy_cl:  push hl
        ld b,3
        call getbits
        ld a,l
        pop hl
        ld e,(hl)
        inc hl
        push hl
        ld d,0
        ld hl,lens
        add hl,de
        ld (hl),a
        pop hl
        dec c
        jr nz,dy_cl
        ld hl,lens
        ld de,19
        call mklit
        ld hl,(nlen)
        ld de,(ndist)
        add hl,de
        ld (ntot),hl
        ld hl,0
        ld (dy_idx),hl
dy_lp:
        ld hl,(dy_idx)
        ld de,(ntot)
        or a
        sbc hl,de
        jr nc,dy_done
        ld ix,LTAB
        ld c,LTABH
        call decodeT
        ld a,l
        cp 16
        jr nc,dy_rep
        call dy_put1
        jr dy_lp
dy_rep:
        jr nz,dy_zero
        ld hl,(dy_idx)          ; 16: repeat the previous length 3..6 times
        ld a,h
        or l
        jp z,ix_data
        ld de,lens-1
        add hl,de
        ld a,(hl)
        ld (dy_val),a
        ld b,2
        call getbits
        ld a,l
        add a,3
        jr dy_fill
dy_zero:
        cp 17                   ; 17: 3..10 zeros, 18: 11..138 zeros
        ld b,3
        ld c,3
        jr z,dy_z
        ld b,7
        ld c,11
dy_z:   xor a
        ld (dy_val),a
        push bc
        call getbits
        pop bc
        ld a,l
        add a,c
dy_fill:
        ld b,a
        ld hl,(dy_idx)
        ld e,b
        ld d,0
        add hl,de
        ex de,hl
        ld hl,(ntot)
        or a
        sbc hl,de
        jp c,ix_data
dy_fl:  ld a,(dy_val)
        call dy_put1
        djnz dy_fl
        jr dy_lp
dy_put1:
        ld hl,(dy_idx)
        push hl
        ld de,lens
        add hl,de
        ld (hl),a
        pop hl
        inc hl
        ld (dy_idx),hl
        ret
dy_done:
        ld hl,lens
        ld de,(nlen)
        call mklit
        ld hl,(nlen)
        ld de,lens
        add hl,de
        ld de,(ndist)
        call mkdist
        call codes
        jp ifl_next

; decode literals / length-distance pairs until the end-of-block code
codes:
cd_lp:
        ld ix,LTAB
        ld c,LTABH
        call decodeT
        ld a,h
        or a
        jr nz,cd_len
        ld a,l                  ; literal (outbyte inlined)
        ld hl,(outptr)
        ld (hl),a
        inc hl
        ld (outptr),hl
        ld a,l
        or a
        jr nz,cd_lp
        ld a,h
        cp WENDH
        call z,flush
        jr cd_lp
cd_len:
        ld de,257
        or a
        sbc hl,de
        ret c                   ; 256 = end of block
        ld a,h
        or a
        jp nz,ix_data
        ld a,l
        cp 29
        jp nc,ix_data
        ld e,a
        ld d,0
        ld hl,lext
        add hl,de
        ld b,(hl)
        ld hl,lbase
        add hl,de
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        push hl
        call getbits
        pop de
        add hl,de
        push hl                 ; length
        ld ix,DTAB
        ld c,DTABH
        call decodeT
        ld a,h
        or a
        jp nz,ix_data
        ld a,l
        cp 30
        jp nc,ix_data
        ld e,a
        ld d,0
        ld hl,dext
        add hl,de
        ld b,(hl)
        ld hl,dbase
        add hl,de
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        push hl
        call getbits
        pop de
        add hl,de
        ex de,hl                ; DE = distance
        pop bc                  ; BC = length
        call lzcopy
        jr cd_lp

lbase:  dw 3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31
        dw 35,43,51,59,67,83,99,115,131,163,195,227,258
lext:   db 0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0
dbase:  dw 1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193
        dw 257,385,513,769,1025,1537,2049,3073,4097,6145
        dw 8193,12289,16385,24577
dext:   db 0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13
clorder: db 16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15

; ==========================================================================
;  Configuration
; ==========================================================================

; cfgpath = PROGRAM env with extension replaced by .CFG
findcfg:
        ld hl,env_program
        ld de,cfgpath
        ld b,100
        ld c,F_GENV
        call BDOS
        or a
        jr nz,fc_fallback
        ld a,(cfgpath)
        or a
        jr z,fc_fallback
        ld hl,cfgpath
        ld de,0
fc_scan:
        ld a,(hl)
        or a
        jr z,fc_end
        cp "."
        jr nz,fc_nodot
        ld d,h
        ld e,l
fc_nodot:
        cp 0x5C
        jr nz,fc_nxt
        ld de,0                 ; a dot before a '\' does not count
fc_nxt: inc hl
        jr fc_scan
fc_end:
        ld a,d
        or e
        jr z,fc_append
        ex de,hl
fc_append:
        ex de,hl                ; DE = where ".CFG" goes
        ld hl,str_cfgext
        jp strcpy
fc_fallback:
        ld b,0
        ld de,cwdbuf
        ld c,F_GETCD
        call BDOS
        ld hl,str_cfgname
        call mkfull
        ld hl,pathbuf
        ld de,cfgpath
        jp strcpy

; read MB.CFG (missing file is fine)
loadcfg:
        xor a
        ld (ldrpath),a
        ld (ldrargs),a
        ld (tmpcfg),a
        ld (startcfg),a
        ld (dskpath),a
        ld (dskargs),a
        ld (edpath),a
        ld (edargs),a
        ld de,cfgpath
        ld a,1
        ld c,F_OPEN
        call BDOS
        or a
        jp nz,lc_default
        push bc
        ld de,iobuf
        ld hl,255
        ld c,F_READ
        call BDOS
        ld de,0
        or a
        jr nz,lc_noread
        ex de,hl                ; DE = bytes read
lc_noread:
        ld hl,iobuf
        add hl,de
        ld (hl),0
        pop bc
        ld c,F_CLOSE
        call BDOS
        ld hl,iobuf
lc_line:
        call skipsp
        ld a,(hl)
        or a
        jp z,lc_default
        push hl
        ld de,key_ldr
        call prefixeq
        jr nz,lc_try2
        pop af
        ld de,ldrpath
        ld b,79
        call cpyline
        jr lc_line
lc_try2:
        pop hl
        push hl
        ld de,key_arg
        call prefixeq
        jr nz,lc_try3
        pop af
        ld de,ldrargs
        ld b,63
        call cpyline
        jr lc_line
lc_try3:
        pop hl
        push hl
        ld de,key_tmp
        call prefixeq
        jr nz,lc_try4
        pop af
        ld de,tmpcfg
        ld b,63
        call cpyline
        jr lc_line
lc_try4:
        pop hl
        push hl
        ld de,key_start
        call prefixeq
        jr nz,lc_try5
        pop af
        ld de,startcfg
        ld b,63
        call cpyline
        jr lc_line
lc_try5:
        pop hl
        push hl
        ld de,key_dldr
        call prefixeq
        jr nz,lc_try6
        pop af
        ld de,dskpath
        ld b,79
        call cpyline
        jr lc_line
lc_try6:
        pop hl
        push hl
        ld de,key_darg
        call prefixeq
        jr nz,lc_try7
        pop af
        ld de,dskargs
        ld b,63
        call cpyline
        jp lc_line
lc_try7:
        pop hl
        push hl
        ld de,key_ed
        call prefixeq
        jr nz,lc_try8
        pop af
        ld de,edpath
        ld b,79
        call cpyline
        jp lc_line
lc_try8:
        pop hl
        push hl
        ld de,key_edarg
        call prefixeq
        jr nz,lc_skip
        pop af
        ld de,edargs
        ld b,63
        call cpyline
        jp lc_line
lc_skip:
        pop hl
lc_skp2:
        ld a,(hl)
        or a
        jr z,lc_default
        inc hl
        cp 0x0A
        jr nz,lc_skp2
        jp lc_line
lc_default:
        ld a,(edargs)
        or a
        jr nz,lc_d1
        ld hl,str_defarg
        ld de,edargs
        call strcpy
lc_d1:  ld a,(dskargs)
        or a
        jr nz,lc_d2
        ld hl,str_defarg
        ld de,dskargs
        call strcpy
lc_d2:  ld a,(ldrargs)
        or a
        ret nz
        ld hl,str_defarg
        ld de,ldrargs
        jp strcpy

; HL = text, DE = key -> Z if text is  key [spaces] = [spaces] ..., HL after it
prefixeq:
        call prefix
        ret nz
        ld de,key_eq
        call prefix0
        ret nz
        call skipsp
        xor a                   ; Z = match
        ret

skipsp:
        ld a,(hl)
        cp 0x20
        jr z,ss_nxt
        cp 0x09
        ret nz
ss_nxt: inc hl
        jr skipsp

prefix0:
        call skipsp
        ld a,(de)
        cp (hl)
        ret nz
        inc hl
        xor a
        ret

; HL = text, DE = prefix -> Z if text starts with prefix, HL after it
prefix:
        ld a,(de)
        or a
        ret z
        call toupper
        ld c,a
        ld a,(hl)
        call toupper
        cp c
        ret nz
        inc hl
        inc de
        jr prefix

; copy rest of the line at HL to DE (max B chars, trailing blanks removed),
; HL -> next line
cpyline:
        ld (cl_last),de
cl_lp:
        ld a,(hl)
        or a
        jr z,cl_end
        cp 0x0D
        jr z,cl_eol
        cp 0x0A
        jr z,cl_eol
        inc hl
        inc b
        dec b
        jr z,cl_lp
        ld (de),a
        inc de
        dec b
        cp 0x20
        jr z,cl_lp
        ld (cl_last),de
        jr cl_lp
cl_eol:
        inc hl
        ld a,(hl)
        cp 0x0A
        jr nz,cl_end
        inc hl
cl_end:
        ld de,(cl_last)
        xor a
        ld (de),a
        ret


; ==========================================================================
;  Screen: SCREEN 2 (256 x 192), two colours
; --------------------------------------------------------------------------
;  The name table holds 0..255 three times, so the pattern table is a plain
;  bitmap in which every 8-pixel high band (b = 0..23) is 256 consecutive
;  bytes: byte (x AND F8h) + row of the band holds pixels x..x+7 of that row.
;  Every band is composed in RAM (bbuf) and sent to VRAM in one go.
;  The colour table is filled with one value: INK on PAPER everywhere.
;  Text uses the machine's own font (main ROM), 6 pixels per character.
;
;  Bands:  0..1    title bar (inverted, 15 rows + gap): path, number of items
;          2..17   list (16 rows), scroll bar on the right
;          18      line (pixel row 148)
;          19..21  details of the selection / full name inside a ZIP (3 lines)
;          22..23  line (row 177), keys or a message for a moment (text at
;                  row 179, key caps 179..186), bottom of the frame (row 189)
; ==========================================================================

CHGMOD:     equ 0x005F          ; BIOS: change screen mode
CALSLT:     equ 0x001C          ; call a routine in a slot (DOS page 0 entry)
FORCLR:     equ 0xF3E9
BAKCLR:     equ 0xF3EA
BDRCLR:     equ 0xF3EB
GRPNAM:     equ 0xF3C7          ; SCREEN 2 name table
GRPCOL:     equ 0xF3C9          ; SCREEN 2 colour table
GRPCGP:     equ 0xF3CB          ; SCREEN 2 pattern table
F_DEFER:    equ 0x64

INK:        equ 1               ; black
PAPER:      equ 15              ; white

B_TITLE:    equ 0
B_LIST:     equ 2
LISTN:      equ 16
LISTPX:     equ LISTN*8         ; height of the list in pixels
B_SEP1:     equ 18
B_STAT:     equ 19
B_KEYS:     equ 22              ; key line: bands 22 and 23
KEY_SEP:    equ 177             ; pixel rows of the key line area
KEY_CAP0:   equ 179
KEY_CAP1:   equ 186
KEY_TXT:    equ 179
KEY_BOT:    equ 189
ZIPDLG_MIN: equ 64              ; ZIPs with this many entries show "Reading"
TXTCHARS:   equ 41              ; characters per line (x = 4 .. 249)

; dialog box (extraction progress / disk error): pixel rows 48..98 (bands 6..12)
B_DLG:      equ 6
DLG_X0:     equ 30
DLG_X1:     equ 225
DLG_H:      equ 48              ; height without the shadow

; ---- start-up ---------------------------------------------------------------------
ginit:
        ; MSX version, VDP ports, font: from the main ROM
        ld a,(EXPTBL)
        ld hl,0x002D
        call RDSLT
        ld (msxver),a
        ld a,(EXPTBL)
        ld hl,0x0007
        call RDSLT
        ld (vport),a
        ld a,(EXPTBL)
        ld hl,0x0006
        call RDSLT
        ld (vportr),a
        ld a,(EXPTBL)
        ld hl,0x0004            ; CGTABL: address of the font
        call RDSLT
        ld e,a
        push de
        ld a,(EXPTBL)
        ld hl,0x0005
        call RDSLT
        pop de
        ld d,a
        ld hl,0x20*8            ; characters 20h..7Eh
        add hl,de
        ld de,gfont
        ld bc,95*8
gi_fnt: push bc
        push hl
        push de
        ld a,(EXPTBL)
        call RDSLT
        pop de
        pop hl
        pop bc
        ld (de),a
        inc hl
        inc de
        dec bc
        ld a,b
        or c
        jr nz,gi_fnt
        ei
        ; function keys: F1 types KEY_F1, the others nothing (F1 is "color ",
        ; F5 "run" + RETURN... in the DOS: they would act as MG keys)
        ld hl,FNKSTR
        ld de,fnksave
        ld bc,160
        ldir
        ld hl,FNKSTR
        ld de,FNKSTR+1
        ld bc,159
        ld (hl),0
        ldir
        ld a,KEY_F1
        ld (FNKSTR),a
        ld a,KEY_F2
        ld (FNKSTR+16),a
        ld a,KEY_F5
        ld (FNKSTR+64),a
        ; colours, SCREEN 2
        ld hl,FORCLR
        ld de,clrsave
        ld bc,3
        ldir
        ld a,INK
        ld (FORCLR),a
        ld a,PAPER
        ld (BAKCLR),a
        ld (BDRCLR),a
        ld a,2
        call setmode
        ld a,1
        ld (gmode),a
        ; colour table: one value everywhere
        ld hl,(GRPCOL)
        call vsetw
        ld de,6144
        ld a,INK*16+PAPER
gi_col: out (c),a
        nop
        nop
        dec de
        ld b,a
        ld a,d
        or e
        ld a,b
        jr nz,gi_col
        ei
        ; name table: 0..255, three times
        ld hl,(GRPNAM)
        call vsetw
        ld de,768
        xor a
gi_nam: out (c),a
        inc a
        nop
        dec de
        ld b,a
        ld a,d
        or e
        ld a,b
        jr nz,gi_nam
        ei
        ; restore the screen however MG ends, and show disk errors ourselves
        ld de,abort_h
        ld c,F_DEFAB
        call BDOS
        ld de,diskerr_h
        ld c,F_DEFER
        jp BDOS

; A = screen mode, through the BIOS in the main ROM
setmode:
        ld iy,(EXPTBL-1)
        ld ix,CHGMOD
        call CALSLT
        ei
        ret

; back to the text screen and the DOS console (before running a program / exit)
scrreset:
        call gtext
        ld de,0
        ld c,F_DEFAB
        call BDOS
        ld de,0
        ld c,F_DEFER
        call BDOS
        ld hl,esc_curon
        call cputs
        ld a,0x0C
        jp cputc

; text mode with the original colours (no DOS calls: also used on abort)
gtext:
        ld a,(gmode)
        or a
        ret z
        xor a
        ld (gmode),a
        ld hl,fnksave           ; function key strings back
        ld de,FNKSTR
        ld bc,160
        ldir
        ld hl,clrsave
        ld de,FORCLR
        ld bc,3
        ldir
        xor a
        jp setmode

; DOS abort routine (program ends on an error): text screen back
abort_h:
        push af
        push bc
        push de
        push hl
        push ix
        push iy
        call gtext
        pop iy
        pop ix
        pop hl
        pop de
        pop bc
        pop af
        ret

; DOS disk error routine: B = drive. Shows a box, returns 1 = abort, 2 = retry
diskerr_h:
        push bc
        push de
        push hl
        push ix
        push iy
        ld a,b
        add a,"A"
        ld (msg_dskd),a
        ld hl,msg_dske
        ld de,msg_dskk
        ld bc,msg_dskr
        call dlg_msg
de_key: call rawkey
        call toupper
        cp "R"
        ld b,2
        jr z,de_ret
        cp "A"
        ld b,1
        jr z,de_ret
        cp KEY_ESC
        jr nz,de_key
de_ret: ld a,b
        pop iy
        pop ix
        pop hl
        pop de
        pop bc
        ret

; wait for a key without DOS (A = key)
rawkey:
        ld hl,(GETPNT)
        ld de,(PUTPNT)
        or a
        sbc hl,de
        jr z,rawkey
        di
        ld hl,(GETPNT)
        ld a,(hl)
        inc hl
        push af
        push hl
        ld de,KEYBUF+40
        or a
        sbc hl,de
        pop hl
        jr c,rk_nw
        ld hl,KEYBUF
rk_nw:  ld (GETPNT),hl
        pop af
        ei
        ret

; console output (DOS), all registers but A preserved
cputc:
        push hl
        push de
        push bc
        ld e,a
        ld c,F_CONOUT
        call BDOS
        pop bc
        pop de
        pop hl
        ret

cputs:
        ld a,(hl)
        or a
        ret z
        call cputc
        inc hl
        jr cputs

; ---- VDP access ----------------------------------------------------------------------
; set the VDP to write at HL (interrupts off). C = data port on return.
vsetw:
        ld a,(vport)
        inc a
        ld c,a
        di
        ld a,(msxver)
        or a
        jr z,vw_1
        xor a                   ; MSX2 and later: VRAM bits 14-16 = 0
        out (c),a
        ld a,0x8E
        out (c),a
vw_1:   out (c),l
        ld a,h
        and 0x3F
        or 0x40
        out (c),a
        dec c
        ret

; set the VDP to read at HL (interrupts off). C = data port on return.
vsetr:
        ld a,(vportr)
        inc a
        ld c,a
        di
        ld a,(msxver)
        or a
        jr z,vr_1
        xor a
        out (c),a
        ld a,0x8E
        out (c),a
vr_1:   out (c),l
        ld a,h
        and 0x3F
        out (c),a
        dec c
        ret

; HL = VRAM address of band A
bandadr:
        ld h,a
        ld l,0
        ld de,(GRPCGP)
        add hl,de
        ret

; send bbuf to band A
bput:
        call bandadr
        call vsetw
        ld hl,bbuf
        ld b,0
        ld a,(msxver)
        or a
        jr nz,bp_fast
bp_lp:  outi                    ; MSX1 VDP: at least 29 T-states per byte
        nop
        jr nz,bp_lp
        ei
        ret
bp_fast:
        otir                    ; MSX2 and later
        ei
        ret

; read band A into bbuf
bget:
        call bandadr
        call vsetr
        ld hl,bbuf
        ld b,0
        ld a,(msxver)
        or a
        jr nz,bg_fast
bg_lp:  ini
        nop
        jr nz,bg_lp
        ei
        ret
bg_fast:
        inir
        ei
        ret

; ---- drawing into bbuf -----------------------------------------------------------------
bclear:                         ; with PUSH: 2 bytes per 11 T-states
        di
        ld (bc_sp),sp
        ld sp,bbuf+256
        ld hl,0
        ld b,16
bc_lp:  push hl
        push hl
        push hl
        push hl
        push hl
        push hl
        push hl
        push hl
        djnz bc_lp
        ld sp,(bc_sp)
        ei
        ret

; rectangle op on bbuf: pixels rx0..rx1, rows rr0..rr1, rop 0 set / 1 clear / 2 xor
brect:
        ld a,(rx0)
        and 7
        ld e,a
        ld d,0
        ld hl,lmasks
        add hl,de
        ld a,(hl)
        ld (rlm),a
        ld a,(rx1)
        and 7
        ld e,a
        ld hl,rmasks
        add hl,de
        ld a,(hl)
        ld (rrm),a
        ld a,(rx0)
        and 0xF8
        ld (rcol),a             ; offset of the current byte column
        ld a,(rx1)
        and 0xF8
        ld (rlast),a
        ld a,(rlm)
br_col: ld c,a                  ; C = mask of this column
        ld a,(rcol)
        ld hl,rlast
        cp (hl)
        jr nz,br_nl
        ld a,(rrm)
        and c
        ld c,a
br_nl:  ld a,(rr1)
        ld hl,rr0
        sub (hl)
        inc a
        ld b,a                  ; rows
        ld a,(rcol)
        add a,(hl)
        ld l,a
        ld h,BBUFH
        ld a,(rop)
        or a
        jr z,br_set
        dec a
        jr z,br_clr
br_xor: ld a,(hl)
        xor c
        ld (hl),a
        inc l
        djnz br_xor
        jr br_next
br_set: ld a,(hl)
        or c
        ld (hl),a
        inc l
        djnz br_set
        jr br_next
br_clr: ld a,c
        cpl
        ld c,a
br_cl2: ld a,(hl)
        and c
        ld (hl),a
        inc l
        djnz br_cl2
br_next:
        ld a,(rcol)
        ld hl,rlast
        cp (hl)
        ret z
        add a,8
        ld (rcol),a
        ld a,0xFF
        jr br_col

lmasks: db 0xFF,0x7F,0x3F,0x1F,0x0F,0x07,0x03,0x01
rmasks: db 0x80,0xC0,0xE0,0xF0,0xF8,0xFC,0xFE,0xFF

; rect with registers: D = x0, E = x1, H = row0, L = row1, A = op
rect:
        ld (rop),a
        ld a,d
        ld (rx0),a
        ld a,e
        ld (rx1),a
        ld a,h
        ld (rr0),a
        ld a,l
        ld (rr1),a
        jp brect

; rect in pixel rows: D = x0, E = x1, H = y0, L = y1, A = op, clipped to the
; band whose first pixel row is (dy0)
crect:
        ld (rop),a
        ld a,d
        ld (rx0),a
        ld a,e
        ld (rx1),a
        ld a,(dy0)
        ld c,a
        ld a,l
        sub c
        ret c                   ; ends above this band
        cp 8
        jr c,cr_1
        ld a,7
cr_1:   ld (rr1),a
        ld a,h
        sub c
        jr nc,cr_2
        xor a
cr_2:   cp 8
        ret nc                  ; starts below this band
        ld (rr0),a
        jp brect

; text HL at x = A, pixel row D (relative like crect), at most B characters
ctext:
        push af
        ld a,(dy0)
        ld c,a
        ld a,d
        sub c                   ; offset in the band, -7..7 or outside
        cp 8
        jr c,ct_ok
        cp 0xF9
        jr nc,ct_ok
        pop af
        ret
ct_ok:  ld (toff),a
        pop af
        call btext
        push af
        xor a
        ld (toff),a
        pop af
        ret

; frame sides (x = 0 and x = 255) on all 8 rows
bsides:
        ld hl,bbuf
        set 7,(hl)
        inc l
        set 7,(hl)
        inc l
        set 7,(hl)
        inc l
        set 7,(hl)
        inc l
        set 7,(hl)
        inc l
        set 7,(hl)
        inc l
        set 7,(hl)
        inc l
        set 7,(hl)
        ld l,0xF8
        ld b,8
bs_r:   set 0,(hl)
        inc l
        djnz bs_r
        ret

; OR an 8x8 pattern (HL, bit 7 = left) into bbuf at pixel x = A.
; The shift is done by rotating each row (rrca / rlca patched into bl_rot)
; and splitting it with two masks (patched into bl_m1 / bl_m2).
blit8:
        ld c,a
        and 0xF8
        ld e,a
        ld d,BBUFH              ; DE = first byte column
        ld a,c
        and 7
        push hl
        push de
        ld e,a
        ld d,0
        ld hl,lmasks
        add hl,de
        ld a,(hl)
        ld (bl_m1+1),a          ; part in this column
        cpl
        ld (bl_m2+1),a          ; part in the next column
        ex de,hl
        add hl,hl
        add hl,hl
        ld de,rotcode
        add hl,de
        ld de,bl_rot
        ldi
        ldi
        ldi
        ldi
        pop de
        pop hl
        ld a,e
        cp 0xF8
        jr nz,bl_go
        xor a                   ; last column: nothing goes further right
        ld (bl_m2+1),a
bl_go:  ld a,(toff)             ; text above / below the band: only some rows
        ld b,8
        or a
        jr z,bl_row
        jp m,bl_neg
        ld c,a                  ; down: rows start lower in the band
        add a,e
        ld e,a
        ld a,8
        sub c
        ld b,a
        jr bl_row
bl_neg: neg                     ; up: skip the first rows of the pattern
        ld c,a
        add a,l
        ld l,a
        jr nc,bl_n0
        inc h
bl_n0:  ld a,8
        sub c
        ld b,a
bl_row: ld a,(hl)
        inc hl
        or a
        jr z,bl_nx
bl_rot: nop
        nop
        nop
        nop
        ld c,a
bl_m1:  and 0xFF
        ex de,hl
        or (hl)
        ld (hl),a
        ld a,l
        add a,8
        ld l,a
        ld a,c
bl_m2:  and 0x00
        or (hl)
        ld (hl),a
        ld a,l
        sub 8
        ld l,a
        ex de,hl
bl_nx:  inc e
        djnz bl_row
        ret

; rotations for a shift of 0..7 pixels (rrca = 0Fh, rlca = 07h, nop = 0)
rotcode: db 0,0,0,0
         db 0x0F,0,0,0
         db 0x0F,0x0F,0,0
         db 0x0F,0x0F,0x0F,0
         db 0x0F,0x0F,0x0F,0x0F
         db 0x07,0x07,0x07,0
         db 0x07,0x07,0,0
         db 0x07,0,0,0

; text HL at x = A, at most B characters. Returns HL after the text, A = next x.
btext:
        ld (tx),a
bt_lp:  ld a,(hl)
        or a
        jr z,bt_end
        push hl
        push bc
        cp 0x21
        jr c,bt_sp              ; space (and control characters) : nothing
        cp 0x7F
        jr c,bt_ok
        ld a,"?"                ; outside the font
bt_ok:  sub 0x20
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,gfont
        add hl,de
        ld a,(tx)
        call blit8
bt_sp:  ld a,(tx)
        add a,6
        ld (tx),a
        pop bc
        pop hl
        inc hl
        djnz bt_lp
bt_end: ld a,(tx)
        ret

; text HL ending at pixel x = A (right aligned), at most 255 characters
btextr:
        push hl
        push af
        call strlen
        pop af
        pop hl
        ld b,c
        inc c
        dec c
        ret z
        push hl
        inc a
        inc a
bx_lp:  sub 6
        djnz bx_lp
        pop hl
        ld b,255
        jp btext

; ---- whole screen ------------------------------------------------------------------------
drawall:
        call draw_title
        call drawlist
        ld a,B_SEP1
        call draw_sep
        call drawstat
        jp helpline

; horizontal line across the frame on row 4 of band A
draw_sep:
        push af
        call bclear
        call bsides
        ld de,0x00FF
        ld hl,0x0404
        xor a
        call rect
        ld de,0xF6F6            ; scroll bar line down to it (rows 144..147)
        ld hl,0x0003
        xor a
        call rect
        pop af
        jp bput

; title bar: path on the left, number of items on the right, inverted
draw_title:
        ; "N items"
        ld hl,(count)
        ld a,h
        or l
        jr z,dt_cnt
        ld hl,0
        call getent
        ld a,(hl)               ; first entry ".." is not counted
        ld hl,(count)
        cp T_PARENT
        jr nz,dt_cnt
        dec hl
dt_cnt: ld (numtmp),hl
        ld hl,0
        ld (numtmp+2),hl
        ld hl,numtmp
        call u32txt
        ld de,itembuf
        call strcpy
        ld hl,str_items
        call strcpy
        ; path: what is left, keeping the end of long paths -> titbuf
        ld hl,itembuf
        call strlen
        ld a,TXTCHARS-1
        sub c
        ld (proom),a
        call mkhdr
        ld hl,hdrbuf
        call strlen             ; BC = length of the path
        ld de,titbuf
        ld hl,hdrbuf
        ld a,b
        or a
        jr nz,dt_cut
        ld a,(proom)
        cp c
        jr nc,dt_full
dt_cut: push bc
        ld hl,str_dots
        call strcpy
        pop bc
        ld hl,hdrbuf
        add hl,bc               ; end of the path
        ld a,(proom)
        sub 3
        ld c,a
        ld b,0
        or a
        sbc hl,bc
dt_full:
        call strcpy
        ; two bands: text 4 rows down, the bar is rows 0..14
        xor a
        call dt_band
        ld a,1
dt_band:
        push af
        call bclear
        pop af
        push af
        add a,a
        add a,a
        add a,a
        ld c,a
        ld a,4
        sub c
        ld (toff),a             ; 4 for band 0, -4 for band 1
        ld hl,titbuf
        ld a,4
        ld b,TXTCHARS
        call btext
        ld hl,itembuf
        ld a,251
        call btextr
        xor a
        ld (toff),a
        pop af
        push af
        ld hl,0x0007
        or a
        jr z,dt_inv
        ld hl,0x0006            ; row 15 stays as a gap
dt_inv: ld de,0x00FF
        ld a,2
        call rect
        pop af
        push af
        or a
        jr z,dt_put
        ; gap row 15: frame sides and the scroll bar line go on up to the bar
        ld de,0x0000
        call dt_gap
        ld de,0xF6F6
        call dt_gap
        ld de,0xFFFF
        call dt_gap
dt_put: pop af
        add a,B_TITLE
        jp bput
dt_gap: ld hl,0x0707
        xor a
        jp rect

; hdrbuf = path shown in the title
mkhdr:
        ld a,(zipmode)
        or a
        jr nz,mh_zip
        ld hl,0
        call mkfull
        ld hl,pathbuf
        ld de,hdrbuf
        jp strcpy
mh_zip:
        ld hl,zipfile
        ld de,hdrbuf
        call strcpy
        ld a,"/"
        ld (de),a
        inc de
        ld hl,zipdir
        jp strcpy

; ---- list ----------------------------------------------------------------------------
drawlist:
        call thumb
        xor a
dl_lp:  push af
        call draw_row
        pop af
        inc a
        cp LISTN
        jr c,dl_lp
        ret

; draw the list row of entry index HL (if visible)
drawline:
        ld de,(top)
        or a
        sbc hl,de
        ret c
        ld a,h
        or a
        ret nz
        ld a,l
        cp LISTN
        ret nc
        jp draw_row

; scroll bar thumb: thy0 .. thy1 (pixel rows of the list)
thumb:
        ld hl,(count)
        ld de,LISTN+1
        or a
        sbc hl,de
        jr nc,th_some
        ld a,0xFF               ; everything fits: no thumb
        ld (thy0),a
        xor a
        ld (thy1),a
        ret
th_some:
        ld a,(LISTPX*LISTN>>8)&0xFF     ; height = LISTPX * LISTN / count
        ld c,LISTPX*LISTN&0xFF
        ld de,(count)
        call div_ac_de
        ld a,c
        cp 6
        jr nc,th_h
        ld a,6
th_h:   ld (thh),a
        ; top = (LISTPX - h) * top / (count - LISTN)
        ld b,a
        ld a,LISTPX
        sub b
        ld hl,(top)
        call mul_a_hl           ; C:HL = product
        ld de,(count)
        push hl
        ld hl,0-LISTN
        add hl,de
        ex de,hl                ; DE = count - LISTN
        pop hl
th_sc:  ld a,c                  ; scale down until the product fits 16 bits
        or a
        jr z,th_dv
        srl c
        rr h
        rr l
        srl d
        rr e
        jr th_sc
th_dv:  ld a,h
        ld c,l
        call div_ac_de          ; AC = quotient
        ld a,c
        ld (thy0),a
        ld hl,thh
        add a,(hl)
        dec a
        ld (thy1),a
        ret

; C:HL = A * HL
mul_a_hl:
        ex de,hl
        ld hl,0
        ld c,0
        ld b,8
ma_lp:  add hl,hl
        rl c
        rla
        jr nc,ma_n
        add hl,de
        jr nc,ma_n
        inc c
ma_n:   djnz ma_lp
        ret

; AC = AC / DE, HL = remainder
div_ac_de:
        ld hl,0
        ld b,16
dv_l:   db 0xCB,0x31            ; sll c (shift left, bit 0 = 1)
        rla
        adc hl,hl
        sbc hl,de
        jr nc,dv_n
        add hl,de
        dec c
dv_n:   djnz dv_l
        ret

; list row A (0 .. LISTN-1)
draw_row:
        ld (drow),a
        call bclear
        call bsides
        ld de,0xF6F6            ; scroll bar lane
        ld hl,0x0007
        xor a
        call rect
        ; part of the thumb in this row
        ld a,(drow)
        add a,a
        add a,a
        add a,a
        ld b,a                  ; first pixel row of this band
        ld a,(thy1)
        cp b
        jr c,dr_nth
        ld a,b
        add a,7
        ld hl,thy0
        cp (hl)
        jr c,dr_nth
        ld a,(thy0)             ; r0 = max(thy0, b) - b
        sub b
        jr nc,dr_r0
        xor a
dr_r0:  ld h,a
        ld a,(thy1)
        sub b
        cp 8
        jr c,dr_r1
        ld a,7
dr_r1:  ld l,a
        ld de,0xF8FC
        xor a
        call rect
dr_nth:
        ; entry
        ld a,(drow)
        ld e,a
        ld d,0
        ld hl,(top)
        add hl,de
        ld (dl_idx),hl
        ld de,(count)
        or a
        sbc hl,de
        jp nc,dr_out
        ld hl,(dl_idx)
        call getent
        ld (drec),hl
        ld a,(hl)
        push af
        call entname
        ld (dname),hl
        pop af
        ld de,ic_up
        cp T_PARENT
        jr z,dr_icon
        ld de,ic_dir
        cp T_DIR
        jr z,dr_icon
        call getext             ; 1 COM, 2 BAT, 3 ROM, 4 ZIP
        ld de,ic_file
        or a
        jr z,dr_icon
        dec a
        add a,a
        add a,a
        add a,a
        ld l,a
        ld h,0
        ld de,ic_com
        add hl,de
        ex de,hl
dr_icon:
        ex de,hl
        ld a,4
        call blit8
        ; name: 29 characters, or 26 and "..."
        ld hl,(dname)
        call strlen
        ld hl,(dname)
        ld a,b
        or a
        jr nz,dr_long
        ld a,c
        cp 30
        jr c,dr_fit
dr_long:
        ld a,14
        ld b,26
        call btext
        ld hl,str_dots
        ld b,3
        call btext
        jr dr_size
dr_fit: ld a,14
        ld b,29
        call btext
dr_size:
        ld hl,(drec)
        ld a,(hl)
        cp T_FILE
        jr z,dr_num
        ld hl,str_updir
        cp T_PARENT
        jr z,dr_tag
        ld hl,str_dir
        jr dr_tag
dr_num: ld de,E_SIZE
        add hl,de
        call u32txt
dr_tag: ld a,242
        call btextr
        ; selected: inverted bar
        ld hl,(dl_idx)
        ld de,(sel)
        or a
        sbc hl,de
        jr nz,dr_out
        ld de,0x01F5
        ld hl,0x0007
        ld a,2
        call rect
dr_out: ld a,(drow)
        add a,B_LIST
        jp bput

; HL = 4-byte number -> HL = its digits (no leading spaces)
u32txt:
        call u32dec
        ld hl,numbuf
ut_sp:  ld a,(hl)
        cp 0x20
        ret nz
        inc hl
        jr ut_sp

; ---- details of the selection ---------------------------------------------------------------
; statmsg = name of the selection, shown on up to 3 lines of 41 characters
updstat0:
        ld hl,(count)
        ld a,h
        or l
        ld hl,str_empty
        jr z,us_set
        ld hl,(sel)
        call getent
        call entname            ; the name of the selection (full, long names too)
us_set: ld (statmsg),hl
        ret

defstatus:
        ld hl,str_empty
        ld (statmsg),hl
        ret

setstatus:
        ld (statmsg),hl
drawstat:
        ld hl,(statmsg)
        ld a,B_STAT
        call ds_line
        ld a,B_STAT+1
        call ds_line
        ; third line: if the text goes on after it, end it with "..."
        push hl
        call strlen
        pop hl
        ld a,b
        or a
        jr nz,ds_cut
        ld a,c
        cp TXTCHARS+1
        jr c,ds_3
ds_cut: ld a,TXTCHARS-3
        ld (ds_n),a
        ld a,B_STAT+2
        push af
        push hl
        call bclear
        call bsides
        pop hl
        ld a,(ds_n)
        ld b,a
        ld a,4
        call btext
        ld hl,str_dots
        ld b,3
        call btext
        pop af
        jp bput
ds_3:   ld a,B_STAT+2
ds_line:
        push af
        push hl
        call bclear
        call bsides
        pop hl
        ld a,4
        ld b,TXTCHARS
        call btext
        pop af
        push hl
        call bput
        pop hl
        ret

; ---- key line ------------------------------------------------------------------------------
; HL = message, shown for about 2 seconds or until a key is pressed
msgshow:
        ld a,1
        jr msgset
; HL = question, shown until a key is pressed
msgprompt:
        ld a,2
msgset: ld (msgon),a
        ld (keymsg),hl
        call keyline
        ld hl,(JIFFY)
        ld (msgt0),hl
        ret

; key caps: inverted key name, then what it does
helpline:
        xor a
        ld (msgon),a
        ld hl,0
        ld (keymsg),hl
; draw bands 22 and 23: line, keys or message (keymsg), bottom of the frame
keyline:
        ld a,B_KEYS
        call kl_band
        ld a,B_KEYS+1
kl_band:
        ld (kl_b),a
        add a,a
        add a,a
        add a,a
        ld (dy0),a
        call bclear
        ld de,0x0000            ; sides down to the bottom edge
        ld hl,(KEY_SEP-8)*256+KEY_BOT
        xor a
        call crect
        ld de,0xFFFF
        ld hl,(KEY_SEP-8)*256+KEY_BOT
        xor a
        call crect
        ld de,0x00FF            ; line above, bottom edge
        ld hl,KEY_SEP*256+KEY_SEP
        xor a
        call crect
        ld de,0x00FF
        ld hl,KEY_BOT*256+KEY_BOT
        xor a
        call crect
        ld hl,(keymsg)
        ld a,h
        or l
        jr z,kl_caps
        ld a,4                  ; message
        ld d,KEY_TXT
        ld b,TXTCHARS
        call ctext
        jp kl_put
kl_caps:
        ld a,KEY_TXT
        ld (kc_y),a
        ld a,4
        ld (kc_gap),a
        ld a,(kinact)           ; behind the editor: caps not inverted
        or a
        ld a,2
        jr z,klc_1
        ld a,0xFF
klc_1:  ld (kc_op),a
        ld hl,keycaps
        ld a,4
        call capsrow
kl_put: ld a,(kl_b)
        jp bput

; ---- built-in editor ---------------------------------------------------------------------
; MGED.ASM, assembled to run at OVB and appended to MG.COM (see BUILD.PY), is
; read from MG.COM into the list memory when a text file is opened.
; Entry points: OVB+0 a file of the directory, +3 a file from the ZIP,
; +10 delete, +13 rename, +16 run a .COM from MGRUNn.BAT.
ED_FOFS:    equ prog_end-0x100   ; where it is in MG.COM
ED_MAX:     equ 0x1400           ; most bytes read
edl_dos:ld hl,(selname)         ; selected again when the editor closes
        ld de,lastname
        call strcpy
        xor a
        jr edl_go
edl_zip:ld a,3
edl_go: ld (edl_ent),a
        ld a,1
        ld (listbad),a          ; the list memory is used now
        call edl_load
        jr c,edl_err
        ld hl,OVB
        ld a,(edl_ent)
        ld e,a
        ld d,0
        add hl,de
        jp (hl)
edl_err:ld (errmsg),hl
        jp reload_err
; -> NC loaded, C and HL = message
edl_load:
        ld hl,env_program       ; the path of MG.COM
        ld de,pathbuf
        ld b,160
        ld c,F_GENV
        call BDOS
        or a
        jr nz,edl_bad
        ld a,(pathbuf)
        or a
        jr z,edl_bad
        ld de,pathbuf
        ld a,1
        ld c,F_OPEN
        call BDOS
        or a
        jr nz,edl_bad
        ld a,b
        ld (edl_fh),a
        ld hl,ED_FOFS
        ld de,0
        xor a
        ld c,F_SEEK
        call BDOS
        ld a,(edl_fh)
        ld b,a
        ld de,OVB
        ld hl,ED_MAX
        ld c,F_READ
        call BDOS
        ld a,(edl_fh)
        ld b,a
        ld c,F_CLOSE
        call BDOS
        ld hl,OVB+6             ; "MGED"?
        ld de,str_mged
        ld b,4
edl_ck: ld a,(de)
        cp (hl)
        jr nz,edl_bad
        inc hl
        inc de
        djnz edl_ck
        or a
        ret
edl_bad:ld hl,msg_noedit
        scf
        ret

; key caps: HL = list (name, 0, label, 0, ..., 0), A = x, text row (kc_y);
; caps drawn with op (kc_op) (0xFF: not inverted), (kc_gap) after each label
capsrow:
cw_lp:  ld (tx2),a
        ld a,(hl)
        or a
        ret z
        push hl
        call strlen             ; width of the key name
        pop hl
        ld b,c
        ld a,(kc_y)
        ld d,a
        ld a,(tx2)
        inc a
        inc a
        push bc
        call ctext              ; key name
        pop bc
        push hl
        dec a
        ld (kl_x1),a            ; cap from x .. x + 6 * len + 1
        ld e,a
        ld a,(tx2)
        ld d,a
        ld a,(kc_y)
        ld h,a
        add a,7
        ld l,a
        ld a,(kc_op)
        cp 0xFF
        call nz,crect
        pop hl
        inc hl                  ; skip the 0
        ld a,(kc_y)
        ld d,a
        ld a,(kl_x1)
        add a,4
        ld b,255
        call ctext              ; label
        inc hl
        ld b,a
        ld a,(kc_gap)
        add a,b
        jr cw_lp

; text HL ending at pixel x = A, pixel row D (clipped like ctext)
ctextr:
        push af
        ld a,(dy0)
        ld c,a
        ld a,d
        sub c
        cp 8
        jr c,ctr_ok
        cp 0xF9
        jr nc,ctr_ok
        pop af
        ret
ctr_ok: ld (toff),a
        pop af
        call btextr
        xor a
        ld (toff),a
        ret

; ---- dialog box ----------------------------------------------------------------------
; Drawn band by band (bands under the box are read back from VRAM, so the
; list stays visible); everything is given in pixel rows of the box and
; clipped to the band.
;   rows 0..14  title bar (dlg_t1)       row 20  text (dlg_t2)
;   rows 32..39 progress bar (dlg_bar) or text (dlg_t3)
;   row 47      bottom edge, then 3 rows of shadow
dlg_band:
        ld (dlg_b),a
        add a,a
        add a,a
        add a,a
        ld (dy0),a
        ld a,(dlg_b)
        add a,B_DLG
        call bget
        ld de,DLG_X0*256+DLG_X1         ; inside
        ld hl,DLG_H-1
        ld a,1
        call crect
        ld de,(DLG_X1+1)*256+DLG_X1+3   ; shadow
        ld hl,3*256+DLG_H+2
        xor a
        call crect
        ld de,(DLG_X0+3)*256+DLG_X1+3
        ld hl,DLG_H*256+DLG_H+2
        xor a
        call crect
        ld hl,(dlg_t1)                  ; title bar: text, then inverted
        ld a,DLG_X0+6
        ld d,4
        ld b,30
        call ctext
        ld de,DLG_X0*256+DLG_X1
        ld hl,14
        ld a,2
        call crect
        ld de,DLG_X0*256+DLG_X0         ; sides and bottom edge
        ld hl,15*256+DLG_H-1
        xor a
        call crect
        ld de,DLG_X1*256+DLG_X1
        ld hl,15*256+DLG_H-1
        xor a
        call crect
        ld de,DLG_X0*256+DLG_X1
        ld hl,(DLG_H-1)*256+DLG_H-1
        xor a
        call crect
        ld hl,(dlg_t2)                  ; first line
        ld a,DLG_X0+8
        ld d,20
        ld b,30
        call ctext
        ld a,(dlg_b)                    ; second line / bar: band 4 only
        cp 4
        jp nz,db_put
        ld a,(dlg_bar)
        or a
        jr nz,db_bar
        ld hl,(dlg_caps)
        ld a,h
        or l
        jr nz,db_caps
        ld hl,(dlg_t3)
        ld a,DLG_X0+8
        ld b,30
        call btext
        jp db_put
db_caps:ld a,32                         ; keys to press, as caps
        ld (kc_y),a
        ld a,2
        ld (kc_op),a
        ld a,10
        ld (kc_gap),a
        ld a,DLG_X0+8
        call capsrow
        jp db_put
db_bar: ; progress bar: box, filled part, percentage
        ld de,(DLG_X0+8)*256+DLG_X1-40
        ld hl,0x0007
        xor a
        call rect
        ld de,(DLG_X0+9)*256+DLG_X1-41
        ld hl,0x0106
        ld a,1
        call rect
        ld a,(lastpct)
        ld b,a
        ld a,DLG_X1-41-DLG_X0-9-2       ; inside width
        ld hl,0
        ld e,a
        ld d,0
dp_m:   ld a,b                          ; width * pct / 100
        or a
        jr z,dp_d
        add hl,de
        dec b
        jr dp_m
dp_d:   ld a,h
        ld c,l
        ld de,100
        call div_ac_de
        ld a,c
        or a
        jr z,dp_txt
        add a,DLG_X0+9
        ld e,a
        ld d,DLG_X0+10
        ld hl,0x0205
        xor a
        call rect
dp_txt: ld hl,pctbuf
        ld a,DLG_X1-8
        call btextr
db_put: ld a,(dlg_b)
        add a,B_DLG
        jp bput

dlg_all:
        xor a
da_lp:  push af
        call dlg_band
        pop af
        inc a
        cp 7
        jr c,da_lp
        ret

; box with title HL and lines DE, BC (no bar)
dlg_msg:
        ld (dlg_t1),hl
        ld (dlg_t2),de
        ld (dlg_t3),bc
        ld hl,0
        ld (dlg_caps),hl
        xor a
        ld (dlg_bar),a
        jr dlg_all

; box with title HL, line DE and key caps BC (keys, labels as in keycaps)
dlg_ask:
        ld (dlg_t1),hl
        ld (dlg_t2),de
        ld (dlg_caps),bc
        xor a
        ld (dlg_bar),a
        jp dlg_all

; "Reading" box for a big ZIP
zread_box:
        ld a,1
        ld (zshow),a
        ld hl,str_read
        ld (dlg_t1),hl
        ld hl,zipfile
        ld (dlg_t2),hl
        ld a,1
        ld (dlg_bar),a
        xor a
        ld (lastpct),a
        call pct_txt
        jp dlg_all

; percentage of the central directory read so far
zread_pct:
        ld hl,(ztotal)
        ld de,(zleft)
        or a
        sbc hl,de               ; done
        ld de,(ztotal)
        call percent
        ld hl,lastpct
        cp (hl)
        ret z
        jp prog_bar

; A = HL * 100 / DE
percent:
        push de
        ld a,100
        call mul_a_hl           ; C:HL
        pop de
pc_sc:  ld a,c
        or a
        jr z,pc_dv
        srl c
        rr h
        rr l
        srl d
        rr e
        jr pc_sc
pc_dv:  ld a,d
        or e
        ld a,100
        ret z
        ld a,h
        ld c,l
        call div_ac_de
        ld a,c
        ret

; extraction box: "Extracting", "to <tmppath>", bar at 0 %
prog_box:
        ld hl,str_extr0
        ld (dlg_t1),hl
        ld de,statbuf
        ld hl,str_to
        call strcpy
        ld hl,tmppath
        call strcpy
        ld hl,statbuf
        ld (dlg_t2),hl
        ld a,1
        ld (dlg_bar),a
        xor a
        ld (lastpct),a
        call pct_txt
        jp dlg_all

; new percentage A: redraw the bar
prog_bar:
        ld (lastpct),a
        call pct_txt
        ld a,4                  ; the band with the bar
        jp dlg_band

; pctbuf = "n%"
pct_txt:
        ld a,(lastpct)
        ld l,a
        ld h,0
        ld (numtmp),hl
        ld hl,0
        ld (numtmp+2),hl
        ld hl,numtmp
        call u32txt
        ld de,pctbuf
        call strcpy
        ld a,"%"
        ld (de),a
        inc de
        xor a
        ld (de),a
        ret

; ---- icons (8 x 8, bit 7 = left) -------------------------------------------------------------
ic_up:   db 0x10,0x38,0x7C,0x10,0x10,0x1E,0x00,0x00
ic_dir:  db 0x00,0xE0,0x9E,0x81,0x81,0x81,0xFF,0x00
ic_file: db 0xF8,0x8C,0x86,0x81,0x81,0x81,0xFF,0x00
ic_com:  db 0xFF,0x81,0xA1,0x91,0xA6,0x81,0xFF,0x00
ic_bat:  db 0xFC,0x86,0xBA,0x81,0xBD,0x81,0xFF,0x00
ic_rom:  db 0x7E,0x81,0xBD,0xBD,0x81,0xA9,0xFF,0x00
ic_zip:  db 0x7E,0x91,0x91,0xB9,0xA9,0xB9,0xFF,0x00
ic_dsk:  db 0xFE,0xB9,0xB9,0x81,0xBD,0xBD,0xFF,0x00
ic_bas:  db 0xFF,0xB1,0xA9,0xB1,0xA9,0xB1,0xFF,0x00
ic_txt:  db 0xF8,0x8C,0x86,0xBD,0x81,0xBD,0xFF,0x00
ic_cfg:  db 0x54,0x7C,0xC6,0x44,0xC6,0x7C,0x54,0x00
ic_ini:  db 0x54,0x7C,0xC6,0x44,0xC6,0x7C,0x54,0x00

keycaps: dm "F1"
         db 0
         dm "Help"
         db 0,0

; ==========================================================================
;  Helpers
; ==========================================================================

; wait for a key. Keys typed while the screen was being redrawn are
; dropped, so held cursor keys do not run on after release.
getkey:
        di
        ld hl,(PUTPNT)
        ld (GETPNT),hl
        ei
gk_wait:
        ld a,(msgon)            ; a timed message: back to the key help?
        dec a
        jr nz,gk_poll
        ld hl,(JIFFY)
        ld de,(msgt0)
        or a
        sbc hl,de
        ld de,MSGTIME
        or a
        sbc hl,de
        call nc,helpline
gk_poll:
        call f1down             ; F1 held (in case its string is not typed)
        ld a,KEY_F1
        ret z
        ld hl,(GETPNT)
        ld de,(PUTPNT)
        or a
        sbc hl,de
        jr z,gk_wait
        ld a,(msgon)            ; a key removes the message
        or a
        call nz,helpline
        ld c,F_DIRIN
        jp BDOS

; Z if F1 is held (keyboard matrix row 6, bit 5; Shift+F1 = F6 too)
f1down:
        di
        in a,(0xAA)
        and 0xF0
        or 6
        out (0xAA),a
        in a,(0xA9)
        ei
        and 0x20
        ret

toupper:
        cp "a"
        ret c
        cp "z"+1
        ret nc
        sub 0x20
        ret

; copy ASCIIZ HL -> DE, DE ends on the terminator
strcpy:
        ld a,(hl)
        ld (de),a
        or a
        ret z
        inc hl
        inc de
        jr strcpy

; HL -> terminating 0 of ASCIIZ HL
strend:
        ld a,(hl)
        or a
        ret z
        inc hl
        jr strend

; BC = length of ASCIIZ HL
strlen:
        ld bc,0
sl_lp:  ld a,(hl)
        or a
        ret z
        inc hl
        inc bc
        jr sl_lp

; compare ASCIIZ HL and DE, Z if equal
strcmp:
        ld a,(de)
        cp (hl)
        ret nz
        or a
        ret z
        inc hl
        inc de
        jr strcmp

; case-insensitive compare, Z if equal (HL = text, DE = upper-case key)
strcmpi:
        ld a,(hl)
        call toupper
        ld c,a
        ld a,(de)
        cp c
        ret nz
        or a
        ret z
        inc hl
        inc de
        jr strcmpi

; 32-bit little endian number at HL -> numbuf, right aligned, 10 chars
u32dec:
        ld de,numtmp
        ld bc,4
        ldir
        ld hl,numbuf
        ld b,10
ud_sp:  ld (hl),0x20
        inc hl
        djnz ud_sp
        ld (hl),0
        ld de,(numtmp+2)        ; below 65536: subtract powers of ten
        ld a,d
        or e
        jr nz,ud_dig
        ld hl,(numtmp)
        ld de,numbuf+5
        ld ix,pow10
        ld c,0                  ; C = a digit has been written
u16_p:  ld a,(ix+0)
        or (ix+1)
        jr z,u16_last
        push de
        ld e,(ix+0)
        ld d,(ix+1)
        ld b,0
u16_s:  or a
        sbc hl,de
        jr c,u16_u
        inc b
        jr u16_s
u16_u:  add hl,de
        pop de
        ld a,b
        or c
        jr z,u16_n              ; leading zero stays a space
        ld a,b
        add a,"0"
        ld (de),a
        ld c,1
u16_n:  inc de
        inc ix
        inc ix
        jr u16_p
u16_last:
        ld a,l
        add a,"0"
        ld (de),a
        ret
pow10:  dw 10000,1000,100,10,0
ud_dig:
        push hl
        call div10
        pop hl
        dec hl
        add a,"0"
        ld (hl),a
        ld a,(numtmp)
        ld de,(numtmp+1)
        or d
        or e
        ld de,numtmp+3
        ld c,a
        ld a,(de)
        or c
        jr nz,ud_dig
        ret

; numtmp (32 bit) /= 10, A = remainder
div10:
        ld hl,numtmp+3
        ld b,4
        xor a
dv_byte:
        ld c,(hl)
        push bc
        ld b,8
dv_bit: sla c
        rla
        cp 10
        jr c,dv_nos
        sub 10
        inc c
dv_nos: djnz dv_bit
        ld (hl),c
        pop bc
        dec hl
        djnz dv_byte
        ret

; ==========================================================================
;  Data
; ==========================================================================
msg_nodos2:  dm "MB requires MSX-DOS2 (or Nextor)."
             db 13,10,0x24
msg_lowmem:  dm "Not enough memory (TPA) for MG."
             db 13,10,0x24
str_help:    dm "RET:Run BS:Up D:Drv L:Ldr ESC:Quit"
             db 0
str_dir:     dm "     <DIR>"
             db 0
str_updir:   dm "      <UP>"
             db 0
str_wild:    dm "*.*"
             db 0
str_dotdot:  dm ".."
             db 0
str_defarg:  dm "%F"
             db 0
str_cfgext:  dm ".CFG"
             db 0
str_cfgname: dm "MB.CFG"
             db 0
str_crlf:    db 13,10,0
str_items:   dm " items"
             db 0
str_tilde:   dm "~"
             db 0
str_extr0:   dm "Extracting"
             db 0
str_read:    dm "Reading"
             db 0
str_to:      dm "to "
             db 0
msg_dske:    dm "Disk error"
             db 0
msg_dskk:    dm "Drive "
msg_dskd:    dm "A"
             db 0x3A
             db 0
msg_dskr:    dm "R = retry    A = abort"
             db 0
key_ldr:     dm "ROMLDR"
             db 0
key_arg:     dm "ROMARG"
             db 0
key_eq:      dm "="
             db 0
key_tmp:     dm "TMPDIR"
             db 0
key_start:   dm "STARTDIR"
             db 0
key_dldr:    dm "DSKLDR"
             db 0
key_darg:    dm "DSKARG"
             db 0
key_ed:      dm "EDITOR"
             db 0
key_edarg:   dm "EDITARG"
             db 0
env_program: dm "PROGRAM"
             db 0
env_params:  dm "PARAMETERS"
             db 0
ext_com:     dm "COM"
             db 0
             dm "BAT"
             db 0
ext_rom:     dm "ROM"
             db 0
             dm "ZIP"
             db 0
ext_dsk:     dm "DSK"
             db 0
ext_bas:     dm "BAS"
             db 0
ext_txt:     dm "TXT"
             db 0
ext_cfg:     dm "CFG"
             db 0
ext_ini:     dm "INI"
             db 0
str_basic:   dm "BASIC "
str_none:    db 0
str_ver:     dm "MG version 1.5"    ; version (F1 box, kept in the .COM file)
             db 0
str_about:   dm "About MG"
             db 0
str_keys:    dm "Keys"
             db 0
str_batq:    dm "Run it or edit it?"
             db 0
recaps:      dm "R"
             db 0
             dm "Run"
             db 0
             dm "E"
             db 0
             dm "Edit"
             db 0
             dm "ESC"
             db 0
             dm "Cancel"
             db 0,0
str_mbcom:   dm "MB.COM"
             db 0
str_mgcom:   dm "MG.COM"
             db 0
helptab:     dm "RET"
             db 0
             dm "Run / open"
             db 0
             dm "UP DOWN"
             db 0
             dm "Select"
             db 0
             dm "LEFT RIGHT"
             db 0
             dm "Page"
             db 0
             dm "HOME"
             db 0
             dm "First item"
             db 0
             dm "BS"
             db 0
             dm "Up a directory"
             db 0
             dm "D"
             db 0
             dm "Drive"
             db 0
             dm "DEL"
             db 0
             dm "Delete"
             db 0
             dm "F2"
             db 0
             dm "Rename"
             db 0
             dm "F5"
             db 0
             dm "Version"
             db 0
             dm "ESC"
             db 0
             dm "Quit"
             db 0
             dm "Q"
             db 0
             dm "Quit, stay here"
             db 0,0
str_desc:    dm "MSX-DOS2 file browser"
             db 0
fnksave:     ds 160                 ; function key strings of the DOS
esc_curoff:  db KEY_ESC
             dm "x5"
             db 0
esc_curon:   db KEY_ESC
             dm "y5"
             db 0
probe_seq:   db KEY_ESC
             dm "Y"
             db 0x20,0x20
             dm "#"
             db KEY_ESC
             dm "Y"
             db 0x21,0x20
             dm "#"
             db 0
msg_trunc:   dm "Too many entries - list truncated"
             db 0
msg_cderr:   dm "Cannot enter directory"
             db 0
msg_notexe:  dm "Not an executable file"
             db 0
msg_noldr:   dm "No ROM loader (ROMLDR in the .CFG)"
             db 0
msg_nodsk:   dm "No DSK launcher (DSKLDR in the .CFG)"
             db 0
msg_noedit:  dm "Cannot load the editor from MG.COM"
             db 0
msg_inzip:   dm "Not inside a ZIP"
             db 0
msg_self:    dm "MB.COM / MG.COM: not from here"
             db 0
str_mged:    dm "MGED"
msg_openerr: dm "Cannot open file"
             db 0
msg_drive:   dm "Drive (A-H)? "
             db 0
msg_baddrv:  dm "Invalid drive"
             db 0
msg_badzip:  dm "Not a valid ZIP file"
             db 0
msg_zipexe:  dm "Can't open this type from a ZIP"
             db 0
msg_nomem:   dm "Not enough memory to extract"
             db 0
msg_crypt:   dm "Encrypted ZIP entries not supported"
             db 0
msg_method:  dm "Unsupported compression method"
             db 0
msg_zdata:   dm "ZIP data error"
             db 0
msg_tmperr:  dm "Cannot create temp file (TMPDIR)"
             db 0
msg_wrerr:   dm "Disk write error (disk full?)"
             db 0
str_extr:    dm "Extracting to "
             db 0
str_extr2:   dm "Extracting "
             db 0
msg_nostart: dm "STARTDIR not found"
             db 0
str_reuse:   dm "Using "
             db 0
sig_local:   db 0x50,0x4B,3,4
msg_deep:    dm "Path inside ZIP too long"
             db 0
str_dots:    dm "..."
str_empty:   db 0
zero4:       db 0,0,0,0
sig_eocd:    db 0x50,0x4B,5,6
sig_cdir:    db 0x50,0x4B,1,2
gaps:        dw 364,121,40,13,4,1,0

; ---- variables (initialised to 0 in the file) ---------------------------------
scrw:        db 0
scrh:        db 0
lrows:       db 0
origdrv:     db 0
truncflg:    db 0
fhandle:     db 0
count:       dw 0
sel:         dw 0
oldsel:      dw 0
top:         dw 0
selname:     dw 0
statmsg:     dw 0
dl_idx:      dw 0
gap:         dw 0
si:          dw 0
sj:          dw 0
sjg:         dw 0
stmp:        dw 0
mf_start:    dw 0
mf_end:      dw 0
cl_last:     dw 0
numtmp:      db 0,0,0,0
namew:       db 0
vmode:       db 0
msxver:      db 0
vport:       db 0
vportr:      db 0
vstride:     db 0
vx:          db 0
vy:          db 0
vorg:        dw 0
vaddr:       dw 0
gmode:       db 0
toff:        db 0
dy0:         db 0
bc_sp:       dw 0
clrsave:     db 0,0,0
rx0:         db 0
rx1:         db 0
rr0:         db 0
rr1:         db 0
rop:         db 0
rlm:         db 0
rrm:         db 0
rcol:        db 0
rlast:       db 0
bl_s:        db 0
tx:          db 0
tx2:         db 0
proom:       db 0
drow:        db 0
drec:        dw 0
dname:       dw 0
thy0:        db 0
thy1:        db 0
thh:         db 0
dlg_b:       db 0
dlg_bar:     db 0
dlg_t1:      dw 0
dlg_t2:      dw 0
dlg_t3:      dw 0
keymsg:      dw 0
kl_b:        db 0
kl_x1:       db 0
ds_n:        db 0
zshow:       db 0
ztotal:      dw 0
itembuf:     ds 20
pctbuf:      db 0,0,0,0,0,0
invon:       db 0
fontmod:     db 0
fi_c:        db 0
fibuf:       db 0,0,0,0,0,0,0,0
msgon:       db 0
msgt0:       dw 0
pendmsg:     dw 0
lptr:        dw 0
zipmode:     db 0
zhandle:     db 0
errmsg:      dw 0
poolptr:     dw 0
ae_type:     db 0
ae_attr:     db 0
ae_name:     dw 0
ae_size:     dw 0
zsize:       db 0,0,0,0
ztail:       dw 0
zleft:       dw 0
znlen:       dw 0
listbad:     db 0
xtype:       db 0
zhopen:      db 0
ohopen:      db 0
ohandle:     db 0
ik:          db 0
lastpct:     db 0
pdone:       db 0,0,0,0
ptot:        db 0,0,0,0
ieof:        db 0
ip:          dw 0
iend:        dw 0
ilim:        dw 0
k_len:       db 0
k_step:      db 0
k_first:     dw 0
k_index:     dw 0
k_cnt:       dw 0
k_k:         dw 0
k_code:      dw 0
k_si:        dw 0
k_sym:       dw 0
lastblk:     db 0
dc_len:      db 0
dy_val:      db 0
infl_sp:     dw 0
xofs:        db 0,0,0,0
xmeth:       dw 0
xflags:      dw 0
xsize:       db 0,0,0,0
xcrc:        db 0,0,0,0
rr_ldr:      dw 0
rb_pfx:      dw 0
chandle:     db 0
ccok:        db 0
outtot:      db 0,0,0,0
remain:      db 0,0,0,0
outptr:      dw 0
c_len:       dw 0
c_n:         dw 0
c_cnt:       dw 0
c_sym:       dw 0
nlen:        dw 0
ndist:       dw 0
ntot:        dw 0
dy_idx:      dw 0
zr_pos:      dw 0
zr_len:      dw 0

dlg_caps:    dw 0
kc_y:        db 0
kc_op:       db 2
kc_gap:      db 4
kinact:      db 0
edl_ent:     db 0
rbatch:      db 0               ; 1 / 2: MG was started from MGRUN1 / MGRUN2.BAT
hb_y:        db 0
hb_x1:       db 0
hb_p:        dw 0
edl_fh:      db 0
prog_end:

; ---- uninitialised buffers (not part of the .COM file) ------------------------
origcwd:     equ prog_end           ; 64
cwdbuf:      equ origcwd+64         ; 64
lastname:    equ cwdbuf+64          ; 256
cfgpath:     equ lastname+256       ; 128
ldrpath:     equ cfgpath+128        ; 80
ldrargs:     equ ldrpath+80         ; 64
dskpath:     equ ldrargs+64         ; 80   DSKLDR
dskargs:     equ dskpath+80         ; 64   DSKARG
edpath:      equ dskargs+64         ; 80   EDITOR
edargs:      equ edpath+80          ; 64   EDITARG
statbuf:     equ edargs+64          ; 112
numbuf:      equ statbuf+112        ; 12
gfont:       equ numbuf+12          ; 760  font 20h..7Eh from the main ROM
bbuf:        equ (gfont+760+255)&0xFF00 ; 256  one 8-pixel band, page aligned
BBUFH:       equ (bbuf>>8)&0xFF
iobuf:       equ bbuf+256           ; 320
zipfile:     equ iobuf+320          ; 128
zipdos:      equ zipfile+128        ; 16
zipdir:      equ zipdos+16          ; ZDIRMAX
zhdr:        equ zipdir+ZDIRMAX     ; 48
namebuf:     equ zhdr+48            ; 256
zipbuf:      equ namebuf+256        ; ZBUFSZ
tmpcfg:      equ zipbuf+ZBUFSZ      ; 64   TMPDIR from MB.CFG
startcfg:    equ tmpcfg+64          ; 64   STARTDIR from MB.CFG
tmpdir:      equ startcfg+64        ; 80   directory for extracted files
tmpname:     equ tmpdir+80          ; 16
tmppath:     equ tmpname+16         ; 112
; not used while a file is extracted (the window of inflate starts here):
fib:         equ tmppath+112        ; 64
pathbuf:     equ fib+64             ; 160
progpath:    equ pathbuf+160        ; 128
tailbuf:     equ progpath+128       ; 128
hdrbuf:      equ tailbuf+128        ; 416
titbuf:      equ hdrbuf+416         ; 48   path shown in the title bar
idx:         equ titbuf+48          ; MAXENT*2
entries:     equ idx+MAXENT*2       ; MAXENT*RECSZ
pool:        equ entries+MAXENT*RECSZ  ; POOLSZ
poolend:     equ pool+POOLSZ
; the overlay (mged.asm) is read to OVB, in the list memory
OVB:         equ (idx+255)&0xFF00
; extraction re-uses the list memory and the buffers above it: 32 KB window
; + Huffman tables
WIN:         equ (fib+255)&0xFF00
WEND:        equ WIN+0x8000
WENDH:       equ (WEND>>8)&0xFF
LTAB:        equ WEND               ; literal/length table (608 + 288*2)
DTAB:        equ LTAB+0x500         ; distance table (608 + 30*2), aligned
LTABH:       equ (LTAB>>8)&0xFF
DTABH:       equ (DTAB>>8)&0xFF
lens:        equ DTAB+608+64        ; 320 code lengths
offs:        equ lens+320           ; 32
INFL_END:    equ offs+32
mem_end:     equ poolend
