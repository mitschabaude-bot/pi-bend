Term tcp_shutdown_run(Env e, Term* f, IoWork* w) {
  int fd = (int)io_hand_v(f[0]);
  int status = shutdown(fd, SHUT_RDWR);
  Term result = status < 0 ? io_fail(e, errno, NULL) : io_done(e, term_pak(CID_UNIT, 0));
  return io_tup(e, io_hand(fd), result);
}

static void __attribute__((constructor)) tcp_shutdown_use(void) {
  io_eff(CID_TCP_SHUTDOWN, tcp_shutdown_run, 0);
}
