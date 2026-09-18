import { Value } from '../build/schema-reference/node_modules/typebox/build/value/index.mjs';
import {schema, encode} from './schema_builder_oracle.mjs';
let text=''; for await (const chunk of process.stdin) text+=chunk;
process.stdout.write(JSON.stringify(JSON.parse(text).map(({policy,value})=>encode(Value.Convert(schema(policy),value)))));
