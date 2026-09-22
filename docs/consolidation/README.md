# Consolidation rename tables

Each file maps `old-module.name` to the name the definition received when its module was merged into a family module (`packages/agent/src` for `renames-agent.json`, `packages/runtime/src` for the others). Names absent from a table were kept. The tables are the record for rewriting branches that still import the pre-merge modules: replace the import path with the family module and apply the table to `Alias.name` references.

| Table | Merge commit | Families |
| --- | --- | --- |
| `renames-agent.json` | 1ea2c24 | agent-loop, agent, stream-fn, types |
| `renames-dns.json` | bebc3ef | dns-message, resolver-config, dns-transport, hosts, dns-resolver, connection-driver |
| `renames-http.json` | c8e962b | socket, http-message, sse, http-response, http-exchange |
| `renames-url.json` | 799e1af | punycode, unicode, idna, url, numeric-host |
| `renames-small.json` | dfcef5f | schema, f64, json, random, utf8, text, string, calendar, bounded, timer, abort |

The first merges also suffixed binders that collided with same-module definitions with `Local`; those names were replaced by hand afterwards (see the parity record for 2026-09-22), so the tables describe definitions only.
