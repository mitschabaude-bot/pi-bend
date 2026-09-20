static Term udp_send_packet(Env e, IoWork* w) {
  int fd = (int)w->hand;
  if (!w->code) {
    ssize_t n = sendto(fd, w->data, w->size, 0,
      (struct sockaddr*)w->text, (socklen_t)w->made);
    io_sys_end(w, n);
    if (w->code == EAGAIN) {
      w->code = 0;
      return IO_PARK;
    }
    if (!w->code && (u64)n != w->size) w->code = EIO;
  }
  Term result = w->code ? io_fail(e, w->code, NULL)
    : io_done(e, term_pak(CID_UNIT, 0));
  free(w->text); free(w->data);
  return result;
}

static void udp_send_prepare(Env e, Term* f, IoWork* w) {
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
}
#ifdef CID_UDP_SEND_BYTES
static Term udp_send_bytes_more(Env e, IoWork* w) {
  Term result = udp_send_packet(e, w);
  return result == IO_PARK ? io_wait_on(w, (int)w->hand, POLLOUT, udp_send_bytes_more)
    : io_tup(e, io_hand(w->hand), result);
}
Term udp_send_bytes_run(Env e, Term* f, IoWork* w) {
  udp_send_prepare(e, f, w);
  return udp_send_bytes_more(e, w);
}
static void __attribute__((constructor)) udp_send_bytes_use(void) {
  io_eff(CID_UDP_SEND_BYTES, udp_send_bytes_run, 0);
}

#endif

#if defined(CID_UDPWRITE_NEW) || defined(CID_UDPWRITE_WAIT) || defined(CID_UDPWRITE_CANCEL) || defined(CID_UDPWRITE_RELEASE)
typedef struct { u32 gen, next, live, cancelled; IoWork payload; IoAct* waiter; } UDPWriteRow;
static UDPWriteRow* udp_write_rows;
static u32 udp_write_len, udp_write_idle = ~0u;
static UDPWriteRow* udp_write_at(Term handle) {
  u64 id = io_hand_v(handle); u32 index = (u32)id & 0xFFFFFF;
  UDPWriteRow* row = index < udp_write_len ? &udp_write_rows[index] : NULL;
  return row && row->live && row->gen == (u32)(id >> 24) ? row : NULL;
}
static Term udp_write_retire(UDPWriteRow* row) {
  Term socket = io_hand(row->payload.hand);
  row->live = 0; row->waiter = NULL; row->payload.text = NULL; row->payload.data = NULL;
  if (row->gen != 0xFFFFFFFFu) { row->next = udp_write_idle; udp_write_idle = (u32)(row-udp_write_rows); }
  return socket;
}
#ifdef CID_UDPWRITE_NEW
Term udpwrite_new_run(Env e, Term* f, IoWork* w) {
  u32 index = udp_write_idle;
  if (index != ~0u) udp_write_idle = udp_write_rows[index].next;
  else {
    if (udp_write_len == (1u << 24)) err_fail("too many UDP writes");
    if ((udp_write_len & (udp_write_len-1)) == 0)
      udp_write_rows = io_mem(realloc(udp_write_rows, (udp_write_len ? 2*udp_write_len : 1)*sizeof(UDPWriteRow)));
    index = udp_write_len++; udp_write_rows[index].gen = 0;
  }
  UDPWriteRow* row = &udp_write_rows[index];
  row->gen++; row->live=1; row->cancelled=0; row->waiter=NULL;
  memset(&row->payload, 0, sizeof(row->payload));
  udp_send_prepare(e, f, &row->payload);
  Term handle = io_hand(((u64)row->gen << 24) | index);
  // Only owned writes need the extra handle storage; plain sends are unchanged.
  row->payload.text = io_mem(realloc(row->payload.text, sizeof(struct sockaddr_storage)+sizeof(Term)));
  memcpy(row->payload.text+sizeof(struct sockaddr_storage), &handle, sizeof(handle));
  return io_tup(e, handle, handle);
}
static void __attribute__((constructor)) udpwrite_new_use(void) { io_eff(CID_UDPWRITE_NEW, udpwrite_new_run, 0); }
#endif
#ifdef CID_UDPWRITE_WAIT
static Term udp_write_more(Env e, IoWork* w) {
  Term handle; memcpy(&handle, w->text+sizeof(struct sockaddr_storage), sizeof(handle));
  UDPWriteRow* row = udp_write_at(handle);
  if (!row) err_fail("invalid UDP write");
  Term result = udp_send_packet(e, w);
  if (result == IO_PARK) {
    row->waiter = (IoAct*)w;
    return io_wait_on(w, (int)w->hand, POLLOUT, udp_write_more);
  }
  return io_tup(e, udp_write_retire(row), io_box(e, CID_SOME, result, IO_HOTS & 32));
}
Term udpwrite_wait_run(Env e, Term* f, IoWork* w) {
  UDPWriteRow* row = udp_write_at(f[0]);
  if (!row || row->waiter) err_fail("invalid UDP write owner");
  if (row->cancelled) {
    free(row->payload.text); free(row->payload.data);
    return io_tup(e, udp_write_retire(row), term_pak(CID_NONE,0));
  }
  *w = row->payload;
  return udp_write_more(e, w);
}
static void __attribute__((constructor)) udpwrite_wait_use(void) { io_eff(CID_UDPWRITE_WAIT, udpwrite_wait_run, 0); }
#endif
#ifdef CID_UDPWRITE_CANCEL
Term udpwrite_cancel_run(Env e, Term* f, IoWork* w) {
  UDPWriteRow* row = udp_write_at(f[0]);
  if (!row || row->cancelled) return term_pak(CID_FALSE,0);
  row->cancelled=1;
  IoAct* activation=row->waiter;
  if (activation) {
    IoAct* previous=NULL; IoAct* current=io_park.head;
    while(current && current!=activation) { previous=current; current=current->next; }
    if(!current) err_fail("UDP write was not parked");
    if(previous) previous->next=activation->next; else io_park.head=activation->next;
    if(io_park.last==activation) io_park.last=previous;
    free(activation->work.text); free(activation->work.data);
    activation->time=0;
    activation->item=io_tup(e,udp_write_retire(row),term_pak(CID_NONE,0));
    io_push(&io_runs,activation);
  }
  return term_pak(CID_TRUE,0);
}
static void __attribute__((constructor)) udpwrite_cancel_use(void) { io_eff(CID_UDPWRITE_CANCEL,udpwrite_cancel_run,0); }
#endif
#ifdef CID_UDPWRITE_RELEASE
Term udpwrite_release_run(Env e, Term* f, IoWork* w) {
  UDPWriteRow* row=udp_write_at(f[0]);
  if(!row || row->waiter) err_fail("invalid UDP write release");
  free(row->payload.text); free(row->payload.data);
  return udp_write_retire(row);
}
static void __attribute__((constructor)) udpwrite_release_use(void) { io_eff(CID_UDPWRITE_RELEASE,udpwrite_release_run,0); }
#endif
#endif
