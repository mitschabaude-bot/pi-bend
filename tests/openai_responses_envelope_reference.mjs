import fs from 'node:fs';
import OpenAI from '/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/openai/index.mjs';
import {getPlatformHeaders} from '/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/openai/internal/detect-platform.mjs';
const rows=JSON.parse(fs.readFileSync(0,'utf8'));
const results=[];
for(const row of rows){
 let body=row.payload;
 if(row.payloadMode==='nan')body=NaN;
 if(row.payloadMode==='infinity')body=Infinity;
 if(row.payloadMode==='negative-infinity')body=-Infinity;
 if(row.payloadMode==='nested-nan')body={data:[null,NaN]};
 const metadata={platform:getPlatformHeaders()};
 try{metadata.query=new URL(row.baseUrl+(row.baseUrl.endsWith('/')?'responses':'/responses')).search.slice(1);}catch{metadata.invalidURL=true;}
 const client=new OpenAI({apiKey:row.apiKey,adminAPIKey:null,organization:row.organization??null,project:row.project??null,webhookSecret:null,baseURL:row.baseUrl,defaultHeaders:row.client,maxRetries:0});
 client.getUserAgent=()=>row.userAgent;
 const options={method:'post',path:'/responses',body,...('timeout' in row?{timeout:row.timeout}:{})};
 const project=result=>({url:result.url,method:result.req.method,headers:Object.fromEntries(result.req.headers.entries()),body:result.req.body??null,timeout:result.timeout});
 try{
  const actual=project(await client.buildRequest(options));
  // Retain actual falsy-body omission. A separate SDK serialization probe
  // obtains its normal JSON headers for the approved present-value behavior.
  const withJSONHeaders=!body?project(await client.buildRequest({...options,body:{probe:true}})):null;
  results.push({...metadata,actual,withJSONHeaders});
 }catch(error){
  const message=String(error.message);
  const kind=message==='timeout must be an integer'?'timeout-integer':message==='timeout must be a positive integer'?'timeout-negative':message.startsWith('Could not resolve authentication method.')?'authentication':message.includes('Invalid URL')?'url':'header';
  results.push({...metadata,error:kind,diagnostic:message});
 }
}
console.log(JSON.stringify(results));
