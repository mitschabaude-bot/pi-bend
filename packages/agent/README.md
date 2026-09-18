# pi-agent library port

Reference: pi-mono `46c9de402`, `packages/agent`. This is a partial library port, separate from the bootstrap CLI. The full agent executor and its upstream behavior suite remain pending.

`src/types.bend` preserves the typed tool, message, event, context, configuration and hook interfaces. Ordinary records and message/tool lists are immutable values. Custom messages and argument/result types are explicit generic parameters. Reusable callbacks, cancellation and running-agent state are effectful resources; they are not hidden inside ordinary data to reproduce JavaScript aliasing.

`toTool` projects an executable tool to its declaration without invoking callbacks. Argument preparation returns an original or replaced call, preserving metadata while allowing different raw/prepared argument types. Before-tool hooks return `BeforeToolCallUpdate` with explicit arguments, context and an optional decision. This preserves the ability to change execution arguments without revalidation. Integrating that update into the complete executor remains pending.

`src/agent-loop.bend` implements parts of the loop: tool selection and execution policy, argument preparation, result merging/projection, after-tool hook finalization, awaited event emission, truncated-call failures, completion handling, queue polling, stop/next-turn hooks, context conversion, API-key resolution and injected assistant request/stream consumption. Pure transformations return updated values. The running request owns a synchronized context cell; emitted messages are immutable snapshots. Listener and hook failures use typed `Result` values and short-circuit subsequent work.

After-tool overrides use `Maybe`: absent fields retain their old values, while supplied fields replace them. Next-turn updates return context/messages/model/thinking changes explicitly. Costs, tool details, headers and configurations require no object disposal. Callback handles and running synchronization resources still require explicit lifetime management.

Run `sh tests/native-agent.sh` for request sequencing, retained event snapshots, queue/hook transitions, typed preparation, awaited emission, truncated failures and completion paths on one and four threads. Supplemental upstream-source comparisons remain in `tool_batch_vectors.py`, `tool_selection_vectors.py`, `before_tool_decision_vectors.py`, `turn_update_vectors.py`, `tool_result_vectors.py` and `failed_turn_vectors.py`. Type/interface checks are in `agent_types.py`, `loop_config_types.py`, `tool_preparation_types.py` and `tool_result_message.py`.

See [native Bend decisions](../../docs/native-bend.md) for approved behavior changes and retired compatibility fixtures. These tests do not establish a complete agent loop, tool scheduler, extension runtime or provider implementation.


`finalizeExecutedToolCall` now awaits the configured after-tool hook, supplies the original call and validated arguments, applies optional overrides and turns hook errors into error tool results. Generic embeddings provide an empty details value and a pure error renderer; JSON-detail embeddings use an empty native dictionary. Nine native cases verify successful/error executions, absent hooks/returns, termination overrides, error conversion and exactly-once invocation. Channel gates verify that asynchronous hooks settle before finalization returns, without timing assumptions.

`createAgentStream` now specializes the generic stream for agent events and final message histories. Agent-end settles the history independently of buffered event consumption; late pushes are ignored. `disposeAgentStream` releases its owned predicate/extractor callbacks after iterator users retire. The public loop entry points and complete executor remain pending.
