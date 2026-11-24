#include <stddef.h>
#include <stdint.h>

#include "zkvm_io.h"

static uint8_t buf[256];

int main(void) {
  const uint8_t *in;
  size_t n;
  read_input(&in, &n);
  size_t k = 0;
  buf[k++] = 'l';
  buf[k++] = 'e';
  buf[k++] = 'n';
  buf[k++] = '=';
  buf[k++] = (uint8_t)('0' + n / 10 % 10);
  buf[k++] = (uint8_t)('0' + n % 10);
  buf[k++] = ';';
  for (size_t i = 0; i < n && k < sizeof(buf); i++) {
    buf[k++] = in[n - 1 - i];
  }
  write_output(buf, k / 2);
  write_output(buf + k / 2, k - k / 2);
  return 0;
}
