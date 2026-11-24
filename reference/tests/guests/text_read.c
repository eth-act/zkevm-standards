#include <stddef.h>
#include <stdint.h>

#include "zkvm_io.h"

/* A known instruction in the text segment: `addi x0, x0, 0` (nop), encoded 0x00000013. */
__asm__(".section .text\n.balign 4\n.globl known_insn\nknown_insn:\n  addi x0, x0, 0\n");
extern const uint8_t known_insn[];

/* Reads the 4 bytes of a code word as data. Under an execute-only profile the load faults; under
   read+execute it returns the real bytes. */
int main(void) {
  uint8_t b[4];
  for (size_t i = 0; i < sizeof b; i++) {
    b[i] = ((const volatile uint8_t *)known_insn)[i];
  }
  write_output(b, sizeof b);
  return 0;
}
