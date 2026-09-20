/* Test-only res_nsearch client. Every query targets the supplied loopback port. */
#define _DEFAULT_SOURCE
#include <arpa/inet.h>
#include <netdb.h>
#include <resolv.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
  if (argc != 8) return 2;
  struct __res_state state = {0};
  state.options = RES_INIT | RES_RECURSE;
  if (atoi(argv[4])) state.options |= RES_DEFNAMES;
  if (atoi(argv[5])) state.options |= RES_DNSRCH;
  if (atoi(argv[6])) state.options |= RES_NOTLDQUERY;
  state.ndots = atoi(argv[3]);
  state.retrans = 1; state.retry = 1; state.nscount = 1;
  state._vcsock = -1;
  for (int i = 0; i < MAXNS; i++) state._u._ext.nssocks[i] = -1;
  state.nsaddr_list[0].sin_family = AF_INET;
  state.nsaddr_list[0].sin_port = htons(atoi(argv[1]));
  inet_pton(AF_INET, "127.0.0.1", &state.nsaddr_list[0].sin_addr);
  char *domains = strdup(argv[7]);
  if (!domains) return 3;
  if (*domains) {
    char *at = domains;
    unsigned count = 0;
    do {
      if (count == MAXDNSRCH) return 4;
      state.dnsrch[count++] = strsep(&at, "|");
    } while (at);
  }
  unsigned char answer[4096];
  int result = res_nsearch(&state, argv[2], ns_c_in, ns_t_a, answer, sizeof(answer));
  printf("%d,%d\n", result, state.res_h_errno);
  res_nclose(&state);
  free(domains);
  return 0;
}
