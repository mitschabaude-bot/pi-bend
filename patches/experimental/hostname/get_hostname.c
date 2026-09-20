#include <sys/utsname.h>

Term io_get_hostname_run(Env e, Term* f, IoWork* w) {
  struct utsname value;
  if (uname(&value) != 0) return io_fail(e, errno, NULL);
  return io_done(e, io_str(e, value.nodename, strlen(value.nodename)));
}

static void __attribute__((constructor)) io_get_hostname_use(void) {
  io_eff(CID_IO_GET_HOSTNAME, io_get_hostname_run, 0);
}
