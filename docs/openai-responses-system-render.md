# System-owned Responses error rendering

`packages/ai/src/api/openai-responses-system-render.bend` composes the system provider's error domain with the native request renderer. System initialization, native acquisition, release, reader and disposal failures retain their own types. Recursive processing errors can contain any of these failures; the interpreter never narrows them into an application hook error or loses an initialization cause.

The interpreter accepts the native renderer's affine pure leaf functions and a pure initialization renderer. It selects one path without callback allocation or runtime handles. Typed formatting failures propagate unchanged. Content and terminal messages reuse their existing helpers. This is presentation composition; concrete initialization and transport diagnostics and installation at the final public provider boundary remain pending.

Seven generic laws quantify reason/hook types, arbitrary leaf functions, initialization renderers and error values. They preserve initialization, acquisition and release diagnostics and establish transparency of all four recursive processing wrappers. They remain standalone, outside the currently running root gate. No unsafe source definition was added; existing imported definitions produce twenty-three specialized annotations in this proof entry.

The runtime fixture exercises a 24-level chain of all four processing wrappers around both initialization and request errors, including typed formatting failures. It also checks release, reader and disposal dispatch. Finite runtime execution complements the universal laws by checking the emitted programs; it does not establish the behavior of concrete transport renderers or complete an upstream test suite.

```sh
BEND="$PWD/build/bend-profiles/dns-transport-teles/bend2/main.ts" sh scripts/build-pure.sh tests/openai-system-render.bend build/openai-system-render
bun build/bend-profiles/dns-transport-teles/bend2/main.ts tests/openai-system-render.bend -o build/openai-system-render.js
python3 tests/openai_system_render_check.py
```

All [30 runtime outcomes](runtime-validation/2026-09-21-system-render.json) pass on native one/four threads and Bun. The [standalone proof record](proof-validation/2026-09-21-system-render-standalone.json) also records two type-correct cause-erasure mutations failing their intended initialization/request contracts. [Build evidence](bend-issues/2026-09-21-system-render-compiler.json) retains source/program hashes and guarded measurements.

Proof integration update: the component laws are now included in the [552-law root check](proof-validation/2026-09-21-diagnostic-root.json), alongside 74 supporting lemmas. Earlier standalone counts and historical validation descriptions above do not limit their current registration.
