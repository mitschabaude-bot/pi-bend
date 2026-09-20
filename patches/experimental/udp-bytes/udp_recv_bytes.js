function udp_recv_bytes(socket, max, k) {
  if (max > 65535) return io_tup(socket, io_fail(22));
  const sys = io_sys();
  const data = new Uint8Array(Number(max) + 1);
  const address = new Uint8Array(128);
  const length = new Uint32Array([128]);
  const go = () => {
    length[0] = address.length;
    const n = Number(sys.recvfrom(socket, sys.ptr(data), data.length, 0,
      sys.ptr(address), sys.ptr(length)));
    if (n < 0) {
      const code = sys.errno();
      if (code === (sys.mac ? 35 : 11)) {
        io_park_on(socket, false, k, go);
        return undefined;
      }
      return io_tup(socket, io_fail(code));
    }
    const view = new DataView(address.buffer);
    const little = new Uint8Array(new Uint16Array([1]).buffer)[0] === 1;
    const family = sys.mac ? address[1] : view.getUint16(0, little);
    let peer;
    if (family === 2 && length[0] >= 16) {
      peer = io_tup(4, view.getUint32(4, false), 0, 0, 0, view.getUint16(2, false), 0);
    } else if (family === (sys.mac ? 30 : 10) && length[0] >= 28) {
      peer = io_tup(6, view.getUint32(8, false), view.getUint32(12, false),
        view.getUint32(16, false), view.getUint32(20, false),
        view.getUint16(2, false), view.getUint32(24, little));
    } else return io_tup(socket, io_fail(sys.mac ? 47 : 97));
    let bytes = { $: "Nil" };
    for (let i = Math.min(n, Number(max)); i > 0; --i)
      bytes = { $: "Con", head: data[i-1], tail: bytes };
    return io_tup(socket, io_done(io_tup(peer, n > max, bytes)));
  };
  return go();
}
function udp_recv_bytes_need() { return { read: true }; }
