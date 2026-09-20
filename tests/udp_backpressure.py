"""Inject test-only would-block failures into generated UDP send effects."""

def inject(native_source, native_target, js_source, js_target):
    source=native_source.read_text()
    needle='static Term udp_send_packet('
    assert source.count(needle)==1
    helper='''
    static unsigned udp_test_blocks;
    static ssize_t udp_test_sendto(int fd,const void* data,size_t size,int flags,const struct sockaddr* to,socklen_t length) {
      if(size==256 && ((const unsigned char*)data)[0]==0) {
        const char* raw=getenv("UDP_TEST_RELEASE_AFTER");
        unsigned limit=raw ? (unsigned)strtoul(raw,NULL,10) : 0;
        if(!limit || udp_test_blocks<limit) { udp_test_blocks++; errno=EAGAIN; return -1; }
      }
      return sendto(fd,data,size,flags,to,length);
    }
    static void __attribute__((destructor)) udp_test_audit(void) { fprintf(stderr,"BLOCKED %u\\n",udp_test_blocks); }
    '''
    source=source.replace(needle,helper+'\n'+needle).replace('ssize_t n = sendto(fd,','ssize_t n = udp_test_sendto(fd,')
    native_target.write_text(source)
    source=js_source.read_text()
    a=source.index('function udp_send_start(');b=source.index('\nfunction udp_send_bytes(',a)
    part=source[a:b]
    needle='const n = Number(sys.sendto(socket, sys.ptr(bytes), length, 0, sys.ptr(at), at.length));'
    assert part.count(needle)==1
    part=part.replace(needle,'''const limit=Number(process.env.UDP_TEST_RELEASE_AFTER || 0);
        const blocks=globalThis.UDP_TEST_BLOCKS || 0;
        const forced=length===256 && bytes[0]===0 && (!limit || blocks<limit);
        if(forced) globalThis.UDP_TEST_BLOCKS=blocks+1;
        const n = forced ? -1 : Number(sys.sendto(socket, sys.ptr(bytes), length, 0, sys.ptr(at), at.length));''').replace('const code = sys.errno();','const code = forced ? (sys.mac ? 35 : 11) : sys.errno();')
    source=source[:a]+part+source[b:]
    source='process.on("exit",()=>console.error("BLOCKED "+(globalThis.UDP_TEST_BLOCKS || 0)));\n'+source
    js_target.write_text(source)
