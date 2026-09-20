function socket_isconnectionrefused(code) {
  return code === (io_sys().mac ? 61 : 111);
}
