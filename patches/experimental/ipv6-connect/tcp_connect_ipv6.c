// Numeric IPv6 connect. No name resolution or address parsing occurs here.
static Term tcp_connect_ipv6_more(Env e, IoWork* w) {
  int fd = (int)w->made;
  int err = (int)w->code;
  socklen_t length = sizeof(err);
  if (err == EINPROGRESS && getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &length)) {
    err = errno;
  }
  if (err != 0 && fd >= 0) {
    close(fd);
  }
  return err != 0 ? io_fail(e, (u32)err, NULL) : io_done(e, io_hand(fd));
}

Term tcp_connect_ipv6_run(Env e, Term* f, IoWork* w) {
  if ((u32)f[4] > 65535) {
    return io_fail(e, EINVAL, NULL);
  }
  struct sockaddr_in6 at;
  memset(&at, 0, sizeof(at));
  at.sin6_family = AF_INET6;
#ifdef __APPLE__
  at.sin6_len = sizeof(at);
#endif
  at.sin6_port = htons((uint16_t)f[4]);
  at.sin6_scope_id = (u32)f[5];
  uint32_t words[4] = {htonl((u32)f[0]), htonl((u32)f[1]),
                       htonl((u32)f[2]), htonl((u32)f[3])};
  memcpy(&at.sin6_addr, words, sizeof(words));
  int fd = socket(AF_INET6, SOCK_STREAM, 0);
  int flags = fd < 0 ? -1 : fcntl(fd, F_GETFL);
  if (fd >= 0 && (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0)) {
    int err = errno;
    close(fd);
    return io_fail(e, (u32)err, NULL);
  }
  w->made = fd;
  io_sys_end(w, fd < 0 ? fd : connect(fd, (struct sockaddr*)&at, sizeof(at)));
  return w->code == EINPROGRESS ? io_wait_on(w, fd, POLLOUT, tcp_connect_ipv6_more)
    : tcp_connect_ipv6_more(e, w);
}

static void __attribute__((constructor)) tcp_connect_ipv6_use(void) {
  io_eff(CID_TCP_CONNECT_IPV6, tcp_connect_ipv6_run, 0);
}
