// The pinned pi-mono checkout for TypeScript/JavaScript references: PI_MONO
// when set (the Python checks export it), else the main pi-bend checkout's
// sibling found through git's common directory, as tests/upstream_pin.py
// does. The pin itself is read from upstream_pin.py and verified here, so a
// reference never silently loads another revision.
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));

function derived() {
	const common = execFileSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd: here, encoding: "utf8" }).trim();
	return path.resolve(common, "..", "..", "pi-mono");
}

export const PIN = /^PIN = '([0-9a-f]{40})'$/m.exec(readFileSync(path.join(here, "upstream_pin.py"), "utf8"))[1];
export const UPSTREAM = path.resolve(process.env.PI_MONO || derived());

const head = execFileSync("git", ["rev-parse", "HEAD"], { cwd: UPSTREAM, encoding: "utf8" }).trim();
if (head !== PIN) throw new Error(`${UPSTREAM} is at ${head}, expected ${PIN}`);
