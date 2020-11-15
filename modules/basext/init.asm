;The MIT License
;
;Copyright (c) 2009 Dylan Smith
;
;Permission is hereby granted, free of charge, to any person obtaining a copy
;of this software and associated documentation files (the "Software"), to deal
;in the Software without restriction, including without limitation the rights
;to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
;copies of the Software, and to permit persons to whom the Software is
;furnished to do so, subject to the following conditions:
;
;The above copyright notice and this permission notice shall be included in
;all copies or substantial portions of the Software.
;
;THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
;THE SOFTWARE.
.include	"spectranet.inc"
.include	"defs.inc"
.include	"zxrom.inc"
.include	"ctrlchars.inc"
.text
;------------------------------------------------------------------------
; F_init: Initializes the interpreter
.globl F_init
F_init:
	; force USR 0 mode on 128K machines (due to +2a/+3 BASIC
	; incompatibilities)
	ld bc, 0x1FFD		; set port 0x1ffd
	ld a, 0x04
	out (c), a
	ld b, 0x7F		; set port 0x7ffd which must be done
	ld a, 0x10		; second due to toastrack 128K machines
	out (c), a		; respoinding also to 0x1ffd
        ld hl, PARSETABLE
        ld b, NUMCMDS
.loop1:
        push bc
        call ADDBASICEXT
        pop bc
        jr c, .installerror1
        djnz .loop1

	; Install the default LOAD "" trap.
	;call F_initbootfile

        ld hl, STR_basicinit
        call PRINT42
        ret
.installerror1:
        ld hl, STR_basinsterr
        call PRINT42
        ret
.data
STR_basicinit:   defb    "BASIC extensions installed",NEWLINE,0
STR_basinsterr:  defb    "Failed to install BASIC extensions",NEWLINE,0

NUMCMDS:         equ     19
PARSETABLE:      
P_mount:         defb    0x0b
                defw    CMD_MOUNT
                defb    0xFF
                defw    F_tbas_mount    ; Mount routine
P_umount:        defb    0x0b
                defw    CMD_UMOUNT
                defb    0xFF
                defw    F_tbas_umount   ; Umount routine
P_chdir:         defb    0x0b
                defw    CMD_CHDIR
                defb    0xFF
                defw    F_tbas_chdir    ; Chdir routine
P_cat:           defb    0x0b
                defw    CMD_LS		; Display a directory
                defb    0xFF
                defw    F_tbas_ls
P_aload:         defb    0x0b
                defw    CMD_ALOAD       ; Arbitrary load
                defb    0xFF
                defw    F_tbas_aload
P_load:          defb    0x0b
                defw    CMD_LOAD        ; Standard LOAD command
                defb    0xFF
                defw    F_tbas_load
P_save:          defb    0x0b
                defw    CMD_SAVE	; Standard SAVE command
                defb    0xFF
                defw    F_tbas_save
P_se_load:      defb    0x0b
                defw    CMD_SELOAD		; SE Basic compatible Standard LOAD command
                defb    0xFF
                defw    F_tbas_load
P_se_save:      defb    0x0b
                defw    CMD_SESAVE		; SE Basic compatible Standard SAVE command
                defb    0xFF
                defw    F_tbas_save
P_tapein:	defb	0x0b
		defw	CMD_TAPEIN	; Set up a tape trap for a TAP file
		defb	0xFF
		defw	F_tbas_tapein
P_info:		defb	0x0b
		defw	CMD_INFO	; Give information on a file
		defb	0xFF
		defw	F_tbas_info
P_fs:		defb	0x0b
		defw	CMD_FS
		defb	0xFF
		defw	F_tbas_fs
P_loadsnap:	defb	0x0b
		defw	CMD_LOADSNAP
		defb	0xFF
		defw	F_loadsnap
P_mv:		defb	0x0b
		defw	CMD_MV		; Rename a file
		defb	0xFF
		defw	F_tbas_mv
P_rm:		defb	0x0b
		defw	CMD_RM		; Remove a file
		defb	0xFF
		defw	F_tbas_rm
P_mkdir:	defb	0x0b
		defw	CMD_MKDIR
		defb 	0xFF
		defw	F_tbas_mkdir
P_rmdir:	defb	0x0b
		defw	CMD_RMDIR
		defb	0xFF
		defw	F_tbas_rmdir
P_cp:		defb	0x0b
		defw	CMD_COPY
		defb	0xFF
		defw	F_tbas_copy
P_asave:	defb	0x0b
		defw	CMD_ASAVE
		defb	0xFF
		defw	F_tbas_asave

CMD_MOUNT:       defb    "%mount",0
CMD_UMOUNT:      defb    "%umount",0
CMD_CHDIR:       defb    "%cd",0
CMD_LS:          defb    "%cat",0
CMD_ALOAD:       defb    "%aload",0
CMD_LOAD:        defb    "%load",0
CMD_SAVE:        defb    "%save",0
CMD_SELOAD:      defb    "%",0xef,0
CMD_SESAVE:      defb    "%",0xf8,0
CMD_TAPEIN:	defb	"%tapein",0
CMD_INFO:	defb	"%info",0
CMD_FS:		defb	"%fs",0
CMD_LOADSNAP:	defb	"%loadsnap",0
CMD_MV:		defb	"%mv",0
CMD_RM:		defb	"%rm",0
CMD_MKDIR:	defb	"%mkdir",0
CMD_RMDIR:	defb	"%rmdir",0
CMD_COPY:	defb	"%cp",0
CMD_ASAVE:	defb	"%asave",0


