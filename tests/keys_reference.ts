import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import assert from 'node:assert/strict';
const root=process.argv[2];
const transpiler=new Bun.Transpiler({loader:'ts'});
const source=readFileSync(join(root,'packages/tui/src/keys.ts'),'utf8');
const code=transpiler.transformSync(source).replace(/\bexport /g,'');
const exports=['matchesKey','parseKey','decodeKittyPrintable','decodePrintableKey','isKeyRelease','isKeyRepeat','setKittyProtocolActive','isKittyProtocolActive','Key'];
const keys=new Function(code+'\nreturn {'+exports.join(',')+',LEGACY_KEY_SEQUENCES,LEGACY_SHIFT_SEQUENCES,LEGACY_CTRL_SEQUENCES,LEGACY_SEQUENCE_KEY_IDS};')();
function windows(){return Boolean(process.env.WT_SESSION)&&!process.env.SSH_CONNECTION&&!process.env.SSH_CLIENT&&!process.env.SSH_TTY;}
function configure(input:any){keys.setKittyProtocolActive(input.kitty??false);for(const name of ['WT_SESSION','SSH_CONNECTION','SSH_CLIENT','SSH_TTY'])delete process.env[name];if(input.windows)process.env.WT_SESSION='native-key-fixture';}
if(process.argv[3]==='--tables'){console.log(JSON.stringify({plain:keys.LEGACY_KEY_SEQUENCES,shift:keys.LEGACY_SHIFT_SEQUENCES,ctrl:keys.LEGACY_CTRL_SEQUENCES,parse:keys.LEGACY_SEQUENCE_KEY_IDS}));}
else if(process.argv[3]==='--original'){
 const cases:any[]=[];const names:string[]=[];let current='';
 const bindings:any={assert,describe:(name:string,fn:()=>void)=>{names.push(name);fn();names.pop();},it:(name:string,fn:()=>void)=>{current=[...names,name].join(' / ');fn();}};
 for(const name of exports)bindings[name]=typeof keys[name]==='function' && !name.includes('KittyProtocolActive') ? (...args:any[])=>{const actual=keys[name](...args);cases.push({name:current,input:{method:name,data:args[0],...(name==='matchesKey'?{key:args[1]}:{}),kitty:keys.isKittyProtocolActive(),windows:windows()},expected:actual??null});return actual;}:keys[name];
 const tests=readFileSync(join(root,'packages/tui/test/keys.test.ts'),'utf8').replace(/^import[\s\S]*?from\s+["'][^"']+["'];\s*/gm,'');
 new Function(...Object.keys(bindings),transpiler.transformSync(tests))(...Object.values(bindings));
 console.log(JSON.stringify(cases));
}else{
 for(const argument of process.argv.slice(3)){
  const result=JSON.parse(argument).map((input:any)=>{configure(input);return (input.method==='matchesKey'?keys.matchesKey(input.data,input.key):keys[input.method](input.data))??null;});
  console.log(JSON.stringify(result));
 }
}
