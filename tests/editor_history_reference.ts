import { UPSTREAM } from "./upstream_pin.mjs";
const { KillRing } = await import(UPSTREAM + '/packages/tui/src/kill-ring.ts');
const { UndoStack } = await import(UPSTREAM + '/packages/tui/src/undo-stack.ts');
const traces = JSON.parse(await Bun.stdin.text());
console.log(JSON.stringify(traces.map((ops: any[]) => {
 const ring = new KillRing(); let stack = new UndoStack<string>(); let saved: string[] = [];
 return ops.map(op => {
  let popped: string | undefined;
  switch(op.op) {
   case 'kill': ring.push(op.text, {prepend:!!op.prepend, accumulate:!!op.accumulate}); break;
   case 'rotate': ring.rotate(); break;
   case 'push': stack.push(op.text); break;
   case 'pop': popped = stack.pop(); break;
   case 'clear': stack.clear(); break;
   case 'save': {
    const values: string[] = []; while(stack.length) values.push(stack.pop()!);
    saved = values.reverse(); for(const value of saved) stack.push(value); break;
   }
   case 'restore': stack = new UndoStack<string>(); for(const value of saved) stack.push(value); break;
  }
  return [ring.length,ring.peek()??null,stack.length,popped??null];
 });
})));
