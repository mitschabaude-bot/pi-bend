import {readFileSync} from 'node:fs';
import {join,resolve,isAbsolute} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const root=process.argv[2],{eastAsianWidth}=await import(resolve(process.argv[3])),transpiler=new Bun.Transpiler({loader:'ts'});
const hashes={"packages/tui/src/utils.ts": "8cda2d53e2361ac5aaf6d7345b2fee058c8df5743eae4e4e90c89a7072c026c3", "packages/tui/src/terminal-image.ts": "f29572354977fd4ef4cc76878d31cce3cb5c45cebdfc9b5c49b50ad9cfb3171f", "packages/tui/src/components/image.ts": "cdef2f757008ce2fecfde6c0108366ebdc160bac70355db855fd264aec8d53f8", "packages/tui/test/terminal-image.test.ts": "d4e7e72dc1ef01aa5f1d217228db5d1f79bc447ef991986dde0ec2006d02cfd2"};
function source(path:string){const s=readFileSync(join(root,path),'utf8');assert.equal(createHash('sha256').update(s).digest('hex'),hashes[path],path);return s;}
const utils=transpiler.transformSync(source('packages/tui/src/utils.ts').replace(/^import.*\n/gm,'')).replace(/\bexport /g,'');
const u=new Function('eastAsianWidth',utils+';return {truncateToWidth,visibleWidth}')(eastAsianWidth);
const terminal=source('packages/tui/src/terminal-image.ts'),names=[...terminal.matchAll(/^export function (\w+)/gm)].map(m=>m[1]);
const terminalCode=transpiler.transformSync(terminal.replace(/^import.*\n/gm,'')).replace(/\bexport /g,'');
const imageCode=transpiler.transformSync(source('packages/tui/src/components/image.ts').replace(/^import[\s\S]*?from [^;]+;\n/gm,'')).replace(/\bexport /g,'');
function make(v:any){
 const process={env:v.env??{},platform:'linux'},api=new Function('process','execSync','homedir','isAbsolute','pathToFileURL',terminalCode+';return {'+names.join(',')+'};')(process,()=>'',()=>v.home??'',isAbsolute,pathToFileURL);
 api.setCellDimensions(v.cells??{widthPx:9,heightPx:18});api.setCapabilityOverrides(v.overrides??{});
 const Image=new Function(...names,'truncateToWidth',imageCode+';return Image;')(...names.map(n=>api[n]),u.truncateToWidth);
 return {api,Image};
}
function query(v:any){
 const {api,Image}=make(v);let callbacks=0;const image=new Image(v.data,v.mime,{fallbackColor:(text:string)=>{callbacks++;return (v.prefix??'')+text+(v.suffix??'');}},v.options??{},v.dimensions);
 const results=v.steps.map((s:any)=>{if(s.invalidate)image.invalidate();if(s.caps)api.setCapabilities(s.caps);const lines=image.render(s.width);return {lines,id:image.getImageId()??null};});return {results,callbacks};
}
if(process.argv[4]==='--named'){
 const {api,Image}=make({home:'/test/home'}),passed:string[]=[],cases:any[]=[];let title='';
 class CapturedImage extends Image {render(width:number){const result=super.render(width);cases.push({title,width,lines:result});return result;}}
 const original=source('packages/tui/test/terminal-image.test.ts').replace(/^import[\s\S]*?from [^;]+;\n/gm,'');
 const describe=(_:string,fn:()=>void)=>fn();const it=(name:string,fn:()=>void)=>{if(['caps Image component height','places image sequence on first line','truncates long image fallback'].some(x=>name.startsWith(x))){title=name;fn();passed.push(name);}};
 new Function('assert','homedir','join','describe','it','process','Image','visibleWidth',...names,transpiler.transformSync(original))(assert,()=>'/test/home',join,describe,it,{env:{}},CapturedImage,u.visibleWidth,...names.map(n=>api[n]));
 console.log(JSON.stringify({passed,cases}));
}else console.log(JSON.stringify(JSON.parse(process.argv[4]).map(query)));
