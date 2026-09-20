/* Test-only uname wrapper. Does not change the host or its UTS namespace. */
#include <sys/utsname.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
int __wrap_uname(struct utsname *value) {
  const char *error=getenv("PI_BEND_HOSTNAME_ERROR");
  if(error) { errno=atoi(error); return -1; }
  const char *name=getenv("PI_BEND_HOSTNAME_VALUE");
  if(!name || strlen(name)>=sizeof(value->nodename)) { errno=EINVAL; return -1; }
  memset(value,0,sizeof(*value));
  strcpy(value->nodename,name);
  return 0;
}
