/* Linker script for RV32I bare-metal core simulation
 *
 * Address map
 *   0x00000000  .text.init  (reset vector / _start)
 *   0x00000000+ .text       (remainder of code)
 *   follows     .data       (initialised data – loaded into dmem via hex)
 *   follows     .bss        (zero-initialised – dmem starts at 0 anyway)
 *
 * tohost / fromhost are absolute symbols at 0x00000C00 / 0x00000C04.
 * These fall within dmem's 1024-word (4 KB) range (word index 768/769).
 * The testbench monitors dmem[768] for the PASS/FAIL result.
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS
{
  . = 0x00000000;

  /* Reset vector / init code first */
  .text.init : {
    *(.text.init)
  }

  /* All remaining code */
  .text : {
    *(.text)
    *(.text.*)
  }

  . = ALIGN(4);

  /* Initialised data (stored in the flat hex, loaded into dmem) */
  .data : {
    *(.data)
    *(.data.*)
    *(.rodata)
    *(.rodata.*)
  }

  . = ALIGN(4);

  /* Zero-initialised data (dmem already starts at 0, so NOLOAD is fine) */
  .bss (NOLOAD) : {
    *(.bss)
    *(.bss.*)
    *(COMMON)
  }
}

/*
 * tohost/fromhost: absolute symbols at the top of the dmem range.
 * PROVIDE means "use the object-file symbol if it already exists".
 * Since our riscv_test.h never defines them in assembly, these take effect.
 */
PROVIDE(tohost   = 0x00000C00);
PROVIDE(fromhost = 0x00000C04);
