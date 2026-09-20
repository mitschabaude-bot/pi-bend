static Term udp_send_bytes_more(Env e, IoWork* w) {
  int fd = (int)w->hand;
  if (!w->code) {
    ssize_t n = sendto(fd, w->data, w->size, 0,
      (struct sockaddr*)w->text, (socklen_t)w->made);
    io_sys_end(w, n);
    if (w->code == EAGAIN) {
      w->code = 0;
      return io_wait_on(w, fd, POLLOUT, udp_send_bytes_more);
    }
    if (!w->code && (u64)n != w->size) w->code = EIO;
  }
  Term result = w->code ? io_fail(e, w->code, NULL)
    : io_done(e, term_pak(CID_UNIT, 0));
  free(w->text); free(w->data);
  return io_tup(e, io_hand(fd), result);
}

Term udp_send_bytes_run(Env e, Term* f, IoWork* w) {
  w->hand = (intptr_t)io_hand_v(f[0]);
  w->code = 0; w->size = 0; w->made = 0;
  w->text = io_mem(calloc(1, sizeof(struct sockaddr_storage)));
  u32 family = f[1], port = f[6], scope = f[7];
  if ((family != 4 && family != 6) || port == 0 || port > 65535 ||
      (family == 4 && (f[3] || f[4] || f[5] || scope))) w->code = EINVAL;
  if (family == 4) {
    struct sockaddr_in* at = (struct sockaddr_in*)w->text;
    at->sin_family = AF_INET; at->sin_port = htons(port);
    at->sin_addr.s_addr = htonl(f[2]); w->made = sizeof(*at);
  } else if (family == 6) {
    struct sockaddr_in6* at = (struct sockaddr_in6*)w->text;
    at->sin6_family = AF_INET6; at->sin6_port = htons(port);
    at->sin6_scope_id = scope;
    uint32_t words[4] = {htonl(f[2]), htonl(f[3]), htonl(f[4]), htonl(f[5])};
    memcpy(&at->sin6_addr, words, sizeof(words)); w->made = sizeof(*at);
  }
  u64 capacity = 64;
  w->data = io_mem(malloc(capacity));
  Term xs = f[8];
  while (term_aux(xs) == CID_CON) {
    Term fields[2];
    spare_free(e, cls_fit(2), ctr_take(e, xs, 2, fields));
    if (fields[0] > 255) w->code = EINVAL;
    if (!w->code && w->size == 65535) w->code = EMSGSIZE;
    if (!w->code) {
      if (w->size == capacity) {
        capacity *= 2;
        w->data = io_mem(realloc(w->data, capacity));
      }
      w->data[w->size++] = (char)fields[0];
    }
    xs = fields[1];
  }
  return udp_send_bytes_more(e, w);
}
static void __attribute__((constructor)) udp_send_bytes_use(void) {
  io_eff(CID_UDP_SEND_BYTES, udp_send_bytes_run, 0);
}
