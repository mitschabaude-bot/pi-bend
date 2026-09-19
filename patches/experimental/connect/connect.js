// Opaque attempt object. All operations run on the existing IO loop thread.
function connect_address(family, port, size) {
  const bytes = new Uint8Array(size);
  const view = new DataView(bytes.buffer);
  const little = new Uint8Array(new Uint16Array([1]).buffer)[0] === 1;
  if (io_sys().mac) bytes.set([size, family]);
  else view.setUint16(0, family, little);
  view.setUint16(2, Number(port), false);
  return { bytes, view, little };
}

function connect_start(family, address) {
  const sys = io_sys();
  const fd = sys.socket(family, 1, 0);
  if (fd < 0) return io_fail(sys.errno());
  const fail = (code) => { sys.close(fd); return io_fail(code); };
  const flags = sys.fcntl(fd, 3, 0);
  if (flags < 0 || sys.fcntl(fd, 4, flags | (sys.mac ? 4 : 0x800)) < 0) return fail(sys.errno());
  const code = sys.connect(fd, sys.ptr(address), address.length) >= 0 ? 0 : sys.errno();
  if (code !== 0 && code !== (sys.mac ? 36 : 115)) return fail(code);
  const row = { fd, code, state: 0, waiter: null };
  return io_done(io_tup(row, row));
}

function connect_ipv4(word, port) {
  if (port > 65535) return io_fail(22);
  const address = connect_address(2, port, 16);
  address.view.setUint32(4, Number(word), false);
  return connect_start(2, address.bytes);
}

function connect_ipv6(a, b, c, d, port, scope) {
  if (port > 65535) return io_fail(22);
  const family = io_sys().mac ? 30 : 10;
  const address = connect_address(family, port, 28);
  for (const [i, word] of [a, b, c, d].entries()) address.view.setUint32(8 + 4*i, Number(word), false);
  address.view.setUint32(24, Number(scope), address.little);
  return connect_start(family, address.bytes);
}

function connect_drop_fd(row) {
  if (row.fd >= 0) { io_sys().close(row.fd); row.fd = -1; }
}

function connect_finish(row, code) {
  const fd = row.fd;
  if (code !== 0) connect_drop_fd(row);
  else row.fd = -1;
  row.state = 3;
  row.waiter = null;
  return code === 0 ? io_done(fd) : io_fail(code);
}

function connect_wait(row, k) {
  if (row.state === 3 || row.waiter !== null) throw Error('invalid connect owner');
  if (row.state === 2) return connect_finish(row, io_sys().mac ? 89 : 125);
  if (row.code === 0) return connect_finish(row, 0);
  const wait = { fd: row.fd, out: true, k, more() {
    if (row.state !== 0 || row.waiter !== wait) throw Error('invalid connect completion');
    const sys = io_sys();
    const value = new Int32Array([0]);
    const length = new Uint32Array([4]);
    const code = sys.getsockopt(row.fd, sys.mac ? 0xffff : 1, sys.mac ? 0x1007 : 4,
      sys.ptr(value), sys.ptr(length)) < 0 ? sys.errno() : value[0];
    return connect_finish(row, code);
  }};
  row.waiter = wait;
  globalThis.BEND_IO.waits.push(wait);
  return undefined;
}

function connect_cancel(row) {
  if (row.state !== 0) return false;
  const io = globalThis.BEND_IO;
  const wait = row.waiter;
  if (wait !== null) {
    const index = io.waits.indexOf(wait);
    // A wait selected by the poller has already committed completion.
    if (index < 0) return false;
    io.waits.splice(index, 1);
  }
  row.state = 2;
  connect_drop_fd(row);
  if (wait !== null) io_push(wait.k, connect_finish(row, io_sys().mac ? 89 : 125), false);
  return true;
}

function connect_close(row) {
  if (row.state === 3 || row.waiter !== null) throw Error('invalid connect retirement');
  connect_drop_fd(row);
  row.state = 3;
  return { $: 'Unit' };
}
