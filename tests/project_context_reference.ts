import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import assert from "node:assert/strict";
const [upstream, base, inputFile] = process.argv.slice(2);
const root = path.join(upstream, "packages/coding-agent");
const read = (name: string) => fs.readFileSync(path.join(root, name), "utf8");
const clean = (source: string) =>
  source.replace(/^import .*;\n/gm, "").replace(/\bexport /g, "");
const transpiler = new Bun.Transpiler({ loader: "ts" });
const footer = read("src/core/footer-data-provider.ts");
const resource = read("src/core/resource-loader.ts");
const source =
  clean(read("src/utils/paths.ts")) +
  "\n" +
  footer.slice(
    footer.indexOf("export type GitPaths"),
    footer.indexOf("/** Ask git"),
  ) +
  "\n" +
  resource.slice(
    resource.indexOf("function loadContextFileFromDir"),
    resource.indexOf("export interface DefaultResourceLoaderOptions"),
  );
const bindings = {
  ...fs,
  ...path,
  fileURLToPath,
  nodeResolvePath: path.resolve,
  homedir: () => base,
  stripBom: (value: string) => value.replace(/^\uFEFF/, ""),
  chalk: { yellow: (value: string) => value },
  console: { error: () => {} },
};
const api = new Function(
  ...Object.keys(bindings),
  transpiler.transformSync(clean(source)) +
    ";return {loadProjectContextFiles,findGitPaths};",
)(...Object.values(bindings));
const records: any[] = [];
const names: string[] = [];
let current = "supplemental";
function loadProjectContextFiles(input: any) {
  const expected = api.loadProjectContextFiles(input);
  records.push({
    name: current,
    input: { ...input, environmentCwd: process.cwd(), home: base },
    expected: { files: expected, diagnostics: [] },
  });
  return expected;
}
const allTests = read("test/resource-loader.test.ts");
const tests = allTests.slice(
  allTests.indexOf(
    '\tdescribe("loadProjectContextFiles - nested worktree dedup"',
  ),
  allTests.lastIndexOf("\n});"),
);
const prelude = `let tempDir,agentDir; let count=0; function describe(name,body){body();} function it(name,body){ tempDir=join(base,'named-'+count++);agentDir=join(tempDir,'agent');mkdirSync(agentDir,{recursive:true});named(name);body();}`;
const expect = (value: any) => ({
  toEqual: (want: any) => assert.deepEqual(value, want),
});
new Function(
  "base",
  "join",
  "mkdirSync",
  "writeFileSync",
  "loadProjectContextFiles",
  "expect",
  "named",
  transpiler.transformSync(prelude + tests),
)(
  base,
  path.join,
  fs.mkdirSync,
  fs.writeFileSync,
  loadProjectContextFiles,
  expect,
  (name: string) => {
    current = name;
    names.push(name);
  },
);
for (const input of JSON.parse(fs.readFileSync(inputFile, "utf8"))) {
  current = input.name ?? "supplemental";
  if (input.mode === "git")
    records.push({
      name: current,
      input,
      expected: api.findGitPaths(input.cwd),
    });
  else loadProjectContextFiles(input);
}
console.log(JSON.stringify({ names, records }));
