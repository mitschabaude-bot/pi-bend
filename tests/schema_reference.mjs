// Test-only oracle, pinned to pi-ai's TypeBox dependency. Never used at runtime.
import { Compile } from '../build/schema-reference/node_modules/typebox/build/compile/index.mjs';
let input = '';
for await (const chunk of process.stdin) input += chunk;
const { schemas, values } = JSON.parse(input);
process.stdout.write(JSON.stringify(schemas.map(schema => {
  const validator = Compile(schema);
  return values.map(value => validator.Check(value));
})));
