// Reading one extra byte detects truncation without platform MSG_TRUNC rules.
static Term udp_packet(Env e, IoWork* w) {
  int fd = (int)w->hand;
  struct sockaddr_storage address;
  memset(&address, 0, sizeof(address));
  socklen_t length = sizeof(address);
  u64 received = io_sys_end(w, recvfrom(fd, w->data, (size_t)w->made + 1, 0,
    (struct sockaddr*)&address, &length));
  if (w->code == EAGAIN) return IO_PARK;
  if (w->code) {
    free(w->data);
    return io_fail(e, w->code, NULL);
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
    return io_fail(e, EAFNOSUPPORT, NULL);
  }
  Term peer = io_tup(e, family, io_tup(e, a, io_tup(e, b, io_tup(e, c,
    io_tup(e, d, io_tup(e, port, scope))))));
  u64 size = received > w->made ? w->made : received;
  Term bytes = term_pak(CID_NIL, 0);
  for (u64 i = size; i > 0; --i)
    bytes = io_node(e, CID_CON, ((uint8_t*)w->data)[i-1], bytes, IO_HOTS & 16);
  Term truncated = term_pak(received > w->made ? CID_TRUE : CID_FALSE, 0);
  free(w->data);
  return io_done(e, io_tup(e, peer, io_tup(e, truncated, bytes)));
}

#ifdef CID_UDP_RECV_BYTES
static Term udp_recv_bytes_more(Env e, IoWork* w) {
  Term result = udp_packet(e, w);
  return result == IO_PARK ? io_wait_on(w, (int)w->hand, POLLIN, udp_recv_bytes_more)
    : io_tup(e, io_hand(w->hand), result);
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

#endif

#if defined(CID_UDPREAD_NEW) || defined(CID_UDPREAD_WAIT) || defined(CID_UDPREAD_CANCEL) || defined(CID_UDPREAD_RELEASE)
// All row and queue operations run on the existing IO loop thread.
typedef struct { u32 gen, next, live, cancelled, maximum; int fd; IoAct* waiter; } UDPReadRow;
static UDPReadRow* udp_read_rows;
static u32 udp_read_len, udp_read_idle = ~0u;
static UDPReadRow* udp_read_at(Term handle) {
  u64 id = io_hand_v(handle);
  u32 index = (u32)id & 0xFFFFFF;
  UDPReadRow* row = index < udp_read_len ? &udp_read_rows[index] : NULL;
  return row && row->live && row->gen == (u32)(id >> 24) ? row : NULL;
}
static Term udp_read_retire(UDPReadRow* row) {
  Term socket = io_hand(row->fd);
  row->live = 0; row->waiter = NULL;
  if (row->gen != 0xFFFFFFFFu) {
    row->next = udp_read_idle;
    udp_read_idle = (u32)(row - udp_read_rows);
  }
  return socket;
}
#ifdef CID_UDPREAD_NEW
Term udpread_new_run(Env e, Term* f, IoWork* w) {
  u32 index = udp_read_idle;
  if (index != ~0u) udp_read_idle = udp_read_rows[index].next;
  else {
    if (udp_read_len == (1u << 24)) err_fail("too many UDP reads");
    if ((udp_read_len & (udp_read_len-1)) == 0)
      udp_read_rows = io_mem(realloc(udp_read_rows, (udp_read_len ? 2*udp_read_len : 1)*sizeof(UDPReadRow)));
    index = udp_read_len++; udp_read_rows[index].gen = 0;
  }
  UDPReadRow* row = &udp_read_rows[index];
  row->gen++; row->live = 1; row->cancelled = 0; row->waiter = NULL;
  row->fd = (int)io_hand_v(f[0]); row->maximum = f[1];
  Term handle = io_hand(((u64)row->gen << 24) | index);
  return io_tup(e, handle, handle);
}
static void __attribute__((constructor)) udpread_new_use(void) { io_eff(CID_UDPREAD_NEW, udpread_new_run, 0); }
#endif
#ifdef CID_UDPREAD_WAIT
static Term udp_read_more(Env e, IoWork* w) {
  UDPReadRow* row = udp_read_at((Term)w->size);
  if (!row) err_fail("invalid UDP read");
  Term result = udp_packet(e, w);
  if (result == IO_PARK) {
    row->waiter = (IoAct*)w;
    return io_wait_on(w, row->fd, POLLIN, udp_read_more);
  }
  return io_tup(e, udp_read_retire(row), io_box(e, CID_SOME, result, IO_HOTS & 32));
}
Term udpread_wait_run(Env e, Term* f, IoWork* w) {
  UDPReadRow* row = udp_read_at(f[0]);
  if (!row || row->waiter) err_fail("invalid UDP read owner");
  if (row->cancelled) return io_tup(e, udp_read_retire(row), term_pak(CID_NONE, 0));
  if (row->maximum > 65535)
    return io_tup(e, udp_read_retire(row), io_box(e, CID_SOME, io_fail(e, EINVAL, NULL), IO_HOTS & 32));
  w->size = f[0]; w->hand = row->fd; w->made = row->maximum;
  w->data = io_mem(malloc((size_t)w->made + 1));
  return udp_read_more(e, w);
}
static void __attribute__((constructor)) udpread_wait_use(void) { io_eff(CID_UDPREAD_WAIT, udpread_wait_run, 0); }
#endif
#ifdef CID_UDPREAD_CANCEL
Term udpread_cancel_run(Env e, Term* f, IoWork* w) {
  UDPReadRow* row = udp_read_at(f[0]);
  if (!row || row->cancelled) return term_pak(CID_FALSE, 0);
  row->cancelled = 1;
  IoAct* activation = row->waiter;
  if (activation) {
    IoAct* previous = NULL; IoAct* current = io_park.head;
    while (current && current != activation) { previous = current; current = current->next; }
    if (!current) err_fail("UDP read was not parked");
    if (previous) previous->next = activation->next; else io_park.head = activation->next;
    if (io_park.last == activation) io_park.last = previous;
    free(activation->work.data);
    activation->time = 0;
    activation->item = io_tup(e, udp_read_retire(row), term_pak(CID_NONE, 0));
    io_push(&io_runs, activation);
  }
  return term_pak(CID_TRUE, 0);
}
static void __attribute__((constructor)) udpread_cancel_use(void) { io_eff(CID_UDPREAD_CANCEL, udpread_cancel_run, 0); }
#endif
#ifdef CID_UDPREAD_RELEASE
Term udpread_release_run(Env e, Term* f, IoWork* w) {
  UDPReadRow* row = udp_read_at(f[0]);
  if (!row || row->waiter) err_fail("invalid UDP read release");
  return udp_read_retire(row);
}
static void __attribute__((constructor)) udpread_release_use(void) { io_eff(CID_UDPREAD_RELEASE, udpread_release_run, 0); }
#endif
#endif
