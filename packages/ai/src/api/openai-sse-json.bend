import Base
import ../../../runtime/src/sse-decoder.bend as SSE
import ../../../runtime/src/json-parse.bend as Json
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as Record
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/u64.bend as Word

# Pure dispatch policy inside openai 6.40.0 Stream.fromSSEResponse.
# The IO wrapper owns iteration, diagnostic sinks, APIError formatting and abort.
type State is Data:
  Receiving{}
  DoneMarker{}

type Message is Data:
  JsonMessage{data: V.Value}
  EventMessage{event: Maybe<&2, String>, data: V.Value}

type DiagnosticTarget is Data:
  ClientLogger{}
  ConsoleLogger{}

type Error is Data:
  InvalidJson{cause: Json.Error, data: String, raw: List<&2, String>, target: DiagnosticTarget}
  ApiErrorPayload{error: V.Value}

type Step is Data:
  Skip{state: State}
  YieldMessage{message: Message}
  Reject{error: Error}

def threadEvent(event: Maybe<&2, String>) -> Bool:
  match event:
    case None{}: False{}
    case Some{name}: String.starts_with(name, "thread.")

def activeNumber(value: F.Decoded) -> Bool:
  match value:
    case F.NotANumber{}: False{}
    case F.Infinity{_}: True{}
    case F.Finite{_, _, significand}: Bool.not(Word.equal(significand, Word.zero()))

# The wire protocol treats null/false/zero/empty-text error fields as absent.
# Arrays and objects, including empty containers, are error payloads.
def activeError(value: V.Value) -> Bool:
  match value:
    case V.Null{}: False{}
    case V.Boolean{value}: value
    case V.Number{value}: activeNumber(F.decode(value))
    case V.Text{text}: Bool.not(String.is_empty(text))
    case _: True{}

def errorField(data: V.Value) -> Maybe<&2, V.Value>:
  match data:
    case V.ObjectValue{fields}: Record.get(V.Value, fields, "error")
    case _: None{}

def message(envelope: Bool, event: Maybe<&2, String>, data: V.Value) -> Step:
  match envelope:
    case True{}: YieldMessage{EventMessage{event, data}}
    case False{}: YieldMessage{JsonMessage{data}}

def errorOrMessage(active: Bool, error: V.Value, synthesize: Bool, event: Maybe<&2, String>, data: V.Value) -> Step:
  match active:
    case True{}: Reject{ApiErrorPayload{error}}
    case False{}: message(synthesize, event, data)

def checkedError(error: Maybe<&2, V.Value>, synthesize: Bool, event: Maybe<&2, String>, data: V.Value) -> Step:
  match error:
    case None{}: message(synthesize, event, data)
    case Some{+value}: errorOrMessage(activeError(value), value, synthesize, event, data)

def parsed(thread: Bool, synthesize: Bool, event: Maybe<&2, String>, data: String, raw: List<&2, String>, result: Result<&2, &2, Json.Error, V.Value>) -> Step:
  match thread result:
    case True{} Fail{cause}: Reject{InvalidJson{cause, data, raw, ConsoleLogger{}}}
    case False{} Fail{cause}: Reject{InvalidJson{cause, data, raw, ClientLogger{}}}
    case True{} Done{value}: message(True{}, event, value)
    case False{} Done{+value}: checkedError(errorField(value), synthesize, event, value)

def parseEvent(marker: Bool, synthesize: Bool, +event: Maybe<&2, String>, +data: String, raw: List<&2, String>) -> Step:
  match marker:
    case True{}: Skip{DoneMarker{}}
    case False{}: parsed(threadEvent(event), synthesize, event, data, raw, Json.parse(data))

# Done suppresses later values and JSON errors, but the wrapper must continue
# draining input. Prefix matching deliberately accepts '[DONE]suffix'.
def step(state: State, synthesize: Bool, event: SSE.ServerSentEvent) -> Step:
  match state event:
    case DoneMarker{} _: Skip{DoneMarker{}}
    case Receiving{} SSE.ServerSentEvent{name, +data, raw}: parseEvent(String.starts_with(data, "[DONE]"), synthesize, name, data, raw)
