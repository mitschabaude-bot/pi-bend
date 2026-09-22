import Base
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/api/transform-tool-results.bend as Repair
import ../packages/ai/src/utils/diagnostics.bend as Diagnostics
import ../packages/runtime/src/f64.bend as F

# Replay repair: every replayed tool call ends with a result, failed turns
# are not replayed, and system messages never split a call from its results.
# Template arguments must be closed, so the effectful laws fix the message
# type parameters and use a frozen clock.

def frozen(unused: Unit) -> IO(F.F64): IO.pure(F.F64, F.fromU32(0))

def Messages() -> Data: Repair.Messages(Unit, String, Unit, Unit)
def State() -> Data: Repair.State<Unit, String, Unit, Unit>

law errored_assistant_turns_are_not_replayed:
  for -P: Data
  for -A: Data
  for -G: Data
  for -D: Data
  for content: List<&2, Ai.AssistantContent<A>>
  for api: String
  for provider: String
  for model: String
  for responseModel: Maybe<&2, String>
  for responseId: Maybe<&2, String>
  for level: Maybe<&2, String>
  for diagnostics: Maybe<&2, List<&2, Diagnostics.AssistantMessageDiagnostic<G>>>
  for usage: Ai.Usage
  for deferred: Maybe<&2, Ai.DeferredHandle>
  for error: Maybe<&2, String>
  for rawReason: Maybe<&2, String>
  for endTurn: Maybe<&2, Bool>
  for timestamp: F.F64
  for output: Repair.Messages(P, A, G, D)
  {Repair.assistantState(P, A, G, D, Ai.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, Ai.Error{}, deferred, error, rawReason, endTurn, timestamp}, output) == Repair.State{Nil{}, Nil{}, Nil{}, output} : Repair.State<P, A, G, D>}

law aborted_assistant_turns_are_not_replayed:
  for -P: Data
  for -A: Data
  for -G: Data
  for -D: Data
  for content: List<&2, Ai.AssistantContent<A>>
  for api: String
  for provider: String
  for model: String
  for responseModel: Maybe<&2, String>
  for responseId: Maybe<&2, String>
  for level: Maybe<&2, String>
  for diagnostics: Maybe<&2, List<&2, Diagnostics.AssistantMessageDiagnostic<G>>>
  for usage: Ai.Usage
  for deferred: Maybe<&2, Ai.DeferredHandle>
  for error: Maybe<&2, String>
  for rawReason: Maybe<&2, String>
  for endTurn: Maybe<&2, Bool>
  for timestamp: F.F64
  for output: Repair.Messages(P, A, G, D)
  {Repair.assistantState(P, A, G, D, Ai.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, Ai.Aborted{}, deferred, error, rawReason, endTurn, timestamp}, output) == Repair.State{Nil{}, Nil{}, Nil{}, output} : Repair.State<P, A, G, D>}

law replayable_assistant_turns_track_their_tool_calls:
  for -P: Data
  for -A: Data
  for -G: Data
  for -D: Data
  for content: List<&2, Ai.AssistantContent<A>>
  for api: String
  for provider: String
  for model: String
  for responseModel: Maybe<&2, String>
  for responseId: Maybe<&2, String>
  for level: Maybe<&2, String>
  for diagnostics: Maybe<&2, List<&2, Diagnostics.AssistantMessageDiagnostic<G>>>
  for usage: Ai.Usage
  for reason: Ai.StopReason
  for deferred: Maybe<&2, Ai.DeferredHandle>
  for error: Maybe<&2, String>
  for rawReason: Maybe<&2, String>
  for endTurn: Maybe<&2, Bool>
  for timestamp: F.F64
  for output: Repair.Messages(P, A, G, D)
  for replayable: {Repair.replayable(reason) == True{} : Bool}
  {Repair.assistantState(P, A, G, D, Ai.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, reason, deferred, error, rawReason, endTurn, timestamp}, output) == Repair.State{Repair.toolCalls(A, content), Nil{}, Nil{}, Ai.Assistant{Ai.AssistantMessage{content, api, provider, model, responseModel, responseId, level, diagnostics, usage, reason, deferred, error, rawReason, endTurn, timestamp}} <> output} : Repair.State<P, A, G, D>}

law tool_results_answer_their_call:
  for -P: Data
  for -A: Data
  for -G: Data
  for -D: Data
  for id: String
  for name: String
  for content: List<&2, Ai.TextImageContent>
  for details: Maybe<&2, D>
  for usage: Maybe<&2, Ai.Usage>
  for isError: Bool
  for timestamp: F.F64
  for pending: List<&2, Ai.ToolCall<A>>
  for seen: List<&2, String>
  for held: Repair.Messages(P, A, G, D)
  for output: Repair.Messages(P, A, G, D)
  {Repair.resultState(P, A, G, D, Ai.ToolResultMessage{id, name, content, details, usage, isError, timestamp}, Repair.State{pending, seen, held, output}) == Repair.State{pending, id <> seen, held, Ai.ToolResult{Ai.ToolResultMessage{id, name, content, details, usage, isError, timestamp}} <> output} : Repair.State<P, A, G, D>}

law system_messages_wait_for_pending_results:
  for -P: Data
  for -A: Data
  for -G: Data
  for -D: Data
  for system: Ai.SystemMessage<P>
  for call: Ai.ToolCall<A>
  for pending: List<&2, Ai.ToolCall<A>>
  for seen: List<&2, String>
  for held: Repair.Messages(P, A, G, D)
  for output: Repair.Messages(P, A, G, D)
  {Repair.systemState(P, A, G, D, system, Repair.State{call <> pending, seen, held, output}) == Repair.State{call <> pending, seen, Ai.System{system} <> held, output} : Repair.State<P, A, G, D>}

law system_messages_pass_when_nothing_is_pending:
  for -P: Data
  for -A: Data
  for -G: Data
  for -D: Data
  for system: Ai.SystemMessage<P>
  for seen: List<&2, String>
  for held: Repair.Messages(P, A, G, D)
  for output: Repair.Messages(P, A, G, D)
  {Repair.systemState(P, A, G, D, system, Repair.State{Nil{}, seen, held, output}) == Repair.State{Nil{}, seen, held, Ai.System{system} <> output} : Repair.State<P, A, G, D>}

law answered_calls_are_left_alone:
  for call: Ai.ToolCall<String>
  for output: Messages()
  {Repair.appendMissing(~Unit, ~String, ~Unit, ~Unit, ~frozen, True{}, call, output) == IO.pure(Messages(), output) : IO(Messages())}

law unanswered_calls_get_an_error_result:
  for id: String
  for name: String
  for arguments: String
  for signature: Maybe<&2, String>
  for namespace: Maybe<&2, String>
  for output: Messages()
  {Repair.appendMissing(~Unit, ~String, ~Unit, ~Unit, ~frozen, False{}, Ai.ToolCall{id, name, arguments, signature, namespace}, output) == IO.pure(Messages(), Ai.ToolResult{Ai.ToolResultMessage{id, name, Ai.TextImageText{Ai.TextContent{"No result provided", None{}}} <> Nil{}, None{}, None{}, True{}, F.fromU32(0)}} <> output) : IO(Messages())}

law flush_without_pending_calls_releases_held_messages:
  for seen: List<&2, String>
  for held: Messages()
  for output: Messages()
  {Repair.flush(~Unit, ~String, ~Unit, ~Unit, ~frozen, Repair.State{Nil{}, seen, held, output}) == IO.pure(Messages(), List.append(&2, Ai.Message<Unit, String, Unit, Unit>, held, output)) : IO(Messages())}

law user_turns_release_held_messages_first:
  for user: Ai.UserMessage
  for seen: List<&2, String>
  for held: Messages()
  for output: Messages()
  {Repair.advance(~Unit, ~String, ~Unit, ~Unit, ~frozen, Ai.User{user}, Repair.State{Nil{}, seen, held, output}) == IO.pure(State(), Repair.State{Nil{}, Nil{}, Nil{}, Ai.User{user} <> List.append(&2, Ai.Message<Unit, String, Unit, Unit>, held, output)}) : IO(State())}

law assistant_turns_release_held_messages_first:
  for source: Ai.AssistantMessage<String, Unit>
  for seen: List<&2, String>
  for held: Messages()
  for output: Messages()
  {Repair.advance(~Unit, ~String, ~Unit, ~Unit, ~frozen, Ai.Assistant{source}, Repair.State{Nil{}, seen, held, output}) == IO.pure(State(), Repair.assistantState(Unit, String, Unit, Unit, source, List.append(&2, Ai.Message<Unit, String, Unit, Unit>, held, output))) : IO(State())}
