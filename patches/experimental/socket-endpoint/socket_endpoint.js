// Bind only when the new effect runs; existing IO paths are unchanged.
function socket_endpoint(socket, side) {
  if (side > 1) return io_tup(socket, io_fail(22));
  const sys = io_sys();
  if (globalThis.BEND_SOCKET_ENDPOINT === undefined) {
    const ffi = require("bun:ffi");
    globalThis.BEND_SOCKET_ENDPOINT = ffi.dlopen(sys.mac ? "libSystem.dylib" : "libc.so.6", {
      getsockname: { args: ["i32", "ptr", "ptr"], returns: "i32" },
      getpeername: { args: ["i32", "ptr", "ptr"], returns: "i32" }
    });
  }
  const address = new Uint8Array(128);
  const length = new Uint32Array([address.length]);
  const call = globalThis.BEND_SOCKET_ENDPOINT.symbols[side === 0 ? "getsockname" : "getpeername"];
  if (call(socket, sys.ptr(address), sys.ptr(length)) < 0) {
    return io_tup(socket, io_fail(sys.errno()));
  }
  const view = new DataView(address.buffer);
  const little = new Uint8Array(new Uint16Array([1]).buffer)[0] === 1;
  const family = sys.mac ? address[1] : view.getUint16(0, little);
  const unsupported = () => io_tup(socket, io_fail(sys.mac ? 47 : 97));
  if (family === 2 && length[0] >= 16) {
    return io_tup(socket, io_done(io_tup(4, view.getUint32(4, false), 0, 0, 0,
      view.getUint16(2, false), 0)));
  }
  if (family === (sys.mac ? 30 : 10) && length[0] >= 28) {
    return io_tup(socket, io_done(io_tup(6, view.getUint32(8, false),
      view.getUint32(12, false), view.getUint32(16, false), view.getUint32(20, false),
      view.getUint16(2, false), view.getUint32(24, little))));
  }
  return unsupported();
}
