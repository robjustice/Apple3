# Titan /// plus //e Emulation Interpreter

This is a SOS Interpreter to allow launching of the //e emulation from a Selector menu.
This is based on a disassembly of the Titan //e disk. The Interpreter is loaded which includes the rom images and other code all bundled together. It then moves things around in memory back to how the original Titan2e boot disk loadeded things and runs. See code for more details.

This is included in the original soshdboot disk images. I just had not got around to documenting and sharing the code until now.

Note, this only allows the emulation to be launched and config changed before launching. No saving of the config via the menu is supported with this current implementation.

## Build the Interpreter:
```
ca65 titan2e.interp.s -l titan2e.interp.lst
ca65 0C00_part.s -l 0C00_part.lst
ld65 titan2e.interp.o 0C00_part.o -o SOS.INTERP#0c0000 -C apple3.cfg
```

## Thanks
I used the following for reference to the original emulation software 
https://github.com/brouhaha/a3a2em

And the Sourcegen Disassembler:
https://6502bench.com/
