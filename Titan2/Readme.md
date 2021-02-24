# Titan /// plus // Emulation patch info for Selector 

This details the patches I did to allow the Titan ///+// card's emulation to be started from Selector ///.

Selector /// includes an install program that sets up the normal Apple II emulation onto a harddisk to allow launching without the need for a floppy. Support for the Titan cards was never provided.

After Selector /// has been installed, and the Emulation installer has been run. The following is the disk structure and files created.
```
-PROGRAMS
        -APPLE2
              -INSTALL.APPLE2 - This is the Selector Apple2 Emulation install program
               SOS.INTERP     - This is the Loader and config code for the Apple2 Emulation
                                it refers and loads the APPLE2.INTERPS and APPLE2.DATA files
               APPLE2.INTERPS   This holds the slot 5-7, Integer and Applesoft BASIC ROMs
               APPLE2.DATA      This looks like it holds the current config settings selected for the emulation
```               
The Titan III+II card is basically a 128k saturn language card with an Apple II game port on it. The whole thing is enabled by setting the A3 to 1MHz and then performing an access to the Card slot rom (I/O select). The card then stays enabled while the speed is kept at 1Mhz. Once you switch back to 2MHz, the card deselects.

I did some fishing around on the III+II disk, and found is has a lda CX00 for each slot, so this allows the disk to work with the card in any slot.
```
         lda     $c100
         lda     $c200
         lda     $c300
         lda     $c400
```
         
Using the diassembly of the A2 emulation available here https://github.com/brouhaha/a3a2em, I found that the SOS.INTERP file mentioned above has the init code in it. After some more digging, I came up with this comparison of the differences in code between the standard and Titan versions.
```
Offset in   Original                                ///+II
SOS.INTERP
                                                
0471        a9 00       lda #$00                    a9 00       lda #$00
0473        8d f2 03    sta $03f2                   8d f2 03    sta $03f2
0476        a9 e0       lda #$e0                    a9 00       lda #$00
0478        8d f3 03    sta $03f3                   8d f4 03    sta $03f4
047b        20 6f fb    jsr $fb6f                   ad 00 c1    lda $c100 ; enable ///+II card
047e        ad 51 c0    lda $c051                   ad 00 c2    lda $c200
0481        ad 56 c0    lda $c056                   ad 00 c3    lda $c300
0484        ad 54 c0    lda $c054                   ad 00 c4    lda $c400
0487        ee f4 03    inc $03f4                   ad 84 c0    lda $c084
048a        58          cli                         4c 62 fa    jmp $fa62 ; jmp A2 reset 
048b        4c 62 fa    jmp $fa62 ; jmp A2 reset
```

Now to patch this in some how. The approach I took was to copy and rename the three selector files for the standard emulation disk to create a set for the Titan card.
```
SOS.INTERP     -> SOS3P2.INTERP
APPLE2.INTERPS -> APP3P2.INTERPS
APPLE2.DATA    -> APP3P2.DATA
```

Then I used a hex editor to change the filenames in the SOS3P2.INTERP file to reference the new names APP3P2.INTERPS & APP3P2.DATA
And finally update the init code in the SOS3P2.INTERP file as detailed above. See the image of the changes in red.

![Changes](/Titan2/sos3p2_edit.jpg)

I then found that due to the A3 having the disk controller in Slot6, and no slot7 to put a block storage device in, then its difficult to boot from one in Slot 1-4 directly.

To support this, I wanted to provide another version and patch the Autostart rom to scan the slots the other way around. I also wanted to apply the patch to only check for 3 ID bytes, and not 4 to allow block devices to boot. For this I created another set of files:
```
SOS3P2.INTERP  -> SOS3P26.INTERP
APP3P2.INTERPS -> AP3P26.INTERPS
APP3P2.DATA    -> AP3P26.DATA
```

Then I investigated which file has the ROMs, and came up with this map for APPLE2.INTERPS file
```
file offset
0000 - 00ff Slot5 rom - applesoft setup?
0100 - 01ff Slot6 rom - applesoft setup?
0200 - 02ff Slot7 rom - applesoft setup?
0300 - 03ff Slot5 rom - integer setup?
0400 - 04ff Slot6 rom - integer setup?
0500 - 05ff Slot7 rom - integer setup?
0600 - 0dff D0 - applesoft
0e00 - 15ff D8 - applesoft
1600 - 1dff E0 - applesoft
1e00 - 25ff E8 - applesoft
2600 - 2dff F0 - applesoft
2e00 - 35ff F8 - Autostart
3600 - 3dff D0 - programmers aid
3e00 - 45ff D8 - blank
4600 - 4dff E0 - integer
4e00 - 55ff E8 - integer
5600 - 5dff F0 - integer
5e00 - 65ff F8 - Autostart?
```

This was the required patch to apply
```
FAB4  A9 *C0               LDA #$C0 ; ; LOAD LOW SLOT -1
FAB6  86 00                STX LOC0 ; ; SETPG3 MUST RETURN X=0
FAB8  85 01                STA LOC1 ; ; SET PTR H
FABA  A0 *05               SLOOP: LDY #5 ;Y is byte ptr, check 3 ID bytes instead of 4
FABC  *E6 01               INC LOC1
FABE  A5 01                LDA LOC1
FAC0  C9 *C7               CMP #$C7 ; ; AT LAST SLOT YET?
FAC2  F0 D7                BEQ FIXSEV ; ; YES AND IT CAN'T BE A DISK
FAC4  8D F8 07             STA MSLOT
FAC7  B1 00        NXTBYT: LDA (LOC0),Y ; ; FETCH A SLOT BYTE
FAC9  D9 01 FB             CMP DISKID-1,Y ; ; IS IT A DISK ??
FACC  D0 EC                BNE SLOOP ; ; NO, SO NEXT SLOT DOWN
FACE  88                   DEY
FACF  88                   DEY  ; YES, SO CHECK NEXT BYTE
FAD0  10 F5                BPL NXTBYT ; ; UNTIL 3 BYTES CHECKED
FAD2  6C 00 00             JMP (LOC0) ; ; GO BOOT...
```

and the changes in the AP3P26.INTERPS:
```
offset
30b5    c8 -> c0
30bb    07 -> 05
30bc    c6 -> e6
30c1    c0 -> c7

60b5    c8 -> c0
60bb    07 -> 05
60bc    c6 -> e6
60c1    c0 -> c7
```

Once these files were all prepared, the last step was to add some new menu entries into Selector to allow these Interpreters to be run directly.
