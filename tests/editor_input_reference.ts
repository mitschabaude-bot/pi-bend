import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const root=process.argv[2],{eastAsianWidth}=await import(resolve(process.argv[3])),transpiler=new Bun.Transpiler({loader:'ts'});
function source(path:string){return readFileSync(resolve(root,path),'utf8');}
const editor=source('packages/tui/src/components/editor.ts');assert.equal(createHash('sha256').update(editor).digest('hex'),'241695859d48f49c6aaba9b9cfc14c6cd28639c6c247adb4fe2c202a9e2c6e20');
const transform=(s:string)=>transpiler.transformSync(s.replace(/^import[\s\S]*?from [^;]+;\n/gm,'')).replace(/\bexport /g,'');
const utils=transform(source('packages/tui/src/utils.ts'));
const u=new Function('eastAsianWidth',utils+';return {visibleWidth,cjkBreakRegex,autocompleteBoundaryRegex,autocompleteSeparatorRegex,isWhitespaceChar,getGraphemeSegmenter,getWordSegmenter,sliceByColumn,PUNCTUATION_REGEX}')(eastAsianWidth);
const KillRing=new Function(transform(source('packages/tui/src/kill-ring.ts'))+';return KillRing')();
const UndoStack=new Function(transform(source('packages/tui/src/undo-stack.ts'))+';return UndoStack')();
const keys=new Function(transform(source('packages/tui/src/keys.ts'))+';return {matchesKey,decodePrintableKey,setKittyProtocolActive}')();
const kb=new Function('matchesKey',transform(source('packages/tui/src/keybindings.ts'))+';return {getKeybindings,KeybindingsManager,setKeybindings,TUI_KEYBINDINGS}')(keys.matchesKey);
const word=new Function(...Object.keys(u),transform(source('packages/tui/src/word-navigation.ts'))+';return {findWordForward,findWordBackward}')(...Object.values(u));
let words={};const originalWords=u.getWordSegmenter;u.getWordSegmenter=()=>({segment(text){const parts=[...originalWords().segment(text)];words[text]=parts.map(s=>({text:s.segment,word:!!s.isWordLike}));return parts;}});
const Editor=new Function(...Object.keys(u),'KillRing','UndoStack','CURSOR_MARKER',...Object.keys(keys),...Object.keys(kb),...Object.keys(word),transform(editor)+';return Editor')(...Object.values(u),KillRing,UndoStack,"\x1b_pi:c\x07",...Object.values(keys),...Object.values(kb),...Object.values(word));
function query(v){words={};const events=[],e=new Editor({requestRender(){events.push('R')},terminal:{rows:24}},{borderColor:s=>s,selectList:{}});e.onChange=s=>events.push('C'+s);e.onSubmit=s=>events.push('S'+s);const results=v.map(op=>{events.length=0;let rendered=null;if(op.op==='set')e.setText(op.text);else if(op.op==='insert')e.insertTextAtCursor(op.text);else if(op.op==='add')e.addToHistory(op.text);else if(op.op==='input')e.handleInput(op.text);else if(op.op==='render')rendered=e.render(op.width);else if(op.op==='mouse')e.handleMouse({type:'click',button:'left',x:op.x,y:op.y,screenX:0,screenY:0,width:op.width,height:24,shift:false,alt:false,ctrl:false,clickCount:1});else if(op.op==='disable')e.disableSubmit=op.value;else if(op.op==='focus')e.focused=op.value;const cursor=e.getCursor();return {text:e.getText(),expanded:e.getExpandedText(),line:cursor.line,col:[...e.getLines()[cursor.line].slice(0,cursor.col)].length,pasteCounter:e.pasteCounter,events:[...events],rendered};});return {results,words};}
console.log(JSON.stringify(JSON.parse(readFileSync(0,'utf8')).map(query)));
