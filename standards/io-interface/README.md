This proposal aims to standardize zkVM IO interface. The input is the private input, the existential part of the relation being proven. The output is the public part of that relation.

# Motivation
Application developers need a zkVM independent way to access input and output. Then the code is portable and can be compiled without changes for various zkVMs.

# Goals
The goal is to define a portable, efficient and convenient way to do IO in zkVMs.

# The interface

The interface consists of the following C function prototypes:
- `void read_input(const uint8_t** buf_ptr, size_t* buf_size)`
- `void write_output(const uint8_t* output, size_t size)`

The `read_input` function is used as follows:

```
    const uint8_t* buf_ptr;
    size_t buf_size;
    read_input(&buf_ptr, &buf_size);
```

After calling `read_input`, the `buf_ptr` variable contains a pointer to the input, and `buf_size` indicates its size. The data provided by `read_input` is the private input described in the introduction. If `buf_size` is 0, then `buf_ptr` may contain an arbitrary value and should be considered invalid. The `read_input` function cannot fail, so no error code is returned. The type `const uint8_t*` for `buf_ptr` indicates that the memory area containing the input may be read-only and that the application code must not write to the memory pointed to by `buf_ptr`. This function has no side effects beyond setting the pointer parameters, may be called multiple times, and is idempotent.

zkVMs that don't preload input will need to read the entire input into an internal buffer during machine initialization to ensure `read_input` can be safely called from `main`. As a consequence, the size of the machine input must be smaller than the zkVM's addressable space.

`write_output` may be called multiple times. The observable result of calling `write_output` multiple times is as if the buffers from successive calls were concatenated, forming the entirety of the public part described in the introduction. Theoretically, this allows writing an unbounded amount of data across multiple calls, more than the maximum value representable by `size_t`, although this is not a practical concern. This function cannot fail, so no error code is returned. The pointer passed to `write_output` must point to readable memory; which memory segments are readable is zkVM-dependent. The 0 (NULL) pointer is not treated specially by this specification.

# Rationale

`read_input` enables zero-copy implementations for zkVMs that preload input into memory, which justifies the departure from the standard libc IO interface. This approach naturally precludes interactive input reading, though this limitation is not a concern for EF's use case.

The `read_input` and `write_output` functions are independent of the libc IO interface. This proposal neither requires the presence of libc IO functions nor prescribes their behavior.

## Normative requirements

Each requirement has an ID. "Checked by" names where it is enforced or tested: `Sail` (the reference in `reference/sail/`), `Lean` (a statement in `reference/lean/ZkvmRef/`), `monitor` (a guest test in eth-act/zkevm-test-monitor), `monitor-static` (a static check there), or `not tested` with the reason.

| ID | Requirement | Applies to | Checked by |
| --- | --- | --- | --- |
| IO1 | The interface consists of the C functions `void read_input(const uint8_t** buf_ptr, size_t* buf_size)` and `void write_output(const uint8_t* output, size_t size)`. | vendor library | Sail, monitor |
| IO2 | After calling `read_input`, `buf_ptr` contains a pointer to the input and `buf_size` indicates its size; the data is the private input. | vendor library | Sail, monitor |
| IO3 | The `read_input` function cannot fail, so no error code is returned. | vendor library | Sail, monitor |
| IO4 | The application code must not write to the memory pointed to by `buf_ptr`. | guest | not tested: guest obligation |
| IO5 | `read_input` has no side effects beyond setting the pointer parameters, may be called multiple times, and is idempotent. | vendor library | Sail, monitor |
| IO6 | zkVMs that don't preload input read the entire input into an internal buffer during machine initialization so that `read_input` can be safely called from `main`. | zkVM | Sail, monitor |
| IO7 | The size of the machine input must be smaller than the zkVM's addressable space. | zkVM | Sail |
| IO8 | `write_output` may be called multiple times; the observable result is as if the buffers from successive calls were concatenated, forming the entirety of the public output. | vendor library | Sail, monitor |
| IO9 | `write_output` cannot fail, so no error code is returned. | vendor library | Sail, monitor |
| IO10 | The pointer passed to `write_output` must point to readable memory; which memory segments are readable is zkVM-dependent. | guest | not tested: guest obligation |
| IO11 | The 0 (NULL) pointer is not treated specially by `write_output`. | vendor library | Sail, monitor |
