function entropy_bytes(count) {
  if (count > 256) return io_fail(22);
  if (count === 0) return io_done({ $: "Nil" });
  if (process.platform !== "linux") return io_fail(process.platform === "darwin" ? 78 : 38);
  const sys = io_sys();
  if (globalThis.BEND_ENTROPY === undefined) {
    const ffi = require("bun:ffi");
    globalThis.BEND_ENTROPY = ffi.dlopen("libc.so.6", {
      getrandom: { args: ["ptr", "u64", "u32"], returns: "i64" }
    });
  }
  const buffer = new Uint8Array(count);
  const size = Number(globalThis.BEND_ENTROPY.symbols.getrandom(sys.ptr(buffer), count, 1));
  if (size < 0) return io_fail(sys.errno());
  if (size !== count) return io_fail(5);
  let bytes = { $: "Nil" };
  for (let i = count; i > 0; i--) bytes = { $: "Con", head: buffer[i - 1], tail: bytes };
  return io_done(bytes);
}
