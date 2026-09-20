// Reading one extra byte detects truncation without platform MSG_TRUNC rules.
static Term udp_recv_bytes_more(Env e, IoWork* w) {
  int fd = (int)w->hand;
  struct sockaddr_storage address;
  memset(&address, 0, sizeof(address));
  socklen_t length = sizeof(address);
  w->size = io_sys_end(w, recvfrom(fd, w->data, (size_t)w->made + 1, 0,
    (struct sockaddr*)&address, &length));
  if (w->code == EAGAIN) return io_wait_on(w, fd, POLLIN, udp_recv_bytes_more);
  if (w->code) {
    free(w->data);
    return io_tup(e, io_hand(fd), io_fail(e, w->code, NULL));
  }
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
    free(w->data);
    return io_tup(e, io_hand(fd), io_fail(e, EAFNOSUPPORT, NULL));
  }
  Term peer = io_tup(e, family, io_tup(e, a, io_tup(e, b, io_tup(e, c,
    io_tup(e, d, io_tup(e, port, scope))))));
  u64 size = w->size > w->made ? w->made : w->size;
  Term bytes = term_pak(CID_NIL, 0);
  for (u64 i = size; i > 0; --i)
    bytes = io_node(e, CID_CON, ((uint8_t*)w->data)[i-1], bytes, IO_HOTS & 16);
  Term truncated = term_pak(w->size > w->made ? CID_TRUE : CID_FALSE, 0);
  free(w->data);
  return io_tup(e, io_hand(fd), io_done(e, io_tup(e, peer, io_tup(e, truncated, bytes))));
}

Term udp_recv_bytes_run(Env e, Term* f, IoWork* w) {
  w->hand = (intptr_t)io_hand_v(f[0]);
  if (f[1] > 65535) return io_tup(e, io_hand(w->hand), io_fail(e, EINVAL, NULL));
  w->made = f[1];
  w->data = io_mem(malloc((size_t)w->made + 1));
  return udp_recv_bytes_more(e, w);
}

static void __attribute__((constructor)) udp_recv_bytes_use(void) {
  io_eff(CID_UDP_RECV_BYTES, udp_recv_bytes_run, IO_READ);
}
