# Softcard /// Interpreter

This is a SOS Interpreter to allow launching of the Softcard /// CPM from a hard disk (ie no floppy needed).

The approach that this uses is to load a virtual floppy driver into a spare bank of memory and then use a small routine in non banked memory to call this. The jump to the Block IO routine in the original code is then redirected to this new one. The floppy blocks requested are mapped to the actual block on the the sos harddisk for the image file. The Softcard CPM includes its own floppy driver and this is also redirected to the virtual driver only for drive A. Drive B requests will still go to the external disk drive.

It requires a disk image of the Softcard /// CPM boot disk in po format to be loaded onto the sos hard disk named 'CPMIMAGE.PO'
 
During the booting/loading process, the driver looks for certain blocks being read and patches these as they are read to redirect to the 'new' floppy driver. That way you can just reload the cpm boot disk image and then it gets patched automatically. (this will not work if the disk contains a newer CPM, I'll update when one surfaces)

I used a disassembly of the CPM boot disk to understand the inner workings better and determine what needed to be patched. I have include the latest for this in the disassembly folder.

# Softcard /// CPM1 hard disk driver

The Softcard came with a driver for use with the Profile hard disk. The Utils disk included a program to create a sos file on the Profile that can then be used as a harddisk from CPM's view. This is similiar in operation to the virtual floppy driver, it maps the CPM block requests to the actual blocks of the CPM1 file. I added this file layer on top of my Problock driver so that this can be used on any prodos block mode card.

The driver uses the device names as the filenames on the sos disk with the '.' removed.

# Ready to use images

I have included in the disks folder a soshdboot harddisk image with this all preloaded and added to the Selector menu. This can be booted with either the new rom or the boot floppy from soshdboot: https://github.com/robjustice/soshdboot

This image has both a CPM1(this is from the apple3rtr image) and CPM2(empty) disk file on it, and the drivers loaded onto the CPMIMAGE.PO. These are configured in CPM as C and D drives.

## Build the Interpreter:
```
ca65 softcard.s -l softcard.lst
ca65 virtualdisk.s -l virtualdisk.lst
ld65 softcard.o virtualdisk.o -o SOFTCARD.INTERP#0c0000 -C apple3.cfg
```

## Build the cpm1 driver:
```
ca65.exe cpm1.s -l cpm1.lst
ld65.exe cpm1.o -o cpm1.o65 -C Apple3_o65.cfg
python A3Driverutil.py update cpm1.o65 SOS.DRIVER#0c0000
```
