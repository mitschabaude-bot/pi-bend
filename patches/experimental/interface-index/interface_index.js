let io_interface_index_library;
function io_interface_index(name) {
  if (name.includes("\0")) return io_fail(22);
  if (process.platform !== "linux") return io_fail(38);
  try {
    // Resolve only the OS primitive. Address/scope policy stays in Bend.
    const ffi = require("bun:ffi");
    if (!io_interface_index_library) {
      io_interface_index_library = ffi.dlopen("libc.so.6", {
        if_nametoindex: { args: ["ptr"], returns: "u32" },
        __errno_location: { args: [], returns: "ptr" },
      });
    }
    const symbols = io_interface_index_library.symbols;
    const bytes = Buffer.from(name + "\0");
    const pointer = ffi.ptr(bytes);
    const errnoPointer = symbols.__errno_location();
    const errnoValue = new Int32Array(ffi.toArrayBuffer(errnoPointer, 0, 4));
    errnoValue[0] = 0;
    // No allocation or async boundary between the call and errno read.
    const index = symbols.if_nametoindex(pointer);
    const code = index === 0 ? errnoValue[0] : 0;
    return index === 0 ? io_fail(code || 5) : io_done(index);
  } catch (error) {
    const code = error.errno ?? error.info?.errno;
    return io_fail(Number.isInteger(code) && code !== 0 ? Math.abs(code) : 5);
  }
}
