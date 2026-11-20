#include <stddef.h>
#include <stdint.h>

#include "zkvm_accelerators.h"

static const uint8_t msg[3] = {1, 2, 3};

int main(void) {
  zkvm_keccak256_hash h;
  zkvm_keccak256(msg, 3, &h);
  return 0;
}
