import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {join} from 'node:path';
import assert from 'node:assert/strict';
const repo=process.argv[2] ?? '/home/agent/code/pi-mono';
const pinned='f07218c4d';
const hashes={
 'utils.ts':'8cda2d53e2361ac5aaf6d7345b2fee058c8df5743eae4e4e90c89a7072c026c3',
 'components/alt-screen-flash.ts':'6d341546b59958e93e4d33fdc1766b10d13c98a779031e2c01b827f0a4c6e30c',
};
function source(path:keyof typeof hashes){const code=execFileSync('git',['-C',repo,'show',`${pinned}:packages/tui/src/${path}`],{encoding:'utf8'});assert.equal(createHash('sha256').update(code).digest('hex'),hashes[path]);return code;}
const ts=new Bun.Transpiler({loader:'ts'});
function compile(path:keyof typeof hashes){return ts.transformSync(source(path).replace(/^import.*\n/gm,'')).replace(/\bexport /g,'');}
const {eastAsianWidth}=await import(join(repo,'node_modules/get-east-asian-width/index.js'));
const {truncateToWidth}=new Function('eastAsianWidth',compile('utils.ts')+';return {truncateToWidth};')(eastAsianWidth);
let nextTimer=0;
const timers=new Map<number,()=>void>();
function setTimeoutFake(callback:()=>void,_delay:number){const id=++nextTimer;timers.set(id,callback);return {id,unref(){}};}
function clearTimeoutFake(timer:{id:number}){timers.delete(timer.id);}
const Flash=new Function('truncateToWidth','setTimeout','clearTimeout',compile('components/alt-screen-flash.ts')+';return AltScreenFlashContainer;')(truncateToWidth,setTimeoutFake,clearTimeoutFake);
let redraws=0;
const flash=new Flash(()=>redraws++);
function snapshot(width:number){const lines=flash.render(width);console.log(`${lines.length}:${lines.join('|')}`);}
flash.flash('hi',300);
for(const width of [0,1,4,10])snapshot(width);
flash.flash('wide 界',50);snapshot(6);
const second=timers.get(2);assert(second);timers.delete(2);second();snapshot(10);
const first=timers.get(1);assert(first);timers.delete(1);first();snapshot(10);
flash.flash('dispose',1000);snapshot(10);
flash.dispose();assert.equal(timers.size,0);
console.log(redraws);

const tied=new Flash(()=>{});
tied.flash('one',10);tied.flash('two',10);
function tiedSnapshot(){const lines=tied.render(10);console.log(`${lines.length}:${lines.join('|')}`);}
tiedSnapshot();
const firstTie=timers.get(4);assert(firstTie);timers.delete(4);firstTie();tiedSnapshot();
const secondTie=timers.get(5);assert(secondTie);timers.delete(5);secondTie();tiedSnapshot();
tied.dispose();
