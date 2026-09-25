import { UPSTREAM } from "./upstream_pin.mjs";
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const repo=process.argv[2] ?? UPSTREAM;
const source=readFileSync(`${repo}/packages/tui/src/components/markdown.ts`);
assert.equal(createHash('sha256').update(source).digest('hex'),'704c1c714a7ff6bdec55573ab38393726fa73a7b47cf4c1161ccc4f08530ac28');
assert.equal(createHash('sha256').update(readFileSync(`${repo}/packages/tui/test/markdown.test.ts`)).digest('hex'),'1060dbf84302c3984479b7a33ad4aaf21ae0616b8c02a45f066ba6e8f200f14d');
const {Markdown}=await import(`${repo}/packages/tui/src/components/markdown.ts`);
const {setCapabilities,resetCapabilitiesCache}=await import(`${repo}/packages/tui/src/terminal-image.ts`);
const plain=(text:string)=>text;
const theme={heading:plain,link:plain,linkUrl:plain,code:plain,codeBlock:plain,codeBlockBorder:plain,quote:plain,quoteBorder:plain,hr:plain,listBullet:plain,bold:plain,italic:plain,strikethrough:plain,underline:plain};
const cases=['hello','hello world','**bold**','*italic*','~~gone~~','`code`','# title','## subtitle','line\nnext','hello\n\nworld','- one\n- two','1. one\n2. two','> quoted','---','```js\nconst x = 1;\n```','[site](https://example.com)','a  \nb','- outer\n  - inner\n- other','3. a\n7. b','# heading\nnext','```js\nx\n```\nnext','> a\n> b','---\nnext','simple <b>tag</b>','\\*literal*','~~foo~~ ~bar~','```x\nfoo\n```\n','| A | B |\n|---|---|\n| one | two |','| A | B |\n|---|---|\n| x | y |\n| z | w |','| Keys | Action |\n| --- | --- |\n| `Ctrl+P` / `Ctrl+K` | choose |'];
for(const source of cases){const lines=new Markdown(source,0,0,theme).render(20);console.log(`${lines.length}:${lines.join('|')}`);}
for(const [source,width] of [['- alpha beta gamma delta epsilon',20],['1. alpha beta gamma delta epsilon',20],['10. alpha beta gamma delta epsilon',21],['- parent\n  - alpha beta gamma delta epsilon',24],['1. parent\n   - alpha beta gamma delta epsilon',24]] as const){const lines=new Markdown(source,0,0,theme).render(width);console.log(`${lines.length}:${lines.join('|')}`);}
for(const [source,width] of [['> This is a very long blockquote line that should wrap to multiple lines when rendered',30],['>Foo\nbar',80],['>Foo\n>bar',80],['> 1. bla bla\n> - nested bullet',80],['> Quote with **bold** and `code`',80],['> One\n\nafter',20]] as const){const lines=new Markdown(source,0,0,theme).render(width);console.log(`${lines.length}:${lines.join('|')}`);}
for(const [source,width] of [['| Command | Description | Example |\n| --- | --- | --- |\n| npm install | Install all dependencies | npm install |\n| npm run build | Build the project | npm run build |',50],['| Header |\n| --- |\n| This is a very long cell content that should wrap |',25],['| Value |\n| --- |\n| prefix https://example.com/this/is/a/very/long/url/that/should/wrap |',30],['| Column One | Column Two |\n| --- | --- |\n| superlongword short | otherword |\n| small | tiny |',32]] as const){const lines=new Markdown(source,0,0,theme).render(width);console.log(`${lines.length}:${lines.join('|')}`);}
setCapabilities({images:null,trueColor:false,hyperlinks:true});
for(const source of ['[click here](https://example.com)','[Email me](mailto:test@example.com)','[label](https://example.com) and more']){const lines=new Markdown(source,0,0,theme).render(80);console.log(`${lines.length}:${lines.join('|')}`);}
resetCapabilitiesCache();
for(const [source,width] of [['| A | B | C |\n| --- | --- | --- |\n| 1 | 2 | 3 |',15],['| A | B | C |\n| --- | --- | --- |\n| 1 | 2 | 3 |',12],['| Long | Header |\n| --- | --- |\n| words words words | split split split |',20]] as const){const lines=new Markdown(source,0,0,theme).render(width);console.log(`${lines.length}:${lines.join('|')}`);}
const ansi=(open:string,close:string)=>(value:string)=>`${open}${value}${close}`;
const styledTheme={...theme,heading:ansi('\x1b[36m','\x1b[39m'),code:ansi('\x1b[33m','\x1b[39m'),bold:ansi('\x1b[1m','\x1b[22m'),underline:ansi('\x1b[4m','\x1b[24m'),italic:ansi('\x1b[3m','\x1b[23m'),quote:ansi('\x1b[35m','\x1b[39m')};
for(const source of ['# Title with `code` inside','## Heading with **bold** and more','> Quote with **bold** and `code`','plain `code` later']){const lines=new Markdown(source,0,0,styledTheme).render(80);console.log(`${lines.length}:${lines.join('|')}`);}
for(const source of ['gray `code` after','before **bold** after']){const lines=new Markdown(source,0,0,styledTheme,{color:ansi('\x1b[90m','\x1b[39m'),italic:true}).render(80);console.log(`${lines.length}:${lines.join('|')}`);}
for(const [source,width] of [['| Code |\n| --- |\n| `averyveryveryverylongidentifier` |',20],['| Plain | Link |\n| --- | --- |\n| normal | [short](https://example.com) |',35]] as const){const lines=new Markdown(source,0,0,styledTheme).render(width);console.log(`${lines.length}:${lines.join('|')}`);}
{const lines=new Markdown('| Left | Center | Right |\n| :--- | :---: | ---: |\n| A | B | C |\n| Long text | Middle | End |',0,0,theme).render(80);console.log(`${lines.length}:${lines.join('|')}`);}

const calls:Array<[string,number]>=[];
const state=new Markdown('source',2,0,theme,undefined,{transform:(source:string,width:number)=>{calls.push([source,width]);return `${source} ${width}`;}});
function stateOutput(width:number){const lines=state.render(width);console.log(`${lines.length}:${lines.join('|')}`);}
stateOutput(80);stateOutput(80);stateOutput(60);state.setText('updated');stateOutput(60);state.invalidate();stateOutput(60);console.log(calls.length);
