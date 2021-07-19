; Modified problock driver to be used as a virtual floppy disk
; The loader needs to setup $3000 to hold the two index blocks for the 
; image file and then pretends to be a 280 block floppy
;
; Not relocatable, hard coded to be at bank 4, at $3600 (256k required)
;
; 
;  By Robert Justice
;
;            .TITLE "Apple /// Virtual Floppy Image Driver"

            .segment "RAM"
            .setcpu "6502"

            .export  VDrvLAddr
            .export  VDrvSize
            .export  DInit
            .export  BlockioStb    ; entry point for blockio stub
            .export  StartStub
            .export  EndStub
            .export  StubLen



VDrvLAddr   = $3600               ; org for this code
VDrvSize    = EndCode - StartCode

IndxBlk1    = VDrvLAddr - $600          ; Index block 1
IndxBlk2    = VDrvLAddr - $400          ; Index block 2
Buffer      = VDrvLAddr - $200          ; Buffer for card block read/writes

; this needs to be in an unused bit of non banked memory
BlockioStb  = $1940          ; entry point for blockio stub 
BankSave    = BlockioStb + (Bank_Tmp -StartStub)
SectioStb   = BlockioStb + (SectIOT - StartStub)    ; entry point for sectio stub
StubLen     = EndStub - StartStub


IBBUFP      = $85
IBCMD       = $87
BUF         = $9b            ; monitor diskio routines buffer

;
; SOS Equates
;
ExtPG       = $1401          ; Driver extended bank address offset
EReg        = $FFDF          ; Environment register
E_IFR       = $FFED          ; VIA E Interrupt Flag Register
E_IER       = $FFEE          ; VIA E Interrupt Enable Register
Bank_Reg    = $FFEF          ; Bank register
CWrtOff     = $C0DA          ; Character loading off
CWrtOn      = $C0DB          ; Character loading on

XDNFERR     = $10            ; Device not found

;
; Extra zero page variables
;
ScreenBase  = $E5            ; 2 bytes lb,hb for save/restore screenholes
Pointer     = $E7            ; 2 byte pointer for signature check

D_TRACK     = $16d8          ; for softcard sectorio
D_SECTOR    = $16d9          ; these are the inputs
D_UNITNUM   = $16da
D_BUFL      = $16db
D_BUFH      = $16dc
D_BUFX      = $16dd
D_COMMAND   = $16de

OrigDriver  = $9cc5          ; Softcard floppy driver entry

ScanStart   = $04            ; Slot number to start scan from

            .SEGMENT    "RAM"
            .org    VDrvLAddr
StartCode   = *

            jmp     BlockIO             ; entry point for BLOCKIO - 3600
            jmp     SectIO              ; entry point for SectorIO - 3603
Slot:       .byte   0                   ; slot for card
EnvSave:    .byte   0                   ; save current environment state
OrigBlk:    .byte   0                   ; temp location for original block num
                                        ; only patch blks <256, so 8bits is enough

;------------------------------------
;
; Local storage locations
;
;------------------------------------

TmpScrH:    .res    $10, $00            ; Storage for screenholes, slot0 & current slot
TmpZero:    .res    $30, $00            ; Storage to save zero page locations
                                        ; we set the prodos call data in here and then swap
                                        ; it in before we call the interface
ProCommand  = TmpZero + $22             ; Command        - $42
ProUnit     = TmpZero + $23             ; Unit number    - $43
ProBuf      = TmpZero + $24             ; buffer pointer - $44
ProBlock    = TmpZero + $26             ; Block number   - $46

ProBufOff   = $44                       ; buffer pointer - $44

Signature:  .byte $FF, $20, $FF, $00    ; Disk card signature for disk controller
            .byte $FF, $03

DInit:      lda     EReg                ; save current environment so we can
            sta     EnvSave             ;  restore on exit
            ora     #$40                ; enable Cxxx I/O
            sta     EReg
            lda     #ScanStart          ; load starting scan slot
            ora     #$C0                ; Form a $Cs00 address, where s = slot #
            sta     Pointer+1
            lda     #$00                
            sta     Pointer
            sta     Pointer+ExtPG       ; zero out the xbyte

CheckNext:  ldy     #$05                ; We check all 3 sig bytes, starting from last
@1:         lda     (Pointer),y
            cmp     Signature,Y
            bne     NoMatch             ; No device if bytes don't match
            dey
            dey
            bpl     @1
            
            ldy     #$ff                ; $CxFF - check last byte
            lda     (Pointer),y
            cmp     #$00
            beq     NoMatch             ; if $00, is a Disk II 16 sector device, error
            cmp     #$ff
            bne     Match               ; if its not $ff (Disk II 13 sector device)
                                        ; Then we found an intelligent disk controller :-)
            
NoMatch:    dec     Pointer+1           ; try next slot
            lda     Pointer+1
            and     #$07
            bne     CheckNext           ; Check next slot
            beq     NoDevice            ; Otherwise we did not find one :-(     
            
Match:      sta     ProDrvAdr+1         ; Set card driver entry low byte
            lda     Pointer+1
            sta     ProDrvAdr+2         ; Set card driver entry high byte
            and     #$07
            sta     Slot
            lda     EnvSave
            sta     EReg
            lda     #0
            rts

NoDevice:   lda     EnvSave
            sta     EReg
            lda     #XDNFERR            ; Device not found
            rts

;
; jsr to card firmware driver
; We update the address based on the slot and firmware CxFF byte
;
ProDriver:  sei                         ; disable interrupts while changing things
            jsr     SaveMem             ; save and swap in card screen hole & zeropage
            jsr     GoSlow
ProDrvAdr:  jsr     $0000               ; call device entry
            sei                         ; Keep interrupts off incase card firmware reenabled
            jsr     GoFast
            jsr     RestMem             ; save and swap out card screen hole & zeropage
            lda     #$18                ; Clear CB1 & CB2 flags - VBL
            sta     E_IFR               ; this seems more for mame, its a little different
            cli                         ; enable interrupts again
            rts

;
; Blockio routine. This replicates the rom routine behaviour
; x = block number msb
; a = block number lsb
; IBCMD = command, 1=read , write?
; IBBUFP = dest pointer
;
; For the Softcard ///, the blockio routine is only used to load in
; the boot block 0 and then the next 24 blocks with the 6502 IO routines and CPM
;
; We'll patch the two blocks to redirect them to our new routines here
; as we read them.
;
; Block 0 - offset $df -> 00 13  (new blockio)
; Block 3 - offset $1b4 -> 16 13 (new sectio) 
;

BlockIO:    cpx     #0                  ; check lk num msb
            beq     Low                 ; block is <256
            tax
            lda     IndxBlk2,X
            sta     ProBlock
            lda     IndxBlk2+256,X
            sta     ProBlock+1
            jmp     HDone

Low:        sta     OrigBlk             ; store for patch check
            tax                         ; map the block number
            lda     IndxBlk1,X
            sta     ProBlock            ; and store for prodos call
            lda     IndxBlk1+256,X
            sta     ProBlock+1

HDone:      lda     EReg                ; save current environment so we can
            sta     EnvSave             ;  restore on exit
            lda     IBCMD
            sta     ProCommand
            lda     IBBUFP
            sta     BUF
            lda     IBBUFP+1
            sta     BUF+1
            jsr     SetProUnit
            jsr     SetProBuf
            lda     EReg                ; enable I/O
            ora     #$40
            sta     EReg
            jsr     ProDriver

            jsr     CheckPatch          ; check if we need to patch it

            ldy     #0                  ; copy the buffer over
looppt1:    lda     Buffer,y            ; using extended addressing
            sta     (BUF),y             ;1940.50.60
            iny
            bne     looppt1

            inc     BUF+1
looppt2:    lda     Buffer+256,y
            sta     (BUF),y
            iny
            bne     looppt2
            
            dec     BUF+1

            lda     EnvSave
            sta     EReg

            lda     #0                 ; dummy no error
            clc

            rts

; check and patch the block to redirect here
; and also repatch the blockio and sectio stubs
; as these are located in memory that get loaded from
; the floppy
CheckPatch: lda     OrigBlk
            bne     nxtchk
            ldy     #$df               ; offset for blockio jsr address in boot block
            lda     #<BlockioStb
            sta     Buffer,Y
            iny
            lda     #>BlockioStb
            sta     Buffer,Y
            bne     donep

nxtchk:     cmp     #3
            bne     donep
            ldy     #$b4               ; offset for sectio jsr address in block 3 (1b4)
            lda     #<SectioStb
            sta     Buffer+256,y
            iny
            lda     #>SectioStb
            sta     Buffer+256,y

            ldy     #0                 ; also in blk3, we patch in the blockio & sectio stub
@p1:        lda     StartStub,y        ; as these would get overwritten with this blk read
            sta     Buffer+256+$40,y
            iny
            cpy     #StubLen
            bne     @p1

donep:      rts

;
; Sectio routine. This replicates the softcard floppy sector routine
; 256 byte sectors are mapped to the appropriate blocks
;
; Inputs
; D_TRACK         .eq     $16d8
; D_SECTOR        .eq     $16d9
; D_UNITNUM       .eq     $16da
; D_BUFL          .eq     $16db
; D_BUFH          .eq     $16dc
; D_BUFX          .eq     $16dd
; D_COMMAND       .eq     $16de
;
;
SectMap:    .byte   0,4,0,4,1,5,1,5,2,6,2,6,3,7,3,7 ;phys to blk
SectHalf:   .byte   0,0,1,1,0,0,1,1,0,0,1,1,0,0,1,1 ;first 256 or second 256 in block


SectIO:     lda     EReg                ; save current environment reg so we can
            sta     EnvSave             ;  restore on exit
            
            lda     D_TRACK             ; get track number to convert to block num
            asl                         ; multiply x 8
            asl
            asl
            bcc     Lt256               ; blknum < 256
            ldx     D_SECTOR            ; use sector number as index into map
            clc
            adc     SectMap,x
            tax                         ; then map the block number to image file blocks
            lda     IndxBlk2,X
            sta     ProBlock            ; and store for prodos call
            lda     IndxBlk2+256,X
            sta     ProBlock+1
            jmp     HDone2

Lt256:      ldx     D_SECTOR            ; use sector number as index into map
            adc     SectMap,x
            tax                         ; then map the block number to image file blocks
            lda     IndxBlk1,X
            sta     ProBlock            ; and store for prodos call
            lda     IndxBlk1+256,X
            sta     ProBlock+1

HDone2:     lda     #1                  ; read the block regardless of write or read
            sta     ProCommand          
            jsr     SetProUnit
            jsr     SetProBuf
            lda     EReg                ; enable Cxxx I/O
            ora     #$40
            sta     EReg
            jsr     ProDriver           ; get block
            bcs     DskError

            lda     D_BUFL              ; dest pointer lsb
            sta     BUF                 ; rom diskio buf lsb
            lda     D_BUFH              ; dest pointer msb
            sta     BUF+1               ; rom diskio buf msb
            lda     D_BUFX              ; dest pointer xbyte
            sta     $149c               ; rom diskio buf xbyte

            lda     D_COMMAND           ; now check if its a read/write 1=read, 0=write
            lsr     a
            bcc     SectWrite           ; yes

;fall through for read
            ldy     #0
            ldx     D_SECTOR            ; use sector number as index into map
            lda     SectHalf,x
            beq     firsthr

secondhr:   lda     Buffer+256,y        ; copy half block buffer into sector buffer
            sta     (BUF),Y
            iny
            bne     secondhr
            beq     done2

firsthr:    lda     Buffer,y            ; copy half block buffer into sector buffer
            sta     (BUF),Y
            iny
            bne     firsthr
            beq     done2

SectWrite:  ldy     #0
            ldx     D_SECTOR            ; use sector number as index into map
            lda     SectHalf,x
            beq     firsthw

secondhw:   lda     (BUF),Y             ; copy sector into block buffer
            sta     Buffer+256,y
            iny
            bne     secondhw
            beq     cont

firsthw:    lda     (BUF),Y             ; copy sector into block buffer
            sta     Buffer,y
            iny
            bne     firsthw

cont:       lda     #2                  ; write
            sta     ProCommand
            jsr     ProDriver           ; write block buffer back
            bcs     DskError

done2:      lda     EnvSave
            sta     EReg

            lda     #0                  ; set no error
            clc

            rts

DskError:   lda    #$27                 ; I/O error?
            sec
            rts


;
; Throttle back to 1 MHz
;
GoSlow:     pha
            php
            lda     EReg
            ora     #$80
            sta     EReg
            plp
            pla
            rts

;
; Throttle up to 2 MHz
;
GoFast:     pha
            php
            lda     EReg
            and     #$7F
            sta     EReg
            plp
            pla
            rts

;
; Save current screenholes and restore peripheral card values (current slot + slot0)
; and save zeropage $42-$47
;
SaveMem:    lda     E_IER
            and     #$18                ; See if either CB1 or CB2 interrupts were enabled
            beq     SkipVbl             ; No, they were not, skip the wait for vbl
            
                                        ; now wait for 2xVBL before we muck with the screenholes
            lda     #$18                ; Clear CB2 flag - VBL
            sta     E_IFR
VWait:      bit     E_IFR               ; Wait for vertical retrace
            beq     VWait
                                        ; wait for another one to ensure font data is loaded
            lda     #$18                ; Clear CB2 flag - VBL
            sta     E_IFR
VWait2:     bit     E_IFR               ; Wait for vertical retrace
            beq     VWait2

SkipVbl:    bit     CWrtOff             ; disable font loading

            jsr     SwapScrH            ; Swap in the screenhole data with ours
            jsr     SwapZero            ; swap zeropage
            rts

;
; Save Card screen holes and restore original values
; and restore zeropage $42-$47
;
RestMem:    pha
            php                         ; keep carry error indication
            jsr     SwapZero            ; swap zeropage
            jsr     SwapScrH            ; Swap back the original screenhole data            
            plp
            pla
            rts

;            
; Swap screenholes with driver values 
; we do Slot 0 and current slot values
; This nice code is from Peter Ferrie, thanks 
;
SwapScrH:   lda     #$07                ; Init ZP Screenbase, X and A
            sta     ScreenBase+1
            lda     #$00
            sta     ScreenBase
            sta     ScreenBase+ExtPG
            ldx     #$0F
            lda     #$F8
@loop:
            tay                         ; A holds screen page index at loop entry
            lda     (ScreenBase),Y   
            pha                         ; Save current screen hole byte on stack.
            lda     TmpScrH,X
            sta     (ScreenBase),Y      ; Restore screen hole byte from array 
            pla
            sta     TmpScrH,X           ; Copy saved screen hole byte into array.
            dex
            bmi     done                ; Exit when array is full (all 16 bytes are copied, X<0).
            txa                         ; TXA/LSR tests whether array index is odd or even
            lsr                         ; and sets carry accordingly (1 = odd).
            tya                         ; Bring screen index into A for manipulation
            eor     Slot                ; Cycle page index between $x8 and $x8+n as long as N in 1..7
            bcc     @loop               ; Take branch every other loop, using array index odd/even 
                                        ;  (carry still valid from TXA/LSR)
            eor     #$80                ; Cycle page index between $F8 and $78
            bpl     @loop               ; If flipping from $78->$F8 (now negative), continue
            dec     ScreenBase+1        ; Go to next page counting down ($07->$06, etc.)
            bne     @loop               ; Always -- equiv. to BRA or JMP.  Never reaches 0.
done:       rts

;
; Swap zeropage with driver values
;
SwapZero:   ldx     #$2f
@loop2:     lda     $20,X   
            pha                         ; Save current zeropage byte on stack.
            lda     TmpZero,X
            sta     $20,X               ; Restore zeropage byte from temp storage 
            pla
            sta     TmpZero,X           ; Copy saved zeropage byte into temp storage.
            dex
            bpl     @loop2
            rts

;
; Set Prodos unit number, assume unit0 only
;
SetProUnit: lda     Slot                ; create the slot/unit byte
            asl                         ; 7 6 5 4 3 2 1 0
            asl                         ; D S S S 0 0 0 0
            asl
            asl
            sta     ProUnit
            rts

;
; Set Prodos buffer pointer
;
SetProBuf:  lda     #<Buffer
            sta     ProBuf
            lda     #>Buffer
            sta     ProBuf+1
            lda     #0                  ; turn off extended addressing
            sta     ProBufOff+ExtPG
            rts

;
;Blockio stub
; This hides in non banked memory
;
StartStub:  ldy     Bank_Reg           ;save current bank
            sty     BankSave
            ldy     #4                 ;set virtual disk driver bank
            sty     Bank_Reg
            jsr     BlockIO            ;go read/write the block
            ldy     BankSave           ;restore bank
            sty     Bank_Reg
            rts
Bank_Tmp:   .byte   0                  ;temp holder for calling bank
;
;Sector IO stub
; This hides in non banked memory
; we only catch unit 0 (D1) as virtual drive
; other wise we pass to the orignal floppy driver
;
SectIOT:    lda     D_UNITNUM
            beq     drive1
            jmp     OrigDriver         ;continue on with original driver

drive1:     ldy     Bank_Reg           ;save current bank
            sty     BankSave
            ldy     #4                 ;set virtual disk driver bank
            sty     Bank_Reg
            jsr     SectIO             ;go read/write the sector
            ldy     BankSave           ;restore bank
            sty     Bank_Reg
            rts
EndStub     =*




EndCode     = *

            .END