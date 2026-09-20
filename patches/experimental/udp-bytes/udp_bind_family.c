Term udp_bind_family_run(Env e, Term* f, IoWork* w) {
  u32 family = f[0], port = f[1];
  if ((family != 4 && family != 6) || port > 65535)
    return io_fail(e, EINVAL, NULL);
  int fd = socket(family == 4 ? AF_INET : AF_INET6, SOCK_DGRAM, 0);
  if (fd < 0) return io_fail(e, errno, NULL);
  int status;
  if (family == 4) {
    struct sockaddr_in at = {0};
    at.sin_family = AF_INET; at.sin_port = htons(port);
    status = bind(fd, (struct sockaddr*)&at, sizeof(at));
  } else {
    int one = 1;
    status = setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &one, sizeof(one));
    if (status == 0) {
      struct sockaddr_in6 at = {0};
      at.sin6_family = AF_INET6; at.sin6_port = htons(port);
      status = bind(fd, (struct sockaddr*)&at, sizeof(at));
    }
  }
  if (status < 0 || fcntl(fd, F_SETFD, FD_CLOEXEC) < 0 ||
      fcntl(fd, F_SETFL, O_NONBLOCK) < 0) {
    int code = errno;
    close(fd);
    return io_fail(e, code, NULL);
  }
  return io_done(e, io_hand(fd));
}
static void __attribute__((constructor)) udp_bind_family_use(void) {
  io_eff(CID_UDP_BIND_FAMILY, udp_bind_family_run, 0);
}
