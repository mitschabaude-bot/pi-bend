import {mock,expect} from 'bun:test';
import {readFileSync} from 'node:fs';
const root=process.argv[2];
const actual={...await import(root+'/src/core/session-manager.ts')};
const cases:any[]=[];const tests:string[]=[];const skipped:string[]=[];let name='';
const mutations=['appendMessage','appendThinkingLevelChange','appendModelChange','appendCompaction','appendCustomEntry','appendCustomMessageEntry','appendSessionInfo','appendLabelChange','branch','resetLeaf','branchWithSummary','createBranchedSession'];
const clone=(value:any)=>JSON.parse(JSON.stringify(value));
function snapshot(s:any){return clone({entries:s.getEntries(),leaf:s.getLeafId(),branch:s.getBranch(),tree:s.getTree(),context:s.buildSessionContext(),name:s.getSessionName()??null,children:s.getEntries().map((e:any)=>[e.id,s.getChildren(e.id).map((c:any)=>c.id)]),paths:s.getEntries().map((e:any)=>[e.id,s.getBranch(e.id).map((c:any)=>c.id)])});}
function watch(s:any){let depth=0;const steps:any[]=[];const testcase={name,header:clone(s.getHeader()),steps};cases.push(testcase);
 for(const key of mutations){const fn=s[key].bind(s);s[key]=(...args:any[])=>{if(depth)return fn(...args);depth++;let result,error;try{result=fn(...args)}catch(e){error=e}finally{depth--}
 const after=snapshot(s);const entry=key.startsWith('append')||key==='branchWithSummary'?s.getLeafEntry():undefined;
 steps.push(clone({key,args,entry:error?undefined:entry,header:key==='createBranchedSession'?s.getHeader():undefined,error:error?String(error):undefined,after}));if(error)throw error;return result;};}
 return s;
}
class SessionManager extends actual.SessionManager{static inMemory(...args:any[]){return watch(actual.SessionManager.inMemory(...args))}}
mock.module(root+'/src/core/session-manager.ts',()=>({...actual,SessionManager}));
// An installed vitest resolves to its own path, which a bare-name mock misses.
const vitestFactory=()=>({expect,describe:(_name:string,fn:()=>void)=>fn(),it:(title:string,fn:()=>void)=>{if(['does not duplicate entries when forking from first user message','preserves tool and summary usage across a file-backed reload','writes file immediately when forking from a point with assistant messages'].includes(title)){skipped.push(title);return}name=title;fn();tests.push(title)}});
mock.module('vitest',vitestFactory);
try{mock.module(Bun.resolveSync('vitest',root+'/test'),vitestFactory)}catch{};
// Evaluate only the two actual pure fixture constructors, avoiding unrelated
// provider catalogs/auth helpers imported by the utilities module.
const utilities=readFileSync(root+'/test/utilities.ts','utf8');
const constructors=utilities.slice(utilities.indexOf('export function userMsg'),utilities.indexOf('\n}',utilities.indexOf('export function assistantMsg'))+2).replaceAll('export function','function');
mock.module(root+'/test/utilities.ts',()=>new Function(new Bun.Transpiler({loader:'ts'}).transformSync(constructors)+'; return {userMsg,assistantMsg};')());
await import(root+'/test/session-manager/tree-traversal.test.ts');
await import(root+'/test/session-manager/labels.test.ts');
name='additional label ordering, root summaries, name sanitization and system compaction';
const s=SessionManager.inMemory('/work');const a=s.appendMessage({role:'system',content:'system',timestamp:1});const b=s.appendMessage({role:'user',content:'hello',timestamp:1});
s.appendLabelChange(a,'first');s.appendLabelChange(b,'second');s.appendLabelChange(a,undefined);s.appendLabelChange(a,'last');s.appendSessionInfo(' \n  title\r\nsecond\n ');s.appendSessionInfo(' \t ');
s.appendCompaction('summary',b,12,{x:1},true);s.branchWithSummary(null,'root summary');s.resetLeaf();s.appendMessage({role:'user',content:'new root',timestamp:2});s.branch(b);s.appendCustomMessageEntry('notice','hello',false,{n:2});s.createBranchedSession(b);
name='fork repairs compaction references to removed labels';
const f=SessionManager.inMemory('/work');const first=f.appendMessage({role:'user',content:'first',timestamp:1});const removed=f.appendLabelChange(first,'bookmark');f.appendMessage({role:'user',content:'retained',timestamp:2});const compact=f.appendCompaction('summary',removed,42);f.createBranchedSession(compact);f.appendLabelChange(first,'');
name='children sort chronologically and equal timestamps remain stable';
const RealDate=Date;let clock=Date.UTC(2025,0,1);
globalThis.Date=class extends RealDate{constructor(...args:any[]){super(...(args.length?args:[clock]) as [any])}static now(){return clock}} as DateConstructor;
const sorted=SessionManager.inMemory('/work');const rootId=sorted.appendMessage({role:'user',content:'root',timestamp:1});
for(const [offset,content] of [[3000,'third'],[1000,'first'],[1000,'second']] as const){sorted.branch(rootId);clock=Date.UTC(2025,0,1)+offset;sorted.appendMessage({role:'user',content,timestamp:1})}
globalThis.Date=RealDate;
console.log(JSON.stringify({cases,tests,skipped}));
