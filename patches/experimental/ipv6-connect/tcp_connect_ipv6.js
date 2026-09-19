// Only sockaddr construction and socket lifecycle; no host URL/DNS APIs.
function tcp_connect_ipv6(a, b, c, d, port, scope, k) {
  if (port > 65535) return io_fail(22);
  const sys = io_sys();
  const family = sys.mac ? 30 : 10;
  const address = new Uint8Array(28);
  const view = new DataView(address.buffer);
  const little = new Uint8Array(new Uint16Array([1]).buffer)[0] === 1;
  if (sys.mac) address.set([28, family]);
  else view.setUint16(0, family, little);
  view.setUint16(2, Number(port), false);
  for (const [i, word] of [a, b, c, d].entries()) {
    view.setUint32(8 + 4 * i, Number(word), false);
  }
  // Scope IDs are native-order integers, unlike the network-order address.
  view.setUint32(24, Number(scope), little);
  const fd = sys.socket(family, 1, 0);
  if (fd < 0) return io_fail(sys.errno());
  const end = (code) => {
    if (code !== 0) {
      sys.close(fd);
      return io_fail(code);
    }
    return io_done(fd);
  };
  const error = () => {
    const value = new Int32Array([0]);
    const length = new Uint32Array([4]);
    return sys.getsockopt(fd, sys.mac ? 0xffff : 1, sys.mac ? 0x1007 : 4,
      sys.ptr(value), sys.ptr(length)) < 0 ? sys.errno() : value[0];
  };
  const flags = sys.fcntl(fd, 3, 0);
  if (flags < 0 || sys.fcntl(fd, 4, flags | (sys.mac ? 4 : 0x800)) < 0) {
    return end(sys.errno());
  }
  const code = sys.connect(fd, sys.ptr(address), address.length) >= 0 ? 0 : sys.errno();
  if (code !== (sys.mac ? 36 : 115)) return end(code);
  io_park_on(fd, true, k, () => end(error()));
  return undefined;
}
