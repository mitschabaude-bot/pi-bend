// Owned one-shot timer; all operations run on the existing IO loop thread.
typedef struct {
  u32 gen, next, live, state;
  u64 deadline;
  IoAct* waiter;
} TimerRow;

static TimerRow* timer_rows;
static u32 timer_len;
static u32 timer_idle = ~0u;

static TimerRow* timer_at(Term handle) {
  u64 id = io_hand_v(handle);
  u32 index = (u32)id & 0xFFFFFF;
  TimerRow* row = index < timer_len ? &timer_rows[index] : NULL;
  return row && row->live && row->gen == (u32)(id >> 24) ? row : NULL;
}

static Term timer_bool(bool value) {
  return term_pak(value ? CID_TRUE : CID_FALSE, 0);
}

static Term timer_result(Env e, Term handle, bool elapsed) {
  return io_tup(e, handle, timer_bool(elapsed));
}

static Term timer_ready(Env e, IoWork* work) {
  Term handle = (Term)work->size;
  TimerRow* row = timer_at(handle);
  if (!row || row->state != 0 || row->waiter != (IoAct*)work) {
    err_fail("invalid timer completion");
  }
  row->state = 1;
  row->waiter = NULL;
  return timer_result(e, handle, true);
}

#ifdef CID_TIMER_NEW
Term timer_new_run(Env e, Term* fields, IoWork* work) {
  u32 index = timer_idle;
  if (index != ~0u) {
    timer_idle = timer_rows[index].next;
  } else {
    if (timer_len == (1u << 24)) err_fail("too many timers");
    if ((timer_len & (timer_len - 1)) == 0) {
      timer_rows = io_mem(realloc(timer_rows,
        (timer_len == 0 ? 1 : 2 * timer_len) * sizeof(TimerRow)));
    }
    index = timer_len++;
    timer_rows[index].gen = 0;
  }
  TimerRow* row = &timer_rows[index];
  row->gen += 1;
  row->live = 1;
  row->state = 0;
  row->deadline = io_tick() + (u64)(u32)fields[0] * 1000000ull;
  row->waiter = NULL;
  Term handle = io_hand(((u64)row->gen << 24) | index);
  return io_tup(e, handle, handle);
}
static void __attribute__((constructor)) timer_new_use(void) {
  io_eff(CID_TIMER_NEW, timer_new_run, 0);
}
#endif

#ifdef CID_TIMER_WAIT
Term timer_wait_run(Env e, Term* fields, IoWork* work) {
  Term handle = fields[0];
  TimerRow* row = timer_at(handle);
  if (!row || row->waiter) err_fail("invalid timer owner");
  if (row->state != 0) return timer_result(e, handle, row->state == 1);
  if (row->deadline <= io_tick()) {
    row->state = 1;
    return timer_result(e, handle, true);
  }
  IoAct* activation = (IoAct*)work;
  work->size = handle;
  work->pack = timer_ready;
  activation->time = row->deadline;
  activation->evts = 0;
  row->waiter = activation;
  io_push(&io_park, activation);
  return IO_PARK;
}
static void __attribute__((constructor)) timer_wait_use(void) {
  io_eff(CID_TIMER_WAIT, timer_wait_run, 0);
}
#endif

#ifdef CID_TIMER_CANCEL
Term timer_cancel_run(Env e, Term* fields, IoWork* work) {
  TimerRow* row = timer_at(fields[0]);
  if (!row || row->state != 0) return timer_bool(false);
  row->state = 2;
  IoAct* activation = row->waiter;
  if (activation) {
    // Only the new cancellation path scans the existing singly linked queue.
    IoAct* previous = NULL;
    IoAct* current = io_park.head;
    while (current && current != activation) {
      previous = current;
      current = current->next;
    }
    if (!current) err_fail("timer wait was not parked");
    if (previous) previous->next = activation->next;
    else io_park.head = activation->next;
    if (io_park.last == activation) io_park.last = previous;
    row->waiter = NULL;
    activation->time = 0;
    activation->item = timer_result(e, fields[0], false);
    io_push(&io_runs, activation);
  }
  return timer_bool(true);
}
static void __attribute__((constructor)) timer_cancel_use(void) {
  io_eff(CID_TIMER_CANCEL, timer_cancel_run, 0);
}
#endif

#ifdef CID_TIMER_CLOSE
Term timer_close_run(Env e, Term* fields, IoWork* work) {
  TimerRow* row = timer_at(fields[0]);
  if (!row || row->waiter) err_fail("invalid timer retirement");
  row->live = 0;
  // Never wrap a generation and accidentally accept an ancient cancel handle.
  if (row->gen != 0xFFFFFFFFu) {
    row->next = timer_idle;
    timer_idle = (u32)(row - timer_rows);
  }
  return term_pak(CID_UNIT, 0);
}
static void __attribute__((constructor)) timer_close_use(void) {
  io_eff(CID_TIMER_CLOSE, timer_close_run, 0);
}
#endif
