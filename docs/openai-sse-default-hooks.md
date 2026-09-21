# Native SSE default hooks

`openai-sse-default-hooks` owns the two callbacks borrowed by the native scoped SSE reader. Malformed JSON emits the SDK's two diagnostic messages to stderr, preserving the payload and current block's raw line contents/order. Raw lines use compact JSON string-list formatting instead of JavaScript console inspection. Both SDK diagnostic targets use stderr under this default policy; applications can still supply their own `SSE.Hooks`. API-error payloads do not produce JSON-parse diagnostics, and no diagnostic history is retained by these callbacks.

The default abort notification has no additional effect. This default is for the owning native reader: its source closes the response/fetch scope before invoking the notification. Aborting the caller's signal at that point would be incorrect. Generic readers needing an active controller notification must supply the appropriate hook. Disposal retires both callback factories after their borrowers finish.

Five [standalone laws](proof-validation/2026-09-21-sse-default-hooks-standalone.json) cover arbitrary diagnostic payloads/raw lines/targets, API-error exclusion, preservation of raw-line count, borrowing and callback disposal order. They are not yet registered in the root gate. No unsafe declaration was added.

The [runtime record](runtime-validation/2026-09-21-sse-default-hooks.json) covers 48 owner lifetimes across plain and audited native one/four-thread and Bun builds. It checks both logger targets, Unicode and escaped raw lines, empty diagnostics, API-error exclusion, repeated abort notifications and a still-live independent caller signal. All audited channels and parked IO finish at zero. These checks validate the hook module; installation in the default provider factory remains separate work.
