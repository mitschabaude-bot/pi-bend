Term socket_is_connection_refused_run(Env e, Term* f, IoWork* w) {
  return term_pak(f[0] == ECONNREFUSED ? CID_TRUE : CID_FALSE, 0);
}

static void __attribute__((constructor)) socket_is_connection_refused_use(void) {
  io_eff(CID_SOCKET_ISCONNECTIONREFUSED, socket_is_connection_refused_run, 0);
}
