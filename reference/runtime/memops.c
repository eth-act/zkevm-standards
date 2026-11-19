/* Reference zkVM runtime: memory operations (standards/accelerated-memory-operations). */

#include <stddef.h>
#include <stdint.h>

void *memcpy(void *restrict dest, const void *restrict src, size_t n) {
  uint8_t *d = dest;
  const uint8_t *s = src;
  for (size_t i = 0; i < n; i++) {
    d[i] = s[i];
  }
  return dest;
}

void *memmove(void *dest, const void *src, size_t n) {
  uint8_t *d = dest;
  const uint8_t *s = src;
  if ((uintptr_t)d > (uintptr_t)s) {
    for (size_t i = n; i > 0; i--) {
      d[i - 1] = s[i - 1];
    }
  } else {
    for (size_t i = 0; i < n; i++) {
      d[i] = s[i];
    }
  }
  return dest;
}

void *memset(void *dest, int c, size_t n) {
  uint8_t *d = dest;
  for (size_t i = 0; i < n; i++) {
    d[i] = (uint8_t)c;
  }
  return dest;
}

int memcmp(const void *s1, const void *s2, size_t n) {
  const uint8_t *a = s1;
  const uint8_t *b = s2;
  for (size_t i = 0; i < n; i++) {
    if (a[i] != b[i]) {
      return (int)a[i] - (int)b[i];
    }
  }
  return 0;
}
