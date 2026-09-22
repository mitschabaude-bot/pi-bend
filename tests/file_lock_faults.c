#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

// Test-only filesystem failures/precision; no production locking policy here.
static _Atomic int stats, touches, removes;
static int selected(const char *path) { return path && strstr(path,".lock") != NULL; }
static int fail(const char *name,int count) {
  const char *value=getenv(name);if(!value)return 0;
  int first=atoi(value);return count==first || (strchr(value,'+') && count>=first);
}
int stat(const char *path,struct stat *value) {
  int (*original)(const char*,struct stat*)=dlsym(RTLD_NEXT,"stat");
  if(selected(path) && fail("BEND_LOCK_STAT_FAIL",atomic_fetch_add(&stats,1)+1)) { errno=EACCES;return -1; }
  return original(path,value);
}
int rmdir(const char *path) {
  int (*original)(const char*)=dlsym(RTLD_NEXT,"rmdir");
  if(selected(path) && fail("BEND_LOCK_REMOVE_FAIL",atomic_fetch_add(&removes,1)+1)) { errno=EIO;return -1; }
  return original(path);
}
int utimensat(int dir,const char *path,const struct timespec times[2],int flags) {
  int (*original)(int,const char*,const struct timespec[2],int)=dlsym(RTLD_NEXT,"utimensat");
  if(!selected(path)) return original(dir,path,times,flags);
  int count=atomic_fetch_add(&touches,1)+1;
  if(count==1 && getenv("BEND_LOCK_PROBE_DELAY")) usleep(120000);
  if(fail("BEND_LOCK_TOUCH_FAIL",count)) { errno=EACCES;return -1; }
  if(count>1 && getenv("BEND_LOCK_TOUCH_DELAY")) usleep(500000);
  if(getenv("BEND_LOCK_SECONDS")) { struct timespec rounded[2]={times[0],times[1]};rounded[0].tv_nsec=rounded[1].tv_nsec=0;return original(dir,path,rounded,flags); }
  return original(dir,path,times,flags);
}
