// Test-only pinned ignore@7.0.8 comparison; production uses Unicode data directly.
import fs from 'node:fs';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const root=process.argv[2];
if(require(root+'/package.json').version!=='7.0.8') throw Error('expected ignore@7.0.8');
const ignore=require(root);
const tests=JSON.parse(fs.readFileSync(0,'utf8'));
process.stdout.write(JSON.stringify({
  legacy: tests.map(([pattern,path])=>ignore().add(pattern).ignores(path)),
  unicode: tests.map(([pattern,path])=>new RegExp('^(?:'+pattern+')$','iu').test(path))
}));
