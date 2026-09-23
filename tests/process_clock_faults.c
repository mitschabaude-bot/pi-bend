#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <stdatomic.h>
static atomic_int clock_calls,local_calls;
static int mode(const char* name) { const char* value=getenv("BEND_CLOCK_FAULT"); return value&&!strcmp(value,name); }
int clock_gettime(clockid_t id,struct timespec* value) {
  static int(*real)(clockid_t,struct timespec*); if(!real)real=dlsym(RTLD_NEXT,"clock_gettime");
  if(id==CLOCK_REALTIME) {
    int call=atomic_fetch_add(&clock_calls,1);
    if(mode("clock")||(mode("clock-once")&&call==0)){errno=EIO;return -1;}
    const char* epoch=getenv("BEND_CLOCK_EPOCH");
    if(epoch){value->tv_sec=(time_t)strtoll(epoch,NULL,10);value->tv_nsec=123000000;return 0;}
  }
  return real(id,value);
}
struct tm* localtime_r(const time_t* value,struct tm* result) {
  static struct tm*(*real)(const time_t*,struct tm*);if(!real)real=dlsym(RTLD_NEXT,"localtime_r");
  int call=atomic_fetch_add(&local_calls,1);
  if(mode("local")||mode("local-no-errno")||(mode("local-once")&&call==0)){errno=mode("local-no-errno")?0:EOVERFLOW;return NULL;}
  return real(value,result);
}
