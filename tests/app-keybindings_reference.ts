import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import assert from 'node:assert/strict';
const root=process.argv[2], transpiler=new Bun.Transpiler({loader:'ts'});
const read=(p:string)=>fs.readFileSync(path.join(root,p),'utf8');
const compile=(s:string)=>transpiler.transformSync(s.replace(/^import[\s\S]*?from\s+["'][^"']+["'];\s*/gm,'')).replace(/\bexport /g,'');
const keyboard=new Function(compile(read('packages/tui/src/keys.ts'))+';return {matchesKey};')();
const tui=new Function('matchesKey',compile(read('packages/tui/src/keybindings.ts'))+';return {KeybindingsManager,TUI_KEYBINDINGS};')(keyboard.matchesKey);
function source(environment:any={platform:'linux'}){
 const runtime={platform:environment.platform??'linux',env:{WSL_DISTRO_NAME:environment.wslDistroName,WSL_INTEROP:environment.wslInterop}};
 return new Function('process','TUI_KEYBINDINGS','TuiKeybindingsManager','existsSync','readFileSync','join','getAgentDir','stripBom',compile(read('packages/coding-agent/src/core/keybindings.ts'))+';return {KEYBINDINGS,KeybindingsManager,useWindowsKeybindings,migrateKeybindingsConfig,KEYBINDING_NAME_MIGRATIONS};')(runtime,tui.TUI_KEYBINDINGS,tui.KeybindingsManager,fs.existsSync,fs.readFileSync,path.join,()=>{throw Error('unexpected default agent dir');},(s:string)=>s.replace(/^\ufeff/,''));
}
function key(value:string){const parts=value.toLowerCase().split('+');let base=parts.pop()!;return ['shift','ctrl','alt','super'].filter(x=>parts.includes(x)).map(x=>x+'+').join('')+({pageup:'pageUp',pagedown:'pageDown',esc:'escape',return:'enter'}[base]??base);}
const keys=(v:any)=>(Array.isArray(v)?v:[v]).map(key);
const config=(v:any)=>Object.fromEntries(Object.entries(v).map(([k,v])=>[k,keys(v)]));
const defs=(v:any)=>Object.fromEntries(Object.entries(v).map(([k,v]:any)=>[k,{defaultKeys:keys(v.defaultKeys),description:v.description??null}]));
function query(input:any){const s=source(input.environment);if(input.method==='windows')return s.useWindowsKeybindings();if(input.method==='definitions')return defs(s.KEYBINDINGS);if(input.method==='migration')return s.migrateKeybindingsConfig(input.config);if(input.method==='memory'){const m=new s.KeybindingsManager(input.config??{});return {user:config(m.getUserBindings()),effective:config(m.getEffectiveConfig())};}throw Error(input.method);}
if(process.argv[3]==='--mappings')console.log(JSON.stringify(source().KEYBINDING_NAME_MIGRATIONS));
else if(process.argv[3]==='--original'){
 const cases:any[]=[];let current='';const stack:string[]=[];const after:any[]=[];
 const env={platform:process.platform,wslDistroName:process.env.WSL_DISTRO_NAME,wslInterop:process.env.WSL_INTEROP};const s=source(env);
 const record=(input:any,expected:any)=>{cases.push({name:current,input,expected});return expected;};
 const bindings:any={describe:(name:string,f:()=>void)=>{stack.push(name);f();stack.pop();},it:(name:string,f:()=>void)=>{current=[...stack,name].join(' / ');try{f();}finally{for(const fn of after)fn();}},afterEach:(fn:any)=>after.push(fn),expect:(actual:any)=>({toBe:(expected:any)=>assert.strictEqual(actual,expected),toEqual:(expected:any)=>assert.deepStrictEqual(actual,expected)}),process};
 bindings.useWindowsKeybindings=(platform=process.platform,environment=process.env)=>record({method:'windows',environment:{platform,wslDistroName:environment.WSL_DISTRO_NAME,wslInterop:environment.WSL_INTEROP}},s.useWindowsKeybindings(platform,environment));
 bindings.KEYBINDINGS=new Proxy(s.KEYBINDINGS,{get(target,name:string){record({method:'definitions',environment:env},defs(target));return target[name];}});
 new Function(...Object.keys(bindings),compile(read('packages/coding-agent/test/keybindings.test.ts')))(...Object.values(bindings));
 const migrationSource=read('packages/coding-agent/src/migrations.ts');const start=migrationSource.indexOf('function migrateKeybindingsConfigFile()');const end=migrationSource.indexOf('\n/**',start);
 const migrateFile=new Function('existsSync','readFileSync','writeFileSync','join','getAgentDir','stripBom','migrateKeybindingsConfig',compile(migrationSource.slice(start,end))+';return migrateKeybindingsConfigFile;')(fs.existsSync,fs.readFileSync,fs.writeFileSync,path.join,()=>process.env.PI_TEST_AGENT_DIR,(v:string)=>v.replace(/^\ufeff/,''),(raw:any)=>record({method:'migration',config:raw,environment:env},s.migrateKeybindingsConfig(raw)));
 Object.assign(bindings,{fs,os,path,ENV_AGENT_DIR:'PI_TEST_AGENT_DIR',runMigrations:()=>migrateFile(),KeybindingsManager:{create:(dir:string)=>{const raw=fs.readFileSync(path.join(dir,'keybindings.json'),'utf8');const m=s.KeybindingsManager.create(dir);record({method:'file',content:raw,environment:env},{user:config(m.getUserBindings()),effective:config(m.getEffectiveConfig())});return m;}}});
 new Function(...Object.keys(bindings),compile(read('packages/coding-agent/test/keybindings-migration.test.ts')))(...Object.values(bindings));
 console.log(JSON.stringify(cases));
}else for(const arg of process.argv.slice(3))console.log(JSON.stringify(JSON.parse(arg).map(query)));
