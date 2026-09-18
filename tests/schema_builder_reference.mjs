import { Value } from '../build/schema-reference/node_modules/typebox/build/value/index.mjs';
import {schema, encode} from './schema_builder_oracle.mjs';
let text=''; for await (const chunk of process.stdin) text+=chunk;
process.stdout.write(JSON.stringify(JSON.parse(text).map(({policy,value})=>{
  const type=schema(policy);
  return {schema:JSON.parse(JSON.stringify(type)),valid:Value.Check(type,value),converted:encode(Value.Convert(type,value))};
})));
