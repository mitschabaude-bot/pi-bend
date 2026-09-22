// Invoke the pinned upstream implementation directly; no reimplemented oracle.
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { createHash } from 'node:crypto';
const source = process.env.PI_MONO ?? '/home/agent/code/pi-mono';
// Exclude unused IO/diff-rendering imports; execute the original pure source.
const original=readFileSync(`${source}/packages/coding-agent/src/core/tools/edit-diff.ts`,'utf8');
if(createHash('sha256').update(original).digest('hex')!=='f85a9809eb44b9828236050cf38a8e45933e5cfd583a186e9a0e55a664dd3e8d') throw Error('Unexpected edit-diff.ts revision; expected pinned46c9de402');
const code=original.split('/** Generate a standard unified patch. */')[0].replace(/^import .*;\n/gm,'');
const edit=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(code)).toString('base64'));
const rows = JSON.parse(readFileSync(0,'utf8'));
function points(value: string) { return [...value].map(c => c.codePointAt(0)).join(','); }
for (const row of rows) {
  try {
    const [kind, ...args] = row;
    switch(kind) {
      case 'n': console.log(points(args[0].normalize('NFKC'))); break;
      case 'f': console.log(points(edit.normalizeForFuzzyMatch(args[0]))); break;
      case 'l': console.log([edit.detectLineEnding(args[0]), edit.normalizeToLF(args[0]), edit.restoreLineEndings(...args)].map(points).join('|')); break;
      case 'm': {
        const result = edit.fuzzyFindText(...args);
        if(!result.found) console.log(`missing|${points(result.contentForReplacement)}`);
        else {
          // Bend positions refer to characters; translate reference UTF-16 offsets.
          const start=[...result.contentForReplacement.slice(0,result.index)].length;
          const size=[...result.contentForReplacement.slice(result.index,result.index+result.matchLength)].length;
          console.log(`${start}|${size}|${result.usedFuzzyMatch ? "True" : "False"}|${points(result.contentForReplacement)}`);
        }
        break;
      }
      case 'e': {
        const result=edit.applyEditsToNormalizedContent(args[0],args[1],'file.txt');
        console.log(`ok|${points(result.baseContent)}|${points(result.newContent)}`);break;
      }
      case 'p': {
        const [original,base,replacements]=args;
        const offset=(n)=>[...base].slice(0,n).join('').length+Math.max(0,n-[...base].length);
        const translated=replacements.map(({matchIndex,matchLength,newText})=>({
          matchIndex:offset(matchIndex),
          matchLength:offset(matchIndex+matchLength)-offset(matchIndex),newText
        }));
        console.log(`ok|${points(edit.applyReplacementsPreservingUnchangedLines(original,base,translated))}`);break;
      }
    }
  } catch(error) { console.log(`error|${error.message}`); }
}
