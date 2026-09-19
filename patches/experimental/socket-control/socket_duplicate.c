Term socket_duplicate_run(Env e, Term* f, IoWork* w) {
  int fd = (int)io_hand_v(f[0]);
  int copy = fcntl(fd, F_DUPFD_CLOEXEC, 0);
  Term result = copy < 0 ? io_fail(e, errno, NULL) : io_done(e, io_hand(copy));
  return io_tup(e, io_hand(fd), result);
}

static void __attribute__((constructor)) socket_duplicate_use(void) {
  io_eff(CID_SOCKET_DUPLICATE, socket_duplicate_run, 0);
}
