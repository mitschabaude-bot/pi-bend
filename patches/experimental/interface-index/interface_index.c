#include <net/if.h>

Term io_interface_index_run(Env e, Term* f, IoWork* w) {
  uint64_t size = 0;
  char* name = io_cstr(e, f[0], &size);
  uint32_t index = 0, code = EINVAL;
  if (!io_nul(name, size)) {
    errno = 0;
    index = if_nametoindex(name);
    code = index == 0 ? (errno != 0 ? errno : EIO) : 0;
  }
  free(name);
  return code != 0 ? io_fail(e, code, NULL) : io_done(e, index);
}

static void __attribute__((constructor)) io_interface_index_use(void) {
  io_eff(CID_IO_INTERFACE_INDEX, io_interface_index_run, 0);
}
