import Base
import ../packages/ai/src/api/openai-responses-stream-error.bend as Format
import ../packages/ai/src/api/openai-responses-reader.bend as Reader
import ../packages/ai/src/api/openai-responses-stream.bend as Stream
import ../packages/ai/src/api/openai-responses-terminal.bend as Terminal
import ../packages/ai/src/api/openai-sse-reader.bend as SSE
import ../packages/ai/src/api/openai-sse-json.bend as Dispatch
import ../packages/runtime/src/json-parse.bend as Parse

# Diagnostic history and its output sink cannot affect the primary parse cause.
law parse_message_independent_of_diagnostic_context:
  for cause: Parse.Error
  for data: String
  for raw: List<&2, String>
  for target: Dispatch.DiagnosticTarget
  {Format.dispatch(Dispatch.InvalidJson{cause, data, raw, target}) == Format.dispatch(Dispatch.InvalidJson{cause, "", Nil{}, Dispatch.ClientLogger{}}) : Format.Formatted()}

law transport_message_survives_reader_wrapping:
  for -E: Data
  for render: E -> Format.Formatted()
  for cause: E
  {Format.reader(E, render, Reader.StreamingFailure{SSE.TransportFailure{cause}}) == render(cause) : Format.Formatted()}

law diagnostic_failure_preserves_its_own_cause:
  for -E: Data
  for render: E -> Format.Formatted()
  for cause: E
  {Format.reader(E, render, Reader.StreamingFailure{SSE.DiagnosticFailure{cause}}) == render(cause) : Format.Formatted()}

law read_preserves_callback_diagnostic:
  for -E: Data
  for render: E -> Format.Formatted()
  for cause: E
  {Format.processing(E, render, Stream.ReadFailure{cause}) == render(cause) : Format.Formatted()}

law tier_resolution_preserves_callback_diagnostic:
  for -E: Data
  for render: E -> Format.Formatted()
  for cause: E
  {Format.processing(E, render, Stream.ResolveServiceTierFailure{cause}) == render(cause) : Format.Formatted()}

law terminal_message_preserved:
  for -E: Data
  for render: E -> Format.Formatted()
  for cause: Terminal.Error
  {Format.processing(E, render, Stream.TerminalFailure{cause}) == Done{Terminal.errorMessage(cause)} : Format.Formatted()}

law emit_preserves_callback_diagnostic:
  for -E: Data
  for render: E -> Format.Formatted()
  for cause: E
  {Format.processing(E, render, Stream.EmitFailure{cause}) == render(cause) : Format.Formatted()}

law pricing_preserves_callback_diagnostic:
  for -E: Data
  for render: E -> Format.Formatted()
  for cause: E
  {Format.processing(E, render, Stream.ApplyServiceTierPricingFailure{cause}) == render(cause) : Format.Formatted()}
