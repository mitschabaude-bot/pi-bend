import Base
import ../packages/ai/src/api/openai-sse.bend as Sse
import ../packages/runtime/src/sse.bend as Event
import ../packages/runtime/src/json.bend as Json
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/schema-value.bend as V

# The SDK's dispatch policy for Responses SSE frames: a `[DONE]` marker ends
# delivery but not draining, `thread.*` events bypass error detection, and an
# `error` field rejects the stream only when it is JS-truthy.

law done_marker_suppresses_later_frames:
  for synthesize: Bool
  for event: Event.ServerSentEvent
  {Sse.step(Sse.DoneMarker{}, synthesize, event) == Sse.Skip{Sse.DoneMarker{}} : Sse.Step}

law done_prefix_enters_done_state:
  for synthesize: Bool
  for name: Maybe<&2, String>
  for raw: List<&2, String>
  {Sse.step(Sse.Receiving{}, synthesize, Event.ServerSentEvent{name, "[DONE]", raw}) == Sse.Skip{Sse.DoneMarker{}} : Sse.Step}

law thread_events_bypass_error_detection:
  for synthesize: Bool
  for event: Maybe<&2, String>
  for data: String
  for raw: List<&2, String>
  for value: V.Value
  {Sse.parsed(True{}, synthesize, event, data, raw, Done{value}) == Sse.YieldMessage{Sse.EventMessage{event, value}} : Sse.Step}

law thread_event_json_failures_target_the_console:
  for synthesize: Bool
  for event: Maybe<&2, String>
  for data: String
  for raw: List<&2, String>
  for cause: Json.ParseError
  {Sse.parsed(True{}, synthesize, event, data, raw, Fail{cause}) == Sse.Reject{Sse.InvalidJson{cause, data, raw, Sse.ConsoleLogger{}}} : Sse.Step}

law data_json_failures_target_the_client_logger:
  for synthesize: Bool
  for event: Maybe<&2, String>
  for data: String
  for raw: List<&2, String>
  for cause: Json.ParseError
  {Sse.parsed(False{}, synthesize, event, data, raw, Fail{cause}) == Sse.Reject{Sse.InvalidJson{cause, data, raw, Sse.ClientLogger{}}} : Sse.Step}

law null_error_field_is_a_message:
  for synthesize: Bool
  for event: Maybe<&2, String>
  for data: V.Value
  {Sse.checkedError(Some{V.Null{}}, synthesize, event, data) == Sse.deliverMessage(synthesize, event, data) : Sse.Step}

law false_error_field_is_a_message:
  for synthesize: Bool
  for event: Maybe<&2, String>
  for data: V.Value
  {Sse.checkedError(Some{V.Boolean{False{}}}, synthesize, event, data) == Sse.deliverMessage(synthesize, event, data) : Sse.Step}

law empty_text_error_field_is_a_message:
  for synthesize: Bool
  for event: Maybe<&2, String>
  for data: V.Value
  {Sse.checkedError(Some{V.Text{""}}, synthesize, event, data) == Sse.deliverMessage(synthesize, event, data) : Sse.Step}

law object_error_field_rejects_the_stream:
  for synthesize: Bool
  for event: Maybe<&2, String>
  for data: V.Value
  for fields: R.Record<V.Value>
  {Sse.checkedError(Some{V.ObjectValue{fields}}, synthesize, event, data) == Sse.Reject{Sse.ApiErrorPayload{V.ObjectValue{fields}}} : Sse.Step}

law array_error_field_rejects_the_stream:
  for synthesize: Bool
  for event: Maybe<&2, String>
  for data: V.Value
  for items: List<&2, V.Value>
  {Sse.checkedError(Some{V.ArrayValue{items}}, synthesize, event, data) == Sse.Reject{Sse.ApiErrorPayload{V.ArrayValue{items}}} : Sse.Step}

law nonempty_text_error_field_rejects_the_stream:
  for synthesize: Bool
  for event: Maybe<&2, String>
  for data: V.Value
  for head: Char
  for tail: String
  {Sse.checkedError(Some{V.Text{SCon{head, tail}}}, synthesize, event, data) == Sse.Reject{Sse.ApiErrorPayload{V.Text{SCon{head, tail}}}} : Sse.Step}

# Synthesized envelopes carry the event name; plain delivery carries only data.
law synthesized_delivery_carries_the_event_name:
  for event: Maybe<&2, String>
  for data: V.Value
  {Sse.deliverMessage(True{}, event, data) == Sse.YieldMessage{Sse.EventMessage{event, data}} : Sse.Step}
