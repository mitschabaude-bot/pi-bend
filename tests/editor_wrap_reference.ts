import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const root=process.argv[2],{eastAsianWidth}=await import(resolve(process.argv[3])),transpiler=new Bun.Transpiler({loader:'ts'});
const hashes={"packages/tui/src/utils.ts":"8cda2d53e2361ac5aaf6d7345b2fee058c8df5743eae4e4e90c89a7072c026c3","packages/tui/src/components/editor.ts":"241695859d48f49c6aaba9b9cfc14c6cd28639c6c247adb4fe2c202a9e2c6e20"};
function source(path:string){const s=readFileSync(resolve(root,path),'utf8');assert.equal(createHash('sha256').update(s).digest('hex'),hashes[path]);return s;}
const utils=transpiler.transformSync(source('packages/tui/src/utils.ts').replace(/^import.*\n/gm,'')).replace(/\bexport /g,'');
const u=new Function('eastAsianWidth',utils+';return {visibleWidth,cjkBreakRegex,autocompleteBoundaryRegex,autocompleteSeparatorRegex,isWhitespaceChar,getGraphemeSegmenter,getWordSegmenter}')(eastAsianWidth);
const editor=source('packages/tui/src/components/editor.ts').split('// Kitty CSI-u sequences')[0].replace(/^import[\s\S]*?from [^;]+;\n/gm,'');
const api=new Function(...Object.keys(u),transpiler.transformSync(editor).replace(/\bexport /g,'')+';return {wordWrapLine,segmentWithMarkers};')(...Object.values(u));
const scalar=(s:string,n:number)=>[...s.slice(0,n)].length;
console.log(JSON.stringify(JSON.parse(readFileSync(0,'utf8')).map((v:any)=>{try{return api.wordWrapLine(v.text,v.width,[...api.segmentWithMarkers(v.text,new Intl.Segmenter(undefined,{granularity:'grapheme'}),new Set(v.ids??[]))]).map((c:any)=>({...c,startIndex:scalar(v.text,c.startIndex),endIndex:scalar(v.text,c.endIndex)}));}catch(e){console.error(v);throw e;}})));
