import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
import assert from 'node:assert';
import {EventEmitter} from 'node:events';
import {stripTypeScriptTypes} from 'node:module';
const root=UPSTREAM + '/packages/tui/';
const code=stripTypeScriptTypes(fs.readFileSync(root+'src/stdin-buffer.ts','utf8')).replace(/^import .*;$/gm,'').replace(/^export /gm,'');
const Real=new Function('EventEmitter',code+';return StdinBuffer;')(EventEmitter);
const keys=stripTypeScriptTypes(fs.readFileSync(root+'src/keys.ts','utf8')).replace(/^export /gm,'');
const matchesKey=new Function(keys+';return matchesKey;')();
const scenarios=[];let active=[];
class Recording extends Real {
 steps=[];depth=0;
 constructor(options){super(options);scenarios.push(this.steps);active.push(this);}
 process(data){if(this.depth===0)this.steps.push(['process',Buffer.isBuffer(data)?data.toString():data]);this.depth++;try{super.process(data);}finally{this.depth--;}}
 flush(){if(this.depth===0)this.steps.push(['flush']);return super.flush();}
 clear(){if(this.depth===0)this.steps.push(['clear']);super.clear();}
}
const tests=[];let hooks=[];
function describe(_name,fn){const saved=hooks;hooks=[...hooks];fn();hooks=saved;}
function beforeEach(fn){hooks.push(fn);}
function it(name,fn){tests.push({name,fn,hooks:[...hooks]});}
const source=stripTypeScriptTypes(fs.readFileSync(root+'test/stdin-buffer.test.ts','utf8')).replace(/^import .*;$/gm,'');
new Function('assert','beforeEach','describe','it','matchesKey','StdinBuffer',source)(assert,beforeEach,describe,it,matchesKey,Recording);
for(const test of tests){for(const hook of test.hooks)await hook();await test.fn();for(const instance of active){instance.depth++;instance.destroy();}active=[];}
console.log(JSON.stringify({names:tests.map(x=>x.name),scenarios}));
