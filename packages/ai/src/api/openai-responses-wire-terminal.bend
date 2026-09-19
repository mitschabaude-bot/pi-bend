import Base
import ./openai-responses-terminal.bend as Terminal
import ./openai-responses-stream-content.bend as Content
import ./openai-responses-wire-items.bend as Items
import ../../../runtime/src/json-decode.bend as D
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/f64.bend as F

# Optional nested fields preserve absence instead of inventing zero accounting.
def details(fields: Maybe<&2, R.Record<V.Value>>) -> R.Record<V.Value>:
  Maybe.default(&2, R.Record<V.Value>, fields, R.new(V.Value))

def usage(value: V.Value) -> Result<&2, &2, D.Error, Terminal.ResponseUsage>:
  do Result<&2, &2, D.Error, Terminal.ResponseUsage>:
    +fields : R.Record<V.Value> <- D.object(value)
    input : Maybe<&2, F.F64> <- D.optional(F.F64, fields, "input_tokens", D.number)
    output : Maybe<&2, F.F64> <- D.optional(F.F64, fields, "output_tokens", D.number)
    total : Maybe<&2, F.F64> <- D.optional(F.F64, fields, "total_tokens", D.number)
    inputDetails : Maybe<&2, R.Record<V.Value>> <- D.optional(R.Record<V.Value>, fields, "input_tokens_details", D.object)
    outputDetails : Maybe<&2, R.Record<V.Value>> <- D.optional(R.Record<V.Value>, fields, "output_tokens_details", D.object)
    +inputFields : R.Record<V.Value> = details(inputDetails)
    cached : Maybe<&2, F.F64> <- D.located(Maybe<&2, F.F64>, D.optional(F.F64, inputFields, "cached_tokens", D.number), D.Field{"input_tokens_details"})
    written : Maybe<&2, F.F64> <- D.located(Maybe<&2, F.F64>, D.optional(F.F64, inputFields, "cache_write_tokens", D.number), D.Field{"input_tokens_details"})
    reasoning : Maybe<&2, F.F64> <- D.located(Maybe<&2, F.F64>, D.optional(F.F64, details(outputDetails), "reasoning_tokens", D.number), D.Field{"output_tokens_details"})
    return Terminal.ResponseUsage{input, output, cached, written, reasoning, total}

def reason(value: V.Value) -> Result<&2, &2, D.Error, Maybe<&2, String>>:
  do Result<&2, &2, D.Error, Maybe<&2, String>>:
    fields : R.Record<V.Value> <- D.object(value)
    D.optional(String, fields, "reason", D.string)

def flatten(-A: Data, value: Maybe<&2, Maybe<&2, A>>) -> Maybe<&2, A>:
  match value:
    case None{}: None{}
    case Some{inner}: inner

def incompleteReason(fields: R.Record<V.Value>) -> Result<&2, &2, D.Error, Maybe<&2, String>>:
  do Result<&2, &2, D.Error, Maybe<&2, String>>:
    value : Maybe<&2, Maybe<&2, String>> <- D.optional(Maybe<&2, String>, fields, "incomplete_details", reason)
    return flatten(String, value)

def output(value: V.Value) -> Result<&2, &2, D.Error, List<&2, Content.OutputItem>>:
  D.list(~Content.OutputItem, ~Items.decode, value)

def response(value: V.Value) -> Result<&2, &2, D.Error, Terminal.Response>:
  do Result<&2, &2, D.Error, Terminal.Response>:
    +fields : R.Record<V.Value> <- D.object(value)
    id : Maybe<&2, String> <- D.optional(String, fields, "id", D.string)
    status : Maybe<&2, String> <- D.optional(String, fields, "status", D.string)
    reason : Maybe<&2, String> <- incompleteReason(fields)
    output : Maybe<&2, List<&2, Content.OutputItem>> <- D.optional(List<&2, Content.OutputItem>, fields, "output", output)
    usage : Maybe<&2, Terminal.ResponseUsage> <- D.optional(Terminal.ResponseUsage, fields, "usage", usage)
    tier : Maybe<&2, String> <- D.optional(String, fields, "service_tier", D.string)
    return Terminal.Response{id, status, reason, Maybe.default(&2, List<&2, Content.OutputItem>, output, Nil{}), usage, tier}

def providerError(value: V.Value) -> Result<&2, &2, D.Error, Terminal.ProviderError>:
  do Result<&2, &2, D.Error, Terminal.ProviderError>:
    +fields : R.Record<V.Value> <- D.object(value)
    code : Maybe<&2, String> <- D.optional(String, fields, "code", D.string)
    message : Maybe<&2, String> <- D.optional(String, fields, "message", D.string)
    return Terminal.ProviderError{code, message}
