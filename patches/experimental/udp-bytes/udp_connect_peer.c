// Associate an existing datagram socket with a numeric peer. UDP has no
// connection handshake; getsockname can then report the selected local route.
Term udp_connect_peer_run(Env e, Term* f, IoWork* w) {
  int fd=(int)io_hand_v(f[0]);
  u32 family=f[1],port=f[6],scope=f[7];
  if((family!=4 && family!=6) || port==0 || port>65535 ||
     (family==4 && (f[3] || f[4] || f[5] || scope)))
    return io_tup(e,io_hand(fd),io_fail(e,EINVAL,NULL));
  struct sockaddr_storage storage={0};
  socklen_t length;
  if(family==4) {
    struct sockaddr_in* at=(struct sockaddr_in*)&storage;
    at->sin_family=AF_INET; at->sin_port=htons(port);
    at->sin_addr.s_addr=htonl(f[2]); length=sizeof(*at);
  } else {
    struct sockaddr_in6* at=(struct sockaddr_in6*)&storage;
    at->sin6_family=AF_INET6; at->sin6_port=htons(port); at->sin6_scope_id=scope;
    uint32_t words[4]={htonl(f[2]),htonl(f[3]),htonl(f[4]),htonl(f[5])};
    memcpy(&at->sin6_addr,words,sizeof(words)); length=sizeof(*at);
  }
  int result=connect(fd,(struct sockaddr*)&storage,length);
  return io_tup(e,io_hand(fd),result<0 ? io_fail(e,errno,NULL) : io_done(e,term_pak(CID_UNIT,0)));
}
static void __attribute__((constructor)) udp_connect_peer_use(void) {
  io_eff(CID_UDP_CONNECT_PEER,udp_connect_peer_run,0);
}
