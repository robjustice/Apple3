;
; This is based on a disassembly of the Titan //e disk
; This is the main setup and config code.
; This loaded as part of the interpreter, and then gets moved to
; its original $0C00 location and then run.
;

SRCPTR      =       $00
DSTPTR      =       $02
STARTBLK    =       $04
ENDBLK      =       $05
IBBUFP      =       $85
IBCMD       =       $87
KBD         =       $c000      ;last key pressed
CLR80VID    =       $c00c      ;W disable 80-column display mode
KBDSTRB     =       $c010      ;RW keyboard strobe
SETTEXTGR   =       $c051      ;Set TEXT/GR mode
CLRPAGE2    =       $c054      ;Clear PAGE2 mode
CLOCK       =       $c070      ;clock
CLRENCWRT   =       $c0da      ;Clear Char Set writing
SETENCWRT   =       $c0db      ;Set Char Set writing
BLOCKIO     =       $f479
A3RESET     =       $f4ee
A2RESET     =       $fa62
Z_REG       =       $ffd0      ;zero page register
ENV_REG     =       $ffdf      ;environment register
E_PCR       =       $ffec
E_IFR       =       $ffed
E_IER       =       $ffee
BNK_REG     =       $ffef      ;bank switch register

L1400       =       $1400
L1401       =       $1401
L1403       =       $1403
L1800       =       $1800


            .segment "RAM"
            
            .import SLOT5ROM
            .import SLOT6ROM
            .import SLOT7ROM
            .import TWOEROM

FONT        =       $9000


            .org $0C00
            
L0C00:      ldy     #$00       ;clear extended addressing pages
L0C02:      lda     SRCPTR,y
            sta     L1800,y
            lda     #$00
            sta     L1400,y
            iny
            bne     L0C02
            lda     #$18       ;set zero page to $18
            sta     Z_REG
;comment this section out, dont need to load from disk now
;            lda     #$00       ;set bank 0
;            sta     BNK_REG
;            lda     #$00       ;set IBBUFP to $9000
;            sta     IBBUFP
;            lda     #$90
;            sta     IBBUFP+1
;            lda     #$11       ;start blk 17
;            sta     STARTBLK
;            lda     #$29       ;end blk 40
;            sta     ENDBLK
;            jsr     READBLKS
;            lda     #$00       ;set IBBUFP to $2000
;            sta     IBBUFP
;            lda     #$20
;            sta     IBBUFP+1
;            lda     #$29       ;start block 41
;            sta     STARTBLK
;            lda     #$2b       ;end block 42
;            sta     ENDBLK
;            jsr     READBLKS

; copy slot roms in (from current bank)
            lda     ENV_REG
            and     #$b7        ;bf  i/o cxxx off, write protect ram off
            sta     ENV_REG
            ldy     #$00
@L0C4A:     lda     SLOT5ROM,y    ;copy slot 5 rom in
            sta     $c500,y
            lda     SLOT6ROM,y    ;copy slot 6 rom in
            sta     $c600,y
            lda     SLOT7ROM,y    ;copy slot 7 rom in
            sta     $c700,y
            iny
            bne     @L0C4A
            lda     ENV_REG
            ora     #$40        ;i/o cxxx on
            sta     ENV_REG

; again comment out, disk loading not needed
;            lda     #$00       ;set IBBUFP to $2000
;            sta     IBBUFP
;            lda     #$20
;            sta     IBBUFP+1
;            lda     #$2b       ;start block 43
;            sta     STARTBLK
;            lda     #$43       ;end block 66
;            sta     ENDBLK
;            jsr     READBLKS

; copy //e rom in (from current bank)
            lda     #<TWOEROM       ;set SCRPTR to TWOEROM
            sta     SRCPTR
            lda     #>TWOEROM
            sta     SRCPTR+1
            lda     #$00       ;disable extended addressing for SRCPTR
            sta     L1401
            sta     DSTPTR     ;set DSTPTR to $D000
            lda     #$d0
            sta     DSTPTR+1
            lda     #$8f       ;set extended addressing to special $8F case 
            sta     L1403      ;(able to copy behind VIAs with 8f)
            ldy     #$00       ;copy $2000-$4FFF to $D000-$FFFF
@L0C94:     lda     (SRCPTR),y
            sta     (DSTPTR),y
            iny
            bne     @L0C94
            inc     SRCPTR+1
            inc     DSTPTR+1
            bne     @L0C94
      
            lda     #$00       ;set bank 0, as we copied the font data to there
            sta     BNK_REG      
            ldx     #>FONT
            lda     #<FONT
            jsr     L0CAB     ;load the font
            jsr     SETCOLOR  ; this is needed now as after sos is loaded, the foreground/background
                              ; colors are set to 'A0', comes out as faint grey in mame
            jmp     L0E00

; load character set
L0CAB:      sta     SRCPTR
            stx     SRCPTR+1
            lda     #$00
            sta     L1401
            sta     STARTBLK
            lda     #$18
            sta     E_IER
            lda     E_PCR
            and     #$0f
            ora     #$30
            sta     E_PCR
@L0CC5:     lda     #$07
            sta     ENDBLK
@L0CC9:     jsr     @L0CFE
            inc     STARTBLK
            lda     SRCPTR
            clc
            adc     #$08
            sta     SRCPTR
            bcc     @L0CD9
            inc     $01
@L0CD9:     dec     ENDBLK
            bpl     @L0CC9
            bit     SETENCWRT
            ldx     #$18
            stx     E_IFR
@L0CE5:     lda     E_IFR
            and     #$10
            beq     @L0CE5
            stx     E_IFR
@L0CEF:     lda     E_IFR
            and     #$18
            beq     @L0CEF
            bit     CLRENCWRT
            lda     STARTBLK
            bpl     @L0CC5
            rts

@L0CFE:     ldx     #$00
            ldy     #$00
@L0D02:     lda     ENDBLK
            and     #$03
            ora     @L0D2A,y
            sta     DSTPTR
            lda     ENDBLK
            lsr     A
            lsr     A
            cpy     #$04
            rol     A
            ora     #$08
            sta     $03
            lda     STARTBLK
            sta     (DSTPTR,x)
            lda     $03
            eor     #$0c
            sta     $03
            lda     (SRCPTR),y
            sta     (DSTPTR,x)
            iny
            cpy     #$08
            bcc     @L0D02
            rts

@L0D2A:     .byte   $78
            .byte   $7c
            .byte   $f8
            .byte   $fc
            .byte   $78
            .byte   $7c
            .byte   $f8
            .byte   $fc

; load blocks in from disk
;READBLKS:   lda     STARTBLK
;            cmp     ENDBLK
;            bcs     @L0D47
;            ldx     #$00
;            jsr     BLOCKIO
;            bcs     @L0D48     ;i/o error
;            inc     IBBUFP+1
;            inc     IBBUFP+1
;            inc     STARTBLK
;            bne     READBLKS
;@L0D47:     rts
;
;; print error
;@L0D48:     ldx     #$00
;@L0D4A:     lda     @L0D60,x
;            bmi     @L0D55
;            sta     $05b5,x
;            inx
;            bne     @L0D4A
;@L0D55:     lda     ENV_REG
;            ora     #$10
;            sta     ENV_REG
;@L0D5D:     jmp     @L0D5D
;
;@L0D60:     .byte   "***  I/O ERROR - RESET  ***"
;            .byte   $80
;            .res    132,$00

;pad out until $0e00
STRTLEN     =       * - L0C00
PAD         =       $200 - STRTLEN
            .res    PAD,$00

L0E00:      lda     #$67          ;(1.I.S.R:W.P.R.R)
                                  ; 0 1 1 0 0 1 1 1
            sta     ENV_REG
            nop
            nop
            lda     #$e7          ;(1.I.S.R:W.P.R.R)
                                  ; 1 1 1 0 0 1 1 1
            sta     ENV_REG
            lda     #$00
            sta     BNK_REG
            sta     $c0a1         ;enable something on 3plus2e card?
            sta     SETTEXTGR     ;set text mode for //e(sets color text for A3)
            sta     CLRPAGE2
            sta     CLR80VID      ;80 column display off
            sta     KBDSTRB

;detect if we have a clock chip?
            ldx     #$11
            ldy     #$14
@L0E24:     lda     #$00
            sta     Z_REG
            lda     CLOCK
            sty     Z_REG
            lda     CLOCK
            beq     @L0E3C
            dex
            bne     @L0E24
            lda     #$60
            sta     $c700

;check /// memory size is 256k (or greater)
@L0E3C:     lda     #$03          ;banks 0-2 for 128k, 0-7 for 256k
            sta     BNK_REG
            lda     $2000
            eor     #$55
            sta     $2000
            cmp     $2000
            php
            eor     #$55
            sta     $2000
            plp
            beq     @L0E5F
            lda     #$80
            sta     $c7aa
            lda     #$00
            sta     $c7ab

@L0E5F:     lda     #$00       ;set bank=0
            sta     BNK_REG
            lda     #$18       ;set zp=$18
            sta     Z_REG
            jsr     L1F29
            jsr     @L0F05     ;display start menu
@L0E6F:     lda     KBD        ;get key
            bpl     @L0E6F
            sta     KBDSTRB
            cmp     #$b1       ;is it '1'?
            beq     @L0ECC     ;start Apple /// mode
            cmp     #$b3       ;is it '3'?
            beq     @L0ED7     ;start Apple //e mode
            cmp     #$b2       ;is it '2'?
            bne     @L0E6F     ;no, get another key, fall through if 2
; change configuration
@L0E83:     jsr     L1F29      ;clear text screen
            ldx     #$c6
            ldy     #$c6
            lda     $c7a0
            beq     @L0E93
            ldx     #$a0
            ldy     #$ee
@L0E93:     sty     L10BA
            stx     L10BB
            jsr     L0FF5      ;display main config menu
@L0E9C:     lda     KBD
            bpl     @L0E9C
            sta     KBDSTRB
            cmp     #$b1       ;is it '1'?
            beq     @L0EC0     ;printer settings
            cmp     #$b3       ;is it '3'?
            beq     @L0EBA     ;double hires
            cmp     #$b2       ;is it '2'?
            beq     @L0EC6     ;communications settings
            cmp     #$b4       ;is it '4'?
            bne     @L0E3C
            jsr     L1DE6      ;save settings
            jmp     @L0E83

@L0EBA:     jsr     @L0EFA     ;double hires
            jmp     @L0E83

@L0EC0:     jsr     L12A3      ;printer settings
            jmp     @L0E83

@L0EC6:     jsr     L1D17      ;communications settings
            jmp     @L0E83

; start Apple /// mode
@L0ECC:     sta     $c0a0      ;disable 3plus2e card?
            lda     #$ff       ;2Mhz,i/o,video,reset,writeprot_ram,prim_stack,rom enabled
            sta     ENV_REG
            jmp     A3RESET

; start Apple //e mode
@L0ED7:     lda     $c7a0
            sta     $a7a0
            ldx     #>FONT
            lda     #<FONT
            jsr     L0CAB      ;load the font
            jsr     L1F29      ;clear text screen
            lda     #$fc       ;1Mhz,i/o,video,reset,writeprot_ram,prim_stack,no rom enabled
            sta     ENV_REG
            lda     #$00
            sta     Z_REG      ;Zero page to 00
            sta     BNK_REG    ;bank 00
            sta     $c300      ;enable 3plus2 card
            jmp     A2RESET    ;go run as Apple IIe

; update double hires setting
@L0EFA:     lda     $c7a0
            eor     #$02
            and     #$02
            sta     $c7a0
            rts

@L0F05:     lda     #$00
@L0F07:     tay
            ldx     @L0F24,y
            bmi     @L0F23
            pha
            lda     @L0F25,y
            ldx     @L0F25+1,y
            pha
            lda     @L0F24,y
            tay
            pla
            jsr     L1F48
            pla
            clc
            adc     #$03
            bne     @L0F07
@L0F23:     rts

; start menu
@L0F24:     .byte   $0a        ;length
@L0F25:     .word   T0F37      ;line address
            .byte   $0e
            .word   T0F56
            .byte   $14
            .word   T0F77
            .byte   $18
            .word   T0F99
            .byte   $1c
            .word   T0FB6
            .byte   $22
            .word   T0FD8
            .byte   $ff
.macro      HiAscii Arg
            .repeat .strlen(Arg), I
            .byte   .strat(Arg, I) | $80
            .endrep
.endmacro
T0F37:      HiAscii "          TITAN   /// plus //e"
            .byte   $00
T0F56:      HiAscii "       MACHINE STARTUP MAIN MENU"
            .byte   $00
T0F77:      HiAscii "   1)   START APPLE /// OPERATION"
            .byte   $00
T0F99:      HiAscii "   2)   CHANGE //e EMULATION"
            .byte   $00
T0FB6:      HiAscii "   3)   START APPLE //e EMULATION"
            .byte   $00
T0FD8:      HiAscii "            SELECT BY NUMBER"
            .byte   $00

; display main config menu
L0FF5:      lda     #$00
@L0FF7:     tay
            ldx     @L1014,y
            bmi     @L1013
            pha
            lda     @L1015,y
            ldx     @L1015+1,y
            pha
            lda     @L1014,y
            tay
            pla
            jsr     L1F48
            pla
            clc
            adc     #$03
            bne     @L0FF7
@L1013:     rts

; main setup menu
@L1014:     .byte   $0a
@L1015:     .word   T102D
            .byte   $0e
            .word   T1048
            .byte   $14
            .word   T1067
            .byte   $18
            .word   T1080
            .byte   $1c
            .word   T10A0
            .byte   $20
            .word   T10BD
            .byte   $26
            .word   T10D7
            .byte   $28
            .word   T10F4
            .byte   $ff
T102D:      HiAscii "       TITAN  /// plus //e"
            .byte   $00
T1048:      HiAscii "  APPLE //e EMULATION SETTINGS"
            .byte   $00
T1067:      HiAscii "   1)   Printer Settings"
            .byte   $00
T1080:      HiAscii "   2)   Communications Settings"
            .byte   $00
T10A0:      HiAscii "   3)   Double Hi-Res is O"
L10BA:      .byte   $ee
L10BB:      .byte   $a0
            .byte   $00
T10BD:      HiAscii "   4)   Save New Settings"
            .byte   $00
T10D7:      HiAscii "      ENTER CHOICE BY NUMBER"
            .byte   $00
T10F4:      HiAscii "    <RETURN> FOR PREVIOUS MENU"
            .byte   $00

L1113:      lda     #$00
@L1115:     tay
            ldx     @L1132,y
            bmi     @L1131
            pha
            lda     @L1133,y
            ldx     @L1133+1,y
            pha
            lda     @L1132,y
            tay
            pla
            jsr     L1F48
            pla
            clc
            adc     #$03
            bne     @L1115
@L1131:     rts

@L1132:     .byte   $02
@L1133:     .word   T1157
            .byte   $06
            .word   T1172
            .byte   $0c
            .word   T1190
            .byte   $10
            .word   T11AC
            .byte   $14
            .word   T11C1
            .byte   $18
            .word   T11DF
            .byte   $1c
            .word   T11F3
            .byte   $20
            .word   T120E
            .byte   $24
            .word   T1229
            .byte   $28
            .word   T1246
            .byte   $2c
            .word   T1261
            .byte   $2e
            .word   T1281
            .byte   $ff
T1157:      HiAscii "       TITAN  /// plus //e"
            .byte   $00
T1172:      HiAscii "      SLOT 1 PRINTER SETTINGS"
            .byte   $00
T1190:      HiAscii "   1)   Baud rate is "
L11A5:      HiAscii " 19200"
            .byte   $00
T11AC:      HiAscii "   2)   "
L11B4:      HiAscii "SPACE Parity"
            .byte   $00
T11C1:      HiAscii "   3)   Data Format is "
L11D8:      HiAscii "8 Bits"
            .byte   $00
T11DF:      HiAscii "   4)   "
L11E7:      HiAscii "2 Stop Bit"
L11F1:      .byte   $f3
            .byte   $00
T11F3:      HiAscii "   5)   Line Length is "
L120A:      .byte   $cf
L120B:      .byte   $c6
L120C:      .byte   $c6
            .byte   $00
T120E:      HiAscii "   6)   Page Length is "
L1225:      .byte   $cf
L1226:      .byte   $c6
L1227:      .byte   $c6
            .byte   $00
T1229:      HiAscii "   7)   Line Feeds are "
L1240:      .byte   $c1
L1241:      .byte   $c4
L1242:      .byte   $c4
L1243:      .byte   $c5
L1244:      .byte   $c4
            .byte   $00
T1246:      HiAscii "   8)   HI-BIT is "
L1258:      .byte   $c4
L1259:      .byte   $c9
L125A:      HiAscii "SABLED"
            .byte   $00
T1261:      HiAscii "        TOGGLE CHOICE BY NUMBER"
            .byte   $00
T1281:      HiAscii "       <RETURN> FOR PREVIOUS MENU"
            .byte   $00

L12A3:      jsr     L1F29
            lda     $c7a6
            pha
            and     #$0f
            asl     A
            asl     A
            asl     A
            tax
            ldy     #$00
@L12B2:     lda     L1C6F,x
            sta     L11A5,y
            inx
            iny
            cpy     #$06
            bne     @L12B2
            pla
            pha
            and     #$60
            lsr     A
            lsr     A
            lsr     A
            lsr     A
            lsr     A
            sta     SRCPTR
            sec
            lda     #$b8
            sbc     SRCPTR
            sta     L11D8
            pla
            bmi     @L12E0
            lda     #$b1
            sta     L11E7
            lda     #$a0
            sta     L11F1
            bne     @L12EA

@L12E0:     lda     #$b2
            sta     L11E7
            lda     #$f3
            sta     L11F1
@L12EA:     lda     $c7a7
            ldx     #$20
            and     #$e0
            beq     @L12F9
            lsr     A
            lsr     A
            lsr     A
            and     #$18
            tax
@L12F9:     ldy     #$00
@L12FB:     lda     L1CEF,x
            sta     L11B4,y
            inx
            iny
            cpy     #$05
            bne     @L12FB
            lda     $c7a3
            bne     @L131B
            lda     #$cf
            sta     L120A
            lda     #$c6
            sta     L120B
            sta     L120C
            bne     @L1327

@L131B:     jsr     L1B19
            sta     L120A
            stx     L120B
            sty     L120C
@L1327:     lda     $c7a4
            bne     @L133B
            lda     #$cf
            sta     L1225
            lda     #$c6
            sta     L1226
            sta     L1227
            bne     @L1347

@L133B:     jsr     L1B19
            sta     L1225
            stx     L1226
            sty     L1227
@L1347:     lda     $c7a5
            pha
            and     #$08
            bne     @L1366
            lda     #$cf
            sta     L1240
            lda     #$c6
            sta     L1241
            sta     L1242
            lda     #$a0
            sta     L1243
            sta     L1244
            bne     @L137B

@L1366:     lda     #$c1
            sta     L1240
            lda     #$c4
            sta     L1241
            sta     L1242
            sta     L1244
            lda     #$c5
            sta     L1243
@L137B:     pla
            and     #$04
            bne     @L1391
            lda     #$c4
            sta     L1258
            lda     #$c9
            sta     L1259
            lda     #$d3
            sta     L125A
            bne     @L13A0

@L1391:     lda     #$a0
            sta     L1258
            lda     #$c5
            sta     L1259
            lda     #$ce
            sta     L125A
@L13A0:     jsr     L1113
@L13A3:     lda     KBD
            bpl     @L13A3
            sta     KBDSTRB
            cmp     #$b1
            beq     @L13E4
            cmp     #$b2
            beq     @L13EA
            cmp     #$b3
            beq     @L13F0
            cmp     #$b4
            beq     @L13F6
            cmp     #$b5
            beq     @L13CC
            cmp     #$b6
            beq     @L13D2
            cmp     #$b7
            beq     @L13D8
            cmp     #$b8
            beq     @L13DE
            rts

@L13CC:     jsr     L1A00
            jmp     L12A3

@L13D2:     jsr     L1A07
            jmp     L12A3

@L13D8:     jsr     L1A0E
            jmp     L12A3

@L13DE:     jsr     L1A17
            jmp     L12A3

@L13E4:     jsr     L1A51
            jmp     L12A3

@L13EA:     jsr     L1A34
            jmp     L12A3

@L13F0:     jsr     L1A20
            jmp     L12A3

@L13F6:     lda     $c7a6
            clc
            adc     #$80
            jmp     L1FA0
;
            .res    1,0

            .res    $600,0

L1A00:      jsr     L1A88
            sta     $c7a3
            rts

L1A07:      jsr     L1A88
            sta     $c7a4
            rts

L1A0E:      lda     $c7a5
            eor     #$08
            sta     $c7a5
            rts

L1A17:      lda     $c7a5
            eor     #$04
            sta     $c7a5
            rts

L1A20:      lda     $c7a6
            pha
            and     #$9f
            sta     SRCPTR
            pla
            clc
            adc     #$20
            and     #$60
            ora     SRCPTR
            sta     $c7a6
            rts

L1A34:      lda     $c7a7
            pha
            rol     A
            rol     A
            rol     A
            rol     A
            and     #$07
            tax
            pla
            and     #$1f
            ora     L1A49,x
            sta     $c7a7
            rts

L1A49:      .byte   $20
            .byte   $60
            .byte   $20
            .byte   $a0
            .byte   $20
            .byte   $e0
            .byte   $20
            .byte   $00

L1A51:      lda     $c7a6
            pha
            and     #$f0
            sta     SRCPTR
            pla
            clc
            adc     #$01
            and     #$0f
            ora     SRCPTR
            sta     $c7a6
            rts

L1A65:      HiAscii "ENTER NUMBER, THEN <RETURN>:"
L1A81:      .byte   $a0
L1A82:      .byte   $a0
L1A83:      .byte   $a0
L1A84:      .byte   $a0
            .byte   $a0
            .byte   $a0
            .byte   $00

L1A88:      jsr     L1F29
            lda     #$a0
            sta     L1A82
            sta     L1A83
            sta     L1A84
            ldy     #$00
@L1A98:     sty     STARTBLK
@L1A9A:     lda     #<L1A65
            ldx     #>L1A65
            ldy     #20
            jsr     L1F48
@L1AA3:     lda     KBD
            bpl     @L1AA3
            sta     KBDSTRB
            ldy     STARTBLK
            cmp     #$8d
            beq     @L1AD6
            cmp     #$88
            bne     @L1ACB
            dec     STARTBLK
            bmi     @L1AC0
            lda     #$a0
            sta     L1A81,y
            bne     @L1A9A

@L1AC0:     lda     #$a0
            sta     L1A82
            lda     #$00
            sta     STARTBLK
            beq     @L1A9A

@L1ACB:     cpy     #$03
            bne     @L1AD0
            dey
@L1AD0:     sta     L1A82,y
            iny
            bne     @L1A98
@L1AD6:     lda     #$00
            sta     SRCPTR
            dec     STARTBLK
            bmi     @L1AFE
            lda     L1A82
            jsr     @L1B01
            bcs     L1A88
            dec     STARTBLK
            bmi     @L1AFE
            lda     L1A83
            jsr     @L1B01
            bcs     L1A88
            dec     STARTBLK
            bmi     @L1AFE
            lda     L1A84
            jsr     @L1B01
            bcs     L1A88
@L1AFE:     lda     SRCPTR
            rts

@L1B01:     cmp     #$b0
            bcc     @L1B17
            cmp     #$ba
            bcs     @L1B17
            and     #$0f
            ldy     #$0a
@L1B0D:     clc
            adc     SRCPTR
            dey
            bne     @L1B0D
            sta     SRCPTR
            clc
            rts

@L1B17:     sec
            rts

L1B19:      cmp     #$64
            bcc     @L1B31
            sbc     #$64
            cmp     #$64
            bcc     @L1B2B
            sbc     #$64
            tay
            lda     #$b2
            pha
            bne     @L1B35

@L1B2B:     tay
            lda     #$b1
            pha
            bne     @L1B35

@L1B31:     tay
            lda     #$a0
            pha
@L1B35:     php
            sed
            lda     #$00
@L1B39:     dey
            bmi     @L1B41
            clc
            adc     #$01
            bne     @L1B39
@L1B41:     pha
            and     #$0f
            ora     #$b0
            tay
            pla
            lsr     A
            lsr     A
            lsr     A
            lsr     A
            ora     #$b0
            tax
            plp
            pla
            cmp     #$a0
            bne     @L1B5B
            cpx     #$b0
            bne     @L1B5B
            ldx     #$a0
@L1B5B:     rts

L1B5C:      lda     #$00
@L1B5E:     tay
            ldx     @L1B7B,y
            bmi     @L1B7A
            pha
            lda     @L1B7C,y
            ldx     @L1B7C+1,y
            pha
            lda     @L1B7B,y
            tay
            pla
            jsr     L1F48
            pla
            clc
            adc     #$03
            bne     @L1B5E
@L1B7A:     rts

@L1B7B:     .byte   $0a
@L1B7C:     .word   T1B94
            .byte   $0e
            .word   T1BAF
            .byte   $14
            .word   T1BD0
            .byte   $18
            .word   T1BEC
            .byte   $1c
            .word   T1C01
            .byte   $20
            .word   T1C1F
            .byte   $26
            .word   T1C33
            .byte   $28
            .word   T1C50
            .byte   $ff
T1B94:      HiAscii "       TITAN  /// plus //e"
            .byte   $00
T1BAF:      HiAscii "  SLOT 2 COMMUNICATIONS SETTINGS"
            .byte   $00
T1BD0:      HiAscii "   1)   Baud rate is "
L1BE5:      HiAscii " 19200"
            .byte   $00
T1BEC:      HiAscii "   2)   "
L1BF4:      HiAscii "SPACE Parity"
            .byte   $00
T1C01:      HiAscii "   3)   Data Format is "
L1C18:      HiAscii "8 Bits"
            .byte   $00
T1C1F:      HiAscii "   4)   "
L1C27:      HiAscii "2 Stop Bit"
L1C31:      .byte   $f3
            .byte   $00
T1C33:      HiAscii "     TOGGLE CHOICE BY NUMBER"
            .byte   $00
T1C50:      HiAscii "    <RETURN> FOR PREVIOUS MENU"
            .byte   $00
L1C6F:      .byte   $b1,$b1,$b5,$b2,$b0,$b0,$a0,$a0,$b5,$b0,$a0,$a0,$a0,$a0,$a0,$a0
            .byte   $b7,$b5,$a0,$a0,$a0,$a0,$a0,$a0,$b1,$b1,$b0,$a0,$a0,$a0,$a0,$a0
            .byte   $b1,$b3,$b5,$a0,$a0,$a0,$a0,$a0,$b1,$b5,$b0,$a0,$a0,$a0,$a0,$a0
            .byte   $b3,$b0,$b0,$a0,$a0,$a0,$a0,$a0,$b6,$b0,$b0,$a0,$a0,$a0,$a0,$a0
            .byte   $b1,$b2,$b0,$b0,$a0,$a0,$a0,$a0,$b1,$b8,$b0,$b0,$a0,$a0,$a0,$a0
            .byte   $b2,$b4,$b0,$b0,$a0,$a0,$a0,$a0,$b3,$b6,$b0,$b0,$a0,$a0,$a0,$a0
            .byte   $b4,$b8,$b0,$b0,$a0,$a0,$a0,$a0,$b7,$b2,$b0,$b0,$a0,$a0,$a0,$a0
            .byte   $b9,$b6,$b0,$b0,$a0,$a0,$a0,$a0,$b1,$b9,$b2,$b0,$b0,$a0,$a0,$a0
L1CEF:      HiAscii "ODD     EVEN    MARK    SPACE   NO      "

L1D17:      jsr     L1F29
            lda     $c7a1
            pha
            and     #$0f
            asl     A
            asl     A
            asl     A
            tax
            ldy     #$00
@L1D26:     lda     L1C6F,x
            sta     L1BE5,y
            inx
            iny
            cpy     #$06
            bne     @L1D26
            pla
            pha
            and     #$60
            lsr     A
            lsr     A
            lsr     A
            lsr     A
            lsr     A
            sta     SRCPTR
            sec
            lda     #$b8
            sbc     SRCPTR
            sta     L1C18
            pla
            bmi     @L1D54
            lda     #$b1
            sta     L1C27
            lda     #$a0
            sta     L1C31
            bne     @L1D5E

@L1D54:     lda     #$b2
            sta     L1C27
            lda     #$f3
            sta     L1C31
@L1D5E:     lda     $c7a2
            ldx     #$20
            and     #$e0
            beq     @L1D6D
            lsr     A
            lsr     A
            lsr     A
            and     #$18
            tax
@L1D6D:     ldy     #$00
@L1D6F:     lda     L1CEF,x
            sta     L1BF4,y
            inx
            iny
            cpy     #$05
            bne     @L1D6F
            jsr     L1B5C
@L1D7E:     lda     KBD
            bpl     @L1D7E
            sta     KBDSTRB
            cmp     #$b1
            beq     @L1D97
            cmp     #$b2
            beq     @L1DAD
            cmp     #$b3
            beq     @L1DC4
            cmp     #$b4
            beq     @L1DDA
            rts

@L1D97:     lda     $c7a1
            pha
            and     #$f0
            sta     SRCPTR
            pla
            clc
            adc     #$01
            and     #$0f
            ora     SRCPTR
            sta     $c7a1
            jmp     L1D17

@L1DAD:     lda     $c7a2
            pha
            rol     A
            rol     A
            rol     A
            rol     A
            and     #$07
            tax
            pla
            and     #$1f
            ora     L1A49,x
            sta     $c7a2
            jmp     L1D17

@L1DC4:     lda     $c7a1
            pha
            and     #$9f
            sta     SRCPTR
            pla
            clc
            adc     #$20
            and     #$60
            ora     SRCPTR
            sta     $c7a1
            jmp     L1D17

@L1DDA:     lda     $c7a1
            clc
            adc     #$80
            sta     $c7a1
            jmp     L1D17

; save config settings
L1DE6:      rts        ;disable the save settings for now, need to adapt to sos some how
            nop

            ;lda     #$01       ;read block $2a into $2000
            sta     IBCMD
            lda     #$00
            sta     IBBUFP
            lda     #$20
            sta     IBBUFP+1
            jsr     L1E50
            ldx     #$00
            lda     #$2a
            jsr     BLOCKIO
            bcs     @L1E2C     ;error reading block
            ldy     #$25       ;check copyright message
@L1E00:     lda     $2100,y
            cmp     L1EB1,y
            bne     L1E7A      ;not matching, error
            dey
            bpl     @L1E00
            ldy     #$00
@L1E0D:     lda     $c700,y
            sta     $2000,y
            iny
            bne     @L1E0D
            lda     #$02
            sta     IBCMD
            lda     #$00
            sta     IBBUFP
            lda     #$20
            sta     IBBUFP+1
            jsr     L1E50
            ldx     #$00
            lda     #$2a
            jsr     BLOCKIO
@L1E2C:     bcs     L1E7A
            lda     #$01
            sta     IBCMD
            jsr     L1F29
            lda     #<L1E5A
            ldx     #>L1E5A
            ldy     #30
            jsr     L1F48
L1E3E:      ldx     #$00
@L1E40:     ldy     #$00
@L1E42:     lda     #$02
            sec
@L1E45:     sbc     #$01
            bne     @L1E45
            dey
            bne     @L1E42
            dex
            bne     @L1E40
            rts

L1E50:      lda     $c0e9
            sta     $c0a4
            sta     $c0a0
            rts

L1E5A:      HiAscii "CONFIGURATION UPDATE SUCCESSFUL"
            .byte   $00

L1E7A:      jsr     L1F29
            lda     #<L1E89
            ldx     #>L1E89
            ldy     #30
            jsr     L1F48
            jmp     L1E3E

L1E89:      HiAscii "UNABLE TO MODIFY DISKETTE--PLEASE CHECK"
            .byte   $00
L1EB1:      HiAscii "COPYRIGHT 1985 BY HARMONY SYSTEMS INC"

            sta     SRCPTR
            stx     $01
            lda     ENV_REG
            pha
            and     #$f7
            sta     ENV_REG
            lda     #$00
            sta     DSTPTR
            lda     #$f8
            sta     $03
            lda     #$8f
            sta     L1403
            ldy     #$00
@L1EF2:     lda     (SRCPTR),y
            sta     (DSTPTR),y
            iny
            bne     @L1EF2
            inc     $01
            inc     $03
            bne     @L1EF2
            pla
            sta     ENV_REG
            rts

            sta     SRCPTR
            stx     $01
            lda     #$00
            sta     DSTPTR
            lda     #$a1
            sta     $03
            lda     #$8f
            sta     L1403
            ldy     #$00
@L1F17:     lda     (SRCPTR),y
            sta     (DSTPTR),y
            iny
            bne     @L1F17
            inc     $01
            inc     $03
            lda     $03
            cmp     #$b0
            bne     @L1F17
            rts

; clear text screen
L1F29:      ldx     #$00       ;disable extended addressing for SRCPTR
            stx     L1401
@L1F2E:     lda     L1F69,x
            sta     SRCPTR
            inx
            lda     L1F69,x
            sta     SRCPTR+1
            inx
            lda     #$a0       ;space character
            ldy     #39        ;number of characters per line
@L1F3E:     sta     (SRCPTR),y
            dey
            bpl     @L1F3E
            cpx     #48        ;number of text lines x2
            bne     @L1F2E
            rts

; display line of text on text screen
; stop when character = 0
; input:
;  a = address low byte of message
;  x = address high byte of message
;  y = line to start message on
; 
L1F48:      sta     SRCPTR
            stx     SRCPTR+1
            lda     L1F69,y
            sta     DSTPTR
            lda     L1F69+1,y
            sta     DSTPTR+1
            lda     #$00
            sta     L1401      ;disable extended addressing for SRCPTR
            sta     L1403      ;disable extended addressing for DSTPTR
            tay
@L1F5F:     lda     (SRCPTR),y
            beq     @L1F68
            sta     (DSTPTR),y
            iny
            bne     @L1F5F
@L1F68:     rts

; text screen lines address table
L1F69:      .word   $0400
            .word   $0480
            .word   $0500
            .word   $0580
            .word   $0600
            .word   $0680
            .word   $0700
            .word   $0780
            .word   $0428
            .word   $04a8
            .word   $0528
            .word   $05a8
            .word   $0628
            .word   $06a8
            .word   $0728
            .word   $07a8
            .word   $0450
            .word   $04d0
            .word   $0550
            .word   $05d0
            .word   $0650
            .word   $06d0
            .word   $0750
            .word   $07d0
            .res    7,$ff

L1FA0:      sta     $c7a6
            jmp     L12A3

; set foreground/background color for text screen
SETCOLOR:   ldx     #$00       ;disable extended addressing for SRCPTR
            stx     L1401
@L1F2E:     lda     L1F69,x
            sta     SRCPTR
            inx
            lda     L1F69,x
            clc
            adc     #$04
            sta     SRCPTR+1
            inx
            lda     #$F0       ;space character
            ldy     #39        ;number of characters per line
@L1F3E:     sta     (SRCPTR),y
            dey
            bpl     @L1F3E
            cpx     #48        ;number of text lines x2
            bne     @L1F2E
            rts

            .res    $2000 - *,0     ;pad out to $1fff

