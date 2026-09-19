// Test-only declarations. Definitions are appended after the emitted runtime
// so they can inspect its private timer table without changing timer effects.
Term testclock_advance_run(Env, Term*, IoWork*);
Term testclock_barrier_run(Env, Term*, IoWork*);
Term testclock_pending_run(Env, Term*, IoWork*);
static void __attribute__((constructor)) testclock_use(void) {
  io_eff(CID_TESTCLOCK_ADVANCE, testclock_advance_run, 0);
  io_eff(CID_TESTCLOCK_BARRIER, testclock_barrier_run, 0);
  io_eff(CID_TESTCLOCK_PENDING, testclock_pending_run, 0);
}
