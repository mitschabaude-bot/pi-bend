// Only the monotonic clock and test controls differ from production. Due timer
// selection, completion, cancellation and retirement use the emitted runtime.
Term testclock_advance_run(Env e, Term* fields, IoWork* work) {
  test_clock_ns += (u64)(u32)fields[0] * 1000000ull;
  for (IoAct* a = io_park.head; a; a = a->next) {
    if (a->time && a->time <= test_clock_ns) {
      io_wait(e); // At least one deadline is due: the poll timeout is zero.
      break;
    }
  }
  return term_pak(CID_UNIT, 0);
}
Term testclock_barrier_run(Env e, Term* fields, IoWork* work) {
  IoAct* a = (IoAct*)work;
  a->item = term_pak(CID_UNIT, 0);
  io_push(&io_runs, a);
  return IO_PARK;
}
Term testclock_pending_run(Env e, Term* fields, IoWork* work) {
  u32 pending = 0;
  for (u32 i = 0; i < timer_len; i++)
    pending += timer_rows[i].live && timer_rows[i].state == 0;
  return pending;
}
static void __attribute__((destructor)) testclock_audit(void) {
  u32 timers=0,waiters=0,channels=0;
  for(u32 i=0;i<timer_len;i++){timers+=timer_rows[i].live;waiters+=timer_rows[i].waiter!=NULL;}
  for(u32 i=0;i<chan_len;i++){channels+=chan_rows[i].live;}
  fprintf(stderr,"CLOCK_AUDIT %u %u %u\n",timers,waiters,channels);
}
