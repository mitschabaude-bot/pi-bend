import Base
import ../packages/ai/src/api/openai-sse-default-hooks.bend as H
import ../packages/ai/src/api/openai-sse-reader.bend as SSE
import ../packages/ai/src/api/openai-sse-json.bend as Json
import ../packages/runtime/src/json-parse.bend as Parse
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/callback.bend as C

law invalid_json_reports_exact_data_and_current_block:
  for cause: Parse.Error
  for data: String
  for raw: List<&2, String>
  for target: Json.DiagnosticTarget
  {H.messages(Json.InvalidJson{cause, data, raw, target}) == ("Could not parse message into JSON: " ++ data) <> ("From chunk: " ++ H.raw(raw)) <> Nil{} : List<&2, String>}

law api_errors_do_not_emit_json_parse_diagnostics:
  for error: V.Value
  {H.messages(Json.ApiErrorPayload{error}) == Nil{} : List<&2, String>}

law borrowing_preserves_owner_and_callbacks:
  for -E: Data
  for hooks: SSE.Hooks<E>
  {H.borrow(E, H.Owner{hooks}) == (H.Owner{hooks}, hooks) : H.Owner<E> & SSE.Hooks<E>}

law disposal_retires_both_callbacks:
  for -E: Data
  for cancel: C.Callback<Unit, Unit>
  for report: C.Callback<Json.Error, Result<&2, &2, SSE.ReadError<E>, Unit>>
  {H.dispose(E, H.Owner{SSE.Hooks{cancel, report}}) == IO.bind(Unit, Unit, C.dispose(Json.Error, Result<&2, &2, SSE.ReadError<E>, Unit>, report), ignored => C.dispose(Unit, Unit, cancel)) : IO(Unit)}

law raw_diagnostics_preserve_number_of_lines:
  for +lines: List<&2, String>
  {List.length(&2, String, H.quoted(lines)) == List.length(&2, String, lines) : Nat}
