import { readFileSync } from "node:fs";
const { stripAnsi } = await import(process.argv[2] + "/utils/ansi.ts");
for (const value of JSON.parse(readFileSync(process.argv[3], "utf8"))) {
  console.log(JSON.stringify(stripAnsi(value)));
}
