#include <stdint.h>

__attribute__((noinline)) uint64_t f(uint64_t n) {
  volatile uint8_t frame[512];
  frame[0] = (uint8_t)n;
  return f(n + 1) + frame[0];
}

int main(void) {
  return (int)f(0);
}
