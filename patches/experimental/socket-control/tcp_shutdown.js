// Bind this syscall only when the effect is used; existing IO paths are unchanged.
function tcp_shutdown(socket) {
  const sys = io_sys();
  if (globalThis.BEND_TCP_SHUTDOWN === undefined) {
    const ffi = require("bun:ffi");
    globalThis.BEND_TCP_SHUTDOWN = ffi.dlopen(sys.mac ? "libSystem.dylib" : "libc.so.6", {
      shutdown: { args: ["i32", "i32"], returns: "i32" }
    });
  }
  const status = globalThis.BEND_TCP_SHUTDOWN.symbols.shutdown(socket, 2);
  return io_tup(socket, status < 0 ? io_fail(sys.errno()) : io_done({ $: "Unit" }));
}
