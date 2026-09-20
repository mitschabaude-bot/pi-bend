/* Test-only libc observer. No queries are sent; no production code links this. */
#define _DEFAULT_SOURCE
#include <resolv.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
  if (argc != 2 || setenv("RES_OPTIONS", argv[1], 1)) return 2;
  struct __res_state state = {0};
  if (res_ninit(&state)) return 3;
  printf("%u,%d,%d", state.ndots, state.retrans, state.retry);
  unsigned long flags[] = {RES_ROTATE, RES_USE_EDNS0, RES_SNGLKUPREOP,
    RES_SNGLKUP, RES_NOTLDQUERY, RES_NORELOAD, RES_USEVC, RES_TRUSTAD, RES_NOAAAA};
  for (unsigned i = 0; i < sizeof(flags)/sizeof(flags[0]); i++)
    printf(",%u", (state.options & flags[i]) != 0);
  puts("");
  res_nclose(&state);
  return 0;
}
