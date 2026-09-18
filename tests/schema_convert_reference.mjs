import { Type } from '../build/schema-reference/node_modules/typebox/build/index.mjs';
import { Value } from '../build/schema-reference/node_modules/typebox/build/value/index.mjs';
let text=''; for await (const chunk of process.stdin) text+=chunk;
const types=[Type.Boolean(),Type.Number(),Type.Integer(),Type.String(),Type.Null()];
function result(value) {
  if (typeof value==='number') {
    const b=new DataView(new ArrayBuffer(8));b.setFloat64(0,value,false);
    return {bits:[b.getUint32(0,false),b.getUint32(4,false)]};
  }
  return {value};
}
process.stdout.write(JSON.stringify(JSON.parse(text).map(({kind,value})=>result(Value.Convert(types[kind],value)))));
