function udp_send_prepare(socket, family, a, b, c, d, port, scope, data) {
  const sys = io_sys();
  let error = ((family !== 4 && family !== 6) || port === 0 || port > 65535 ||
    (family === 4 && (b !== 0 || c !== 0 || d !== 0 || scope !== 0))) ? 22 : 0;
  const values = [];
  for (let xs = data; xs.$ === "Con"; xs = xs.tail) {
    if (xs.head > 255) error = 22;
    if (!error && values.length === 65535) error = sys.mac ? 40 : 90;
    if (!error) values.push(xs.head);
  }
  if (error) return {socket, error};
  const at = new Uint8Array(family === 4 ? 16 : 28);
  const view = new DataView(at.buffer);
  const little = new Uint8Array(new Uint16Array([1]).buffer)[0] === 1;
  const af = family === 4 ? 2 : (sys.mac ? 30 : 10);
  if (sys.mac) { at[0] = at.length; at[1] = af; }
  else view.setUint16(0, af, little);
  view.setUint16(2, port, false);
  if (family === 4) view.setUint32(4, a, false);
  else {
    [a,b,c,d].forEach((word, i) => view.setUint32(8+4*i, word, false));
    view.setUint32(24, scope, little);
  }
  const bytes = new Uint8Array(Math.max(1, values.length));
  bytes.set(values);
  return {socket, error: 0, bytes, length: values.length, at};
}
function udp_send_start(prepared, complete, park) {
  const {socket, error, bytes, length, at} = prepared;
  if (error) return complete(io_fail(error));
  const sys = io_sys();
  const go = () => {
    const n = Number(sys.sendto(socket, sys.ptr(bytes), length, 0, sys.ptr(at), at.length));
    if (n < 0) {
      const code = sys.errno();
      if (code === (sys.mac ? 35 : 11)) {
        park(go);
        return undefined;
      }
      return complete(io_fail(code));
    }
    return complete(n === length ? io_done({ $: "Unit" }) : io_fail(5));
  };
  return go();
}

function udp_send_bytes(socket, family, a, b, c, d, port, scope, data, k) {
  return udp_send_start(udp_send_prepare(socket,family,a,b,c,d,port,scope,data),
    result => io_tup(socket,result), go => io_park_on(socket,true,k,go));
}
function udpwrite_new(socket,family,a,b,c,d,port,scope,data) {
  const row={socket,state:0,waiter:null,prepared:udp_send_prepare(socket,family,a,b,c,d,port,scope,data)};
  return io_tup(row,row);
}
function udpwrite_wait(row,k) {
  if(row.state===3 || row.waiter!==null) throw Error("invalid UDP write owner");
  if(row.state===2) { row.state=3; row.prepared=null; return io_tup(row.socket,{$:"None"}); }
  return udp_send_start(row.prepared,result=>{
    row.waiter=null; row.prepared=null; row.state=3;
    return io_tup(row.socket,{$:"Some",value:result});
  },more=>{
    const wait={fd:row.socket,out:true,k,more:()=>{
      if(row.state===2) {
        row.waiter=null; row.prepared=null; row.state=3;
        return io_tup(row.socket,{$:"None"});
      }
      return more();
    }}; row.waiter=wait;
    globalThis.BEND_IO.waits.push(wait);
  });
}
function udpwrite_cancel(row) {
  if(row.state!==0) return false;
  if(row.waiter!==null) {
    const io=globalThis.BEND_IO,index=io.waits.indexOf(row.waiter);
    if(index<0) { row.state=2; return true; }
    const wait=row.waiter; io.waits.splice(index,1);
    row.waiter=null; row.prepared=null; row.state=3;
    io_push(wait.k,io_tup(row.socket,{$:"None"}),false);
  } else row.state=2;
  return true;
}
function udpwrite_release(row) {
  if(row.state===3 || row.waiter!==null) throw Error("invalid UDP write release");
  row.state=3; row.prepared=null; return row.socket;
}
