function io_system_identity() {
  try {
    const os = require("node:os");
    return io_done(io_tup(os.platform(), os.release(), os.arch()));
  } catch (error) {
    const code = error.errno ?? error.info?.errno;
    return io_fail(Number.isInteger(code) && code !== 0 ? Math.abs(code) : 5);
  }
}
