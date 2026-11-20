#include <stddef.h>
#include <stdint.h>

#include "zkvm_io.h"

void *memcpy(void *dest, const void *src, size_t n);
void *memmove(void *dest, const void *src, size_t n);
void *memset(void *dest, int c, size_t n);
int memcmp(const void *lhs, const void *rhs, size_t n);

static uint8_t a[16] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16};
static uint8_t b[16];

int main(void) {
  memcpy(b, a, 8);
  memmove(a + 2, a, 8);
  memset(b + 8, 0x1AB, 4);
  int c1 = memcmp(a, b, 8);
  int c2 = memcmp(b, b, 16);
  uint8_t out[34];
  memcpy(out, a, 16);
  memcpy(out + 16, b, 16);
  out[32] = (uint8_t)(c1 < 0 ? 0xff : c1 > 0 ? 1 : 0);
  out[33] = (uint8_t)c2;
  write_output(out, 34);
  return 0;
}
