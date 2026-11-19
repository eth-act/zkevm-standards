int main(void) {
  /* csrw mtvec, zero */
  __asm__ volatile(".word 0x30501073");
  return 0;
}
