import Base
import ./openai-responses-stream.bend as Stream
import ./openai-responses-stream-state.bend as State
import ./openai-responses-stream-content.bend as Content
import ./openai-responses-terminal.bend as Terminal
import ./openai-responses-wire-items.bend as Items
import ./openai-responses-wire-terminal.bend as Response
import ./openai-sse-json.bend as SSE
import ../../../runtime/src/json-decode.bend as D
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/f64.bend as F

# Wire spelling is data. Classify once, then dispatch on the native sum type.
# Long string patterns currently trigger BEND-016's code-generation explosion.
type EventKind is Data:
  CreatedKind{}
  AddedKind{}
  SummaryTextKind{}
  ReasoningTextKind{}
  SummaryPartKind{}
  OutputTextKind{}
  RefusalKind{}
  FunctionDeltaKind{}
  FunctionDoneKind{}
  CustomDeltaKind{}
  CustomDoneKind{}
  ItemDoneKind{}
  CompletedKind{}
  IncompleteKind{}
  FailedKind{}
  ErrorKind{}
  UnknownKind{}

def names() -> R.Record<EventKind>:
  R.Record{
    R.Property{"response.created", CreatedKind{}} <>
    R.Property{"response.output_item.added", AddedKind{}} <>
    R.Property{"response.reasoning_summary_text.delta", SummaryTextKind{}} <>
    R.Property{"response.reasoning_text.delta", ReasoningTextKind{}} <>
    R.Property{"response.reasoning_summary_part.done", SummaryPartKind{}} <>
    R.Property{"response.output_text.delta", OutputTextKind{}} <>
    R.Property{"response.refusal.delta", RefusalKind{}} <>
    R.Property{"response.function_call_arguments.delta", FunctionDeltaKind{}} <>
    R.Property{"response.function_call_arguments.done", FunctionDoneKind{}} <>
    R.Property{"response.custom_tool_call_input.delta", CustomDeltaKind{}} <>
    R.Property{"response.custom_tool_call_input.done", CustomDoneKind{}} <>
    R.Property{"response.output_item.done", ItemDoneKind{}} <>
    R.Property{"response.completed", CompletedKind{}} <>
    R.Property{"response.incomplete", IncompleteKind{}} <>
    R.Property{"response.failed", FailedKind{}} <>
    R.Property{"error", ErrorKind{}} <>
    Nil{}
  }

def classify(value: Maybe<&2, String>) -> EventKind:
  match value:
    case None{}: UnknownKind{}
    case Some{name}: Maybe.default(&2, EventKind, R.get(EventKind, names(), name), UnknownKind{})

# Decode the event's JSON type discriminator, not the SSE event name. Fields
# unused by pi remain uninspected, including unknown future event variants.
def added(+fields: R.Record<V.Value>) -> Result<&2, &2, D.Error, Stream.ResponseStreamEvent>:
  do Result<&2, &2, D.Error, Stream.ResponseStreamEvent>:
    index : F.F64 <- D.required(F.F64, fields, "output_index", D.number)
    item : Content.OutputItem <- D.required(Content.OutputItem, fields, "item", Items.decode)
    return Stream.ContentEvent{State.Added{index, item}}

def changed(+fields: R.Record<V.Value>, input: R.Record<V.Value> -> Result<&2, &2, D.Error, Content.Input>) -> Result<&2, &2, D.Error, Stream.ResponseStreamEvent>:
  do Result<&2, &2, D.Error, Stream.ResponseStreamEvent>:
    index : F.F64 <- D.required(F.F64, fields, "output_index", D.number)
    value : Content.Input <- input(fields)
    return Stream.ContentEvent{State.Changed{index, value}}

def textInput(fields: R.Record<V.Value>, key: String, make: String -> Content.Input) -> Result<&2, &2, D.Error, Content.Input>:
  Result.map(&2, &2, D.Error, String, Content.Input, make, D.required(String, fields, key, D.string))

def itemDone(fields: R.Record<V.Value>) -> Result<&2, &2, D.Error, Content.Input>:
  Result.map(&2, &2, D.Error, Content.OutputItem, Content.Input, item => Content.ItemDone{item}, D.required(Content.OutputItem, fields, "item", Items.decode))

def responseId(value: V.Value) -> Result<&2, &2, D.Error, String>:
  do Result<&2, &2, D.Error, String>:
    fields : R.Record<V.Value> <- D.object(value)
    D.required(String, fields, "id", D.string)

def created(fields: R.Record<V.Value>) -> Result<&2, &2, D.Error, Stream.ResponseStreamEvent>:
  Result.map(&2, &2, D.Error, String, Stream.ResponseStreamEvent, id => Stream.ResponseCreated{id}, D.required(String, fields, "response", responseId))

def finalized(fields: R.Record<V.Value>, complete: Bool) -> Result<&2, &2, D.Error, Stream.ResponseStreamEvent>:
  do Result<&2, &2, D.Error, Stream.ResponseStreamEvent>:
    +response : Terminal.Response <- D.required(Terminal.Response, fields, "response", Response.response)
    return Bool.pick(Stream.ResponseStreamEvent, complete, Stream.ResponseCompleted{response}, Stream.ResponseIncomplete{response})

def failedResponse(+fields: R.Record<V.Value>) -> Result<&2, &2, D.Error, Stream.ResponseStreamEvent>:
  do Result<&2, &2, D.Error, Stream.ResponseStreamEvent>:
    status : Maybe<&2, String> <- D.optional(String, fields, "status", D.string)
    error : Maybe<&2, Terminal.ProviderError> <- D.optional(Terminal.ProviderError, fields, "error", Response.providerError)
    reason : Maybe<&2, String> <- Response.incompleteReason(fields)
    return Stream.ResponseFailed{status, error, reason}

def failed(fields: R.Record<V.Value>) -> Result<&2, &2, D.Error, Stream.ResponseStreamEvent>:
  do Result<&2, &2, D.Error, Stream.ResponseStreamEvent>:
    response : Maybe<&2, R.Record<V.Value>> <- D.optional(R.Record<V.Value>, fields, "response", D.object)
    D.located(Stream.ResponseStreamEvent, failedResponse(Response.details(response)), D.Field{"response"})

def error(+fields: R.Record<V.Value>) -> Result<&2, &2, D.Error, Stream.ResponseStreamEvent>:
  do Result<&2, &2, D.Error, Stream.ResponseStreamEvent>:
    code : Maybe<&2, String> <- D.optional(String, fields, "code", D.string)
    message : String <- D.required(String, fields, "message", D.string)
    return Stream.ResponseError{code, message}

def tagged(kind: EventKind, fields: R.Record<V.Value>) -> Result<&2, &2, D.Error, Stream.ResponseStreamEvent>:
  match kind:
    case CreatedKind{}: created(fields)
    case AddedKind{}: added(fields)
    case SummaryTextKind{}: changed(fields, record => textInput(record, "delta", text => Content.ThinkingDelta{text}))
    case ReasoningTextKind{}: changed(fields, record => textInput(record, "delta", text => Content.ThinkingDelta{text}))
    case SummaryPartKind{}: changed(fields, record => Done{Content.SummaryPartDone{}})
    case OutputTextKind{}: changed(fields, record => textInput(record, "delta", text => Content.TextDelta{text}))
    case RefusalKind{}: changed(fields, record => textInput(record, "delta", text => Content.TextDelta{text}))
    case FunctionDeltaKind{}: changed(fields, record => textInput(record, "delta", text => Content.FunctionDelta{text}))
    case FunctionDoneKind{}: changed(fields, record => textInput(record, "arguments", text => Content.FunctionDone{text}))
    case CustomDeltaKind{}: changed(fields, record => textInput(record, "delta", text => Content.CustomDelta{text}))
    case CustomDoneKind{}: changed(fields, record => textInput(record, "input", text => Content.CustomDone{text}))
    case ItemDoneKind{}: changed(fields, itemDone)
    case CompletedKind{}: finalized(fields, True{})
    case IncompleteKind{}: finalized(fields, False{})
    case FailedKind{}: failed(fields)
    case ErrorKind{}: error(fields)
    case _: Done{Stream.IgnoredEvent{}}

def decode(value: V.Value) -> Result<&2, &2, D.Error, Stream.ResponseStreamEvent>:
  do Result<&2, &2, D.Error, Stream.ResponseStreamEvent>:
    +fields : R.Record<V.Value> <- D.object(value)
    kind : Maybe<&2, String> <- D.optional(String, fields, "type", D.string)
    tagged(classify(kind), fields)

# SDK-synthesized envelopes have no top-level type, so pi ignores them.
def fromMessage(message: SSE.Message) -> Result<&2, &2, D.Error, Stream.ResponseStreamEvent>:
  match message:
    case SSE.JsonMessage{value}: decode(value)
    case SSE.EventMessage{_, _}: Done{Stream.IgnoredEvent{}}
