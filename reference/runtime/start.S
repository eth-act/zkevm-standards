/* Reference zkVM runtime: entry point and trap vector. */

	.section .text._trap, "ax", @progbits
	.globl _zkvm_trap
	.balign 4
/* Any trap ends the run with HTIF exit code 2^32 (fault). */
_zkvm_trap:
	li t0, 1
	slli t0, t0, 33
	ori t0, t0, 1
	la t1, tohost
	sd t0, 0(t1)
1:	j 1b

	.section .text._start, "ax", @progbits
	.globl _start
	.balign 4
_start:
	.option push
	.option norelax
	la gp, __global_pointer$
	.option pop
	la sp, __stack_top
	call main
	call zkvm_exit
