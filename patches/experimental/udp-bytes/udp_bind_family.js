function udp_bind_family(family, port) {
  if ((family !== 4 && family !== 6) || port > 65535) return io_fail(22);
  const sys = io_sys();
  const af = family === 4 ? 2 : (sys.mac ? 30 : 10);
  const fd = sys.socket(af, 2, 0);
  if (fd < 0) return io_fail(sys.errno());
  const fail = () => { const code = sys.errno(); sys.close(fd); return io_fail(code); };
  const at = new Uint8Array(family === 4 ? 16 : 28);
  const view = new DataView(at.buffer);
  const little = new Uint8Array(new Uint16Array([1]).buffer)[0] === 1;
  if (sys.mac) { at[0] = at.length; at[1] = af; }
  else view.setUint16(0, af, little);
  view.setUint16(2, port, false);
  if (family === 6) {
    const one = new Int32Array([1]);
    if (sys.setsockopt(fd, 41, sys.mac ? 27 : 26, sys.ptr(one), 4) < 0) return fail();
  }
  if (sys.bind(fd, sys.ptr(at), at.length) < 0 ||
      sys.fcntl(fd, 2, 1) < 0 ||
      sys.fcntl(fd, 4, sys.mac ? 4 : 0x800) < 0) return fail();
  return io_done(fd);
}
