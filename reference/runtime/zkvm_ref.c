/* Reference zkVM runtime: termination and I/O (standards/io-interface). */

#include <stddef.h>
#include <stdint.h>

#include "zkvm_io.h"

#define ZKVM_IO_BASE 0x00F0000000000000ULL
#define ZKVM_IO_OUTPUT (ZKVM_IO_BASE + 0x08)

/* HTIF mailbox; the emulator locates it through the `tohost` symbol. */
__attribute__((section(".tohost"), aligned(8))) volatile uint64_t tohost;
__attribute__((section(".tohost"), aligned(8))) volatile uint64_t fromhost;

/* Input region: u64 length followed by the input bytes (placed by the loader). */
extern const uint8_t _zkvm_input_base[];

_Noreturn void zkvm_exit(int code);

_Noreturn void zkvm_exit(int code) {
  tohost = ((uint64_t)(uint32_t)code << 1) | 1;
  for (;;) {
  }
}

void read_input(const uint8_t **buf_ptr, size_t *buf_size) {
  *buf_size = (size_t)*(const volatile uint64_t *)_zkvm_input_base;
  *buf_ptr = _zkvm_input_base + 8;
}

void write_output(const uint8_t *output, size_t size) {
  const volatile uint8_t *src = output;
  for (size_t i = 0; i < size; i++) {
    *(volatile uint8_t *)ZKVM_IO_OUTPUT = src[i];
  }
}
