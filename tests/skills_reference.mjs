import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import assert from "node:assert/strict";
import { parse } from "../build/reference/node_modules/yaml/dist/index.js";
import ignore from "../build/reference/node_modules/ignore/index.js";
const { root, home, extras, source, tests } = JSON.parse(fs.readFileSync(0, "utf8"));
const imports = { parse, stripBom: (s) => s.replace(/^\uFEFF/, ""), ignore, existsSync: fs.existsSync, readdirSync: fs.readdirSync, readFileSync: fs.readFileSync, statSync: fs.statSync, realpathSync: fs.realpathSync, basename: path.basename, dirname: path.dirname, join: path.join, relative: path.relative, resolve: path.resolve, nodeResolvePath: path.resolve, sep: path.sep, isAbsolute: path.isAbsolute, fileURLToPath, homedir: () => home, CONFIG_DIR_NAME: ".pi", getAgentDir: () => path.join(home, ".pi/agent") };
const api = new Function(...Object.keys(imports), source + ";return {loadSkills,loadSkillsFromDir,formatSkillsForPrompt,createSyntheticSourceInfo};")(...Object.values(imports));
const records = [];
const names = [];
const suites = [];
let current = "";
function describe(name, fn) {
  suites.push(name);
  fn();
  suites.pop();
}
function it(name, fn) {
  current = [...suites, name].join(" / ");
  names.push(current);
  try {
    fn();
  } catch (e) {
    console.error(current, records.slice(-1));
    throw e;
  }
}
function expect(value) {
  return { toBe: (want) => assert.equal(value, want), toEqual: (want) => assert.deepEqual(value, want), toHaveLength: (want) => assert.equal(value.length, want), toContain: (want) => assert.ok(value.includes(want)), toBeGreaterThanOrEqual: (want) => assert.ok(value >= want), not: { toContain: (want) => assert.ok(!value.includes(want)) } };
}
function loadSkillsFromDir(options) {
  const result = api.loadSkillsFromDir(options);
  records.push({ name: current, input: { mode: "dir", ...options }, expected: result });
  return result;
}
function loadSkills(options) {
  const result = api.loadSkills(options);
  records.push({ name: current, input: { mode: "load", ...options, home, environmentCwd: process.cwd() }, expected: result });
  return result;
}
new Function("describe", "it", "expect", "loadSkills", "loadSkillsFromDir", "formatSkillsForPrompt", "createSyntheticSourceInfo", "homedir", "join", "resolve", "fixtureDirectory", tests)(describe, it, expect, loadSkills, loadSkillsFromDir, api.formatSkillsForPrompt, api.createSyntheticSourceInfo, () => home, path.join, path.resolve, path.join(root, "test"));
current = "supplemental filesystem scenario";
for (const input of extras)
  input.mode === "dir" ? loadSkillsFromDir(input) : loadSkills(input);
console.log(JSON.stringify({ names, records }));
