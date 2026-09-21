# System-owned Responses error rendering

`packages/ai/src/api/openai-responses-system-render.bend` composes the system provider's error domain with the native request renderer. System initialization, native acquisition, release, reader and disposal failures retain their own types. Recursive processing errors can contain any of these failures; the interpreter never narrows them into an application hook error or loses an initialization cause.

The `format` entry point installs the concrete initialization formatter: resolver configuration and entropy failures get their native diagnostics without an application-supplied handler. `render` additionally accepts an explicit initialization formatter for embedders. Both accept the native renderer's affine pure leaf functions, select one path without callback allocation or runtime handles, and propagate typed formatting failures. Content and terminal messages reuse their existing helpers. Concrete transport leaves and installation at the final public provider boundary remain pending.

Eight generic laws quantify reason/hook types, arbitrary leaf functions, initialization renderers and error values. They preserve initialization, acquisition and release diagnostics, establish transparency of all four recursive processing wrappers, and require the standard initialization path to use its concrete formatter for every initialization cause. They are included in the [553-law root check](proof-validation/2026-09-21-system-format-root.json), alongside 74 supporting lemmas. No unsafe source definition was added.

The runtime fixture exercises a 24-level chain of all four processing wrappers around both initialization and request errors, including typed formatting failures. It also checks release, reader and disposal dispatch. The standard formatter is checked directly and through the same 96 nested wrappers. Finite runtime execution complements the universal laws by checking emitted programs; it does not establish the behavior of concrete transport renderers or complete an upstream test suite.

```sh
BEND="$PWD/build/bend-profiles/dns-transport-teles/bend2/main.ts" sh scripts/build-pure.sh tests/openai-system-render.bend build/openai-system-render
bun build/bend-profiles/dns-transport-teles/bend2/main.ts tests/openai-system-render.bend -o build/openai-system-render.js
python3 tests/openai_system_render_check.py
```

All [36 runtime outcomes](runtime-validation/2026-09-21-system-format.json) pass on native one/four threads and Bun. The record retains source/program hashes and guarded build measurements. This validates the standard initialization handler as well as the existing custom-handler paths.
