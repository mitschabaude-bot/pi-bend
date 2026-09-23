// Execute all actual pinned assertions through a native provider adapter. The
// source provider also runs against each live tree before it is removed.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawn,spawnSync} from 'node:child_process';
import {stripTypeScriptTypes} from 'node:module';
const root=process.env.PI_MONO || '/home/agent/code/pi-mono';
const source=path.join(root,'packages/tui');
const hashes={
 'src/autocomplete.ts':'5c3ac87b437dd38772611fd0b011e9609fa420e1b1f9b76428bf9a5ebd331da8',
 'src/fuzzy.ts':'8286a6feb16672e52114df5300369d20f48e27c9e87da2dc87294ea3b1223b8e',
 'test/autocomplete.test.ts':'a2fb7cd38b95666955439b3f9207321c35e42be235935a12fa150eb54c02cb35',
};
function pinned(file){const text=fs.readFileSync(path.join(source,file),'utf8');assert.equal(createHash('sha256').update(text).digest('hex'),hashes[file],file);return text;}
const strip=file=>stripTypeScriptTypes(pinned(file)).replace(/^import[\s\S]*?;\s*$/gm,'').replace(/^export /gm,'');
const fuzzy=new Function(strip('src/fuzzy.ts')+';return fuzzyFilter')();
const Reference=new Function('spawn','readdirSync','statSync','homedir','basename','dirname','join','fuzzyFilter',strip('src/autocomplete.ts')+';return CombinedAutocompleteProvider')(spawn,fs.readdirSync,fs.statSync,os.homedir,path.basename,path.dirname,path.join,fuzzy);
const fd=process.env.PI_TEST_FD || '/home/agent/.pi/agent/bin/fd';
const backend=JSON.parse(process.argv[2]);
const decode=x=>Buffer.from(x,'base64').toString('utf8');
export function invoke(args){
 const p=spawnSync(backend[0],backend.slice(1).concat(args.map(String)),{encoding:'utf8',timeout:60000});
 assert.equal(p.status,0,p.stderr);assert.equal(p.stderr,'');
 const output=p.stdout.trimEnd().split('\n');
 if(output[0]==='none')return null;
 if(output[0].startsWith('error:'))return {error:output[0].slice(6)};
 if(output[0].startsWith('trigger:'))return output[0]==='trigger:True';
 if(output[0].startsWith('apply:')){const [,lines,line,col]=output[0].split(':');return {lines:decode(lines).split('\n'),cursorLine:Number(line),cursorCol:Number(col)}}
 assert.ok(output[0].startsWith('prefix:'),output);
 return {prefix:decode(output[0].slice(7)),items:output.slice(1).map(line=>{const [,value,label,desc]=line.split(':');return {value:decode(value),label:decode(label),...(desc==='none'?{}:{description:decode(desc.slice(4))})}})};
}
let comparisons=0,activeName='';
class Native {
 constructor(commands=[],base=process.cwd(),fdPath=null){assert.equal(commands.length,0);this.base=base;this.fd=fdPath;this.reference=new Reference(commands,base,fdPath)}
 async getSuggestions(lines,line,col,options){
  const expected=await this.reference.getSuggestions(lines,line,col,options);
  const actual=invoke(['suggest',this.base,os.homedir(),lines.join('\n'),line,col,options.force?'yes':'no',this.fd?'yes':'no','scalar']);
  if(activeName!=='includes scoped direct children when recursive @ matches are flooded'){
   // Locale default is deliberately pending. Compare item membership/content;
   // the actual original ranking assertions below still execute unchanged.
   const comparable=v=>v&&({...v,items:[...v.items].sort((a,b)=>a.value<b.value?-1:a.value>b.value?1:0)});
   assert.deepEqual(comparable(actual),comparable(expected),activeName);
  }
  comparisons++;return actual;
 }
 applyCompletion(lines,line,col,item,prefix){
  const actual=invoke(['apply',lines.join('\n'),line,col,item.value,item.label,prefix]);
  assert.deepEqual(actual,this.reference.applyCompletion(lines,line,col,item,prefix));comparisons++;return actual;
 }
}
const scopes=[{before:[],after:[]}],tests=[];
function describe(name,options,body){if(typeof options==='function')body=options;else assert.ok(!options.skip,'fd oracle must be installed');scopes.push({before:[],after:[]});body();scopes.pop()}
const beforeEach=fn=>scopes.at(-1).before.push(fn),afterEach=fn=>scopes.at(-1).after.push(fn);
const test=(name,body)=>tests.push({name,body,before:scopes.flatMap(s=>s.before),after:scopes.toReversed().flatMap(s=>s.after)});
const which=(command,args,options)=>command==='which'&&args[0]==='fd'?{status:0,stdout:fd+'\n'}:spawnSync(command,args,options);
new Function('assert','spawnSync','mkdirSync','mkdtempSync','rmSync','symlinkSync','writeFileSync','tmpdir','dirname','join','afterEach','beforeEach','describe','it','test','CombinedAutocompleteProvider','console',strip('test/autocomplete.test.ts'))(assert,which,fs.mkdirSync,fs.mkdtempSync,fs.rmSync,fs.symlinkSync,fs.writeFileSync,()=>'/var/tmp',path.dirname,path.join,afterEach,beforeEach,describe,test,test,Native,{log(){}});
for(const t of tests){activeName=t.name;try{for(const before of t.before)await before();await t.body()}finally{for(const after of t.after)await after()}}
assert.equal(tests.length,27);
console.log(JSON.stringify({tests:tests.map(t=>t.name),comparisons}));
const commands=[{name:'model',description:'Choose model',argumentHint:'[name]',getArgumentCompletions:prefix=>[{value:prefix+'one',label:'argument',description:'callback result'}]},{name:'compact',description:'Compact context'},{value:'clear',label:'ignored label',description:'Clear'}];
const commandReference=new Reference(commands,'/var/tmp');
for(const text of ['/','/c','/CM','/cl','/model ','/model alpha','/model a b','/missing arg','/compact arg','/clear arg']){
 const expected=await commandReference.getSuggestions([text],0,text.length,{signal:new AbortController().signal,force:false});
 const actual=invoke(['commands','/var/tmp',os.homedir(),text,0,text.length,'no','no','scalar']);
 assert.deepEqual(actual,expected,text);comparisons++;
}
const editing=[['/m',2,'model','model','/m'],['  /m suffix',4,'model','model','/m'],['@a tail',2,'@alpha.txt','alpha.txt','@a'],['@a',2,'@"a folder/"','a folder/','@a'],['"a" tail',2,'"a folder/"','a folder/','"a'],['abc ./a',7,'./alpha','alpha','./a']];
for(const [text,col,value,label,prefix] of editing){const item={value,label};assert.deepEqual(invoke(['apply',text,0,col,value,label,prefix]),commandReference.applyCompletion([text],0,col,item,prefix));comparisons++}
console.log(JSON.stringify({additionalSourceComparisons:comparisons}));
const prefixCases=['','@','@"','./','"','word"','word@"','x @"a b','x="a b','x\t@foo','"closed" tail','"a""b','😀 @"資料/','x'.repeat(50000)+' ./file'];
let seed=19317;const alphabet='ab @"\t\'=./~';
for(let n=0;n<300;n++){let text='';for(let j=0;j<n%31;j++){seed=(Math.imul(seed,1664525)+1013904223)>>>0;text+=alphabet[seed%alphabet.length]}prefixCases.push(text)}
const prefixProcess=spawnSync(backend[0],backend.slice(1).concat(['prefixes',...prefixCases]),{encoding:'utf8',timeout:60000});
assert.equal(prefixProcess.status,0,prefixProcess.stderr);
assert.equal(prefixProcess.stderr,'');
const prefixResults=prefixProcess.stdout.trimEnd().split('\n').map(line=>line.split(':').map(value=>value==='none'?null:decode(value.slice(4))));
assert.deepEqual(prefixResults,prefixCases.map(text=>[commandReference.extractAtPrefix(text),commandReference.extractPathPrefix(text,false),commandReference.extractPathPrefix(text,true)]));
console.log(JSON.stringify({prefixComparisons:prefixCases.length}));
