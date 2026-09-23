// Pinned proper-lockfile is an independent interprocess oracle, never production.
const fs=require('node:fs');
const lockfile=require(process.argv[2]);
const [mode,path,duration='0']=process.argv.slice(3);
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
(async()=>{
 try {
  const release=await lockfile.lock(path,{realpath:false,stale:2000,update:1000,retries:mode==='increment'?{retries:1000,factor:1,minTimeout:5,maxTimeout:5}:0});
  if(mode==='increment') {
   let value=0;try{value=Number(fs.readFileSync(path,'utf8'))}catch(e){if(e.code!=='ENOENT')throw e}
   await sleep(2);fs.writeFileSync(path,String(value+1));await release();console.log('increment:ok');
  } else {console.log('acquired');await sleep(Number(duration));await release();console.log('released')}
 } catch(e) {console.log(e.code==='ELOCKED'?'locked':'error:'+e.code);if(e.code!=='ELOCKED')process.exitCode=1}
})();
