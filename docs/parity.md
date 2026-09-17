# Port status

Reference: pi 0.85.1, commit `46c9de402`. This checklist describes the requested destination, not completed features. JavaScript extension compatibility is explicitly excluded by the user.

- [ ] Native build and dependency setup
- [ ] JSON and incremental SSE parsing
- [ ] HTTPS, streaming, cancellation, timeouts, retries, proxies, WebSockets
- [ ] OpenAI OAuth credential loading, refresh and persistence
- [ ] Provider adapters and model catalog parity
- [ ] Agent loop, event ordering, steering, tool validation and cancellation
- [ ] Read, bash, edit, write, grep, find, ls tools with upstream semantics
- [ ] Project instructions, skills, prompt templates, settings and themes
- [ ] Session persistence, tree navigation, continue/resume/fork and compaction
- [ ] Print, JSON event and RPC modes; embedding interface
- [ ] Terminal editor, differential rendering, Markdown, images, shortcuts and dialogs
- [ ] Bend extension interface, discovery, hooks and custom tools/UI
- [ ] Native Linux/macOS portability; account for upstream Windows support
- [ ] Upstream-derived behavioral and terminal snapshot tests
- [ ] Live pi-bend subagent develops and tests a feature

Authentication preflight: upstream pi successfully called `openai-codex/gpt-5.6-sol` using the existing private auth file on 2026-09-17. No interactive login was required. This is not yet evidence for authentication implemented in Bend.
