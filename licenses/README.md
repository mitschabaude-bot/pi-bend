# Dependency notices

`openai-sdk.txt` contains the Apache License 2.0 distributed with OpenAI's `openai` npm package version 6.40.0. `packages/runtime/src/line-decoder.bend` ports the behavior of its `src/internal/decoders/line.ts` (distributed as `internal/decoders/line.mjs`), using new immutable Bend storage and transitions. `packages/runtime/src/sse-chunks.bend` similarly ports `iterSSEChunks` from `src/core/streaming.ts`. Upstream repository: https://github.com/openai/openai-node. The SDK identifies its line decoder as a reimplementation of httpx's line decoder. The SDK's license is retained here; no SDK JavaScript is part of the native runtime.

`partial-json.txt` retains the license for the partial JSON dependency used as a behavioral reference by the native JSON recovery implementation.
