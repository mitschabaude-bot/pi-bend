// All attempt/registry operations run on the existing IO loop thread.
typedef struct {
  u32 gen, next, live, cancelled, code;
  int fd;
  IoAct* waiter;
} ConnectRow;

static ConnectRow* connect_rows;
static u32 connect_len;
static u32 connect_idle = ~0u;

static ConnectRow* connect_at(Term handle) {
  u64 id = io_hand_v(handle);
  u32 index = (u32)id & 0xFFFFFF;
  ConnectRow* row = index < connect_len ? &connect_rows[index] : NULL;
  return row && row->live && row->gen == (u32)(id >> 24) ? row : NULL;
}

static void connect_drop_fd(ConnectRow* row) {
  if (row->fd >= 0) {
    close(row->fd);
    row->fd = -1;
  }
}

static void connect_retire(ConnectRow* row) {
  row->live = 0;
  row->waiter = NULL;
  // Never recycle a generation that could alias an old cancellation handle.
  if (row->gen != 0xFFFFFFFFu) {
    row->next = connect_idle;
    connect_idle = (u32)(row - connect_rows);
  }
}

static Term connect_finish(Env e, ConnectRow* row, u32 code) {
  int fd = row->fd;
  if (code != 0) connect_drop_fd(row);
  else row->fd = -1; // Ownership transfers to the returned Socket.
  connect_retire(row);
  return code == 0 ? io_done(e, io_hand(fd)) : io_fail(e, code, NULL);
}

static Term connect_ready(Env e, IoWork* work) {
  ConnectRow* row = connect_at((Term)work->size);
  if (!row || row->cancelled || row->waiter != (IoAct*)work) {
    err_fail("invalid connect completion");
  }
  int code = 0;
  socklen_t length = sizeof(code);
  if (getsockopt(row->fd, SOL_SOCKET, SO_ERROR, &code, &length)) code = errno;
  return connect_finish(e, row, (u32)code);
}

static Term connect_owner(Env e, int fd, u32 code) {
  u32 index = connect_idle;
  if (index != ~0u) {
    connect_idle = connect_rows[index].next;
  } else {
    if (connect_len == (1u << 24)) err_fail("too many connection attempts");
    if ((connect_len & (connect_len - 1)) == 0) {
      connect_rows = io_mem(realloc(connect_rows,
        (connect_len == 0 ? 1 : 2 * connect_len) * sizeof(ConnectRow)));
    }
    index = connect_len++;
    connect_rows[index].gen = 0;
  }
  ConnectRow* row = &connect_rows[index];
  row->gen += 1;
  row->live = 1;
  row->cancelled = 0;
  row->code = code;
  row->fd = fd;
  row->waiter = NULL;
  Term handle = io_hand(((u64)row->gen << 24) | index);
  return io_done(e, io_tup(e, handle, handle));
}

static Term connect_start(Env e, int family, const struct sockaddr* address, socklen_t length) {
  int fd = socket(family, SOCK_STREAM, 0);
  if (fd < 0) return io_fail(e, (u32)errno, NULL);
  int flags = fcntl(fd, F_GETFL);
  if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) {
    int code = errno;
    close(fd);
    return io_fail(e, (u32)code, NULL);
  }
  int code = connect(fd, address, length) == 0 ? 0 : errno;
  if (code != 0 && code != EINPROGRESS) {
    close(fd);
    return io_fail(e, (u32)code, NULL);
  }
  return connect_owner(e, fd, (u32)code);
}

#ifdef CID_CONNECT_IPV4
Term connect_ipv4_run(Env e, Term* fields, IoWork* work) {
  if ((u32)fields[1] > 65535) return io_fail(e, EINVAL, NULL);
  struct sockaddr_in address;
  memset(&address, 0, sizeof(address));
  address.sin_family = AF_INET;
#ifdef __APPLE__
  address.sin_len = sizeof(address);
#endif
  address.sin_port = htons((uint16_t)fields[1]);
  address.sin_addr.s_addr = htonl((u32)fields[0]);
  return connect_start(e, AF_INET, (struct sockaddr*)&address, sizeof(address));
}
static void __attribute__((constructor)) connect_ipv4_use(void) {
  io_eff(CID_CONNECT_IPV4, connect_ipv4_run, 0);
}
#endif

#ifdef CID_CONNECT_IPV6
Term connect_ipv6_run(Env e, Term* fields, IoWork* work) {
  if ((u32)fields[4] > 65535) return io_fail(e, EINVAL, NULL);
  struct sockaddr_in6 address;
  memset(&address, 0, sizeof(address));
  address.sin6_family = AF_INET6;
#ifdef __APPLE__
  address.sin6_len = sizeof(address);
#endif
  address.sin6_port = htons((uint16_t)fields[4]);
  address.sin6_scope_id = (u32)fields[5];
  uint32_t words[4] = {htonl((u32)fields[0]), htonl((u32)fields[1]),
                       htonl((u32)fields[2]), htonl((u32)fields[3])};
  memcpy(&address.sin6_addr, words, sizeof(words));
  return connect_start(e, AF_INET6, (struct sockaddr*)&address, sizeof(address));
}
static void __attribute__((constructor)) connect_ipv6_use(void) {
  io_eff(CID_CONNECT_IPV6, connect_ipv6_run, 0);
}
#endif

#ifdef CID_CONNECT_WAIT
Term connect_wait_run(Env e, Term* fields, IoWork* work) {
  ConnectRow* row = connect_at(fields[0]);
  if (!row || row->waiter) err_fail("invalid connect owner");
  if (row->cancelled) return connect_finish(e, row, ECANCELED);
  if (row->code == 0) return connect_finish(e, row, 0);
  row->waiter = (IoAct*)work;
  work->size = fields[0];
  return io_wait_on(work, row->fd, POLLOUT, connect_ready);
}
static void __attribute__((constructor)) connect_wait_use(void) {
  io_eff(CID_CONNECT_WAIT, connect_wait_run, 0);
}
#endif

#ifdef CID_CONNECT_CANCEL
Term connect_cancel_run(Env e, Term* fields, IoWork* work) {
  ConnectRow* row = connect_at(fields[0]);
  if (!row || row->cancelled) return term_pak(CID_FALSE, 0);
  row->cancelled = 1;
  connect_drop_fd(row);
  IoAct* activation = row->waiter;
  if (activation) {
    IoAct* previous = NULL;
    IoAct* current = io_park.head;
    while (current && current != activation) {
      previous = current;
      current = current->next;
    }
    if (!current) err_fail("connect wait was not parked");
    if (previous) previous->next = activation->next;
    else io_park.head = activation->next;
    if (io_park.last == activation) io_park.last = previous;
    activation->time = 0;
    activation->item = connect_finish(e, row, ECANCELED);
    io_push(&io_runs, activation);
  }
  return term_pak(CID_TRUE, 0);
}
static void __attribute__((constructor)) connect_cancel_use(void) {
  io_eff(CID_CONNECT_CANCEL, connect_cancel_run, 0);
}
#endif

#ifdef CID_CONNECT_CLOSE
Term connect_close_run(Env e, Term* fields, IoWork* work) {
  ConnectRow* row = connect_at(fields[0]);
  if (!row || row->waiter) err_fail("invalid connect retirement");
  connect_drop_fd(row);
  connect_retire(row);
  return term_pak(CID_UNIT, 0);
}
static void __attribute__((constructor)) connect_close_use(void) {
  io_eff(CID_CONNECT_CLOSE, connect_close_run, 0);
}
#endif
