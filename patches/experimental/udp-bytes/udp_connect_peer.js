function udp_connect_peer(socket,family,a,b,c,d,port,scope) {
  if((family!==4 && family!==6) || port===0 || port>65535 ||
      (family===4 && (b!==0 || c!==0 || d!==0 || scope!==0)))
    return io_tup(socket,io_fail(22));
  const sys=io_sys();
  const at=new Uint8Array(family===4?16:28);
  const view=new DataView(at.buffer);
  const little=new Uint8Array(new Uint16Array([1]).buffer)[0]===1;
  const af=family===4?2:(sys.mac?30:10);
  if(sys.mac){at[0]=at.length;at[1]=af;}else view.setUint16(0,af,little);
  view.setUint16(2,port,false);
  if(family===4)view.setUint32(4,a,false);
  else {
    [a,b,c,d].forEach((word,i)=>view.setUint32(8+4*i,word,false));
    view.setUint32(24,scope,little);
  }
  const result=sys.connect(socket,sys.ptr(at),at.length);
  return io_tup(socket,result<0?io_fail(sys.errno()):io_done({$:"Unit"}));
}
