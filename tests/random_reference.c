/* Test-only SplitMix64 oracle, following Sebastiano Vigna's public-domain
 * reference (2015), https://prng.di.unimi.it/splitmix64.c.
 * Generator code is public domain; no warranty. Not linked into pi-bend. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static uint64_t next(uint64_t *state) {
  uint64_t z = (*state += UINT64_C(0x9e3779b97f4a7c15));
  z = (z ^ (z >> 30)) * UINT64_C(0xbf58476d1ce4e5b9);
  z = (z ^ (z >> 27)) * UINT64_C(0x94d049bb133111eb);
  return z ^ (z >> 31);
}
int main(int argc, char **argv) {
  if (argc != 4) return 2;
  uint64_t state = (strtoull(argv[1], 0, 10) << 32) | strtoull(argv[2], 0, 10);
  unsigned count = (unsigned)strtoul(argv[3], 0, 10);
  for (unsigned i = 0; i < count; i++) {
    uint64_t word = next(&state), bits;
    double value = (double)(word >> 11) * 0x1p-53;
    memcpy(&bits, &value, sizeof bits);
    printf("%u:%u;%u:%u\n", (unsigned)(word >> 32), (unsigned)word,
           (unsigned)(bits >> 32), (unsigned)bits);
  }
  return 0;
}
