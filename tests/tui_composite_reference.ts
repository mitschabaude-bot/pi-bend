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
const tuiCode=transpiler.transformSync(tuiText.slice(tuiText.indexOf('const SEGMENT_RESET'),tuiText.indexOf('export type TuiMode'))).replace(/\bexport /g,'');
const composite=new Function('isImageLine','extractSegments','sliceWithWidth','visibleWidth','sliceByColumn',tuiCode+';return compositeTuiLine')(isImageLine,source.extractSegments,source.sliceWithWidth,source.visibleWidth,source.sliceByColumn);
function query(v:any){return composite(v.base,v.overlay,v.start,v.width,v.total);}
if(process.argv[4]==='--original'){
 const calls:any[]=[];let name='';const names:string[]=[];
 const capture=(base:string,overlay:string,start:number,width:number,total:number)=>{const input={base,overlay,start,width,total};const result=query(input);calls.push({name,input,result});return result;};
 const tests=transpiler.transformSync(pinned('packages/tui/test/regression-overlay-cjk-boundary.test.ts').replace(/^import.*\n/gm,''));
 new Function('assert','describe','it','compositeTuiLine','extractSegments','sliceByColumn','visibleWidth',tests)(assert,(_n:string,fn:Function)=>fn(),(n:string,fn:Function)=>{name=n;fn();names.push(n);},capture,source.extractSegments,source.sliceByColumn,source.visibleWidth);
 console.log(JSON.stringify({names,calls}));
}else console.log(JSON.stringify(JSON.parse(process.argv[4]).map(query)));
