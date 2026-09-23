// Execute the pinned POSIX policies; production Bend does not call this oracle.
import {readFileSync} from 'node:fs';
const shell = await import(process.argv[2]+'/utils/shell.ts');
const config = await import(process.argv[2]+'/config.ts');
const cases=JSON.parse(readFileSync(process.argv[3],'utf8'));
for(const item of cases) {
  if(item.kind==='sanitize') console.log(JSON.stringify(Array.from(shell.sanitizeBinaryOutput(String.fromCodePoint(...item.codes)), c=>c.codePointAt(0))));
  else if(item.kind==='env') {
    process.env=Object.fromEntries(item.entries);
    console.log(JSON.stringify({bin:config.getBinDir(),entries:Object.entries(shell.getShellEnv())}));
  } else {
    try { console.log(JSON.stringify(shell.getShellConfig(item.custom))); }
    catch(error) { console.log(JSON.stringify({error:String(error.message)})); }
  }
}
