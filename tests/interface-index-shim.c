#include <errno.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

unsigned int __wrap_if_nametoindex(const char *name) {
  const char *expected = getenv("PI_BEND_IF_NAME");
  if (!expected || strcmp(name, expected)) { errno = EINVAL; return 0; }
  const char *failure = getenv("PI_BEND_IF_ERROR");
  if (failure) { errno = atoi(failure); return 0; }
  return (uint32_t)strtoul(getenv("PI_BEND_IF_INDEX"), NULL, 10);
}
