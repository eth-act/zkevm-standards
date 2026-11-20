#include <stddef.h>
#include <stdint.h>

/* Zero-initialised data lives in .bss (p_memsz > p_filesz); the loader must zero it. */
static uint8_t z[8192];

int main(void) {
  const volatile uint8_t *p = z;
  for (size_t i = 0; i < sizeof z; i++) {
    if (p[i]) {
      return 1;
    }
  }
  return 0;
}
