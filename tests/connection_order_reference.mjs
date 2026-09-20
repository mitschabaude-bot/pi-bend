// Exercise the local Node connection planner. The BlockList denies every IP;
// observing its checks captures attempted order before any connect syscall.
import net from 'node:net';
import crypto from 'node:crypto';
let input='';for await(const chunk of process.stdin)input+=chunk;
const cases=JSON.parse(input),results=[];
for(const addresses of cases){
  if(!addresses.length){results.push([]);continue;}
  const deny=new net.BlockList();deny.addSubnet('0.0.0.0',0,'ipv4');deny.addSubnet('::',0,'ipv6');
  const check=deny.check.bind(deny),seen=[];
  for(const {address,family} of addresses)if(!check(address,`ipv${family}`))throw Error('fixture address not blocked');
  deny.check=(address,family)=>{if(!check(address,family))throw Error('unexpected unblocked address');seen.push({address,family:Number(family.slice(3))});return true;};
  await new Promise((resolve,reject)=>{
    const socket=net.createConnection({host:'fixture.invalid',port:9,autoSelectFamily:true,blockList:deny,lookup:(host,options,callback)=>queueMicrotask(()=>callback(null,addresses))});
    let failed=false;
    socket.on('connect',()=>{socket.destroy();reject(Error('blocked fixture connected'));});
    socket.on('error',error=>{failed=true;if(error.code!=='ERR_IP_BLOCKED')reject(error);});
    socket.on('close',()=>failed?resolve():reject(Error('missing blocked error')));
  });
  results.push(seen);
}
console.log(JSON.stringify({version:process.version,net_sha256:crypto.createHash('sha256').update(process.binding('natives').net).digest('hex'),auto:net.getDefaultAutoSelectFamily(),attemptTimeout:net.getDefaultAutoSelectFamilyAttemptTimeout(),results}));
