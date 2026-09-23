#include <sys/utsname.h>
#include <string.h>
#include <errno.h>

static const char* node_platform(const char* name) {
  if (!strcmp(name, "Linux")) return "linux";
  if (!strcmp(name, "Darwin")) return "darwin";
  if (!strcmp(name, "FreeBSD")) return "freebsd";
  if (!strcmp(name, "OpenBSD")) return "openbsd";
  if (!strcmp(name, "NetBSD")) return "netbsd";
  if (!strcmp(name, "SunOS")) return "sunos";
  if (!strcmp(name, "AIX")) return "aix";
  return NULL;
}

static const char* node_arch(const char* name) {
  if (!strcmp(name, "x86_64") || !strcmp(name, "amd64")) return "x64";
  if (!strcmp(name, "aarch64") || !strcmp(name, "arm64")) return "arm64";
  if (!strcmp(name, "i386") || !strcmp(name, "i486") || !strcmp(name, "i586") || !strcmp(name, "i686")) return "ia32";
  if (!strcmp(name, "armv7l") || !strcmp(name, "armv6l")) return "arm";
  if (!strcmp(name, "ppc64le")) return "ppc64";
  if (!strcmp(name, "s390x")) return "s390x";
  if (!strcmp(name, "riscv64")) return "riscv64";
  return NULL;
}

Term io_system_identity_run(Env e, Term* f, IoWork* w) {
  struct utsname value;
  if (uname(&value) != 0) return io_fail(e, errno, NULL);
  const char* platform = node_platform(value.sysname);
  const char* arch = node_arch(value.machine);
  if (!platform || !arch) return io_fail(e, ENOTSUP, NULL);
  return io_done(e, io_tup(e, io_str(e, platform, strlen(platform)),
    io_tup(e, io_str(e, value.release, strlen(value.release)),
      io_str(e, arch, strlen(arch)))));
}

static void __attribute__((constructor)) io_system_identity_use(void) {
  io_eff(CID_IO_SYSTEM_IDENTITY, io_system_identity_run, 0);
}
