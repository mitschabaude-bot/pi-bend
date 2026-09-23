import {readFileSync} from 'node:fs';
import {join,isAbsolute} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const root=process.argv[2];
const source=readFileSync(join(root,'packages/tui/src/terminal-image.ts'),'utf8');
const expectedHash='f29572354977fd4ef4cc76878d31cce3cb5c45cebdfc9b5c49b50ad9cfb3171f';
assert.equal(createHash('sha256').update(source).digest('hex'),expectedHash);
const compiled=new Bun.Transpiler({loader:'ts'}).transformSync(source.replace(/^import .*;\n/gm,'')).replace(/\bexport /g,'');
const names=[...source.matchAll(/^export function (\w+)/gm)].map(m=>m[1]);
function query(v:any){
 const process={env:v.env??{},platform:v.platform??'linux'};
 const api=new Function('process','execSync','homedir','isAbsolute','pathToFileURL',compiled+';return {'+names.join(',')+'};')(process,()=>v.probe?'hyperlinks':'',()=>v.home??'',isAbsolute,pathToFileURL);
 api.setCellDimensions(v.cells??{widthPx:9,heightPx:18});api.setCapabilityOverrides(v.overrides??{});
 const meta={imageId:v.imageId,columns:v.columns,rows:v.rows,widthPx:v.widthPx,heightPx:v.heightPx};
 switch(v.method){
 case 'isImageLine':return api.isImageLine(v.text);
 case 'encodeKitty':return api.encodeKitty(v.data,v.options??{});
 case 'encodeITerm2':{const o={...v.options};for(const k of ['width','height'])if(o[k]&&typeof o[k]==='object')o[k]=`${o[k].value}${o[k].unit==='pixels'?'px':'%'}`;return api.encodeITerm2(v.data,o);}
 case 'dimensions':return api.getImageDimensions(v.data,v.mime);
 case 'size':return api.calculateImageCellSize(v.dimensions,v.width,v.height,v.cells);
 case 'caps':return api.getCapabilities();
 case 'render':{const r=api.renderImage(v.data,v.dimensions,v.options??{});return r?{...r,imageId:r.imageId??null}:null;}
 case 'crop':api.registerKittyImageMetadata(meta);return api.cropKittyImageLine(v.text,v.hidden,v.visible);
 case 'placement':api.registerKittyImageMetadata(meta);return api.getKittyImagePlacement(v.text)??null;
 case 'hyperlink':return api.hyperlink(v.text,v.url);
 case 'fallback':return api.imageFallback(v.mime,v.dimensions,v.filename);
 case 'delete':return api.deleteKittyImage(v.imageId);
 case 'deleteAll':return api.deleteAllKittyImages();
 case 'deletePlacements':return api.deleteAllKittyPlacements();
 }
}
console.log(JSON.stringify(JSON.parse(process.argv[3]).map(query)));
