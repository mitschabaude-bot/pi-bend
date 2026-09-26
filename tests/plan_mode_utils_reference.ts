// Reference oracle for tests/plan_mode_utils_check.py: runs pinned upstream
// examples/extensions/plan-mode/utils.ts over JSON cases on stdin.
const [utilsPath] = process.argv.slice(2);
const utils = await import(utilsPath);
const cases = JSON.parse(await new Response(Bun.stdin.stream()).text());
const results = cases.map(([fn, input, items]: [string, string, string]) => {
	switch (fn) {
		case "isSafeCommand": return utils.isSafeCommand(input);
		case "cleanStepText": return utils.cleanStepText(input);
		case "extractTodoItems": return utils.extractTodoItems(input);
		case "extractDoneSteps": return utils.extractDoneSteps(input);
		default: {
			const todos = items.split(",").map((part) => {
				const [step, completed] = part.split(":");
				return { step: Number(step), text: "Step", completed: completed === "1" };
			});
			const count = utils.markCompletedSteps(input, todos);
			return { count, completed: todos.map((t: { completed: boolean }) => t.completed) };
		}
	}
});
console.log(JSON.stringify(results));
