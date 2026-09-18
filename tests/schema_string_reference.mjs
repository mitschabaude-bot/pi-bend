import { GraphemeCount } from '../build/schema-reference/node_modules/typebox/build/guard/string.mjs';
let text='';for await (const chunk of process.stdin) text+=chunk;
process.stdout.write(JSON.stringify(JSON.parse(text).map(GraphemeCount)));
