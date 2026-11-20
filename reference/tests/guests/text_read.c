#include <stddef.h>
#include <stdint.h>

#include "zkvm_io.h"

int main(void) {
  uint8_t b = *(const volatile uint8_t *)(uintptr_t)&main;
  write_output(&b, 1);
  return 0;
}
