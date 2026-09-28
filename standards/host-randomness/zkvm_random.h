/**
 * zkVM Host Randomness C Interface
 *
 * This header defines the standard C interface for guest programs to obtain
 * cryptographically strong random values from the host.
 *
 * The function follows:
 * https://github.com/eth-act/zkvm-standards/tree/main/standards/host-randomness
 */

#ifndef ZKVM_RANDOM_H
#define ZKVM_RANDOM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Return 64 uniformly distributed random bits.
 *
 * Each call returns bits independent of every other call. The host draws them
 * from a cryptographically secure pseudorandom number generator, independently
 * for each guest execution, so the author of the guest input cannot predict
 * them. A guest that needs more bits calls again rather than expanding one
 * value itself.
 *
 * The function cannot fail, so no error code is returned.
 *
 * The values are free witness values and carry no attestation. For a fixed
 * guest input, the public output and the exit code must be identical for every
 * sequence this function can return.
 *
 * @return 64 random bits
 */
uint64_t zkvm_random_u64(void);

#ifdef __cplusplus
}
#endif

#endif /* ZKVM_RANDOM_H */
