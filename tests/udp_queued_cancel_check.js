// Deterministically exercise the Bun runtime's ready-but-not-yet-run boundary.
// OS calls are stubbed; real socket integration is covered by the Python runners.
import {readFileSync, writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const runs=[];
const hashes={};
for(const kind of ['read','write']) {
  const path=`patches/experimental/udp-bytes/udp_${kind==='read'?'recv':'send'}_bytes.js`;
  const source=readFileSync(path,'utf8');
  hashes[path]=createHash('sha256').update(source).digest('hex');
  for(const queued of [false,true]) {
    let calls=0;
    const sys={mac:false,ptr:x=>x,errno:()=>11,
      recvfrom:()=>{calls++;return -1},sendto:()=>{calls++;return -1}};
    const emitted=[];
    globalThis.BEND_IO={waits:[]};
    const api=new Function('io_sys','io_tup','io_push','io_fail',source+`
      return {new:udp${kind}_new,wait:udp${kind}_wait,cancel:udp${kind}_cancel};`)(
        ()=>sys,(...xs)=>xs,(k,x)=>emitted.push([k,x]),code=>({code}));
    const [owner,handle]=kind==='read'?api.new(42,16):api.new(42,4,2130706433,0,0,0,53,0,{$:'Nil'});
    const k=x=>x;
    assert.equal(api.wait(owner,k),undefined);
    assert.equal(calls,1);
    const wake=globalThis.BEND_IO.waits[0];
    if(queued) globalThis.BEND_IO.waits.shift();
    assert.equal(api.cancel(handle),true);
    assert.equal(api.cancel(handle),false);
    if(queued) {
      assert.equal(emitted.length,0);
      assert.deepEqual(wake.more(),[42,{$:'None'}]);
    } else {
      assert.deepEqual(emitted,[[k,[42,{$:'None'}]]]);
    }
    assert.equal(calls,1,'cancellation must prevent another syscall');
    assert.equal(globalThis.BEND_IO.waits.length,0);
    assert.equal(handle.waiter,null);
    assert.equal(handle.state,3);
    assert.equal(api.cancel(handle),false);
    if(kind==='write') assert.equal(handle.prepared,null);
    runs.push({kind,queued,syscalls:calls});
  }
}
hashes['tests/udp_queued_cancel_check.js']=createHash('sha256').update(readFileSync('tests/udp_queued_cancel_check.js')).digest('hex');
writeFileSync('build/udp-queued-cancel-result.json',JSON.stringify({scope:'Deterministic JS effect scheduling boundary with stubbed OS calls',runs,sha256:hashes},null,2)+'\n');
console.log('4 parked/queued read/write cancellation boundaries PASS');
