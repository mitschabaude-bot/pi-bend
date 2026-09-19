import Base
import ../types.bend as T
import ./openai-responses-stream-content.bend as Content
import ./openai-responses-stream-state.bend as Stream
import ./transform-messages.bend as Transform
import ../utils/cost.bend as Cost
import ../utils/json.bend as Json
import ../utils/schema-json.bend as SchemaJson
import ../../../runtime/src/json-parse.bend as Parse
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/f64.bend as F

# Missing usage fields are distinct from an absent usage record: the latter
# retains previous accounting, but both paths recalculate cost.
type ResponseUsage is Data:
  ResponseUsage{input: Maybe<&2, F.F64>, output: Maybe<&2, F.F64>, cached: Maybe<&2, F.F64>, cacheWrite: Maybe<&2, F.F64>, reasoning: Maybe<&2, F.F64>, total: Maybe<&2, F.F64>}

type Response is Data:
  Response{id: Maybe<&2, String>, status: Maybe<&2, String>, incompleteReason: Maybe<&2, String>, output: List<&2, Content.OutputItem>, usage: Maybe<&2, ResponseUsage>, serviceTier: Maybe<&2, String>}

type Error is Data:
  InvalidReasoningSignature{}
  UnhandledStopReason{status: String}
  ProviderFailure{message: String}
  MissingTerminalResponse{}

type Update<-G: Data> is Data:
  Update{state: Stream.State<G>, error: Maybe<&2, Error>}

def errorMessage(error: Error) -> String:
  match error:
    case InvalidReasoningSignature{}: "Invalid stored Responses reasoning signature"
    case UnhandledStopReason{status}: "Unhandled stop reason: " ++ status
    case ProviderFailure{message}: message
    case MissingTerminalResponse{}: "OpenAI Responses stream ended before a terminal response event"

def withOutput(-G: Data, state: Stream.State<G>, output: T.AssistantMessage<V.Value, G>) -> Stream.State<G>:
  match state:
    case Stream.State{_, slots, refs, properties}: Stream.State{output, slots, refs, properties}

def withResponseId(-G: Data, message: T.AssistantMessage<V.Value, G>, id: Maybe<&2, String>) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, _, thinking, diagnostics, usage, stop, deferred, error, raw, endTurn, time}:
      T.AssistantMessage{content, api, provider, model, responseModel, id, thinking, diagnostics, usage, stop, deferred, error, raw, endTurn, time}

def responseId(-G: Data, message: T.AssistantMessage<V.Value, G>, id: Maybe<&2, String>) -> T.AssistantMessage<V.Value, G>:
  match id:
    case None{}: message
    case Some{""}: message
    case other: withResponseId(G, message, other)

def getUsage(-G: Data, message: T.AssistantMessage<V.Value, G>) -> T.Usage:
  match message:
    case T.AssistantMessage{_, _, _, _, _, _, _, _, value, _, _, _, _, _, _}: value

def withUsage(-G: Data, message: T.AssistantMessage<V.Value, G>, usage: T.Usage) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, id, thinking, diagnostics, _, stop, deferred, error, raw, endTurn, time}:
      T.AssistantMessage{content, api, provider, model, responseModel, id, thinking, diagnostics, usage, stop, deferred, error, raw, endTurn, time}

def normalizedNumber(+number: F.F64, compared: Maybe<&2, Cmp>) -> F.F64:
  match compared:
    case None{}: F.fromU32(0)
    case Some{EQ{}}: F.fromU32(0)
    case _: number

def usageNumber(value: Maybe<&2, F.F64>) -> F.F64:
  match value:
    case None{}: F.fromU32(0)
    case Some{+amount}: normalizedNumber(amount, F.compare(amount, F.fromU32(0)))

def nonnegative(value: F.F64, compared: Maybe<&2, Cmp>) -> F.F64:
  match compared:
    case Some{LT{}}: F.fromU32(0)
    case Some{EQ{}}: F.fromU32(0)
    case _: value

def inputTokens(input: F.F64, cached: F.F64, written: F.F64) -> F.F64:
  +remaining = F.subtract(F.subtract(input, cached), written)
  nonnegative(remaining, F.compare(remaining, F.fromU32(0)))

def responseUsage(previous: T.Usage, value: Maybe<&2, ResponseUsage>) -> T.Usage:
  match value:
    case None{}: previous
    case Some{ResponseUsage{input, output, cached, written, reasoning, total}}:
      +read = usageNumber(cached)
      +write = usageNumber(written)
      +zero = F.fromU32(0)
      T.Usage{inputTokens(usageNumber(input), read, write), usageNumber(output), read, write, None{}, Some{usageNumber(reasoning)}, usageNumber(total), T.UsageCost{zero, zero, zero, zero, zero}}

def withCost(usage: T.Usage, cost: T.UsageCost) -> T.Usage:
  match usage:
    case T.Usage{input, output, read, write, longWrite, reasoning, total, _}: T.Usage{input, output, read, write, longWrite, reasoning, total, cost}

def accounting(-G: Data, +message: T.AssistantMessage<V.Value, G>, id: Maybe<&2, String>, incoming: Maybe<&2, ResponseUsage>, cost: T.ModelCost) -> T.AssistantMessage<V.Value, G>:
  +next = responseUsage(getUsage(G, message), incoming)
  withUsage(G, responseId(G, message, id), withCost(next, Cost.compute(cost, next)))

# Only completed reasoning items are indexed by the stream state. Backfill
# their opaque signatures without emitting an extra content event.
def encodeSignature(fields: R.Record<V.Value>, encrypted: String) -> Maybe<&2, String>:
  Json.stringify(SchemaJson.toJson(V.ObjectValue{R.set(V.Value, fields, "encrypted_content", V.Text{encrypted})}))

def encodedSignature(value: Maybe<&2, String>) -> Result<&2, &2, Error, String>:
  match value:
    case None{}: Fail{InvalidReasoningSignature{}}
    case Some{text}: Done{text}

def selectedSignature(text: String, encrypted: String, fields: R.Record<V.Value>, existing: String) -> Result<&2, &2, Error, String>:
  match existing:
    case "": encodedSignature(encodeSignature(fields, encrypted))
    case _: Done{text}

def decodedSignature(text: String, encrypted: String, parsed: Result<&2, &2, Parse.Error, V.Value>) -> Result<&2, &2, Error, String>:
  match parsed:
    case Done{V.ObjectValue{+fields}}: selectedSignature(text, encrypted, fields, Content.textField(R.get(V.Value, fields, "encrypted_content")))
    case _: Fail{InvalidReasoningSignature{}}

def thinkingSignature(text: String, redacted: Maybe<&2, Bool>, result: Result<&2, &2, Error, String>) -> Result<&2, &2, Error, T.AssistantContent<V.Value>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{signature}: Done{T.AssistantThinking{T.ThinkingContent{text, Some{signature}, redacted}}}

def repairStored(text: String, redacted: Maybe<&2, Bool>, +stored: String, encrypted: String) -> Result<&2, &2, Error, T.AssistantContent<V.Value>>:
  match stored:
    case "": Done{T.AssistantThinking{T.ThinkingContent{text, Some{""}, redacted}}}
    case +signature: thinkingSignature(text, redacted, decodedSignature(signature, encrypted, Parse.parse(signature)))

def repairBlock(block: T.AssistantContent<V.Value>, +encrypted: String) -> Result<&2, &2, Error, T.AssistantContent<V.Value>>:
  match block:
    case T.AssistantThinking{T.ThinkingContent{text, Some{+stored}, redacted}}:
      repairStored(text, redacted, stored, encrypted)
    case other: Done{other}

def prepend(block: T.AssistantContent<V.Value>, result: Result<&2, &2, Error, List<&2, T.AssistantContent<V.Value>>>) -> Result<&2, &2, Error, List<&2, T.AssistantContent<V.Value>>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{rest}: Done{block <> rest}

def repairedHead(result: Result<&2, &2, Error, T.AssistantContent<V.Value>>, rest: List<&2, T.AssistantContent<V.Value>>) -> Result<&2, &2, Error, List<&2, T.AssistantContent<V.Value>>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{block}: Done{block <> rest}

def repairAt(blocks: List<&2, T.AssistantContent<V.Value>>, index: Nat, encrypted: String) -> Result<&2, &2, Error, List<&2, T.AssistantContent<V.Value>>>:
  match blocks index:
    case Nil{} _: Done{Nil{}}
    case head <> rest 0n: repairedHead(repairBlock(head, encrypted), rest)
    case head <> rest 1n+tail: prepend(head, repairAt(rest, tail, encrypted))

def backfilled(-G: Data, +state: Stream.State<G>, result: Result<&2, &2, Error, List<&2, T.AssistantContent<V.Value>>>) -> Update<G>:
  match result:
    case Fail{error}: Update{state, Some{error}}
    case Done{blocks}: Update{withOutput(G, state, Transform.withContent(V.Value, G, Stream.output(G, state), blocks)), None{}}

def repairReference(-G: Data, +state: Stream.State<G>, encrypted: String, reference: Maybe<&2, Nat>) -> Update<G>:
  match encrypted reference:
    case "" _: Update{state, None{}}
    case _ None{}: Update{state, None{}}
    case text Some{position}: backfilled(G, state, repairAt(Stream.blocks(G, Stream.output(G, state)), position, text))

def backfillItem(-G: Data, state: Stream.State<G>, item: Content.OutputItem) -> Update<G>:
  match state item:
    case Stream.State{message, slots, +refs, properties} Content.ReasoningItem{+fields}:
      repairReference(G, Stream.State{message, slots, refs, properties}, Content.textField(R.get(V.Value, fields, "encrypted_content")), R.get(Nat, refs, Content.textField(R.get(V.Value, fields, "id"))))
    case other _: Update{other, None{}}

def backfill(-G: Data, items: List<&2, Content.OutputItem>, current: Update<G>) -> Update<G>:
  match items current:
    case _ Update{state, Some{error}}: Update{state, Some{error}}
    case Nil{} other: other
    case head <> rest Update{state, None{}}: backfill(G, rest, backfillItem(G, state, head))

def prepared(-G: Data, id: Maybe<&2, String>, incoming: Maybe<&2, ResponseUsage>, cost: T.ModelCost, current: Update<G>) -> Update<G>:
  match current:
    case Update{state, Some{error}}: Update{state, Some{error}}
    case Update{+state, None{}}: Update{withOutput(G, state, accounting(G, Stream.output(G, state), id, incoming, cost)), None{}}

# The IO driver invokes optional tier resolution/pricing after prepare and
# before finish. Pricing receives calculated usage and returns an updated value.
def prepare(-G: Data, state: Stream.State<G>, response: Response, cost: T.ModelCost) -> Update<G>:
  match response:
    case Response{id, _, _, items, incoming, _}: prepared(G, id, incoming, cost, backfill(G, items, Update{state, None{}}))

def resolveServiceTier(response: Maybe<&2, String>, requested: Maybe<&2, String>) -> Maybe<&2, String>:
  match response:
    case None{}: requested
    case some: some

def withRaw(-G: Data, message: T.AssistantMessage<V.Value, G>, raw: Maybe<&2, String>) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, id, thinking, diagnostics, usage, stop, deferred, error, _, endTurn, time}:
      T.AssistantMessage{content, api, provider, model, responseModel, id, thinking, diagnostics, usage, stop, deferred, error, raw, endTurn, time}

type MappedStop is Data:
  MappedStop{reason: T.StopReason, errorMessage: Maybe<&2, String>}

def incomplete(reason: Maybe<&2, String>) -> MappedStop:
  match reason:
    case Some{"max_output_tokens"}: MappedStop{T.Length{}, None{}}
    case None{}: MappedStop{T.Error{}, Some{"Response incomplete without a provider reason"}}
    case Some{""}: MappedStop{T.Error{}, Some{"Response incomplete without a provider reason"}}
    case Some{text}: MappedStop{T.Error{}, Some{"Response incomplete: " ++ text}}

def mapStopReason(status: Maybe<&2, String>, reason: Maybe<&2, String>) -> Result<&2, &2, Error, MappedStop>:
  match status:
    case None{}: Done{MappedStop{T.Stop{}, None{}}}
    case Some{""}: Done{MappedStop{T.Stop{}, None{}}}
    case Some{"completed"}: Done{MappedStop{T.Stop{}, None{}}}
    case Some{"incomplete"}: Done{incomplete(reason)}
    case Some{"failed"}: Done{MappedStop{T.Error{}, None{}}}
    case Some{"cancelled"}: Done{MappedStop{T.Error{}, None{}}}
    case Some{"in_progress"}: Done{MappedStop{T.Stop{}, None{}}}
    case Some{"queued"}: Done{MappedStop{T.Stop{}, None{}}}
    case Some{text}: Fail{UnhandledStopReason{text}}

def hasTool(blocks: List<&2, T.AssistantContent<V.Value>>) -> Bool:
  match blocks:
    case Nil{}: False{}
    case T.AssistantToolCall{_} <> _: True{}
    case _ <> rest: hasTool(rest)

def toolStop(stop: T.StopReason, tool: Bool) -> T.StopReason:
  match stop tool:
    case T.Stop{} True{}: T.ToolUse{}
    case reason _: reason

def withStop(-G: Data, message: T.AssistantMessage<V.Value, G>, mapped: MappedStop) -> T.AssistantMessage<V.Value, G>:
  match message mapped:
    case T.AssistantMessage{+content, api, provider, model, responseModel, id, thinking, diagnostics, usage, _, deferred, _, raw, endTurn, time} MappedStop{reason, error}:
      T.AssistantMessage{content, api, provider, model, responseModel, id, thinking, diagnostics, usage, toolStop(reason, hasTool(content)), deferred, error, raw, endTurn, time}

def rawReason(status: Maybe<&2, String>, reason: Maybe<&2, String>) -> Maybe<&2, String>:
  match reason:
    case None{}: status
    case Some{""}: status
    case Some{text}: Some{Content.optionalText(status, "undefined") ++ "." ++ text}

def mapped(-G: Data, +state: Stream.State<G>, result: Result<&2, &2, Error, MappedStop>) -> Update<G>:
  match result:
    case Fail{error}: Update{state, Some{error}}
    case Done{stop}: Update{withOutput(G, state, withStop(G, Stream.output(G, state), stop)), None{}}

def finish(-G: Data, +state: Stream.State<G>, +status: Maybe<&2, String>, +reason: Maybe<&2, String>) -> Update<G>:
  mapped(G, withOutput(G, state, withRaw(G, Stream.output(G, state), rawReason(status, reason))), mapStopReason(status, reason))

type ProviderError is Data:
  ProviderError{code: Maybe<&2, String>, message: Maybe<&2, String>}

def failureReason(reason: Maybe<&2, String>) -> String:
  match reason:
    case None{}: ""
    case Some{""}: ""
    case Some{text}: "incomplete: " ++ text

def failureMessage(error: Maybe<&2, ProviderError>, reason: Maybe<&2, String>) -> String:
  match error:
    case Some{ProviderError{code, message}}: Content.orText(Content.optionalText(code, ""), "unknown") ++ ": " ++ Content.orText(Content.optionalText(message, ""), "no message")
    case None{}: Content.orText(failureReason(reason), "Unknown error (no error details in response)")

def failed(-G: Data, +state: Stream.State<G>, status: Maybe<&2, String>, error: Maybe<&2, ProviderError>, reason: Maybe<&2, String>) -> Update<G>:
  Update{withOutput(G, state, withRaw(G, Stream.output(G, state), status)), Some{ProviderFailure{failureMessage(error, reason)}}}

def streamError(code: Maybe<&2, String>, message: String) -> Error:
  ProviderFailure{"Error Code " ++ Content.optionalText(code, "null") ++ ": " ++ message}

def end(sawTerminalResponse: Bool) -> Maybe<&2, Error>:
  match sawTerminalResponse:
    case True{}: None{}
    case False{}: Some{MissingTerminalResponse{}}
