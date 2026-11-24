int main(void) {
  *(volatile char *)0xfff = 1;
  return 0;
}
