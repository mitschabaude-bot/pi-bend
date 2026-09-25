import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const root=process.argv[2],{eastAsianWidth}=await import(resolve(process.argv[3])),transpiler=new Bun.Transpiler({loader:'ts'});
function source(path:string){return readFileSync(resolve(root,path),'utf8');}
const editor=source('packages/tui/src/components/editor.ts');assert.equal(createHash('sha256').update(editor).digest('hex'),'241695859d48f49c6aaba9b9cfc14c6cd28639c6c247adb4fe2c202a9e2c6e20');
const transform=(s:string)=>transpiler.transformSync(s.replace(/^import[\s\S]*?from [^;]+;\n/gm,'')).replace(/\bexport /g,'');
const utils=transform(source('packages/tui/src/utils.ts'));
const u=new Function('eastAsianWidth',utils+';return {visibleWidth,cjkBreakRegex,autocompleteBoundaryRegex,autocompleteSeparatorRegex,isWhitespaceChar,getGraphemeSegmenter,getWordSegmenter,sliceByColumn}')(eastAsianWidth);
const KillRing=new Function(transform(source('packages/tui/src/kill-ring.ts'))+';return KillRing')();
const UndoStack=new Function(transform(source('packages/tui/src/undo-stack.ts'))+';return UndoStack')();
const Editor=new Function(...Object.keys(u),'KillRing','UndoStack','CURSOR_MARKER',transform(editor)+';return Editor')(...Object.values(u),KillRing,UndoStack,"\x1b_pi:c\x07");
function query(v:any){const e=new Editor({requestRender(){},terminal:{rows:v.rows}},{borderColor:(s:string)=>'<'+s+'>',selectList:{}},{paddingX:v.padding});e.setText(v.text);e.focused=v.focused;e.state.cursorLine=v.line;e.state.cursorCol=[...e.getLines()[v.line]].slice(0,v.col).join('').length;return e.render(v.width);}
console.log(JSON.stringify(JSON.parse(readFileSync(0,'utf8')).map(query)));
