#include <stddef.h>
#include <stdint.h>

#include "zkvm_io.h"

static uint8_t buf[32] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16};

int main(void) {
  /* Hide the alignment of `buf` so GCC emits a single misaligned ld/sd instead of
     splitting the accesses into byte loads and stores. */
  uint8_t *p = buf;
  __asm__("" : "+r"(p));
  uint64_t v = *(volatile uint64_t *)(p + 3);
  *(volatile uint64_t *)(p + 17) = v;
  write_output(p + 17, 8);
  return v == 0x0b0a090807060504ULL ? 0 : 1;
}
