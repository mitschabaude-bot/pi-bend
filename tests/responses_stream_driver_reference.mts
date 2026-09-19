import {processStream,clean} from './responses_stream_reference.mts';
let input='';for await(const chunk of process.stdin)input+=chunk;
function encodeUsage(u){const value={input:u.input,output:u.output,cacheRead:u.cacheRead,cacheWrite:u.cacheWrite,totalTokens:u.totalTokens,cost:structuredClone(u.cost)};for(const k of ['cacheWrite1h','reasoning'])if(u[k]!==undefined)value[k]=u[k];return value;}
const results=[];
for(const c of JSON.parse(input)){
 const output={content:[],responseId:'initial',stopReason:'toolUse',errorMessage:'old error',rawStopReason:'old raw',usage:{input:11,output:3,cacheRead:7,cacheWrite:2,cacheWrite1h:1,reasoning:9,totalTokens:23,cost:{input:99,output:99,cacheRead:99,cacheWrite:99,total:99}}};
 const trace=[];let reads=0,emits=0;
 const source={ [Symbol.asyncIterator](){return this;},async next(){trace.push('read');const n=reads++;if(c.mode==='ReadFails'&&n===c.index)throw Error('read failed');return n<c.events.length?{done:false,value:c.events[n]}:{done:true};},async return(){trace.push('close');if(c.mode==='CloseFails')throw Error('close failed');return {done:true};} };
 const sink={push(e){const value={type:e.type,contentIndex:e.contentIndex};for(const k of ['delta','content'])if(e[k]!==undefined)value[k]=e[k];if(e.toolCall)value.toolCall=clean(e.toolCall);value.partial={content:e.partial.content.map(clean),stopReason:e.partial.stopReason};trace.push({emit:value});if(['SinkFails','CloseFails'].includes(c.mode)&&emits===c.index)throw Error('sink failed');emits++;}};
 const options={serviceTier:c.requested??undefined};
 if(['ResolverOnly','Both','ResolverFails','PricingFails'].includes(c.mode))options.resolveServiceTier=(actual,requested)=>{trace.push({resolve:[actual??null,requested??null]});if(c.mode==='ResolverFails')throw Error('resolver failed');return 'resolved';};
 if(['PriceOnly','Both','ResolverFails','PricingFails'].includes(c.mode))options.applyServiceTierPricing=(usage,tier)=>{trace.push({price:{usage:encodeUsage(usage),tier:tier??null}});if(c.mode==='PricingFails')throw Error('pricing failed');usage.input=777;usage.cost.total=123;};
 let error;try{await processStream(source,output,sink,{cost:{input:0,output:0,cacheRead:0,cacheWrite:0}},options);}catch(e){error=e.message;}
 const message={content:output.content.map(clean),usage:encodeUsage(output.usage),stopReason:output.stopReason};for(const k of ['responseId','errorMessage','rawStopReason'])if(output[k]!==undefined)message[k]=output[k];
 const result={output:message,trace};if(error)result.error=error;results.push(JSON.stringify(result));
}
process.stdout.write(JSON.stringify(results));
