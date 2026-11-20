#include <stddef.h>
#include <stdint.h>

#include "zkvm_io.h"

int main(void) {
  write_output((const uint8_t *)"partial", 7);
  return 5;
}
