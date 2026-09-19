function socket_isconnectionreset(code) {
  return code === (io_sys().mac ? 54 : 104);
}
