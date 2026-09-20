#if defined(__linux__)
#include <sys/random.h>
#endif

Term entropy_bytes_run(Env e, Term* f, IoWork* w) {
  u32 count = (u32)f[0];
  if (count > 256) return io_fail(e, EINVAL, NULL);
  Term bytes = term_pak(CID_NIL, 0);
  if (count == 0) return io_done(e, bytes);
#if defined(__linux__)
  uint8_t buffer[256];
  ssize_t size = getrandom(buffer, count, GRND_NONBLOCK);
  if (size < 0) return io_fail(e, errno, NULL);
  if (size != count) return io_fail(e, EIO, NULL);
  for (u32 i = count; i > 0; i -= 1) {
    bytes = io_node(e, CID_CON, buffer[i - 1], bytes, IO_HOTS & 16);
  }
  return io_done(e, bytes);
#else
  return io_fail(e, ENOSYS, NULL);
#endif
}

static void __attribute__((constructor)) entropy_bytes_use(void) {
  io_eff(CID_ENTROPY_BYTES, entropy_bytes_run, 0);
}
