// Reference for tests/git_url_check.py: the pinned upstream parseGitUrl (with
// its hosted-git-info dependency) over the JSON array of sources on stdin,
// printed in tests/git-ssh-url.bend's differential format.
import { UPSTREAM } from "./upstream_pin.mjs";
import { readFileSync } from "node:fs";
const { parseGitUrl } = await import(UPSTREAM + "/packages/coding-agent/src/utils/git.ts");
const show = (text: string) => Array.from(text, (c) => c.codePointAt(0)).join(",");
for (const source of JSON.parse(readFileSync(0, "utf8")) as string[]) {
	const r = parseGitUrl(source);
	console.log(r === null ? "null" : `${show(r.repo)}|${show(r.host)}|${show(r.path)}|${r.ref === undefined ? "-" : show(r.ref)}|${r.pinned}`);
}
