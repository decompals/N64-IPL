# N64 IPL

This repository contains disassemblies of IPL1, IPL2 (both in `src/pifrom.s`) and IPL3 (`src/ipl3.s`), the three stages of Nintendo 64 boot code.

When assembling with the IDO 5.3 compiler with -O2 optimization, they produce matching binaries. Instructions in the disassembly are often reordered with respect to their locations in the final binaries, the pre-reordering locations are often the more natural way to write it.

These disassemblies are primarily for educational, preservation and reference purposes. The PIF ROM inside the N64 where IPL1 and IPL2 are stored is not overwritable by software, the only way to change it on a console is to replace the PIF. IPL3 is verified with a checksum prior to execution, the only way to edit or write a new IPL3 is to find a hash collision via bruteforce, tools for doing so are not provided.

## Building

Run `make` to build all binaries. To test matching, provide a binary file for the version you want to test against in the root directory before running `make`. The binary should be named one of the following:
 - `pifrom.ntsc.bin`
 - `pifrom.pal.bin`
 - `pifrom.mpal.bin`
 - `ipl3.6106.bin`
 - `ipl3.6102_7101.bin`
 - `ipl3.7102.bin`
 - `ipl3.X103.bin`
 - `ipl3.X105.bin`
 - `ipl3.X106.bin`

To build a specific binary, run `make` followed by one of the above names excluding `.bin`.

## IPL1

IPL1 is the first code that runs on the CPU after it is powered on or reset. It performs very basic hardware initialization, before copying IPL2 to RSP IMEM and jumping to it.

## IPL2

IPL2 will read the ROM header and IPL3 from the cartridge into RSP DMEM, compute a checksum over IPL3 and ask the PIF to verify the checksum. If the checksum is OK, IPL3 is entered.

## IPL3

IPL3 has several versions with varying associated CICs, however the functionality is broadly the same. IPL3 initializes RDRAM and the caches before computing and verifying the ROM checksum. If the computed ROM checksum matches the ROM header, the ROM entrypoint function is entered.
