// Reference for tests/semver_check.py: node-semver's valid() and compare()
// from the pinned pi-mono dependency tree, over JSON [a, b] pairs on stdin.
import { UPSTREAM } from "./upstream_pin.mjs";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
const semver = createRequire(UPSTREAM + "/packages/coding-agent/package.json")("semver");
if (semver.SEMVER_SPEC_VERSION !== "2.0.0" || JSON.parse(readFileSync(UPSTREAM + "/node_modules/semver/package.json", "utf8")).version !== "7.8.5") throw new Error("unexpected semver");
const show = (text: string | null) => (text === null ? "-" : Array.from(text, (c) => c.codePointAt(0)).join(","));
for (const [a, b] of JSON.parse(readFileSync(0, "utf8")) as [string, string][]) {
	const va = semver.valid(a);
	const vb = semver.valid(b);
	console.log(`${show(va)}|${show(vb)}|${va && vb ? semver.compare(a, b) : "-"}`);
}
