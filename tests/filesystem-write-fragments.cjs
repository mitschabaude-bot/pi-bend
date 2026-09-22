// Test-only equivalent of the POSIX write shim for the hosted backend.
const fs=require('node:fs'),write=fs.writeSync;
let calls=0;
fs.writeSync=function(fd,bytes,offset,count,position){
 let target=false;
 try {target=fd>2 && fs.readlinkSync(`/proc/self/fd/${fd}`)===process.env.BEND_TEST_WRITE_PATH;} catch {}
 if(target){
  if(process.env.BEND_TEST_WRITE_ZERO) return 0;
  if(calls++===0) throw Object.assign(new Error('interrupted test write'),{code:'EINTR',errno:-4});
  count=Math.min(count,7);
 }
 return write(fd,bytes,offset,count,position);
};
