import fs from 'node:fs';
import assert from 'node:assert/strict';
import { parse, stringify } from '../build/reference/node_modules/yaml/dist/index.js';
const root=process.argv[2];
const source=fs.readFileSync(root+'/packages/coding-agent/src/utils/frontmatter.ts','utf8').replace(/^import .*;\n/gm,'').replace(/\bexport /g,'');
const api=new Function('parse','stripBom',new Bun.Transpiler({loader:'ts'}).transformSync(source)+'; return {parseFrontmatter,stripFrontmatter}')(parse,(s:string)=>s.replace(/^\uFEFF/,''));
const names:string[]=[];const cases:any[]=[];let name='';
function it(label:string,fn:()=>void){name=label;names.push(label);fn();}
function expect(value:any){return {toBe:(want:any)=>assert.equal(value,want),toEqual:(want:any)=>assert.deepEqual(value,want),toThrow:(pattern:RegExp)=>assert.throws(value,pattern)}}
function parseFrontmatter(source:string){try{const value=api.parseFrontmatter(source);cases.push({name,source,expected:{ok:true,...value}});return value}catch(e:any){cases.push({name,source,expected:{ok:false},referenceError:e.message});throw e}}
function stripFrontmatter(source:string){return parseFrontmatter(source).body}
const tests=fs.readFileSync(root+'/packages/coding-agent/test/frontmatter.test.ts','utf8').replace(/^import .*;\n/gm,'');
new Function('describe','it','expect','parseFrontmatter','stripFrontmatter',new Bun.Transpiler({loader:'ts'}).transformSync(tests))((_name:string,f:()=>void)=>f(),it,expect,parseFrontmatter,stripFrontmatter);
name='supplemental BOM/newline and body preservation';
parseFrontmatter('\uFEFF---\rname: test\rdescription: desc\r---\r\rBody\rsecond');
parseFrontmatter('---\n---\nBody');
const yaml:any[]=[];
function record(source:string){try{yaml.push({source,expected:{ok:true,value:parse(source)}})}catch(e:any){yaml.push({source,expected:{ok:false},referenceError:e.message})}}
for(const style of ['|','|-','|+','>','>-','>+','|2','>2-']) for(const content of ['', '\n','\n\n','  one','  one\n','  one\n\n','  one\n  two','  one\n\n  two','  one\n    extra\n  two','\n  one\n  two\n\n']) record('value: '+style+'\n'+content);
const scalars=['text','"quoted"',"'it''s good'",'null','~','true','False','false','0','1','-2','3.25','0x10','0o17','0b10','1_000','.5','-.5','1e2','+1','Infinity','.inf','-.Inf','.nan','http://example.test/a:b','a # comment','"line\\n\\x41\\u0042\\U0001f600"','"bad\\q"'];
for(const value of scalars) {record('value: '+value);record('[ '+value+', tail ]');}
for(const source of ['a: [one, {two: [3, true]}, null]','a:\n  b: text\n  c:\n    - one\n    - two','items:\n  - name: first\n    description: desc\n  - name: second\n    x: 2','a: &name [one, two]\nb: *name','a: first\na: second','a: [bad','a: {bad','a: \"bad','a:','- one\n- two','a: |\n  hi\nb: after','a: >\n  hi\nb: after'])record(source);
for(let i=0;i<50;i++){const value={name:'skill-'+i,description:i%2?'Multiline\nDescription\n':'A skill: uses [brackets] # chars',enabled:i%3===0,meta:{array:[i,'text',null,true],sub:{n:-i}},items:[{x:'one'},{x:'two'}]};record(stringify(value,{lineWidth:0}));}
console.log(JSON.stringify({names,cases,yaml}));
