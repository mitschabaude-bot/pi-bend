import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/api/openai-responses-stream.bend as D
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/f64.bend as F
import ../packages/ai/src/utils/diagnostics.bend as Diagnostics

# Terminal handling of a Responses stream: which response status settles
# which stop reason, and what a terminal failure suppresses.

law response_service_tier_overrides_the_request:
  for tier: String
  for requested: Maybe<&2, String>
  {D.resolveServiceTier(Some{tier}, requested) == Some{tier} : Maybe<&2, String>}

law absent_response_service_tier_uses_the_request:
  for requested: Maybe<&2, String>
  {D.resolveServiceTier(None{}, requested) == requested : Maybe<&2, String>}

# A terminal error from backfilling the output items is final: usage is
# neither priced nor is a stop reason mapped afterwards.
law terminal_failure_suppresses_pricing_and_stop_mapping:
  for model: T.Model<Unit>
  for requested: Maybe<&2, String>
  for response: Maybe<&2, String>
  for status: Maybe<&2, String>
  for reason: Maybe<&2, String>
  for state: D.State<Unit>
  for error: D.TerminalError
  {D.priced(~Unit, ~Unit, ~D.defaultResolveServiceTier, ~(D.noServiceTierPricing(Unit)), model, requested, response, status, reason, D.Terminal{state, Some{error}}) == D.Terminal{state, Some{error}} : D.Terminal<Unit>}

law max_output_truncation_is_a_length_stop:
  {D.mapStopReason(Some{"incomplete"}, Some{"max_output_tokens"}) == Done{D.MappedStop{T.Length{}, None{}}} : Result<&2, &2, D.TerminalError, D.MappedStop>}

law tool_calls_promote_a_plain_stop:
  {D.toolStop(T.Stop{}, True{}) == T.ToolUse{} : T.StopReason}

law tool_calls_never_change_other_stops:
  for tool: Bool
  {D.toolStop(T.Length{}, tool) == T.Length{} : T.StopReason}

law error_stops_ignore_tool_calls:
  for tool: Bool
  {D.toolStop(T.Error{}, tool) == T.Error{} : T.StopReason}

# A stop mapping replaces only the stop reason and error message.
law stop_mapping_preserves_message_fields:
  for -G: Data
  for content: List<&2, T.AssistantContent<V.Value>>
  for api: T.Api()
  for provider: T.ProviderId()
  for model: String
  for responseModel: Maybe<&2, String>
  for responseId: Maybe<&2, String>
  for thinking: Maybe<&2, String>
  for diagnostics: Maybe<&2, List<&2, Diagnostics.AssistantMessageDiagnostic<G>>>
  for usage: T.Usage
  for stop: T.StopReason
  for deferred: Maybe<&2, T.DeferredHandle>
  for error: Maybe<&2, String>
  for raw: Maybe<&2, String>
  for endTurn: Maybe<&2, Bool>
  for timestamp: F64
  for reason: T.StopReason
  for message: Maybe<&2, String>
  {D.withStop(G, T.AssistantMessage{content, api, provider, model, responseModel, responseId, thinking, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}, D.MappedStop{reason, message}) == T.AssistantMessage{content, api, provider, model, responseModel, responseId, thinking, diagnostics, usage, D.toolStop(reason, D.hasToolCall(content)), deferred, message, raw, endTurn, timestamp} : T.AssistantMessage<V.Value, G>}

law end_without_terminal_response_is_an_error:
  {D.endOfStream(False{}) == Some{D.MissingTerminalResponse{}} : Maybe<&2, D.TerminalError>}
