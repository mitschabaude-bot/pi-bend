import {readFileSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const root=process.argv[2],{eastAsianWidth}=await import(resolve(process.argv[3]));
const transpiler=new Bun.Transpiler({loader:'ts'});
const hashes:Record<string,string>={
 'packages/tui/test/regression-overlay-cjk-boundary.test.ts':'51438c36784bb4ffb6304e1d179eb9daa046b8b93c80582c87c41f6415449b20',
 'packages/tui/src/tui.ts':'2ca47c56f4a4f24b8c6a4c9c9f2a06004bfc312d9dbcd0ac1921a2cae32bc675',
 'packages/tui/src/terminal-image.ts':'f29572354977fd4ef4cc76878d31cce3cb5c45cebdfc9b5c49b50ad9cfb3171f',
 'packages/tui/src/utils.ts':'8cda2d53e2361ac5aaf6d7345b2fee058c8df5743eae4e4e90c89a7072c026c3',
 'packages/tui/test/truncate-to-width.test.ts':'fd75a99d47ff465d56a1f3ede16e37ca7d29aa910e2322881e824e6c2937b7b8',
 'packages/tui/test/wrap-ansi.test.ts':'9c238d85ad676ca6d4e063caa8d44d493b0c220dd9aba9ea11a31d51c92d791d',
 'packages/tui/test/regression-regional-indicator-width.test.ts':'a057bc5b61cd287e2f2f554e878222ebace84a515e6cf67b87191eba5c91ae47',
 'packages/tui/test/tab-width.test.ts':'59fff93aeecb3809f41f7bf68d88ef8ba9f0f38cd3a2db785a1f16a0ac114419',
};
function pinned(file:string){const text=readFileSync(join(root,file),'utf8');assert.equal(createHash('sha256').update(text).digest('hex'),hashes[file],file);return text;}
const sourceText=pinned('packages/tui/src/utils.ts');
const compiled=transpiler.transformSync(sourceText.replace(/^import.*\n/, '')).replace(/\bexport /g,'');
const names=['visibleWidth','graphemeWidth','normalizeTerminalOutput','truncateToWidth','wrapTextWithAnsi','extractSegments','sliceWithWidth','sliceByColumn','cjkBreakRegex'];
const source=new Function('eastAsianWidth',compiled+';return {'+names.join(',')+'};')(eastAsianWidth);

const imageText=pinned('packages/tui/src/terminal-image.ts');
const imageCode=transpiler.transformSync(imageText.slice(imageText.indexOf('const KITTY_PREFIX'),imageText.indexOf('export function allocateImageId'))).replace(/\bexport /g,'');
const isImageLine=new Function(imageCode+';return isImageLine')();
const tuiText=pinned('packages/tui/src/tui.ts');

const resetDeclaration=tuiText.match(/const SEGMENT_RESET = [^\n]+/)![0];
const markerDeclaration=tuiText.match(/export const CURSOR_MARKER = [^\n]+/)![0].replace('export ','');
const resetMethod=tuiText.slice(tuiText.indexOf('\tprotected applyLineResets('),tuiText.indexOf('\n\tprivate compositeLineAt('));
const cursorStart=tuiText.indexOf('\tprotected extractCursorPosition(');
const cursorEnd=tuiText.indexOf('\n\t}\n',cursorStart)+4;
const cursorMethod=tuiText.slice(cursorStart,cursorEnd);
const frameCode=transpiler.transformSync(resetDeclaration+'\n'+markerDeclaration+'\nclass Frame {\n'+resetMethod+'\n'+cursorMethod+'\n}');
const Frame=new Function('isImageLine','normalizeTerminalOutput','visibleWidth',frameCode+';return Frame;')(isImageLine,source.normalizeTerminalOutput,source.visibleWidth);
const frame=new Frame();
function query(value:any){const lines=[...value.lines];if(value.op==='reset')return frame.applyLineResets(lines);const cursor=frame.extractCursorPosition(lines,value.height);return {lines:value.op==='frame'?frame.applyLineResets(lines):lines,cursor};}
if(process.argv[4]==='--original'){
 const calls:any[]=[];const names:string[]=[];let name='';
 const normalize=(input:string)=>{const v={op:'reset',lines:[input]};const result=query(v);calls.push({name,input:v,result});return result[0].slice(0,-'\x1b[0m\x1b]8;;\x07'.length);};
 const width=(input:string)=>{const v={op:'cursor',lines:[input+'\x1b_pi:c\x07'],height:1};const result=query(v);calls.push({name,input:v,result});return result.cursor.col;};
 for(const [file,label] of [['packages/tui/test/truncate-to-width.test.ts','normalizes Thai and Lao AM vowels only for terminal output'],['packages/tui/test/tab-width.test.ts','keeps tabs inside terminal control sequences byte-identical']]){
  const source=pinned(file);const start=source.indexOf('\tit("'+label+'"');assert(start>=0);const end=source.indexOf('\n\t});',start)+6;
  const code=transpiler.transformSync(source.slice(start,end));
  new Function('assert','it','normalizeTerminalOutput','visibleWidth',code)(assert,(label:string,fn:Function)=>{name=label;fn();names.push(label);},normalize,width);
 }
 console.log(JSON.stringify({names,calls}));
}else console.log(JSON.stringify(JSON.parse(process.argv[4]).map(query)));
