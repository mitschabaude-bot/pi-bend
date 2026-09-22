// Executes the pinned implementation; JSON is only this fixture's transport.
import { readFileSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve, isAbsolute, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
const root = process.argv[2];
const source = readFileSync(join(root,'packages/coding-agent/src/core/settings-manager.ts'),'utf8').replace(/^import .*;\n/gm,'');
const dispatcher = readFileSync(join(root,'packages/coding-agent/src/core/http-dispatcher.ts'),'utf8');
const timeout = dispatcher.slice(dispatcher.indexOf('export function parseHttpIdleTimeoutMs'), dispatcher.indexOf('\n}',dispatcher.indexOf('export function parseHttpIdleTimeoutMs'))+2);
const transpiler = new Bun.Transpiler({loader:'ts'});
const code = transpiler.transformSync(source+'\n'+timeout).replace(/\bexport /g,'');
const pathSource=readFileSync(join(root,'packages/coding-agent/src/utils/paths.ts'),'utf8').replace(/^import .*;\n/gm,'');
const pathCode=transpiler.transformSync(pathSource).replace(/\bexport /g,'');
const {normalizePath}=new Function('bindings',`const {homedir,fileURLToPath,isAbsolute,join,nodeResolvePath,relative,sep}=bindings;\n${pathCode}\nreturn {normalizePath};`)({homedir:()=>'/home/test',fileURLToPath,isAbsolute,join,nodeResolvePath:resolve,relative,sep});

const {SettingsManager,InMemorySettingsStorage} = new Function('bindings',`const {readFileSync, existsSync, mkdirSync, writeFileSync, dirname, join, randomUUID, resolvePath, normalizePath, stripBom, CONFIG_DIR_NAME, getAgentDir, DEFAULT_HTTP_IDLE_TIMEOUT_MS, DEFAULT_MAX_AGENT_RETRY_DELAY_MS} = bindings;\n${code}\nreturn {SettingsManager,InMemorySettingsStorage};`)({readFileSync,existsSync,mkdirSync,writeFileSync,dirname,join,randomUUID,resolvePath:resolve,normalizePath,stripBom:(s:string)=>s.replace(/^\uFEFF/,''),CONFIG_DIR_NAME:'.pi',getAgentDir:()=>'/unused',DEFAULT_HTTP_IDLE_TIMEOUT_MS:300000,DEFAULT_MAX_AGENT_RETRY_DELAY_MS:60000});
const missing={undefined:true};
const setterNames={extensions:'setExtensionPaths',skills:'setSkillPaths',prompts:'setPromptTemplatePaths',themes:'setThemePaths'};
function encode(v:unknown) {return v===undefined?missing:v;}
function raw(v:unknown) {return v===null||v===undefined?undefined:typeof v==='string'?v:JSON.stringify(v);}
async function run(input:any) {
 const storage=new InMemorySettingsStorage();
 for(const scope of ['global','project']) storage.withLock(scope,()=>raw(input[scope]));
 const manager=SettingsManager.fromStorage(storage,{projectTrusted:input.trusted??true});
 const results=[];
 for(const op of input.operations??[]) {
  if(op.op==='set') {
   let method=setterNames[op.key]??'set'+op.key[0].toUpperCase()+op.key.slice(1);
   if(op.project) method=method.replace('set','setProject');
   try {manager[method](op.value);} catch {results.push({error:true});}
  } else if(op.op==='model') manager.setDefaultModelAndProvider(op.provider,op.model);
  else if(op.op==='analytics') manager.setEnableAnalytics(op.value);
  else if(op.op==='nested') manager[op.method](op.value);
  else if(op.op==='external') storage.withLock(op.scope,()=>raw(op.value));
  else if(op.op==='override') {try {manager.applyOverrides(op.value);} catch {results.push({error:true});}}
  else if(op.op==='flush') await manager.flush();
  else if(op.op==='reload') await manager.reload();
  else if(op.op==='trust') manager.setProjectTrusted(op.value);
  else if(op.op==='errors') results.push(manager.drainErrors().map((x:any)=>({scope:x.scope,path:x.path??null})));
  else if(['getExternalEditorCommand','getShowHardwareCursor','getClearOnShrink'].includes(op.op)) {
   const e=op.value??{};
   if(e.visual===undefined)delete process.env.VISUAL;else process.env.VISUAL=e.visual;
   if(e.editor===undefined)delete process.env.EDITOR;else process.env.EDITOR=e.editor;
   process.env.PI_CLEAR_ON_SHRINK=e.clear?'1':'0';process.env.PI_HARDWARE_CURSOR=e.cursor?'1':'0';
   const platform=Object.getOwnPropertyDescriptor(process,'platform')!;
   Object.defineProperty(process,'platform',{value:e.windows?'win32':'linux'});
   results.push(manager[op.op]());Object.defineProperty(process,'platform',platform);
  } else results.push(encode(manager[op.op](op.value??undefined)));
 }
 const stored:any={};
 for(const scope of ['global','project']) storage.withLock(scope,(value:any)=>{stored[scope]=value??null;return undefined;});
 return {stored,global:manager.getGlobalSettings(),project:manager.getProjectSettings(),results};
}
for(const input of process.argv.slice(3)) console.log(JSON.stringify(await run(JSON.parse(input))));
