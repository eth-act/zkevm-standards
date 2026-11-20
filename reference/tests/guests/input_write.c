#include <stddef.h>
#include <stdint.h>

#include "zkvm_io.h"

int main(void) {
  const uint8_t *in;
  size_t n;
  read_input(&in, &n);
  *(volatile uint8_t *)in = 0;
  return 0;
}
