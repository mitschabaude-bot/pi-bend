// Transpile the pinned sources, then run them under Node's actual fs semantics.
// Bun readdirSync preserves OS order while Node sorts; resource precedence must
// be compared against Pi's Node host rather than normalizing observed results.
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
const [root,home,extraFile]=process.argv.slice(2);
const clean=(source:string)=>source.replace(/^import .*;\n/gm,'').replace(/\bexport /g,'');
const read=(file:string)=>fs.readFileSync(path.join(root,file),'utf8');
const transpiler=new Bun.Transpiler({loader:'ts'});
const source=transpiler.transformSync(['src/utils/frontmatter.ts','src/utils/paths.ts','src/core/source-info.ts','src/core/skills.ts'].map(file=>clean(read(file))).join('\n'));
const tests=transpiler.transformSync(clean(read('test/skills.test.ts')).replace(/\b__dirname\b/g,'fixtureDirectory'));
const extras=extraFile?JSON.parse(fs.readFileSync(extraFile,'utf8')):[];
const result=spawnSync('node',['tests/skills_reference.mjs'],{input:JSON.stringify({root,home,extras,source,tests}),encoding:'utf8',maxBuffer:32*1024*1024});
process.stdout.write(result.stdout);process.stderr.write(result.stderr);process.exit(result.status??1);
