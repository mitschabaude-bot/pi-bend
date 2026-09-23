// Drives the actual pinned SessionManager with JSON operations (one per
// line of the file named by argv[3]) and prints one JSON result per line.
// The Bend runner tests/session-file.bend answers the same operations.
import {readFileSync} from 'node:fs';
const root=process.argv[2];const ops=readFileSync(process.argv[3],'utf8').split('\n').filter(l=>l.trim());
const sm=await import(root+'/src/core/session-manager.ts');
const SessionManager=sm.SessionManager;
let session:any;
const usage={input:1,output:1,cacheRead:0,cacheWrite:0,totalTokens:2,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}};
const shape=(s:any)=>({sessionId:s.getSessionId(),cwd:s.getCwd(),sessionFile:s.getSessionFile()??null,sessionDir:s.getSessionDir(),persisted:s.isPersisted(),entries:s.getEntries().length,header:s.getHeader()});
function tree(nodes:any[],depth=0):string[]{const out:string[]=[];for(const n of nodes){out.push([depth,n.entry.id,n.label??'',n.labelTimestamp??''].join(':'));out.push(...tree(n.children,depth+1));}return out;}
function snapshot(s:any){const labels:Record<string,string>={};for(const e of s.getEntries()){const l=s.getLabel(e.id);if(l!==undefined)labels[e.id]=l;}
 return {sessionId:s.getSessionId(),sessionFile:s.getSessionFile()??null,cwd:s.getCwd(),persisted:s.isPersisted(),leafId:s.getLeafId(),entries:s.getEntries(),branch:s.getBranch().map((e:any)=>e.id),tree:tree(s.getTree()),context:s.buildContextEntries().map((e:any)=>e.id),messages:s.buildSessionContext().messages.length,labels,name:s.getSessionName()??null};}
function run(op:any):any{
 switch(op.op){
  case 'load':return {entries:sm.loadEntriesFromFile(op.path)};
  case 'open':session=SessionManager.open(op.path,op.sessionDir,op.cwdOverride);return shape(session);
  case 'create':session=SessionManager.create(op.cwd,op.sessionDir,op.id!==undefined?{id:op.id}:undefined);return shape(session);
  case 'inMemory':session=SessionManager.inMemory(op.cwd,op.id!==undefined?{id:op.id}:(op.parentSession!==undefined?{parentSession:op.parentSession}:undefined),op.entries);return shape(session);
  case 'continueRecent':session=SessionManager.continueRecent(op.cwd,op.sessionDir);return shape(session);
  case 'forkFrom':session=SessionManager.forkFrom(op.sourcePath,op.targetCwd,op.sessionDir,op.id!==undefined?{id:op.id}:undefined);return shape(session);
  case 'newSession':{const file=session.newSession(op.id!==undefined||op.parentSession!==undefined?{id:op.id,parentSession:op.parentSession}:undefined);return {...shape(session),returned:file??null};}
  case 'appendUser':{const timestamp=Date.now();return {id:session.appendMessage({role:'user',content:op.blocks?[{type:'text',text:op.text}]:op.text,timestamp}),timestamp};}
  case 'appendAssistant':{const timestamp=Date.now();return {id:session.appendMessage({role:'assistant',content:[{type:'text',text:op.text}],api:'anthropic-messages',provider:'anthropic',model:'test',usage,stopReason:'stop',timestamp}),timestamp};}
  case 'appendModelChange':return {id:session.appendModelChange(op.provider,op.modelId)};
  case 'appendCustomEntry':return {id:session.appendCustomEntry(op.customType,op.data)};
  case 'appendLabelChange':return {id:session.appendLabelChange(op.targetId,op.label)};
  case 'appendCompaction':return {id:session.appendCompaction(op.summary,op.firstKeptEntryId,op.tokensBefore)};
  case 'appendContextEdit':return {id:session.appendContextEdit(op.targetId,op.replacement)};
  case 'branch':session.branch(op.id);return snapshot(session);
  case 'createBranchedSession':{const file=session.createBranchedSession(op.leafId??session.getLeafId());return {...shape(session),returned:file??null};}
  case 'snapshot':return snapshot(session);
  case 'findMostRecent':return {path:sm.findMostRecentSession(op.dir,op.cwd)};
  case 'findById':return {path:SessionManager.findById(op.cwd,op.id,op.sessionDir)??null};
  case 'list':return SessionManager.list(op.cwd,op.sessionDir).then((infos:any[])=>({sessions:infos.map(i=>({path:i.path,id:i.id,cwd:i.cwd,name:i.name??null,parentSessionPath:i.parentSessionPath??null,created:i.created.getTime(),modified:i.modified.getTime(),messageCount:i.messageCount,firstMessage:i.firstMessage,allMessagesText:i.allMessagesText}))}));
  case 'listAll':return SessionManager.listAll(op.sessionDir).then((infos:any[])=>({paths:infos.map(i=>i.path)}));
  case 'migrate':{const entries=op.entries;sm.migrateSessionEntries(entries);return {entries};}
  case 'sleep':Bun.sleepSync(op.ms);return {};
  default:throw new Error('unknown op '+op.op);
 }
}
for(const line of ops){let result:any;try{result=await run(JSON.parse(line));}catch(e:any){result={error:e.message};}console.log(JSON.stringify(result));}
