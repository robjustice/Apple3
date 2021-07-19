; This is a modified version of the Problock3 driver for use with the Softcard ///
; This has an additional layer on top that maps two sos files, CPM1 & CPM2 to
; appear as CPM disks. This driver assumes a tree type file, so must be larger then 128k.
; The names in the DIBs are used as the filenames with the '.' removed. So in theory, it could
; be used to mount any po image file on a drive by changing the names.
;
; The Softcard /// came with this driver for the Profile only as far as I can tell.
;
; This verion buffers the data locally with the driver and copys it in or out as required
; This is to simplify the extended addressing handling.
;
; It also reads and holds the tree index blocks for each file when the driver is initialised
; So not very kind on the memory usage, but that does not seem to be an issue for this.
;
;
; If the Driver Slot is configured with ff, then the driver scans all slots
; from 4 to 1 looking for the prodos card signature and uses the first
; one it finds.
; If the Driver Slot is configured with 1 - 4, then it uses that configured slot
; The default setting is to autoscan
;
; before calling the card firmware the driver
; - saves the screenholes for the current slot and slot0
; - saves zeropage locations 20-4f (this seemed to remove any inconsistencies)
; - disable interrupts
; - tries to detect if there is any font loading underway and waits if there is
;   so as not to corrupt the font
;
;
; By Robert Justice
;
;            .TITLE "Apple /// Softcard CPM Prodos Block Mode Driver"
            .PROC  CPMProblock
            .setcpu "6502"
            .reloc

DriverVersion   = $001B      ; Version number
DriverMfgr      = $524A      ; Driver Manufacturer - RJ
DriverType      = $E1        ; No formatter present for the time being
DriverSubtype   = $02        ;
ScanStart       = $04        ; Slot number to start scan from
AutoScan        = $FF        ; Auto scan slots

;
; SOS Equates
;
ExtPG       = $1401          ; Driver extended bank address offset
ALLOCSIR    = $1913          ; Allocate system internal resource
SELC800     = $1922          ; Enable Expansion Rom Space
DEALCSIR    = $1916          ; De-allocate system internal resource
SYSERR      = $1928          ; Report error to system
EReg        = $FFDF          ; Environment register
E_IFR       = $FFED          ; VIA E Interrupt Flag Register
E_IER       = $FFEE          ; VIA E Interrupt Enable Register
Bank_Reg    = $FFEF          ; Bank register
CWrtOff     = $C0DA          ; Character loading off
CWrtOn      = $C0DB          ; Character loading on
E1908       = $1908          ; GLOBAL FLAG FOR MOUSE DRIVER
                             ; TO SAY WE CANNOT BE INTERRUPTED


;
; SOS Zero page parameters
;
ReqCode     = $C0            ; Request code
SOS_Unit    = $C1            ; Unit number
SosBuf      = $C2            ; SOS buffer pointer
ReqCnt      = $C4            ; Requested byte count
CtlStat     = $C2            ; Control/status code
CSList      = $C3            ; Control/status list pointer
SosBlk      = $C6            ; Starting block number
QtyRead     = $C8            ; Bytes read return by D_READ

;
; Parameter block specific to current SOS request
;
Num_Blks    = $E2            ; Number of blocks requested (we'll never ever have > 128 blocks)
Count       = $E3            ; 2 bytes lb,hb

;
; Extra zero page variables
;
ScreenBase  = $E5            ; 2 bytes lb,hb for save/restore screenholes
Pointer     = $E7            ; 2 byte pointer for signature check
CurrBank    = $E9            ; current bank (needs to be out of bank switching memory)
begin       = $EA            ; for the directory searching
end         = $EC            ; for the directory searching
;
; SOS Error Codes
;
XDNFERR     = $10            ; Device not found
XBADDNUM    = $11            ; Invalid device number
XREQCODE    = $20            ; Invalid request code
XCTLCODE    = $21            ; Invalid control/status code
XCTLPARAM   = $22            ; Invalid control/status parameter
XNORESRC    = $25            ; Resource not available
XBADOP      = $26            ; Invalid operation
XIOERROR    = $27            ; I/O error
XNODRIVE    = $28            ; Drive not connected
XBYTECNT    = $2C            ; Byte count not a multiple of 512
XBLKNUM     = $2D            ; Block number to large
XDISKSW     = $2E            ; Disk switched
XDCMDERR    = $31            ; device command ABORTED error occurred
XCKDEVER    = $32            ; Check device readiness routine failed
XNORESET    = $33            ; Device reset failed
XNODEVIC    = $38            ; Device not connected

; Prodos block mode commands
Read        = 1
Write       = 2
Status      = 0

; for directory searching
storage     = 0                   ; file's storage type
tree        = $30                 ; storage type = tree index file
rootdir     = $f0                 ; storage type = root directory
nextdblk    = 2                   ; loc of next directory block
xblk        = $11                 ; loc of index block address in file entry
blks_used   = $13                 ; loc of blocks used in file entry
entry_len   = $27                 ; entry length in directory

;
; Switch Macro
;
.MACRO        SWITCH index,bounds,adrs_table,noexec    ; See SOS Reference
.IFNBLANK index                           ; If PARM1 is present,
            lda        index              ; load A with switch index
.ENDIF
.IFNBLANK   bounds                        ; If PARM2 is present,
            cmp        #bounds+1          ; perform bounds checking
            bcs        @110               ; on switch index
.ENDIF
            asl        A                  ; Multiply by 2 for table index
            tay
            lda        adrs_table+1,y     ; Get switch address from table
            pha                           ; and push onto Stack
            lda        adrs_table,y
            pha
.IFBLANK    noexec
            rts                           ; Exit to code
.ENDIF
@110:
.ENDMACRO

            .SEGMENT "TEXT"

;
; Comment Field of driver
;
            .word    $FFFF ; Signal that we have a comment
            .word    COMMENT_END - COMMENT
COMMENT:    .byte    "Apple /// Softcard CPM Block Driver - RJ"
COMMENT_END:

            .SEGMENT    "DATA"


;------------------------------------
;
; Device identification Block (DIB) - Volume #1
;
;------------------------------------

DIB1:       .word   DIB2             ; Link pointer
            .word   Entry            ; Entry pointer
DIB1_Name:  .byte   $05              ; Name length byte
            .byte   ".CPM1          "; Device name
            .byte   $80              ; Active, no page alignment
DIB1_Slot:  .byte   AutoScan         ; Slot number
            .byte   $00              ; Unit number
            .byte   DriverType       ; Type
            .byte   DriverSubtype    ; Subtype
            .byte   $00              ; Filler
DIB1_Blks:  .word   $0000            ; # Blocks in device
            .word   DriverMfgr       ; Manufacturer
            .word   DriverVersion    ; Driver version
            .word   $0000            ; DCB length followed by DCB
;
; Device identification Block (DIB) - Volume #2
; Page alignment begins here
;
DIB2:       .word   0000             ; Link pointer
            .word   Entry            ; Entry pointer
DIB2_Name:  .byte   $05              ; Name length byte
            .byte   ".CPM2          "; Device name
            .byte   $80              ; Active
DIB2_Slot:  .byte   AutoScan         ; Slot number
            .byte   $01              ; Unit number
            .byte   DriverType       ; Type
            .byte   DriverSubtype    ; Subtype
            .byte   $00              ; Filler
DIB2_Blks:  .word   $0000            ; # Blocks in device
            .word   DriverMfgr       ; Driver manufacturer
            .word   DriverVersion    ; Driver version
            .word   $0000            ; DCB length followed by DCB


;------------------------------------
;
; Local storage locations
;
;------------------------------------

LastOP:     .res    $02, $FF            ; Last operation for D_REPEAT calls
SIR_Addr:   .word   SIR_Tbl
SIR_Tbl:    .res    $05, $00
SIR_Len     =       *-SIR_Tbl
MaxUnits:   .byte   $02                    ; The maximum number of units

DCB_Idx:    .byte   $00                    ; DCB 0's blocks
            .byte   DIB2_Blks-DIB1_Blks    ; DCB 1's blocks

CardIsOK:   .byte   $00                    ; Have we found an intelligent disk controller yet?

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

ProBank:    .byte   $00                 ; destination bank for block data
Offset:     .byte   $00

xbytetmp:   .byte   $00                 ; save xbyte

namlen:     .byte   $00                 ; temp holder for name length
entry0:     .word   Buffer+4            ; loc of first file entry in directory

BlksUsed:   .word   0
infoblks:   .byte   0

TreeBlk1:   .res    512,0               ; buffer to hold tree index block
TreeBlk2:   .res    512,0               ; buffer to hold tree index block

Buffer:     .res    512,0               ; buffer for block read/writes
                                        ; buffered to remove the need working around the
                                        ; enhanced addressing

TreeBlk1Ad: .word   TreeBlk1            ;make sure reloc address is 16bit
TreeBlk2Ad: .word   TreeBlk2
BufferAd:   .word   Buffer



;------------------------------------
;
; Driver request handlers
;
;------------------------------------

Entry:
            jsr     Dispatch            ; Call the dispatcher
            ldx     SOS_Unit            ; Get drive number for this unit
            lda     ReqCode             ; Keep request around for D_REPEAT
            sta     LastOP,x            ; Keep track of last operation
            rts

;
; The Dispatcher.  Note that if we came in on a D_INIT call,
; we do a branch to Dispatch normally.  
; Dispatch is called as a subroutine!
;
DoTable:    .word    DRead-1            ; 0 Read request
            .word    DWrite-1           ; 1 Write request
            .word    DStatus-1          ; 2 Status request
            .word    DControl-1         ; 3 Control request
            .word    BadReq-1           ; 4 Unused
            .word    BadReq-1           ; 5 Unused
            .word    BadOp-1            ; 6 Open - valid for character devices
            .word    BadOp-1            ; 7 Close - valid for character devices
            .word    DInit-1            ; 8 Init request
            .word    DRepeat-1          ; 9 Repeat last read or write request

Dispatch:    SWITCH  ReqCode,9,DoTable  ; Serve the request

;
; Dispatch errors
;
BadReq:     lda     #XREQCODE           ; Bad request code!
            jsr     SYSERR              ; Return to SOS with error in A

BadOp:      lda     #XBADOP             ; Invalid operation!
            jsr     SYSERR              ; Return to SOS with error in A

;
; D_REPEAT - repeat the last D_READ or D_WRITE call
;
DRepeat:    ldx     SOS_Unit
            lda     LastOP,x            ; Recall the last thing we did
            cmp     #$02                ; Looking for operation < 2
            bcs     BadOp               ; Can only repeat a read or write
            sta     ReqCode
            jmp     Dispatch

NoDevice:   lda     #XDNFERR            ; Device not found
            jsr     SYSERR              ; Return to SOS with error in A

;
; D_INIT call processing - called once each for all volumes.
; on first entry we search the slots from 4 to 1 for a block devices 
; and use the first one we find
;
DInit:      
            lda     CardIsOK            ; Check if we have checked for a card already
            bne     FoundCard           ; Yes, skip signature check

CheckSig:
            lda     DIB1_Slot           ; Check configured slot for autoscan
            bpl     FixedSlot           ; No, use configured DIB1 slot
            lda     #ScanStart          ; else load starting scan slot
FixedSlot:  ora     #$C0                ; Form a $Cs00 address, where s = slot #
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
            
NoMatch:    lda     DIB1_Slot           ; No match, check if we are autoscanning
            cmp     #$ff
            bne     NoDevice            ; No we are not, error
            
            dec     Pointer+1           ; Else try next slot
            lda     Pointer+1
            and     #$07
            bne     CheckNext           ; Check next slot
            beq     NoDevice            ; Otherwise we did not find one :-(     
            
Match:      sta     ProDrvAdr+1         ; Set card driver entry low byte
            lda     Pointer+1
            sta     ProDrvAdr+2         ; Set card driver entry high byte
            and     #$07
            sta     DIB1_Slot           ; Set found slot for both DIBs
            sta     DIB2_Slot
            ora     #$10                ; SIR = $10+slot#
            sta     SIR_Tbl
            sta     CardIsOK            ; Remember that we found a card
            lda     #SIR_Len
            ldx     SIR_Addr
            ldy     SIR_Addr+1
            jsr     ALLOCSIR            ; Claim SIR
            bcs     NoDevice

FoundCard:  jsr     SetupIndex          ; find file and read in tree blk
            ldx     BlksUsed
            ldy     BlksUsed+1
            lda     SOS_Unit            ; determine which unit
            bne     Unit1

            stx     DIB1_Blks
            sty     DIB1_Blks+1
            lda     #0                  ; no error
            clc
            rts

Unit1:      stx     DIB2_Blks
            sty     DIB2_Blks+1
            lda     #0                  ; no error
            clc
            rts

NoDevice2:  lda     #XDNFERR            ; Device not found
            jsr     SYSERR              ; Return to SOS with error in A

;
; D_READ call processing
;
DRead:
            lda     CardIsOK            ; Did we previously find a card?
            bne     DReadGo
            jmp     NoDevice            ; If not... then bail
DReadGo:
            jsr     CkCnt               ; Checks for validity, aborts if not
            jsr     CkUnit              ; Checks for unit below unit max
            jsr     SetProUnit          ; Set Prodos unit
            lda     #$00                ; Zero # bytes read
            sta     Count               ; Local count of bytes read
            sta     Count+1
            tay
            sta     (QtyRead),Y         ; Userland count of bytes read
            iny
            sta     (QtyRead),Y         ; Msb of userland bytes read
            lda     Num_Blks            ; Check for block count greater than zero
            beq     ReadExit
            jsr     FixUp               ; Correct for addressing anomalies

            lda     ProBufOff+ExtPG     ; save xbyte
            sta     xbytetmp

ReadOne:    jsr     SetBlk              ; map file block to disk block
            jsr     SetProBuf           ; set Prodos buffer pointer
            jsr     ProDriver           ; call card prodos firmware interface
            bcs     IO_Error

            jsr     CopyBufR            ; copy the buffer to target memory

            inc     Count+1             ; increment our byte count by 512
            inc     Count+1
            inc     SosBlk
            bne     SkipReadMSBIncrement
            inc     SosBlk+1
SkipReadMSBIncrement:
            inc     SosBuf+1            ; Go get the next block in the buffer
            jsr     BumpSosBuf          ;   ...512 bytes in, and check the pointer
            dec     Num_Blks
            bne     ReadOne
            ldy     #0
            lda     Count               ; Local count of bytes read
            sta     (QtyRead),Y         ; Update # of bytes actually read
            lda     Count+1
            iny
            sta     (QtyRead),Y
            clc
ReadExit:
            lda     xbytetmp            ; restore xbyte
            sta     ProBufOff+ExtPG
            rts                         ; Exit read routines

IO_Error:   lda     #XIOERROR           ; I/O error
            jsr     SYSERR              ; Return to SOS with error in A

;
; D_WRITE call processing
;
DWrite:
            lda     CardIsOK            ; Did we previously find a card?
            bne     DWriteGo
            jmp     NoDevice            ; If not... then bail

DWriteGo:
            jsr     CkCnt               ; Checks for validity, aborts if not
            jsr     CkUnit              ; Checks for unit below unit max
            jsr     SetProUnit          ; Set Prodos unit
            lda     Num_Blks            ; Check for block count greater than zero
            beq     WriteExit
            jsr     FixUp               ; Correct for addressing anomalies
            lda     ProBufOff+ExtPG     ; save xbyte
            sta     xbytetmp

            jsr     SetProBuf           ; set Prodos buffer pointer

WriteOne:   jsr     SetBlk              ; map file block to disk block
            lda     #Write
            sta     ProCommand
            jsr     CopyBufW            ; copy data into local write buffer
            jsr     ProDriver           ; call card prodos firmware interface
            bcs     IO_Error

            inc     SosBlk              ; Bump the block number
            bne     SkipWriteMSBIncrement
            inc     SosBlk+1
SkipWriteMSBIncrement:
            inc     SosBuf+1            ; Go get the next block in the buffer
            jsr     BumpSosBuf          ;   ...512 bytes in, and check the pointer
            dec     Num_Blks
            bne     WriteOne
            clc
WriteExit:
            lda     xbytetmp            ; restore xbyte
            sta     ProBufOff+ExtPG
            rts

;
; D_STATUS call processing
;  $00 = Driver Status
;  $FE = Return preferred bitmap location ($FFFF)
;
DStatus:
            lda     CardIsOK            ; Did we previously find a card?
            bne     DStatusGo

            jmp     NoDevice            ; If not... then bail

DStatusGo:
            lda     CtlStat             ; Which status code to run?
            bne     DS0
                                        ; get status from card
            lda     #Status
            sta     ProCommand          ; Prepare to get status
            jsr     SetProUnit          ; set unitnumber
            jsr     ProDriver           ; call prodos block driver
            bcc     @ok
            jmp     NoDevice
            
@ok:        rts
            
DS0:        cmp     #$FE
            bne     DSWhat

            ldy     #$00                ; Return preferred bit map locations.
            lda     #$FF                ; We return FFFF, don't care
            sta     (CSList),Y
            iny
            sta     (CSList),Y       
            clc
            rts

DSWhat:     lda     #XCTLCODE           ; Control/status code no good
            jsr     SYSERR              ; Return to SOS with error in A

;
; D_CONTROL call processing
;  $00 = Reset device
;
DControl:
            lda     CardIsOK            ; Did we previously find a card?
            bne     DContGo
            jmp     NoDevice            ; If not... then bail
            
DContGo:    lda     CtlStat             ; Control command
            beq     CReset
            jmp     DCWhat              ; Control code no good!
CReset:     clc                         ; No-op
DCDone:     rts
          
DCWhat:     lda     #XCTLCODE           ; Control/status code no good
            jsr     SYSERR              ; Return to SOS with error in A

;------------------------------------
;
; Utility routines
;
;------------------------------------

;
; map requested block number to actual block in file
; Tree index block is pre loaded during unit init
; returns with ProBlock set
;
SetBlk:     lda     #Read
            sta     ProCommand          ; Prepare to read a block
            jsr     SetProBuf           ; set local buffer
            lda     SosBlk+1            ; get msb of requested file block
            tay

            lda     SOS_Unit            ; check which unit
            bne     SetBUnit1

            lda     TreeBlk1,y          ; lookup next index block
            sta     ProBlock
            lda     TreeBlk1+256,y
            sta     ProBlock+1
            jmp     GetBlk

SetBUnit1:  lda     TreeBlk2,y          ; lookup next index block
            sta     ProBlock
            lda     TreeBlk2+256,y
            sta     ProBlock+1

GetBlk:     jsr     ProDriver           ; and read it into Buffer

            lda     SosBlk              ; get lsb of file block
            tay
            lda     Buffer,y            ; lookup target block
            sta     ProBlock
            lda     Buffer+256,y
            sta     ProBlock+1
            rts

;
; Copy Buffer to target location
;
CopyBufR:   ldy     #0                  ; copy the buffer over
@C1:        lda     Buffer,y            ; using extended addressing
            sta     (SosBuf),y          ; to sos buffer pointer
            iny
            bne     @C1

            inc     SosBuf+1
@C2:        lda     Buffer+256,y
            sta     (SosBuf),y
            iny
            bne     @C2
            
            dec     SosBuf+1
            rts

;
; Copy write data into Buffer for writing
;
CopyBufW:   ldy     #0                  ; copy the data from sos buffer pointer
@C1:        lda     (SosBuf),y          ; using extended addressing
            sta     Buffer,y            ; to local Buffer
            iny
            bne     @C1

            inc     SosBuf+1
@C2:        lda     (SosBuf),y
            sta     Buffer+256,y
            iny
            bne     @C2
            
            dec     SosBuf+1            ; restore sosbuf pointer
            rts

;
; Check ReqCnt to ensure it is a multiple of 512.
;
CkCnt:      lda     ReqCnt              ; Look at the lsb of bytes requested
            bne     @1                  ; No good!  lsb should be 00
            lda     ReqCnt+1            ; Look at the msb
            lsr     A                   ; Put bottom bit into carry, 0 into top
            sta     Num_Blks            ; Convert bytes to number of blks to xfer
            bcc     CvtBlk              ; Carry is set from LSR to mark error.
@1:         lda     #XBYTECNT
            jsr     SYSERR              ; Return to SOS with error in A

;
; Test for valid block number; abort on error
;
CvtBlk:
            ldx     SOS_Unit
            ldy     DCB_Idx,x
            sec
            lda     DIB1_Blks+1,y       ; Blocks on unit msb
            sbc     SosBlk+1            ; User requested block number msb
            bvs     BlkErr              ; Not enough blocks on device for request
            beq     @1                  ; Equal msb; check lsb.
            rts                         ; Greater msb; we're ok.
@1:         lda     DIB1_Blks,y         ; Blocks on unit lsb
            sbc     SosBlk              ; User requested block number lsb
            bvs     BlkErr              ; Not enough blocks on device for request
            rts                         ; Equal or greater msb; we're ok.

BlkErr:     lda     #XBLKNUM
            jsr     SYSERR              ; Return to SOS with error in A

BumpSosBuf: inc     SosBuf+1            ; Increment SosBuf MSB
            ; fallthrough to FixUp

;
; Fix up the buffer pointer to correct for addressing
; anomalies.  We just need to do the initial checking
; for two cases:
; 00xx bank N -> 80xx bank N-1
; 20xx bank 8F if N was 0
; FDxx bank N -> 7Dxx bank N+1
; If pointer is adjusted, return with carry set
;
FixUp:      lda     SosBuf+1            ; Look at msb
            beq     @1                  ; That's one!
            cmp     #$FD                ; Is it the other one?
            bcs     @2                  ; Yep. fix it!
            rts                         ; Pointer unchanged, return carry clear.
@1:         lda     #$80                ; 00xx -> 80xx
            sta     SosBuf+1
            dec     SosBuf+ExtPG        ; Bank N -> band N-1
            lda     SosBuf+ExtPG        ; See if it was bank 0
            cmp     #$7F                ; (80) before the DEC.
            bne     @3                  ; Nope! all fixed.
            lda     #$20                ; If it was, change both
            sta     SosBuf+1            ; Msb of address and
            lda     #$8F
            sta     SosBuf+ExtPG        ; Bank number for bank 8F
            rts                         ; Return carry set
@2:         and     #$7F                ; Strip off high bit
            sta     SosBuf+1            ; FDxx ->7Dxx
            inc     SosBuf+ExtPG        ; Bank N -> bank N+1
@3:         rts                         ; Return carry set

CkUnit:     lda     SOS_Unit            ; Checks for unit below unit max
            cmp     MaxUnits
            bmi     UnitOk
NoUnit:     lda     XBADDNUM            ; Report no unit to SOS
            jsr     SYSERR
UnitOk:     clc
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
; Set Prodos buffer pointer
;
SetProBuf:  lda     BufferAd            ; setup ProBuf
            sta     ProBuf
            lda     BufferAd+1
            sta     ProBuf+1
            lda     #0                  ; turn off extended addressing
            sta     ProBufOff+ExtPG
            rts

;
; jsr to card firmware driver
; We update the address based on the slot and firmware CxFF byte
;
ProDriver:  sei                         ; disable interrupts while changing things
            lda     #$FF
            sta     E1908               ; E1908 = NON-ZERO LOCKOUT MOUSE
            jsr     SaveMem             ; save and swap in card screen hole & zeropage
            jsr     GoSlow
ProDrvAdr:  jsr     $0000               ; call device entry
            sei                         ; Keep interrupts off incase card firmware reenabled
            jsr     GoFast
            jsr     RestMem             ; save and swap out card screen hole & zeropage
            lda     #$18                ; Clear CB1 & CB2 flags - VBL
            sta     E_IFR               ; this seems more for mame, its a little different
            lda     #$00
            sta     E1908               ; SAY OK TO MOUSE
            cli                         ; enable interrupts again
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
            eor     DIB1_Slot           ; Cycle page index between $x8 and $x8+n as long as N in 1..7
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
; Set Prodos unit number
; this driver assumes both files are on unit0
;
SetProUnit: lda     DIB1_Slot           ; create the slot/unit byte
            asl                         ; 7 6 5 4 3 2 1 0
            asl                         ; D S S S 0 0 0 0
            asl
            asl
            sta     ProUnit
            rts


;
; Search directory and find the cpm disk image file then
; read in the tree index blk and setup the number of blocks
;
SetupIndex: jsr     SetProBuf           ; set local buffer
            lda     #Read               ; read command
            sta     ProCommand
            jsr     SetProUnit          ; unit
            lda     #2                  ; block 2 (first directory block)
            sta     ProBlock
            lda     #0
            sta     ProBlock+1
rd_dir:     jsr     ProDriver           ; read the block

;
; search directory for file 'CPM1' or 'CPM2'
;

FindFile:   lda $fff0

            lda     entry0              ; loc of first file entry in directory
            sta     begin
            lda     entry0+1
            sta     begin+1
            lda     #0                  ; xbyte=0
            sta     begin+ExtPG

search:     clc                         ; end:=begin+512-entry.len
            lda     begin+1
            adc     #2
            sta     end+1
            sec     
            lda     begin
            sbc     #entry_len          ; entry length
            sta     end
            lda     end+1
            sbc     #0
            sta     end+1

srch020:    lda     SOS_Unit            ; setup namlen depending on unit 
            bne     srch021
            ldy     DIB1_Name
            dey                         ; -1 to remove '.'
            sty     namlen
            bne     srch022

srch021:    ldy     DIB2_Name
            dey
            sty     namlen

srch022:    ldy     #0                  ; does count match?
            lda     (begin),y
            and     #$f
            cmp     namlen
            bne     srch040             ; no match
            tay
srch030:    lda     SOS_Unit
            bne     srch060

            lda     (begin),y           ; do chars match?
            cmp     DIB1_Name+1,y
            bne     srch040             ; no match
            dey
            bne     srch030
            beq     srch050

srch060:    lda     (begin),y           ; do chars match?
            cmp     DIB2_Name+1,y
            bne     srch040             ; no match
            dey
            bne     srch030

srch050:    ldy     #storage            ; test storage type
            lda     (begin),y           ; must be tree
            and     #$f0
            cmp     #tree
            beq     match
            cmp     #rootdir            ; skip if stg type=rootdir
            beq     srch040

srch040:    clc
            lda     begin
            adc     #entry_len
            sta     begin
            lda     begin+1
            adc     #0
            sta     begin+1
            lda     end
            cmp     begin               ; is begin <=end?
            lda     end+1
            sbc     begin+1
            bcs     srch020             ; yes,search next field in current block

            clc                         ; begin :=end+entry.len
            lda     end
            adc     #entry_len
            sta     begin
            lda     end+1
            adc     #0
            sta     begin+1

            ldy     #nextdblk           ; if nextdir field = 0 then done
            lda     Buffer,y
            sta     ProBlock
            iny
            lda     Buffer,y
            sta     ProBlock+1
            bne     NxtDirBlk
            lda     ProBlock
            bne     NxtDirBlk
            beq     BadDrive            ; disk image file not found

NxtDirBlk:  jmp     rd_dir

BadDrive:   lda     #XNODRIVE           ; Drive not connected
            jsr     SYSERR

;
; file entry found
; read in its index block into the TreeBlock buffer
;
match:      ldy     #xblk
            lda     (begin),y
            sta     ProBlock
            iny
            lda     (begin),y
            sta     ProBlock+1
            lda     SOS_Unit             ; which unit?
            bne     MaUnit1

            lda     TreeBlk1Ad           ; setup buffer for disk1
            ldx     TreeBlk1Ad+1
            jmp     GetTreeB

MaUnit1:    lda     TreeBlk2Ad           ; setup buffer for disk2
            ldx     TreeBlk2Ad+1

GetTreeB:   sta     ProBuf
            stx     ProBuf+1
            jsr     ProDriver            ; read tree index block

            ldy     #blks_used           ; now we need to update the total
            lda     (begin),y            ; blocks for this file into the DIB
            sta     BlksUsed
            iny
            lda     (begin),y
            sta     BlksUsed+1
            
            ldy     #0                   ; now we need to subtract the index overhead
            lda     SOS_Unit
            bne     chk1

chk0:       lda     TreeBlk1,y           ; counter the number of sapling blks
            beq     chkmsb0
            iny
            bne     chk0
chkmsb0:    lda     TreeBlk1+256,y
            beq     fin1
            iny
            bne     chk0

chk1:       lda     TreeBlk2,y
            beq     chkmsb1
            iny
            bne     chk1
chkmsb1:    lda     TreeBlk2+256,y
            beq     fin1
            iny
            bne     chk1

fin1:       iny                          ; add one for tree block
            sty     infoblks             ; total number of info blocks

            lda     BlksUsed             ; now subtract the info blocks count
            clc
            sbc     infoblks
            sta     BlksUsed
            lda     BlksUsed+1
            sbc     #0
            sta     BlksUsed+1

            rts

            .ENDPROC
            .END

