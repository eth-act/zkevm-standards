#include <stddef.h>
#include <stdint.h>

void *memcpy(void *dest, const void *src, size_t n);
void *memmove(void *dest, const void *src, size_t n);
void *memset(void *dest, int c, size_t n);
int memcmp(const void *lhs, const void *rhs, size_t n);

static uint8_t a[16] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16};
static uint8_t b[16];

/* a and b after the operations below, then the sign of memcmp(a, b, 8) (0xff: negative) and
   memcmp(b, b, 16). */
static const uint8_t expected[34] = {
    0x01, 0x02, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x0b, 0x0c,
    0x0d, 0x0e, 0x0f, 0x10, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
    0xab, 0xab, 0xab, 0xab, 0x00, 0x00, 0x00, 0x00, 0xff, 0x00,
};

/* Returns 0 if every byte matches, else 1 + the index of the first mismatching byte. */
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
  for (size_t i = 0; i < sizeof out; i++) {
    if (out[i] != expected[i]) {
      return (int)i + 1;
    }
  }
  return 0;
}
