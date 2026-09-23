import {readFileSync} from 'node:fs';
import {join,isAbsolute} from 'node:path';
import {pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const root=globalThis.process.argv[2],transpiler=new Bun.Transpiler({loader:'ts'});
const source=readFileSync(join(root,'packages/tui/src/terminal-image.ts'),'utf8');
assert.equal(createHash('sha256').update(source).digest('hex'),'f29572354977fd4ef4cc76878d31cce3cb5c45cebdfc9b5c49b50ad9cfb3171f');
const test=readFileSync(join(root,'packages/tui/test/terminal-image.test.ts'),'utf8');
assert.equal(createHash('sha256').update(test).digest('hex'),'d4e7e72dc1ef01aa5f1d217228db5d1f79bc447ef991986dde0ec2006d02cfd2');
const names=[...source.matchAll(/^export function (\w+)/gm)].map(m=>m[1]);
const compiled=transpiler.transformSync(source.replace(/^import .*;\n/gm,'')).replace(/\bexport /g,'');
const process={env:{} as any,platform:'linux'},home='/test/home';
const api=new Function('process','execSync','homedir','isAbsolute','pathToFileURL',compiled+';return {'+names.join(',')+'};')(process,()=>'',()=>home,isAbsolute,pathToFileURL);
let name='',cells={widthPx:9,heightPx:18},overrides:any={},manual:any=undefined;
const metadata=new Map<number,any>(),calls:any[]=[],passed:string[]=[],pending:string[]=[];
const wrapped:any={};
function remember(v:any,result:any){calls.push({name,input:v,expected:result??null});}
function config(){const o={...(manual??overrides)};if(o.images===null)o.images='none';return {env:{...process.env},platform:process.platform,home,cells:{...cells},overrides:o};}
for(const key of names)wrapped[key]=(...args:any[])=>{
 let probe=false;
 if(key==='detectCapabilities' && args[0]){const callback=args[0];args[0]=()=>{probe=callback();return probe;};}
 const result=api[key](...args);
 if(key==='setCapabilities')manual=args[0];
 if(key==='resetCapabilitiesCache')manual=undefined;
 if(key==='setCapabilityOverrides'){overrides=args[0];manual=undefined;}
 if(key==='setCellDimensions')cells=args[0];
 if(key==='registerKittyImageMetadata')metadata.set(args[0].imageId,args[0]);
 let v:any;
 switch(key){
 case 'isImageLine':v={method:key,text:args[0]};break;
 case 'encodeKitty':case 'encodeITerm2':v={method:key,data:args[0],options:args[1]};break;
 case 'deleteKittyImage':v={method:'delete',imageId:args[0]};break;
 case 'deleteAllKittyImages':v={method:'deleteAll'};break;
 case 'deleteAllKittyPlacements':v={method:'deletePlacements'};break;
 case 'detectCapabilities':v={...config(),overrides:{},method:'caps',probe};break;
 case 'getCapabilities':v={...config(),method:'caps'};break;
 case 'hyperlink':v={method:key,text:args[0],url:args[1]};break;
 case 'imageFallback':v={...config(),method:'fallback',mime:args[0],dimensions:args[1],filename:args[2]};break;
 case 'renderImage':{v={...config(),method:'render',data:args[0],dimensions:args[1],options:args[2]};if(result?.imageId)metadata.set(result.imageId,{imageId:result.imageId,columns:result.columns,rows:result.rows,...args[1]});remember(v,result?{...result,imageId:result.imageId??null}:null);return result;}
 case 'getKittyImageMetadata':if(result)v={method:'metadata',text:args[0],...result};break;
 case 'cropKittyImageLine':{const m=api.getKittyImageMetadata(args[0]);if(m)v={method:'crop',text:args[0],hidden:args[1],visible:args[2],...m};break;}
 case 'getKittyImagePlacement':{const m=api.getKittyImageMetadata(args[0]);if(m){v={method:'placement',text:args[0],...m};remember(v,result?{...result,transmissionGeneration:1}:null);}return result;}
 }
 if(v)remember(v,result);
 return result;
};
const suites:string[]=[];
function describe(title:string,body:()=>void){suites.push(title);body();suites.pop();}
function it(title:string,body:()=>void){name=[...suites,title].join(' / ');if(['old implementation would return false','caps Image component height','places image sequence on first line','truncates long image fallback'].some(x=>title.startsWith(x))){pending.push(name);return;}body();passed.push(name);}
const stripped=test.replace(/^import[\s\S]*?from [^;]+;\n/gm,'');
new Function('assert','homedir','join','describe','it','process',...names,transpiler.transformSync(stripped))(assert,()=>home,join,describe,it,process,...names.map(n=>wrapped[n]));
const regression=readFileSync(join(root,'packages/tui/test/bug-regression-isimageline-startswith-bug.test.ts'),'utf8');
assert.equal(createHash('sha256').update(regression).digest('hex'),'89f2ce2cf538aedb404b872aba345309b92c6f44375ea1882e0540c4900dfb00');
const regressionCode=regression.replace(/^import.*;\n/gm,'').replace(/const \{ isImageLine \} = await import\([^;]+;/g,'').replace(/async \(\) =>/g,'() =>');
new Function('assert','describe','it','isImageLine',transpiler.transformSync(regressionCode))(assert,describe,it,wrapped.isImageLine);
console.log(JSON.stringify({calls,passed,pending}));
