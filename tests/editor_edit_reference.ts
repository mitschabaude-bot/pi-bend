import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const root=process.argv[2],{eastAsianWidth}=await import(resolve(process.argv[3])),transpiler=new Bun.Transpiler({loader:'ts'});
function source(path:string){return readFileSync(resolve(root,path),'utf8');}
const editor=source('packages/tui/src/components/editor.ts');assert.equal(createHash('sha256').update(editor).digest('hex'),'88076036a3ff33da05f347101a6ab56749c8be398d7a35dea1976e62230c4ac5');
const transform=(s:string)=>transpiler.transformSync(s.replace(/^import[\s\S]*?from [^;]+;\n/gm,'')).replace(/\bexport /g,'');
const utils=transform(source('packages/tui/src/utils.ts'));
const u=new Function('eastAsianWidth',utils+';return {visibleWidth,cjkBreakRegex,isWhitespaceChar,getGraphemeSegmenter,getWordSegmenter,sliceByColumn}')(eastAsianWidth);
const KillRing=new Function(transform(source('packages/tui/src/kill-ring.ts'))+';return KillRing')();
const UndoStack=new Function(transform(source('packages/tui/src/undo-stack.ts'))+';return UndoStack')();
const Editor=new Function(...Object.keys(u),'KillRing','UndoStack',transform(editor)+';return Editor')(...Object.values(u),KillRing,UndoStack);
const operations={set:'setText',insert:'insertTextAtCursor',type:'insertCharacter',paste:'handlePaste',home:'moveToLineStart',end:'moveToLineEnd',backspace:'handleBackspace',delete:'handleForwardDelete',killStart:'deleteToStartOfLine',killEnd:'deleteToEndOfLine',yank:'yank',yankPop:'yankPop',undo:'undo'};
function query(ops:any[]){const e=new Editor({requestRender(){}},{borderColor:(s:string)=>s,selectList:{}});return ops.map(v=>{if(v.op==='left')e.moveCursor(0,-1);else if(v.op==='right')e.moveCursor(0,1);else e[operations[v.op]](v.text??'');const c=e.getCursor();return {text:e.getText(),expanded:e.getExpandedText(),line:c.line,col:[...e.getLines()[c.line].slice(0,c.col)].length,pasteCounter:e.pasteCounter};});}
console.log(JSON.stringify(JSON.parse(readFileSync(0,'utf8')).map(query)));
