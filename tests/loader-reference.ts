import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const repo=process.argv[2] ?? '/home/agent/code/pi-mono';
const pinned='f07218c4d';
const hashes={
 'components/text.ts':'3042e09dd8dcb870c23506e6fafb2dfcc095e7e375adad2fb62e447da17e5e3b',
 'components/loader.ts':'614b39cd2f493e289a12ee4f42404f779cc3a5784735066760c1d9f13bf5d287',
 'components/cancellable-loader.ts':'5f0ae0a56f299e5f6c9585c79bbe16c38a845f038a7254f8dffe7a44f6082e16',
};
function source(path:keyof typeof hashes){const code=execFileSync('git',['-C',repo,'show',`${pinned}:packages/tui/src/${path}`],{encoding:'utf8'});assert.equal(createHash('sha256').update(code).digest('hex'),hashes[path]);return code;}
const ts=new Bun.Transpiler({loader:'ts'});
function compile(path:keyof typeof hashes){return ts.transformSync(source(path).replace(/^import.*\n/gm,'')).replace(/\bexport /g,'');}
const Text=new Function(compile('components/text.ts')+';return Text;')();
const Loader=new Function('Text',compile('components/loader.ts')+';return Loader;')(Text);
const cancelSource=source('components/cancellable-loader.ts');
assert.match(cancelSource,/this\.abortController\.abort\(\)/);
assert.match(cancelSource,/kb\.matches\(data, "tui\.select\.cancel"\)/);
const ui={requestRender(){}};
const loader=new Loader(ui,(s:string)=>'s'+s,(s:string)=>'m'+s);
function output(){console.log((loader as any).text);}
loader.stop();output();
(loader as any).currentFrame=1;(loader as any).updateDisplay();output();
loader.setMessage('Work');output();
loader.setIndicator({frames:['*','-'],intervalMs:7});loader.stop();output();
(loader as any).currentFrame=1;(loader as any).updateDisplay();output();
loader.setIndicator({frames:[]});output();
loader.setIndicator();loader.stop();output();
loader.invalidate();output();
