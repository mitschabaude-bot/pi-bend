// Execute the pinned source and named assertions; serialize full outputs for Bend.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
const root = process.argv[2];
const read = (file:string) => fs.readFileSync(path.join(root,file),'utf8');
const transpiler = new Bun.Transpiler({loader:'ts'});
const clean = (source:string) => source.replace(/^import .*;\n/gm,'').replace(/\bexport /g,'');
const skillsSource=read('packages/coding-agent/src/core/skills.ts');
const skills = skillsSource.slice(skillsSource.indexOf('export function formatSkillsForPrompt'),skillsSource.indexOf('export interface LoadSkillsOptions'));
const source=clean(read('packages/ai/src/utils/text.ts'))+'\n'+clean(skills)+'\n'+clean(read('packages/coding-agent/src/core/source-info.ts'))+'\n'+clean(read('packages/coding-agent/src/core/system-prompt.ts'));
const api = new Function('getDocsPath','getExamplesPath','getReadmePath',transpiler.transformSync(source)+ '\nreturn {buildSystemPrompt,buildSystemPromptSections,buildSystemPromptState,diffSystemPromptSections,formatSkillsForPrompt,createSyntheticSourceInfo};')(()=>'/pi/docs',()=>'/pi/examples',()=>'/pi/README.md');
const records:any[]=[]; const names:string[]=[]; const suites:string[]=[]; let current='supplemental';
function describe(name:string,body:()=>void){suites.push(name);body();suites.pop();}
function test(name:string,body:()=>void){current=[...suites,name].join(' / ');names.push(current);body();}
(test as any).each=(values:any[]) => (name:string,body:(...args:any[])=>void)=>values.forEach((value,index)=>test(`${name} [${index}]`,()=>body(...(Array.isArray(value)?value:[value]))));
function expect(value:any){return {
 toBe:(wanted:any)=>assert.strictEqual(value,wanted),toEqual:(wanted:any)=>assert.deepEqual(value,wanted),
 toContain:(wanted:any)=>assert.ok(value.includes(wanted)),not:{toContain:(wanted:any)=>assert.ok(!value.includes(wanted))},
 toHaveLength:(wanted:any)=>assert.equal(value.length,wanted),toBeUndefined:()=>assert.equal(value,undefined),
 toThrow:(wanted:string)=>assert.throws(value,(error:any)=>error.message.includes(wanted)),
};}
function capture(op:string,input:any,call:()=>any,encode:(value:any)=>any=(x)=>x){
 try {const result=call();records.push({name:current,input:{op,...input},expected:encode(result)});return result;}
 catch(error:any){records.push({name:current,input:{op,...input},expected:{error:error.message}});throw error;}
}
const sectionEntries=(x:any)=>x===undefined?null:Object.entries(x);
const wrapped:any={
 buildSystemPrompt:(options:any)=>capture('prompt',{options},()=>api.buildSystemPrompt(options)),
 buildSystemPromptSections:(options:any)=>capture('sections',{options},()=>api.buildSystemPromptSections(options),sectionEntries),
 buildSystemPromptState:(options:any)=>capture('state',{options},()=>api.buildSystemPromptState(options),(x:any)=>[x.content,sectionEntries(x.sections)]),
 diffSystemPromptSections:(previous:any,current:any)=>capture('diff',{previous,current},()=>api.diffSystemPromptSections(previous,current),sectionEntries),
 formatSkillsForPrompt:(skills:any[],readTool='read')=>capture('skills',{skills,readTool},()=>api.formatSkillsForPrompt(skills,readTool)),
 createSyntheticSourceInfo:api.createSyntheticSourceInfo,
};
function run(source:string){new Function('describe','test','it','expect',...Object.keys(wrapped),transpiler.transformSync(clean(source)))(describe,test,test,expect,...Object.values(wrapped));}
run(read('packages/coding-agent/test/system-prompt.test.ts'));
const updates=read('packages/coding-agent/test/system-prompt-updates.test.ts');
run(updates.slice(updates.indexOf('\ttest("diffs sections into a patch"'),updates.indexOf('\ttest("a forced prompt is sent')));
const skillTests=read('packages/coding-agent/test/skills.test.ts');
run(skillTests.slice(skillTests.indexOf('function createTestSkill'),skillTests.indexOf('describe("skills"'))+skillTests.slice(skillTests.indexOf('\tdescribe("formatSkillsForPrompt"'),skillTests.indexOf('\tdescribe("loadSkills with options"')));
current='supplemental exact ordering/precedence';
const skill={name:`<&\"'雪`,description:`Use <this> & \"that\" 'now'.`,filePath:'/skills/a&b/SKILL.md',baseDir:'/skills/a&b',sourceInfo:api.createSyntheticSourceInfo('/skills/a&b/SKILL.md',{source:'test'}),disableModelInvocation:false};
const tools=[[],['read'],['bash'],['powershell'],['bash','powershell'],['bash','find'],['powershell','grep'],['bash','read'],['read','bash','read']];
for(const selectedTools of tools) for(const customPrompt of [undefined,'','Custom.','  ']) {
 const options={cwd:'C:\\雪\\project',customPrompt,selectedTools,skills:[skill,{...skill,disableModelInvocation:true}],toolSnippets:{read:'Read it',bash:'Run it',powershell:' ',find:''},toolGuidelines:{read:[' rule ','rule',''],bash:['rule',' next ','Be concise in your responses']},promptGuidelines:['next','\u00a0third\uFEFF',''],appendSystemPrompt:'Addendum',contextFiles:[{path:'/a"',content:'<raw>\ntext'},{path:'/b',content:''}],sections:{rules:'Overridden',cwd:'Override cwd',extra:'Extra',empty:''}};
 wrapped.buildSystemPrompt(options);wrapped.buildSystemPromptSections(options);wrapped.buildSystemPromptState(options);
}
for(const name of ['','Preamble','preamble','1name','a b','a/b','a>','é']) {
 try {wrapped.buildSystemPromptSections({cwd:'/tmp',sections:{[name]:'x'}});} catch {}
 wrapped.buildSystemPromptState({cwd:'/tmp',forceSystemPrompt:'',sections:{[name]:'x'}});
}
for(const [previous,now] of [[{},{}],[{a:'x'},{a:'x'}],[{a:null},{a:'x'}],[{a:'x',b:'y'},{b:'y',a:'x'}],[{a:'x',b:null,c:'z'},{c:'new',d:'new'}]]) wrapped.diffSystemPromptSections(previous,now);
wrapped.buildSystemPromptSections({cwd:'/',sections:{'a-1_x':'OK',tools:'',docs:''}});
for(const readTool of ['read','bash']) wrapped.formatSkillsForPrompt([skill,{...skill,name:'second'}],readTool);
// Large content is reconstructed by the Bend fixture, avoiding OS argument-size limits.
current='150KB project context';
const content='Project instructions.\n'.repeat(7500);
const options={cwd:'/large',contextFiles:[{path:'/large/AGENTS.md',content}]};
records.push({name:current,input:{op:'large'},expected:api.buildSystemPrompt(options)});
console.log(JSON.stringify({names,records}));
