import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/api/openai-responses-options.bend as O

law extension_preserves_base:
  for -Value: Data
  for -Choice: Data
  for -Signal: Data
  for -Telemetry: Data
  for -Fetch: Data
  for -Error: Data
  for +base: T.StreamOptions<Value, Signal, Telemetry, Fetch, Error>
  for extra: O.ResponsesSettings<Choice>
  {O.toStreamOptions(Value, Choice, Signal, Telemetry, Fetch, Error, O.fromStreamOptions(Value, Choice, Signal, Telemetry, Fetch, Error, base, extra)) == base : T.StreamOptions<Value, Signal, Telemetry, Fetch, Error>}

law extension_preserves_provider_settings:
  for -Value: Data
  for -Choice: Data
  for -Signal: Data
  for -Telemetry: Data
  for -Fetch: Data
  for -Error: Data
  for base: T.StreamOptions<Value, Signal, Telemetry, Fetch, Error>
  for +extra: O.ResponsesSettings<Choice>
  {O.settings(Value, Choice, Signal, Telemetry, Fetch, Error, O.fromStreamOptions(Value, Choice, Signal, Telemetry, Fetch, Error, base, extra)) == extra : O.ResponsesSettings<Choice>}

law projections_reconstruct_all_options:
  for -Value: Data
  for -Choice: Data
  for -Signal: Data
  for -Telemetry: Data
  for -Fetch: Data
  for -Error: Data
  for +options: O.OpenAIResponsesOptions<Value, Choice, Signal, Telemetry, Fetch, Error>
  {O.fromStreamOptions(Value, Choice, Signal, Telemetry, Fetch, Error, O.toStreamOptions(Value, Choice, Signal, Telemetry, Fetch, Error, options), O.settings(Value, Choice, Signal, Telemetry, Fetch, Error, options)) == options : O.OpenAIResponsesOptions<Value, Choice, Signal, Telemetry, Fetch, Error>}
