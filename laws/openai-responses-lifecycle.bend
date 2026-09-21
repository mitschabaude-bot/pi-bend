import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/api/openai-responses-lifecycle.bend as Life
import ../packages/ai/src/api/openai-responses-driver.bend as Driver
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/f64.bend as F
import ../packages/ai/src/utils/diagnostics.bend as D

law successful_event_retains_message:
  for -A: Data
  for -G: Data
  for -E: Data
  for reason: T.DoneReason
  for output: T.AssistantMessage<A, G>
  {Life.event(A, G, E, Life.Successful{reason, output}) == T.StreamDone{reason, output} : T.AssistantMessageEvent<A, G>}

law failed_event_retains_message:
  for -A: Data
  for -G: Data
  for -E: Data
  for reason: T.ErrorReason
  for output: T.AssistantMessage<A, G>
  for cause: Life.Failure<E>
  {Life.event(A, G, E, Life.Failed{reason, output, cause}) == T.StreamError{reason, output} : T.AssistantMessageEvent<A, G>}

law cancellation_precedes_stop_reason:
  for -E: Data
  for reason: T.StopReason
  for detail: Maybe<&2, String>
  {Life.check(E, True{}, reason, detail) == Fail{Life.RequestAborted{}} : Result<&2, &2, Life.Failure<E>, T.DoneReason>}

law stop_retains_terminal_kind:
  for -E: Data
  for detail: Maybe<&2, String>
  {Life.check(E, False{}, T.Stop{}, detail) == Done{T.DoneStop{}} : Result<&2, &2, Life.Failure<E>, T.DoneReason>}

law length_retains_terminal_kind:
  for -E: Data
  for detail: Maybe<&2, String>
  {Life.check(E, False{}, T.Length{}, detail) == Done{T.DoneLength{}} : Result<&2, &2, Life.Failure<E>, T.DoneReason>}

law tool_use_retains_terminal_kind:
  for -E: Data
  for detail: Maybe<&2, String>
  {Life.check(E, False{}, T.ToolUse{}, detail) == Done{T.DoneToolUse{}} : Result<&2, &2, Life.Failure<E>, T.DoneReason>}

law deferred_retains_terminal_kind:
  for -E: Data
  for detail: Maybe<&2, String>
  {Life.check(E, False{}, T.Deferred{}, detail) == Done{T.DoneDeferred{}} : Result<&2, &2, Life.Failure<E>, T.DoneReason>}

law pending_cannot_succeed:
  for -E: Data
  for detail: Maybe<&2, String>
  {Life.check(E, False{}, T.Pending{}, detail) == Fail{Life.MissingStopReason{}} : Result<&2, &2, Life.Failure<E>, T.DoneReason>}

law failure_update_last_wins:
  for -A: Data
  for -G: Data
  for output: T.AssistantMessage<A, G>
  for firstAborted: Bool
  for firstDetail: String
  for lastAborted: Bool
  for lastDetail: String
  {Life.withFailure(A, G, Life.withFailure(A, G, output, firstAborted, firstDetail), lastAborted, lastDetail) == Life.withFailure(A, G, output, lastAborted, lastDetail) : T.AssistantMessage<A, G>}

law existing_failure_survives_cancellation:
  for -A: Data
  for -G: Data
  for -E: Data
  for output: T.AssistantMessage<A, G>
  for aborted: Bool
  for render: E -> String
  for cause: Life.Failure<E>
  {Life.complete(A, G, E, output, aborted, render, Some{cause}) == Life.failed(A, G, E, output, aborted, render, cause) : Life.Terminal<A, G, E>}

law primary_failure_precedes_cleanup:
  for -E: Data
  for cause: E
  for cleanup: Maybe<&2, E>
  {Life.processingFailure(E, Some{cause}, cleanup) == Some{Life.ProcessingFailure{cause}} : Maybe<&2, Life.Failure<E>>}

law cleanup_failure_cannot_succeed:
  for -E: Data
  for cause: E
  {Life.processingFailure(E, None{}, Some{cause}) == Some{Life.CleanupFailure{cause}} : Maybe<&2, Life.Failure<E>>}

law failed_delivery_retains_primary:
  for -A: Data
  for -G: Data
  for -E: Data
  for reason: T.ErrorReason
  for output: T.AssistantMessage<A, G>
  for primary: Life.Failure<E>
  for aborted: Bool
  for render: E -> String
  for cause: E
  {Life.deliveryFailed(A, G, E, Life.Failed{reason, output, primary}, aborted, render, cause) == Life.Failed{reason, output, primary} : Life.Terminal<A, G, E>}

law close_precedes_run_result:
  for -A: Data
  for -G: Data
  for -E: Data
  for emit: C.Callback<T.AssistantMessageEvent<A, G>, Result<&2, &2, E, Unit>>
  for aborted: C.Callback<Unit, Bool>
  for finish: C.Callback<T.AssistantMessage<A, G>, Unit>
  for terminal: Life.Terminal<A, G, E>
  for cleanup: Maybe<&2, E>
  for delivery: Maybe<&2, E>
  {Driver.close(A, G, E, Driver.Effects{emit, aborted, finish}, terminal, cleanup, delivery) == IO.bind(Unit, Life.RunResult<A, G, E>, C.call(T.AssistantMessage<A, G>, Unit, finish, Life.message(A, G, E, terminal)), ignored => IO.pure(Life.RunResult<A, G, E>, Life.RunResult{terminal, cleanup, delivery})) : IO(Life.RunResult<A, G, E>)}

law failure_preserves_unrelated_fields:
  for -A: Data
  for -G: Data
  for content: List<&2, T.AssistantContent<A>>
  for api: String
  for provider: String
  for model: String
  for responseModel: Maybe<&2, String>
  for responseId: Maybe<&2, String>
  for thinking: Maybe<&2, String>
  for diagnostics: Maybe<&2, List<&2, D.AssistantMessageDiagnostic<G>>>
  for usage: T.Usage
  for stop: T.StopReason
  for deferred: Maybe<&2, T.DeferredHandle>
  for error: Maybe<&2, String>
  for raw: Maybe<&2, String>
  for endTurn: Maybe<&2, Bool>
  for timestamp: F.F64
  for aborted: Bool
  for detail: String
  {Life.withFailure(A, G, T.AssistantMessage{content, api, provider, model, responseModel, responseId, thinking, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}, aborted, detail) == T.AssistantMessage{content, api, provider, model, responseModel, responseId, thinking, diagnostics, usage, Life.stopReason(aborted), deferred, Some{detail}, raw, endTurn, timestamp} : T.AssistantMessage<A, G>}
