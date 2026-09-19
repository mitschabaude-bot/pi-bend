Term socket_is_connection_reset_run(Env e, Term* f, IoWork* w) {
  return term_pak(f[0] == ECONNRESET ? CID_TRUE : CID_FALSE, 0);
}

static void __attribute__((constructor)) socket_is_connection_reset_use(void) {
  io_eff(CID_SOCKET_ISCONNECTIONRESET, socket_is_connection_reset_run, 0);
}
