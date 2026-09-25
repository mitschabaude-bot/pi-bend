import {readFileSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const root=process.argv[2],vendor=resolve(process.argv[3]);
const {eastAsianWidth}=await import(join(vendor,'get-east-asian-width/index.js'));
const transpiler=new Bun.Transpiler({loader:'ts'});
const hashes:Record<string,string>={"src/utils.ts": "8cda2d53e2361ac5aaf6d7345b2fee058c8df5743eae4e4e90c89a7072c026c3", "src/keys.ts": "b972facce4233a4623239fc38029e28cae15d0fb326558c0c09dc02cf4345fa7", "src/keybindings.ts": "eea5e3fe258ad50337595bb5320955a6d97bac0c8f6c0a838f988d75079bcf38", "src/word-navigation.ts": "b73e915a524926ac8881731e89026b0bc7b5b0bd465de67257af81a420465c7f", "src/kill-ring.ts": "d829ae816560b12d2800a38db9f7278f76d9ef43d0e53e004a86add9b56c559a", "src/undo-stack.ts": "1373c1e0a1e2c58ac90c93d32a9e5c1226d7f53314c77dd3d0f8ec349d2b3627", "src/components/input.ts": "416ceeb28f10b7146f6a284f276589797763b604d439574fbdc2a3ca52c00234", "test/input.test.ts": "dcbed4da6d52e41dd52faaef9861ee4662806d5529e33b612f22e691e9a51386", "src/fuzzy.ts": "8286a6feb16672e52114df5300369d20f48e27c9e87da2dc87294ea3b1223b8e", "src/components/settings-list.ts": "8d6b91d3c4aaaf11225854847d42ae6da852ef2646d54542c5b51a97dde15605", "test/settings-list.test.ts": "36418fe2495b92835c24a15129c5371f2dcffdfb72d0ecce7208b1ab0056062d"};
function source(path:string){const value=readFileSync(join(root,'packages/tui',path),'utf8');assert.equal(createHash('sha256').update(value).digest('hex'),hashes[path],path);return value;}
function compiled(path:string){return transpiler.transformSync(source(path).replace(/^import.*\n/gm,'')).replace(/\bexport /g,'');}
const utils=new Function('eastAsianWidth',compiled('src/utils.ts')+';return {getGraphemeSegmenter,isWhitespaceChar,sliceByColumn,truncateToWidth,visibleWidth,stripTerminalSequences,wrapTextWithAnsi,PUNCTUATION_REGEX};')(eastAsianWidth);
const keys=new Function(compiled('src/keys.ts')+';return {matchesKey,decodeKittyPrintable,setKittyProtocolActive};')();
const {KeybindingsManager,TUI_KEYBINDINGS}=new Function(...Object.keys(keys),compiled('src/keybindings.ts')+';return {KeybindingsManager,TUI_KEYBINDINGS};')(...Object.values(keys));
let manager=new KeybindingsManager(TUI_KEYBINDINGS,{});

const wordSegmenter=new Intl.Segmenter(undefined,{granularity:'word'});
const getWordSegmenter=()=>wordSegmenter;
const navigation=new Function(...Object.keys(utils),'getWordSegmenter',compiled('src/word-navigation.ts')+';return {findWordBackward,findWordForward};')(...Object.values(utils),getWordSegmenter);
const {KillRing}=new Function(compiled('src/kill-ring.ts')+';return {KillRing};')();
const {UndoStack}=new Function(compiled('src/undo-stack.ts')+';return {UndoStack};')();
const SourceInput=new Function(...Object.keys(utils),...Object.keys(navigation),'decodeKittyPrintable','getKeybindings','KillRing','UndoStack','CURSOR_MARKER',compiled('src/components/input.ts')+';return Input;')(...Object.values(utils),...Object.values(navigation),keys.decodeKittyPrintable,()=>manager,KillRing,UndoStack,'\x1b_pi:c\x07');
const {fuzzyFilter}=new Function(compiled('src/fuzzy.ts')+';return {fuzzyFilter};')();
const SourceSettings=new Function(...Object.keys(utils),'fuzzyFilter','getKeybindings','Input',compiled('src/components/settings-list.ts')+';return SettingsList;')(...Object.values(utils),fuzzyFilter,()=>manager,SourceInput);

assert.equal(process.versions.icu,'78.3');
// The native context has its CJK engine loaded before the first event.
[...wordSegmenter.segment('日本')];
const cases=JSON.parse(readFileSync(process.argv[4],'utf8'));
for(const value of cases){
 const input=new SourceInput();
 const settings=new SourceSettings([{id:'text',label:value.text,currentValue:'value'},{id:'other',label:'Unrelated',currentValue:'value'}],5,{label:(x:string)=>x,value:(x:string)=>x,description:(x:string)=>x,hint:(x:string)=>x,cursor:'> '},()=>{},()=>{},{enableSearch:true});
 const shown=(input:any)=>({value:input.getValue(),cursor:[...input.getValue().slice(0,input.cursor)].length});
 const settingsShown=()=>({input:shown(settings.searchInput),selected:settings.getDisplayItems()[settings.selectedIndex]?.id??null});
 const observations=[];
 for(const key of ['\x1b[200~'+value.text+'\x1b[201~',...value.keys]){
  input.handleInput(key);settings.handleInput(key);
  observations.push({input:shown(input),settings:settingsShown()});
 }
 console.log(JSON.stringify({observations,finalInput:shown(input),finalSettings:settingsShown()}));
}
