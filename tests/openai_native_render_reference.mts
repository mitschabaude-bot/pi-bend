// Evaluate the pinned upstream retry implementation; no provider or network IO.
import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const source = stripTypeScriptTypes(fs.readFileSync('../pi-mono/packages/ai/src/utils/provider-retry.ts', 'utf8')).replace(/^export /gm, '');
const {abort, delay} = new Function(source + '\nreturn {abort:createAbortError, delay:validateServerRetryDelayMs};')();
let tooLong;
try { delay(1001, 1000, 'provider'); } catch (error) { tooLong = error.message; }
if (!tooLong) throw new Error('Expected actual retry validator to reject excessive delay');
console.log(JSON.stringify({abort:abort().message, delay:tooLong}));
