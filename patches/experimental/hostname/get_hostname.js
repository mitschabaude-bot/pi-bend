function io_get_hostname() {
  try {
    return io_done(require("node:os").hostname());
  } catch (error) {
    const code = error.errno ?? error.info?.errno;
    return io_fail(Number.isInteger(code) && code !== 0 ? Math.abs(code) : 5);
  }
}
