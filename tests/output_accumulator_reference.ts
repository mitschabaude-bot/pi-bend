// Test-only execution of the pinned upstream implementation.
import { readFileSync, unlinkSync } from 'node:fs';
const { OutputAccumulator } = await import(process.argv[2]);
const cases = JSON.parse(readFileSync(process.argv[3], 'utf8'));
for (const item of cases) {
  const acc = new OutputAccumulator({maxLines:item.lines,maxBytes:item.bytes,tempFilePrefix:'pi-upstream-output-test'});
  const snapshots=[];
  for (const command of item.commands) {
    let status='ok';
    try {
      if(command==='f') acc.finish();
      else if(command==='s') acc.snapshot({persistIfTruncated:true});
      else if(command==='c') await acc.closeTempFile();
      else acc.append(Buffer.from(command,'hex'));
    } catch(error) { status='finished'; }
    const value=acc.snapshot();
    snapshots.push({status,truncation:value.truncation,last:acc.getLastLineBytes(),path:!!value.fullOutputPath});
  }
  await acc.closeTempFile();
  const value=acc.snapshot();
  snapshots.push({status:'ok',truncation:value.truncation,last:acc.getLastLineBytes(),path:!!value.fullOutputPath});
  const raw=value.fullOutputPath ? readFileSync(value.fullOutputPath).toString('hex') : null;
  if(value.fullOutputPath)unlinkSync(value.fullOutputPath);
  console.log(JSON.stringify({snapshots,raw}));
}
