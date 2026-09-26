// A minimal node:test stand-in for executing original upstream test files
// whose implementation imports were redirected to native adapters. Tests keep
// their full describe/it names; `pending` names are listed by the runner with
// the reason they are not executed yet, and never count as passed.
type Body = (context: Context) => unknown;
type Hook = () => unknown;
type Options = { skip?: boolean | string; timeout?: number };
type Entry = { name: string; body: Body; skip: boolean; before: Hook[]; after: Hook[] };

class Context {
	private cleanups: Hook[] = [];
	after(hook: Hook) {
		this.cleanups.push(hook);
	}
	get mock(): never {
		throw new Error("node:test mocks are not provided by the original-test harness");
	}
	async cleanup() {
		for (const hook of this.cleanups.reverse()) await hook();
	}
}

const scopes: { name: string; skip: boolean; before: Hook[]; after: Hook[] }[] = [{ name: "", skip: false, before: [], after: [] }];
const entries: Entry[] = [];

function split(options: Options | Body | undefined, body: Body | undefined): [Options, Body | undefined] {
	return typeof options === "function" ? [{}, options] : [options ?? {}, body];
}

export function describe(name: string, options?: Options | (() => void), body?: () => void) {
	const [opts, fn] = split(options as Options, body as Body);
	scopes.push({ name, skip: Boolean(opts.skip) || scopes.at(-1)!.skip, before: [], after: [] });
	(fn as () => void)?.();
	scopes.pop();
}

export function it(name: string, options?: Options | Body, body?: Body) {
	const [opts, fn] = split(options, body);
	const path = [...scopes.slice(1).map((scope) => scope.name), name].join(" > ");
	entries.push({
		name: path,
		body: fn ?? (() => {}),
		skip: Boolean(opts.skip) || scopes.at(-1)!.skip,
		before: scopes.flatMap((scope) => scope.before),
		after: scopes.toReversed().flatMap((scope) => scope.after),
	});
}
export const test = it;
export const beforeEach = (hook: Hook) => scopes.at(-1)!.before.push(hook);
export const afterEach = (hook: Hook) => scopes.at(-1)!.after.push(hook);
export const before = (hook: Hook) => hook();
export const after = (hook: Hook) => scopes.at(-1)!.after.push(hook);

export type Outcome = { passed: string[]; pending: string[]; failed: [string, unknown][] };

// Runs every collected test; tests `pending` names (by exact name, or by
// describe prefix ending in " > ") must exist and are not run.
export async function run(pending: string[]): Promise<Outcome> {
	const outcome: Outcome = { passed: [], pending: [], failed: [] };
	const held = (name: string) => pending.some((p) => (p.endsWith(" > ") ? name.startsWith(p) : name === p));
	for (const p of pending) {
		if (!entries.some((entry) => held(entry.name) && (p.endsWith(" > ") ? entry.name.startsWith(p) : entry.name === p))) throw new Error(`pending test not found: ${p}`);
	}
	for (const entry of entries.splice(0)) {
		if (entry.skip) throw new Error(`upstream skips ${entry.name}`);
		if (held(entry.name)) {
			outcome.pending.push(entry.name);
			continue;
		}
		const context = new Context();
		try {
			for (const hook of entry.before) await hook();
			await entry.body(context);
			outcome.passed.push(entry.name);
		} catch (error) {
			outcome.failed.push([entry.name, error]);
		} finally {
			await context.cleanup();
			for (const hook of entry.after) await hook();
		}
	}
	return outcome;
}
