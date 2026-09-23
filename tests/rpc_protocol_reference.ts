import { PassThrough } from "node:stream";

const root = process.env.PI_MONO ?? new URL("../../../pi-mono", import.meta.url).pathname;
const { attachJsonlLineReader, serializeJsonLine } = await import(`${root}/packages/coding-agent/src/modes/rpc/jsonl.ts`);

function records(chunks: string[]): string[] {
  const stream = new PassThrough();
  const lines: string[] = [];
  attachJsonlLineReader(stream, (line) => lines.push(line));
  for (const chunk of chunks) stream.write(chunk);
  stream.destroy();
  return lines;
}

function frame(chunks: string[], pending: string): string {
  return serializeJsonLine({ records: records(chunks), pending });
}

process.stdout.write(frame(['{"a":1}\r\n{"b":2}\r\n'], ""));
process.stdout.write(frame(['{"text":"a\u2028b\u2029c"}\n'], ""));
process.stdout.write(frame(['{"a":1}'], '{"a":1}'));
process.stdout.write(frame(['{"a":', '1}\n{"b":2}'], '{"b":2}'));
process.stdout.write(serializeJsonLine({ id: "r1", type: "response", command: "abort", success: true }));
process.stdout.write(serializeJsonLine({ type: "response", command: "unknown", success: false, error: "Unknown command: unknown" }));
