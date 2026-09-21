# Recursive native Responses diagnostics

`packages/ai/src/api/openai-responses-native-render.bend` interprets the immutable native session error tree. It reuses preparation, envelope, retry, content and terminal diagnostic helpers. Payload, response-hook, retry and streaming wrappers preserve the primary failure; cleanup failures and retry metadata stay in the original typed value but do not replace its displayed diagnostic. Rendering does not drive retry policy.

The `Leaves` record contains affine pure functions for application hooks, transport attempts, reader, disposal and release errors. The interpreter consumes only the selected function. No callback server, object inspection or mutable registry is involved. Leaf formatting failures remain typed rather than becoming an invented fallback message. This component composes recursive presentation; the concrete native transport leaves and system-provider boundary still need assembly.

[Eight generic laws](proof-validation/2026-09-21-native-render-standalone.json) quantify arbitrary error types, leaf functions, nested causes, response cleanup results and retry metadata. They preserve primary diagnostics through each wrapper. Three deliberately incorrect implementations typecheck but fail their contracts: losing a payload cause, displaying cleanup instead of the response-hook failure, and displaying retry metadata instead of the original failure. These laws are standalone and are not counted in the currently running expanded root gate. Existing imported runtime definitions produce eighteen specialized unsafe annotations; no new unsafe source definition was added.

The runtime fixture complements the laws by exercising emitted programs, affine leaf selection and finite recursion. It checks a 32-level chain of three nested wrappers, typed formatting failure through that same chain, retry metadata precedence, nested processing callbacks, reader/disposal/release dispatch and their typed failures, envelope diagnostics and introduced retry messages. `tests/openai_native_render_reference.mts` evaluates the pinned pi retry implementation for abort and excessive-delay text; remaining expectations are native typed-routing contracts. These executions are not proofs for all nesting depths and do not complete an upstream suite.

```sh
BEND="$PWD/build/bend-profiles/dns-transport-teles/bend2/main.ts" sh scripts/build-pure.sh tests/openai-native-render.bend build/openai-native-render
bun build/bend-profiles/dns-transport-teles/bend2/main.ts tests/openai-native-render.bend -o build/openai-native-render.js
python3 tests/openai_native_render_check.py
```

All [42 diagnostic outcomes](runtime-validation/2026-09-21-native-render.json) pass across native one/four threads and Bun. The [compiler record](bend-issues/2026-09-21-native-render-compiler.json) records source/program hashes and guarded emission/build measurements. This fixture uses the accepted isolated compiler, with no experimental lifetime change.
