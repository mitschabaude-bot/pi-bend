# Interactive tool execution display

`packages/coding-agent/src/modes/interactive/components/tool-execution.bend` retains immutable tool-call arguments, partial/final result content, error status, expansion and execution flags. Generic display uses native Text, pretty JSON and theme colors. Definition-style display uses native Box painting with fallback preview and borrowed call/result renderer callbacks. Self-rendered callbacks supply their own framing. `fromAiToolCall` and `updateFromAgent` let the transcript reducer update one retained tool row as events arrive.

`tests/tool_execution_check.py` compares 39 raw ANSI byte snapshots with upstream `f07218c4d` under a controlled colored terminal (`FORCE_COLOR=1`, `TERM=xterm-256color`, `NO_COLOR` unset). The oracle hashes upstream ToolExecutionComponent, the four built-in renderer modules, result-text normalization, theme asset, Box/Text and key-hint implementations. Cases cover generic pending/args/start/partial/success/error, fallback and custom slots, read/bash/edit/write pending/partial/final/error, read range and expanded result, bash five-line tail preview, and write ten-line preview and expansion. Build `tests/tool-execution.bend` with the File.rename-capable compiler, then run the checker on Bun and native one/four threads.

This is a partial port. The built-ins cover text output with ordinary relative paths. Read's compact docs/skill/resource labels, edit's asynchronous diff preview and result details, bash's visual-line wrapping/truncation and elapsed-time display, path hyperlinks/home shortening, result truncation metadata, custom renderer shared state/exception fallback, click-to-expand mouse routing, and image conversion/capability display remain pending. `setShowImages` retains the setting but image rendering is pending. The fixture pins colored terminal behavior; honoring `NO_COLOR` at runtime is separate.

Rendered lines are cached per component and reused until the tool state, the width or the shown elapsed time changes, as upstream's components keep their text between frames. Write previews keep upstream's highlight cache: streamed arguments highlight new lines one at a time and the first 50 lines together, complete arguments are highlighted as a whole. `tests/write_highlight_check.py` streams 19 writes (TypeScript, Python and plain text, 5 to 120 lines, CRLF, tabs, block comments and strings crossing line 50, rewritten content) in random chunks and compares all 343 previews with upstream `writeRenderers.renderCall` reusing its component:

```sh
bun build/bend-native-toolchain/bend2/main.ts tests/write-highlight.bend -o build/write-highlight.js
python3 tests/write_highlight_check.py bun build/write-highlight.js
```
