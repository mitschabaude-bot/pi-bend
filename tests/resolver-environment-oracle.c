/* Test-only observer: environment is supplied by the parent; no DNS queries. */
#define _DEFAULT_SOURCE
#include <resolv.h>
#include <stdio.h>
#include <string.h>
int main(void) {
  struct __res_state state = {0};
  if (res_ninit(&state)) return 2;
  for (unsigned i=0; i<MAXDNSRCH && state.dnsrch[i]; ++i)
    printf("%zu:%s\n",strlen(state.dnsrch[i]),state.dnsrch[i]);
  res_nclose(&state);
  return 0;
}
