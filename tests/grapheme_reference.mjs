import fs from 'node:fs';
if(process.versions.unicode!=='17.0')throw new Error(`Unicode17 oracle required; Node has ${process.versions.unicode}`);
const segmenter=new Intl.Segmenter('en',{granularity:'grapheme'});
console.log(JSON.stringify(JSON.parse(fs.readFileSync(0,'utf8')).map(text=>Array.from(segmenter.segment(text),item=>item.segment))));
