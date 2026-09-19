function socket_duplicate(socket) {
  const sys = io_sys();
  const copy = sys.fcntl(socket, sys.mac ? 67 : 1030, 0);
  return io_tup(socket, copy < 0 ? io_fail(sys.errno()) : io_done(copy));
}
