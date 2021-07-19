; SOS based launcher for the Microsoft Softcard ///
;
; Uses a disk image in .po format and mounts this like a virtual floppy
; The CPM disk image is patched to redirect the inbuilt floppy driver to
; this virtual drive for unit0 (D1)
;
; Inspired by the idea of Holodeck for the Apple2
; this is a trimmed down version of my /// proof of concept version
;
;
;    Memory layout:
;    $1300          Holds the stub to replace the ROM Blockio routine (out of bank switched memory)
;                   and Sectio routine that the internal CPM driver uses
;    Bank4
;    $3000 - $33FF  This will hold the two index blocks for the image file
;    $3400 - $35FF  Buffer for the disk read/writes
;    $3600 - $xxFF  The virtual disk driver is moved here, called by the stub
;
;  29/06/21 Robert Justice
;

            .segment "RAM"
            .setcpu "6502"
            
            .import  VDrvLAddr     ; virtual driver load address
            .import  VDrvSize      ; size of virtual disk driver
            .import  DInit         ; init virtual disk driver
            .import  BlockioStb    ; entry point for blockio stub
            .import  StartStub
            .import  EndStub
            .import  StubLen

SysErr        = $1928          ; Report error to system
Bank_Reg      = $FFEF          ; Bank register
EReg          = $FFDF          ; Environment register

TERMINATE     = $65
GET_FILE_INFO = $C4
SET_PREFIX    = $C6
OPEN          = $C8
READ          = $CA
WRITE         = $CB
CLOSE         = $CC
SET_MARK      = $CE

Ptr1        = $20            ; ZP pointer 1
Ptr2        = $22            ; ZP pointer 2
CExtPG      = $1601          ; Interp extended address offset

IBBUFP      = $85
IBCMD       = $87


            .org     $A200 - 14    ; use $A200 so we are out of paged mem
                                   ; and above boot sector
; sos interp header
            .byte    "SOS NTRP"
            .word    0000
            .word    CodeSt
            .word    (CodeEnd-CodeSt)+VDrvSize

CodeSt:     jmp      Init

;------------------
; param lists
; open console param list
OpenCon:    .byte   4
            .word   NameCon
ConRef:     .byte   0
            .word   0
            .byte   0

NameCon:    .byte   8
            .byte   ".CONSOLE"

; init console param list
InitCon:    .byte   3
InitRef:    .byte   0a 
            .word   initscr
            .word   endinit-initscr

initscr:    .byte   16                ; set text mode
            .byte   3                 ; 80x24
            .byte   28                ; clear viewport 
            .byte   24,30,25,11         ; set cursor xpos, column, ypos, row
            .byte   "Softcard /// Loader"
            .byte   24,27,25,13         ; set cursor xpos, column, ypos, row
endinit     =       *

;
; copy the virtual disk driver code to bank 4
; its added at the end of this code by the linker
;
Init:       brk                        ;open console
            .byte   OPEN
            .word   OpenCon
            beq     @ok_c1
            jmp     Error

@ok_c1:     lda     ConRef             ;update reference numbers
            sta     InitRef
            sta     WriteRef
            sta     CloseRef

            brk                        ;init console
            .byte   WRITE
            .word   InitCon
            beq     @ok_c2
            jmp     Error


@ok_c2:     lda     #<VDrvCode     ; set source ptr to virtual disk drv code
            sta     Ptr1
            lda     #>VDrvCode
            sta     Ptr1+1
            lda     #0
            sta     Ptr1+CExtPG

            lda     #0             ; set dest ptr = 04:1600
            sta     Ptr2
            lda     #$16
            sta     Ptr2+1
            lda     #$84
            sta     Ptr2+CExtPG

            ldx     #0
@c1:        jsr     Copy1
            inc     Ptr1+1
            inc     Ptr2+1
            inx
            cpx     #>VDrvSize     ; just check in page sizes, close enough
            bcc     @c1
            beq     @c1

            jmp     SetupImg

;
; open disk image file param list
OpenImg:    .byte   4          ;#params
            .word   FileNam2   ;pointer to filename
ImgRef:     .byte   0          ;ref_num result
            .word   OptLst     ;option list ptr
            .byte   4          ;length option list 

FileNam2:   .byte   11
            .byte   "CPMIMAGE.PO"

OptLst:     .byte   1          ;req_access=open for reading only
            .byte   4          ;pages, 1024 byte io-buffer
            .word   Ptr1       ;io_buffer (extended pointer)

; set mark for disk image file param list
MarkImg:    .byte   3          ;#params
MarkRef:    .byte   0          ;ref_num
            .byte   0          ;base=absolute
            .byte   $00        ;absolute byte pos = 00020000
            .byte   $00
            .byte   $02
            .byte   $00
            
;
; setup the index blocks for the image file, so we can map the requested
; image file block to the real block on the harddisk block device
; We'll try to use SOS to do some of this
; 
; if we open the image file and specify an io buffer (1k), we get the first index block
; easily.


SetupImg:   lda     #4          ;**************for debug to check we have loaded it
            sta     Bank_Reg    ;**************

            lda     #0                 ;set buffer extended pointer 04:0800
            sta     Ptr1
            lda     #$08
            sta     Ptr1+1
            lda     #$84               ;and its xbyte
            sta     Ptr1+CExtPG

            brk                        ;open the disk image file
            .byte   OPEN               ;as we allocated our own buffer, we get the first
            .word   OpenImg            ; blk of data and the first index blk read to that
            beq     @ok4               ; buffer
            jmp     Error              ;report error and exit

@ok4:       lda     #0                 ;now we'll copy the index block to 04:1000
            sta     Ptr2               ;Ptr2 = destination 04:1000
            lda     #$10
            sta     Ptr2+1
            lda     #$84
            sta     Ptr2+CExtPG
            inc     Ptr1+1             ;Ptr1 = source 04:0A00
            inc     Ptr1+1
            jsr     Copy
;
; need the second index block, set the file mark to 128k bytes
; will trigger sos to get the next index block into the io buffer
;
            lda     ImgRef             ;update the ref num
            sta     MarkRef
            brk                        ;set the current file position for image to 128k
            .byte   SET_MARK
            .word   MarkImg
            beq     @ok5
            jmp     Error              ;report error and exit

@ok5:       dec     Ptr1+1             ;setup Ptrs
            inc     Ptr2+1
            jsr     Copy               ;and copy the next index blk
;
; Move code to page x for call to rom block interface
; to allow switching to other bank
; hopefully, this stays out of the way
;
            ldx     #<StubLen-1
@1:         lda     VDrvCode+(StartStub - VDrvCode),x
            sta     BlockioStb,x
            dex
            bpl     @1
;
; init the virtual disk driver
;
            lda     #4
            sta     Bank_Reg
            jsr     DInit
            bne     Error
;
; Now lets pretend to be the rom and boot the disk image
; load block 0 to $A000, and then jmp there
;
            lda     #$77               ;set environmnent same as monitor
            sta     EReg
            lda     #3                 ;set zero page to 3 (same as monitor) 
            sta     $FFD0
            ;LDA     $C052              ;40 column
            JSR     $FB63 ;;COL40
            lda     #0                 ;set buffer to $A000
            sta     IBBUFP
            sta     Bank_Reg           ;and also set bank0
            lda     #$A0
            sta     IBBUFP+1
            ldx     #1                 ;read
            stx     IBCMD
            dex                        ;x=block msb
            txa                        ;a=block lsb
            jsr     BlockioStb         ;go call our blockio and read block 0
            jmp     $A000              ;now go run the bootloader

;
; subroutines
;
;Copy 2 x pages from Ptr1 to Ptr2
;using extended addressing if xbyte is set
Copy:       ldy     #0
@c1:        lda     (Ptr1),y
            sta     (Ptr2),y
            iny
            bne     @c1
            inc     Ptr1+1
            inc     Ptr2+1
Copy1:      ldy     #0                 ; ldy #0 lets us enter for one page copy
@c2:        lda     (Ptr1),y
            sta     (Ptr2),y
            iny
            bne     @c2
            rts
;
; Error handling
;
; error console param list
WriteErr:   .byte   3
WriteRef:   .byte   0a 
ErrRef:     .word   0                  ; data buffer
            .word   0                  ; request count

error1:     .byte   "CPMIMAGE.PO file not found"
enderror1   = *

error2:     .byte   "    SOS Error: "
ErrCode:    .byte   "xx"
enderror2   = *

; close console param list
CloseCon:   .byte   1
CloseRef:   .byte   0

Error:      cmp     #$46               ; file not found
            bne     @e1
            lda     #<error1
            sta     ErrRef
            lda     #>error1
            sta     ErrRef+1
            lda     #enderror1-error1
            sta     ErrRef+2
            jmp     exit

@e1:        jsr     PrByte             ; all other errors, print the code
            lda     #<error2
            sta     ErrRef
            lda     #>error2
            sta     ErrRef+1
            lda     #enderror2-error2
            sta     ErrRef+2

exit:       brk
            .byte   WRITE
            .word   WriteErr

            ldx     #0                ;delay before exit
            ldy     #0
@w1:        dey
            bne     @w1
            dex
            bne     @w1

            brk                       ;close .CONSOLE
            .byte   CLOSE
            .word   CloseCon

term:       brk                       ;terminate back to Selector
            .byte   TERMINATE
            .word   term

;
; subroutine to print a byte in a in hex form (destructive)
; puts result into ErrCode
;
PrByte:      ldx    #0
             pha                      ;save a for lsd
             lsr                      ;msd to lsd position
             lsr
             lsr
             lsr
             jsr    PrHex             ;output hex digit
             pla                      ;restore a
; fall through to print hex routine

PrHex:       and    #$0f              ;mask lsd for hex print
             ora    #'0'              ;add "0"
             cmp    #'9'+1            ;is it a decimal digit?
             bcc    Store             ;yes! output it
             adc    #6                ;add offset for letter a-f
; fall through to print routine

Store:       sta    ErrCode,x
             inx
             rts

; we append the virtual disk driver here during linking
VDrvCode    = *

CodeEnd     = *