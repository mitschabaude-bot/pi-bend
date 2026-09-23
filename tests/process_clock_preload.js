// Test-only control of the hosted clock; production uses the actual Date API.
const ActualDate=globalThis.Date;
const epoch=process.env.BEND_CLOCK_EPOCH;
if(epoch!==undefined) globalThis.Date=class extends ActualDate {
  constructor(...args){super(...(args.length?args:[Number(epoch)*1000+123]));}
};
