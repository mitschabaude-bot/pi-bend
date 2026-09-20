function udp_send_bytes(socket, family, a, b, c, d, port, scope, data, k) {
  const sys = io_sys();
  let error = ((family !== 4 && family !== 6) || port === 0 || port > 65535 ||
    (family === 4 && (b !== 0 || c !== 0 || d !== 0 || scope !== 0))) ? 22 : 0;
  const values = [];
  for (let xs = data; xs.$ === "Con"; xs = xs.tail) {
    if (xs.head > 255) error = 22;
    if (!error && values.length === 65535) error = sys.mac ? 40 : 90;
    if (!error) values.push(xs.head);
  }
  if (error) return io_tup(socket, io_fail(error));
  const at = new Uint8Array(family === 4 ? 16 : 28);
  const view = new DataView(at.buffer);
  const little = new Uint8Array(new Uint16Array([1]).buffer)[0] === 1;
  const af = family === 4 ? 2 : (sys.mac ? 30 : 10);
  if (sys.mac) { at[0] = at.length; at[1] = af; }
  else view.setUint16(0, af, little);
  view.setUint16(2, port, false);
  if (family === 4) view.setUint32(4, a, false);
  else {
    [a,b,c,d].forEach((word, i) => view.setUint32(8+4*i, word, false));
    view.setUint32(24, scope, little);
  }
  const bytes = new Uint8Array(Math.max(1, values.length));
  bytes.set(values);
  const go = () => {
    const n = Number(sys.sendto(socket, sys.ptr(bytes), values.length, 0, sys.ptr(at), at.length));
    if (n < 0) {
      const code = sys.errno();
      if (code === (sys.mac ? 35 : 11)) {
        io_park_on(socket, true, k, go);
        return undefined;
      }
      return io_tup(socket, io_fail(code));
    }
    return io_tup(socket, n === values.length ? io_done({ $: "Unit" }) : io_fail(5));
  };
  return go();
}
