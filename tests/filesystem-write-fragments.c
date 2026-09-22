// Test-only POSIX write interposition: real writes, shortened and interrupted.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

ssize_t write(int fd, const void* data, size_t count) {
  static _Atomic unsigned calls;
  ssize_t (*real_write)(int,const void*,size_t) = dlsym(RTLD_NEXT,"write");
  const char* target = getenv("BEND_TEST_WRITE_PATH");
  if (target && fd > 2) {
    char proc[64],path[4096];
    snprintf(proc,sizeof(proc),"/proc/self/fd/%d",fd);
    ssize_t n = readlink(proc,path,sizeof(path)-1);
    if (n >= 0) {
      path[n] = 0;
      if (strcmp(path,target) == 0) {
        if (getenv("BEND_TEST_WRITE_ZERO")) return 0;
        if (atomic_fetch_add(&calls,1) == 0) { errno=EINTR; return -1; }
        if (count > 7) count=7;
      }
    }
  }
  return real_write(fd,data,count);
}
