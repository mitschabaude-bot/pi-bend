import { Type } from '../build/schema-reference/node_modules/typebox/build/index.mjs';
const primitives=[Type.Boolean,Type.Number,Type.Integer,Type.String,Type.Null];
export function schema(p) {
  const options=p.options ?? {};
  if (p.kind==='scalar') return primitives[p.index](options);
  if (p.kind==='object') return Type.Object(Object.fromEntries(p.fields.map(([key,p,optional])=>[key,optional ? Type.Optional(schema(p)) : schema(p)])), options);
  if (p.kind==='never') return Type.Never(options);
  if (p.kind==='literal') return Type.Literal(p.value,options);
  if (p.kind==='union') return Type.Union(p.items.map(schema),options);
  if (p.kind==='array') return Type.Array(schema(p.item),p.options ?? {});
  if (p.kind==='tuple') return Type.Tuple(p.items.map(schema),options);
  return Type.Unknown(options);
}
export function encode(v) {
  if (typeof v==='number') {
    const b=new DataView(new ArrayBuffer(8));b.setFloat64(0,v,false);
    return {number:[b.getUint32(0,false),b.getUint32(4,false)]};
  }
  if (Array.isArray(v)) return {array:v.map(encode)};
  if (v!==null && typeof v==='object') return {object:Object.entries(v).map(([k,v])=>[k,encode(v)])};
  return {scalar:v};
}
