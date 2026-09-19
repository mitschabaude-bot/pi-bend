// Endpoint observation neither closes nor duplicates the socket descriptor.
Term socket_endpoint_run(Env e, Term* f, IoWork* w) {
  int fd = (int)io_hand_v(f[0]);
  u32 side = (u32)f[1];
  if (side > 1) return io_tup(e, io_hand(fd), io_fail(e, EINVAL, NULL));
  struct sockaddr_storage address;
  memset(&address, 0, sizeof(address));
  socklen_t length = sizeof(address);
  int status = side == 0
    ? getsockname(fd, (struct sockaddr*)&address, &length)
    : getpeername(fd, (struct sockaddr*)&address, &length);
  if (status < 0) return io_tup(e, io_hand(fd), io_fail(e, errno, NULL));
  u32 family, a = 0, b = 0, c = 0, d = 0, port, scope = 0;
  if (address.ss_family == AF_INET && length >= sizeof(struct sockaddr_in)) {
    struct sockaddr_in at;
    memcpy(&at, &address, sizeof(at));
    family = 4; a = ntohl(at.sin_addr.s_addr); port = ntohs(at.sin_port);
  } else if (address.ss_family == AF_INET6 && length >= sizeof(struct sockaddr_in6)) {
    struct sockaddr_in6 at;
    memcpy(&at, &address, sizeof(at));
    uint32_t words[4];
    memcpy(words, &at.sin6_addr, sizeof(words));
    family = 6; a = ntohl(words[0]); b = ntohl(words[1]);
    c = ntohl(words[2]); d = ntohl(words[3]);
    port = ntohs(at.sin6_port); scope = at.sin6_scope_id;
  } else {
    return io_tup(e, io_hand(fd), io_fail(e, EAFNOSUPPORT, NULL));
  }
  return io_tup(e, io_hand(fd), io_done(e, io_tup(e, family,
    io_tup(e, a, io_tup(e, b, io_tup(e, c, io_tup(e, d,
      io_tup(e, port, scope))))))));
}

static void __attribute__((constructor)) socket_endpoint_use(void) {
  io_eff(CID_SOCKET_ENDPOINT, socket_endpoint_run, 0);
}
