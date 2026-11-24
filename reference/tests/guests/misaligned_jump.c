int main(void) {
  __asm__ volatile("la t0, 1f\n addi t0, t0, 2\n jalr x0, 0(t0)\n 1: nop\n nop\n" ::: "t0");
  return 0;
}
