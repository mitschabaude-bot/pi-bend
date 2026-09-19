// Shared by all four effects; included only when a timer effect is reachable.
function timer_new(ms) {
  const row = { deadline: performance.now() + Number(ms), state: 0, waiter: null };
  return io_tup(row, row);
}

function timer_wait(row, k) {
  if (row.state === 3 || row.waiter !== null) throw Error('invalid timer owner');
  if (row.state !== 0) return io_tup(row, row.state === 1);
  if (row.deadline <= performance.now()) {
    row.state = 1;
    return io_tup(row, true);
  }
  const wait = { at: row.deadline, k, more() {
    if (row.state !== 0 || row.waiter !== wait) throw Error('invalid timer completion');
    row.state = 1;
    row.waiter = null;
    return io_tup(row, true);
  }};
  row.waiter = wait;
  globalThis.BEND_IO.waits.push(wait);
  return undefined;
}

function timer_cancel(row) {
  if (row.state !== 0) return false;
  if (row.waiter !== null) {
    const io = globalThis.BEND_IO;
    const index = io.waits.indexOf(row.waiter);
    // The poller has committed completion and queued its continuation already.
    if (index < 0) return false;
    const wait = row.waiter;
    io.waits.splice(index, 1);
    row.waiter = null;
    row.state = 2;
    io_push(wait.k, io_tup(row, false), false);
  } else {
    row.state = 2;
  }
  return true;
}

function timer_close(row) {
  if (row.state === 3 || row.waiter !== null) throw Error('invalid timer retirement');
  row.state = 3;
  return { $: 'Unit' };
}
