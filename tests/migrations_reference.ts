// Reference for tests/migrations_check.py: the pinned upstream runMigrations
// with PI_CODING_AGENT_DIR=<agentDir>, printing its result like
// tests/migrations.bend (console output passes through).
import { UPSTREAM } from "./upstream_pin.mjs";
const [agentDir, cwd] = process.argv.slice(2);
process.env.PI_CODING_AGENT_DIR = agentDir;
const { runMigrations } = await import(UPSTREAM + "/packages/coding-agent/src/migrations.ts");
const result = runMigrations(cwd);
console.log(`migratedAuthProviders: ${result.migratedAuthProviders.join(",")}`);
console.log(`deprecationWarnings: ${result.deprecationWarnings.join(" | ")}`);
