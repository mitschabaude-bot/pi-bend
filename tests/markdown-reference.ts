import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const repo=process.argv[2] ?? '/home/agent/code/pi-mono';
const source=readFileSync(`${repo}/packages/tui/src/components/markdown.ts`);
assert.equal(createHash('sha256').update(source).digest('hex'),'704c1c714a7ff6bdec55573ab38393726fa73a7b47cf4c1161ccc4f08530ac28');
assert.equal(createHash('sha256').update(readFileSync(`${repo}/packages/tui/test/markdown.test.ts`)).digest('hex'),'1060dbf84302c3984479b7a33ad4aaf21ae0616b8c02a45f066ba6e8f200f14d');
const {Markdown}=await import(`${repo}/packages/tui/src/components/markdown.ts`);
const plain=(text:string)=>text;
const theme={heading:plain,link:plain,linkUrl:plain,code:plain,codeBlock:plain,codeBlockBorder:plain,quote:plain,quoteBorder:plain,hr:plain,listBullet:plain,bold:plain,italic:plain,strikethrough:plain,underline:plain};
const cases=['hello','hello world','**bold**','*italic*','~~gone~~','`code`','# title','## subtitle','line\nnext','hello\n\nworld','- one\n- two','1. one\n2. two','> quoted','---','```js\nconst x = 1;\n```','[site](https://example.com)','a  \nb','- outer\n  - inner\n- other','3. a\n7. b','# heading\nnext','```js\nx\n```\nnext','> a\n> b','---\nnext','simple <b>tag</b>','\\*literal*','~~foo~~ ~bar~','```x\nfoo\n```\n','| A | B |\n|---|---|\n| one | two |','| A | B |\n|---|---|\n| x | y |\n| z | w |'];
for(const source of cases){const lines=new Markdown(source,0,0,theme).render(20);console.log(`${lines.length}:${lines.join('|')}`);}
for(const [source,width] of [['- alpha beta gamma delta epsilon',20],['1. alpha beta gamma delta epsilon',20],['10. alpha beta gamma delta epsilon',21],['- parent\n  - alpha beta gamma delta epsilon',24],['1. parent\n   - alpha beta gamma delta epsilon',24]] as const){const lines=new Markdown(source,0,0,theme).render(width);console.log(`${lines.length}:${lines.join('|')}`);}

const calls:Array<[string,number]>=[];
const state=new Markdown('source',2,0,theme,undefined,{transform:(source:string,width:number)=>{calls.push([source,width]);return `${source} ${width}`;}});
function stateOutput(width:number){const lines=state.render(width);console.log(`${lines.length}:${lines.join('|')}`);}
stateOutput(80);stateOutput(80);stateOutput(60);state.setText('updated');stateOutput(60);state.invalidate();stateOutput(60);console.log(calls.length);
