/* Test-only glibc client: explicit loopback servers, no system DNS queries. */
#include <arpa/inet.h>
#include <resolv.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc, char **argv) {
  if (argc < 3 || argc > 2 + MAXNS) return 2;
  struct __res_state state;
  memset(&state, 0, sizeof state);
  state.options = RES_INIT | RES_RECURSE | RES_USEVC;
  state.retrans = 1; state.retry = 2; state.nscount = argc - 2;
  state._vcsock = -1;
  for (int i = 0; i < MAXNS; ++i) state._u._ext.nssocks[i] = -1;
  if (state.nscount > MAXNS) return 2;
  for (int i = 0; i < state.nscount; ++i) {
    state.nsaddr_list[i].sin_family = AF_INET;
    state.nsaddr_list[i].sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    state.nsaddr_list[i].sin_port = htons((unsigned short)atoi(argv[i+2]));
  }
  unsigned char query[17] = {0,42,1,0,0,1,0,0,0,0,0,0,0,0,1,0,1};
  unsigned char answer[512];
  for (const char *flag = argv[1]; *flag; ++flag) {
    if (*flag == '1') state.options |= RES_ROTATE;
    else state.options &= ~RES_ROTATE;
    int size = res_nsend(&state, query, sizeof query, answer, sizeof answer);
    if (size != 17) { res_nclose(&state); return 3; }
  }
  res_nclose(&state);
  puts("PASS libc rotation");
  return 0;
}
