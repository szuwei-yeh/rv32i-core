#!/usr/bin/env python3
"""
elf2hex.py – Convert a 32-bit RISC-V ELF into a flat $readmemh-compatible
hex file (one 32-bit word per line, little-endian, no address markers).

Usage:
    python3 elf2hex.py input.elf output.hex [mem_words]

    mem_words : size of the output hex in 32-bit words (default 4096 = 16 KB).
                Words are pre-filled with 0x00000013 (ADDI x0,x0,0 = NOP).

The script reads every PT_LOAD programme-header segment from the ELF and
places its bytes at the correct byte offset in the flat image.  This means
both the .text section (code) and the .data section (initialised data) end up
at their correct virtual addresses – both imem and dmem can be initialised
from the same file.
"""

import sys
import struct

def parse_elf32(path: str, mem_words: int) -> bytearray:
    """Return a flat byte-array representing the memory image.

    The image is zero-initialised.  Zero decodes as an illegal instruction
    in RV32I (all valid opcodes have bits[1:0] = 11), but control.v treats
    any unrecognised opcode as a NOP, so stray fetches to unpopulated words
    are harmless.  More importantly, the tohost word (at dmem address 0xC00)
    must start at 0 so the testbench does not interpret it as a pre-loaded
    PASS/FAIL result.
    """
    mem = bytearray(mem_words * 4)  # all zeros

    with open(path, 'rb') as f:
        raw = f.read()

    # ── ELF identification ────────────────────────────────────────────────
    if raw[:4] != b'\x7fELF':
        sys.exit(f'elf2hex: {path}: not an ELF file')

    ei_class = raw[4]   # 1 = 32-bit
    ei_data  = raw[5]   # 1 = little-endian

    if ei_class != 1:
        sys.exit(f'elf2hex: {path}: not a 32-bit ELF (class={ei_class})')
    if ei_data != 1:
        sys.exit(f'elf2hex: {path}: not little-endian (data={ei_data})')

    # ── ELF32 header fields we need ───────────────────────────────────────
    # Offsets per the ELF32 spec:
    #   0x18 e_entry  (4 B)
    #   0x1C e_phoff  (4 B)  – programme-header table offset
    #   0x28 e_phentsize (2 B)
    #   0x2C e_phnum     (2 B)
    # ELF32 header layout (all little-endian):
    #   0x1C  e_phoff     (4 B) – programme-header table file offset
    #   0x28  e_ehsize    (2 B) – ELF header size (52 for ELF32)
    #   0x2A  e_phentsize (2 B) – programme-header entry size (32 for ELF32)
    #   0x2C  e_phnum     (2 B) – number of programme-header entries
    e_phoff     = struct.unpack_from('<I', raw, 0x1C)[0]
    e_phentsize = struct.unpack_from('<H', raw, 0x2A)[0]
    e_phnum     = struct.unpack_from('<H', raw, 0x2C)[0]

    # ── Walk programme headers ─────────────────────────────────────────────
    # ELF32 programme-header fields:
    #   +0x00  p_type   (4 B)
    #   +0x04  p_offset (4 B) – byte offset in file
    #   +0x08  p_vaddr  (4 B) – virtual address in memory
    #   +0x0C  p_paddr  (4 B) – physical address (ignored)
    #   +0x10  p_filesz (4 B) – bytes in file image
    #   +0x14  p_memsz  (4 B) – bytes in memory image
    #   +0x18  p_flags  (4 B)
    #   +0x1C  p_align  (4 B)
    PT_LOAD = 1

    for i in range(e_phnum):
        ph = e_phoff + i * e_phentsize
        p_type   = struct.unpack_from('<I', raw, ph + 0x00)[0]
        p_offset = struct.unpack_from('<I', raw, ph + 0x04)[0]
        p_vaddr  = struct.unpack_from('<I', raw, ph + 0x08)[0]
        p_filesz = struct.unpack_from('<I', raw, ph + 0x10)[0]

        if p_type != PT_LOAD or p_filesz == 0:
            continue

        end_byte = p_vaddr + p_filesz
        mem_bytes = mem_words * 4

        if p_vaddr >= mem_bytes:
            print(f'elf2hex: warning: segment vaddr=0x{p_vaddr:08x} '
                  f'is beyond mem size 0x{mem_bytes:08x}; skipping',
                  file=sys.stderr)
            continue

        # Clamp copy length if segment overflows the memory image.
        copy_len = min(p_filesz, mem_bytes - p_vaddr)
        if copy_len < p_filesz:
            print(f'elf2hex: warning: segment truncated '
                  f'(vaddr=0x{p_vaddr:08x}, filesz=0x{p_filesz:x})',
                  file=sys.stderr)

        mem[p_vaddr: p_vaddr + copy_len] = raw[p_offset: p_offset + copy_len]

    return mem


def write_hex(mem: bytearray, path: str) -> None:
    """Write one 32-bit word per line in uppercase hex."""
    with open(path, 'w') as f:
        for i in range(0, len(mem), 4):
            word = struct.unpack_from('<I', mem, i)[0]
            f.write(f'{word:08X}\n')


def main() -> None:
    if len(sys.argv) < 3:
        print(f'Usage: {sys.argv[0]} input.elf output.hex [mem_words]',
              file=sys.stderr)
        sys.exit(1)

    elf_path  = sys.argv[1]
    hex_path  = sys.argv[2]
    mem_words = int(sys.argv[3]) if len(sys.argv) > 3 else 4096

    mem = parse_elf32(elf_path, mem_words)
    write_hex(mem, hex_path)


if __name__ == '__main__':
    main()
