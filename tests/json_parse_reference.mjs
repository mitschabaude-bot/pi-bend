let input='';for await(const chunk of process.stdin)input+=chunk;
const encode=value=>{
 if(value===null)return {null:true};
 if(typeof value==='number'){const bytes=new DataView(new ArrayBuffer(8));bytes.setFloat64(0,value);return {number:[bytes.getUint32(0),bytes.getUint32(4)]};}
 if(typeof value==='string')return {text:value};
 if(typeof value==='boolean')return {boolean:value};
 if(Array.isArray(value))return {array:value.map(encode)};
 return {object:Object.entries(value).map(([key,v])=>[key,encode(v)])};
};
process.stdout.write(JSON.stringify(JSON.parse(input).map(text=>{try{return {ok:true,value:encode(JSON.parse(text))}}catch{return {ok:false}}})));
