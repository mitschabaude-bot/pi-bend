import fs from 'node:fs';
const source = fs.readFileSync('../pi-mono/packages/agent/src/agent-loop.ts', 'utf8');
const selection = source.slice(source.indexOf('async function executeToolCalls('));
const start = selection.indexOf('const toolCalls =');
const end = selection.indexOf('return executeToolCallsSequential(');
const select = new Function('currentContext', 'assistantMessage', 'config', selection.slice(start, end) + 'return "sequential"; } return "parallel";');
const termination = source.match(/function shouldTerminateToolBatch\([^\n]*\)\s*:\s*boolean \{([\s\S]*?)\n\}/)[1];
const shouldTerminate = new Function('finalizedCalls', termination);
const toolSets = [[], [{name:'a'}], [{name:'a',executionMode:'sequential'}], [{name:'a',executionMode:'parallel'},{name:'b',executionMode:'sequential'}], [{name:'a'},{name:'a',executionMode:'sequential'}], [{name:'a',executionMode:'parallel'},{name:'a',executionMode:'sequential'}], [{name:'a',executionMode:'sequential'},{name:'a',executionMode:'parallel'}]];
const callSets = [[], ['a'], ['b'], ['missing'], ['a','b'], ['b','a','a']];
const modes = [];
for (const tools of toolSets) for (const names of callSets) for (const configured of [null,'parallel','sequential']) {
  const content = names.map(name => ({type:'toolCall', name}));
  modes.push({tools, names, configured, expected:select({tools}, {content}, {toolExecution:configured ?? undefined})});
}
const terminations = [];
function visit(values, depth) {
  terminations.push({values, expected:shouldTerminate(values.map(terminate => ({result:{terminate:terminate ?? undefined}})))});
  if (depth) for (const value of [null,false,true]) visit([...values,value],depth-1);
}
visit([],4);
console.log(JSON.stringify({modes, terminations}));
