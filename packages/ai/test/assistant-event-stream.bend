import Base
import ../src/types.bend as T
import ../src/utils/event-stream.bend as E
import ../../runtime/src/deferred.bend as D
import ../../runtime/src/f64.bend as N

# A caller-defined opaque argument record, including a live non-JSON value.
type Arguments is Data:
  Arguments{path: String, flag: Bool}

type DiagnosticDetails is Data:
  DiagnosticDetails{attempt: U32}

def Message() -> Data: T.AssistantMessage<Arguments, DiagnosticDetails>
def EventValue() -> Data: T.AssistantMessageEvent<Arguments, DiagnosticDetails>
def Stream() -> Data: E.AssistantMessageEventStream(Arguments, DiagnosticDetails)

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def message(contents: List<&2, T.AssistantContent<Arguments>>, usage: T.Usage, reason: T.StopReason) -> Message():
  +zero = N.fromU32(0)
  T.AssistantMessage{contents, "custom-api", "custom-provider", "requested-model", Some{"actual-model"}, Some{"response-id"}, Some{"provider-effort"}, None{}, usage, reason, None{}, None{}, Some{"native-reason"}, Some{False{}}, N.fromU32(1234)}

def tag(value: EventValue()) -> U32:
  match value:
    case T.Start{_}: 0
    case T.TextStart{_, _}: 1
    case T.TextDelta{_, _, _}: 2
    case T.TextEnd{_, _, _}: 3
    case T.ThinkingStart{_, _}: 4
    case T.ThinkingDelta{_, _, _}: 5
    case T.ThinkingEnd{_, _, _}: 6
    case T.ToolcallStart{_, _}: 7
    case T.ToolcallDelta{_, _, _}: 8
    case T.ToolcallEnd{_, _, _}: 9
    case T.StreamDone{_, _}: 10
    case T.StreamError{_, _}: 11

def checkTag(value: E.Iteration<EventValue()>, expected: U32) -> IO(Unit):
  match value:
    case E.Yield{event}: assertion(U32.is_eq(tag(event), expected), "event variant/order changed")
    case E.End{}: assertion(False{}, "stream ended before its terminal event")

def checkEnd(value: E.Iteration<EventValue()>) -> IO(Unit):
  match value:
    case E.End{}: IO.pure(Unit, Unit{})
    case E.Yield{_}: assertion(False{}, "push after terminal event must be ignored")

def pending(stream: Stream()) -> IO(Unit):
  match stream:
    case E.EventStream{_, result, _, _}:
      do IO<Unit>:
        observed : Maybe<&2, Message()> <- D.peek(Message(), result)
        assertion(Maybe.is_none(&2, Message(), observed), "partial event settled the result")

def partials(+stream: Stream(), +partial: Message(), tool: T.ToolCall<Arguments>) -> IO(Unit):
  do IO<Unit>:
    E.push(EventValue(), Message(), stream, T.Start{partial})
    E.push(EventValue(), Message(), stream, T.TextStart{N.fromU32(0), partial})
    E.push(EventValue(), Message(), stream, T.TextDelta{N.fromU32(0), "delta", partial})
    E.push(EventValue(), Message(), stream, T.TextEnd{N.fromU32(0), "text", partial})
    E.push(EventValue(), Message(), stream, T.ThinkingStart{N.fromU32(1), partial})
    E.push(EventValue(), Message(), stream, T.ThinkingDelta{N.fromU32(1), "thinking delta", partial})
    E.push(EventValue(), Message(), stream, T.ThinkingEnd{N.fromU32(1), "thinking", partial})
    E.push(EventValue(), Message(), stream, T.ToolcallStart{N.fromU32(2), partial})
    E.push(EventValue(), Message(), stream, T.ToolcallDelta{N.fromU32(2), "{}", partial})
    E.push(EventValue(), Message(), stream, T.ToolcallEnd{N.fromU32(2), tool, partial})
    pending(stream)

def terminal(error: Bool, partial: Message()) -> EventValue():
  match error:
    case False{}: T.StreamDone{T.DoneStop{}, partial}
    case True{}: T.StreamError{T.ErrorError{}, partial}

def drain(count: Nat, +expected: U32, +cursor: E.Iterator<EventValue(), Message()>) -> IO(Unit):
  match count:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+n:
      do IO<Unit>:
        value : E.Iteration<EventValue()> <- E.nextValue(EventValue(), Message(), cursor)
        checkTag(value, expected)
        drain(n, (expected + 1 : U32), cursor)

def checkText(value: T.TextContent) -> IO(Unit):
  match value:
    case T.TextContent{text, _}: assertion(String.eq(text, ""), "retained content value changed")

def checkTool(value: T.ToolCall<Arguments>) -> IO(Unit):
  match value:
    case T.ToolCall{_, _, Arguments{path, flag}, _, namespace}:
      do IO<Unit>:
        observed : Bool <- IO.pure(Bool, flag)
        assertion(String.eq(path, "source.bend") && observed, "opaque tool argument value lost")

def checkContents(contents: List<&2, T.AssistantContent<Arguments>>) -> IO(Unit):
  match contents:
    case T.AssistantText{text} <> T.AssistantThinking{thinking} <> T.AssistantToolCall{tool} <> Nil{}:
      do IO<Unit>:
        observedText : T.TextContent = text
        checkText(observedText)
        observedTool : T.ToolCall<Arguments> = tool
        checkTool(observedTool)
    case _: assertion(False{}, "message content variants changed")

def checkToolEvent(value: E.Iteration<EventValue()>) -> IO(Unit):
  match value:
    case E.Yield{T.ToolcallEnd{_, tool, _}}:
      do IO<Unit>:
        observed : T.ToolCall<Arguments> = tool
        checkTool(observed)
    case _: assertion(False{}, "expected toolcall_end event")

def checkMessage(value: Message()) -> IO(Unit):
  match value:
    case T.AssistantMessage{contents, _, _, _, _, _, _, _, _, T.Pending{}, _, _, _, _, _}:
      do IO<Unit>:
        values : List<&2, T.AssistantContent<Arguments>> = contents
        checkContents(values)
    case _: assertion(False{}, "retained message must preserve its emitted value")

def checkRetained(value: E.Iteration<EventValue()>) -> IO(Unit):
  match value:
    case E.Yield{T.Start{partial}}:
      do IO<Unit>:
        observed : Message() <- IO.pure(Message(), partial)
        checkMessage(observed)
    case _: assertion(False{}, "expected retained start event")

def run(+error: Bool) -> IO(Unit):
  do IO<Unit>:
    +flag : Bool <- IO.pure(Bool, True{})
    +text : T.TextContent = T.TextContent{"", None{}}
    +thinking : T.ThinkingContent = T.ThinkingContent{"", None{}, Some{False{}}}
    +tool : T.ToolCall<Arguments> = T.ToolCall{"call-id", "read", Arguments{"source.bend", flag}, Some{"signature"}, Some{"namespace"}}
    +cost : T.UsageCost = T.UsageCost{N.fromU32(0), N.fromU32(0), N.fromU32(0), N.fromU32(0), N.fromU32(0)}
    +usage : T.Usage = T.Usage{N.fromU32(0), N.fromU32(0), N.fromU32(0), N.fromU32(0), Some{N.fromU32(0)}, Some{N.fromU32(0)}, N.fromU32(0), cost}
    +contents : List<&2, T.AssistantContent<Arguments>> = T.AssistantText{text} <> T.AssistantThinking{thinking} <> T.AssistantToolCall{tool} <> Nil{}
    +partial : Message() <- IO.pure(Message(), message(contents, usage, T.Pending{}))
    +stream : Stream() <- E.createAssistantMessageEventStream(~Arguments, ~DiagnosticDetails)
    partials(stream, partial, tool)
    +cursor : E.Iterator<EventValue(), Message()> <- E.iterator(EventValue(), Message(), stream)
    retained : E.Iteration<EventValue()> <- E.nextValue(EventValue(), Message(), cursor)
    E.push(EventValue(), Message(), stream, terminal(error, partial))
    E.push(EventValue(), Message(), stream, T.Start{partial})
    resultRef : Message() <- E.resultValue(EventValue(), Message(), stream)
    checkRetained(retained)
    drain(8n, 1, cursor)
    toolEvent : E.Iteration<EventValue()> <- E.nextValue(EventValue(), Message(), cursor)
    checkToolEvent(toolEvent)
    value : E.Iteration<EventValue()> <- E.nextValue(EventValue(), Message(), cursor)
    checkTag(value, Bool.pick(U32, error, 11, 10))
    value : E.Iteration<EventValue()> <- E.nextValue(EventValue(), Message(), cursor)
    checkEnd(value)
    E.disposeIterator(EventValue(), Message(), cursor)
    E.disposeAssistantMessageEventStream(Arguments, DiagnosticDetails, stream)
    previous : Message() <- IO.pure(Message(), partial)
    oldUsage : T.Usage = usage
    oldContents : List<&2, T.AssistantContent<Arguments>> = contents
    previous : T.UsageCost = cost
    previous : T.TextContent = text
    previous : T.ThinkingContent = thinking
    previous : T.ToolCall<Arguments> = tool
    previous : Bool <- IO.pure(Bool, flag)
    return Unit{}

# Setup failures may terminate directly with error, without a start event.
def setupFailure() -> IO(Unit):
  do IO<Unit>:
    +flag : Bool <- IO.pure(Bool, True{})
    +text : T.TextContent = T.TextContent{"", None{}}
    +thinking : T.ThinkingContent = T.ThinkingContent{"", None{}, Some{False{}}}
    +tool : T.ToolCall<Arguments> = T.ToolCall{"call-id", "read", Arguments{"source.bend", flag}, None{}, None{}}
    +cost : T.UsageCost = T.UsageCost{N.fromU32(0), N.fromU32(0), N.fromU32(0), N.fromU32(0), N.fromU32(0)}
    +usage : T.Usage = T.Usage{N.fromU32(0), N.fromU32(0), N.fromU32(0), N.fromU32(0), Some{N.fromU32(0)}, Some{N.fromU32(0)}, N.fromU32(0), cost}
    +contents : List<&2, T.AssistantContent<Arguments>> = T.AssistantText{text} <> T.AssistantThinking{thinking} <> T.AssistantToolCall{tool} <> Nil{}
    +partial : Message() <- IO.pure(Message(), message(contents, usage, T.Aborted{}))
    +stream : Stream() <- E.createAssistantMessageEventStream(~Arguments, ~DiagnosticDetails)
    E.push(EventValue(), Message(), stream, T.StreamError{T.ErrorAborted{}, partial})
    resultRef : Message() <- E.resultValue(EventValue(), Message(), stream)
    +cursor : E.Iterator<EventValue(), Message()> <- E.iterator(EventValue(), Message(), stream)
    value : E.Iteration<EventValue()> <- E.nextValue(EventValue(), Message(), cursor)
    checkTag(value, 11)
    value : E.Iteration<EventValue()> <- E.nextValue(EventValue(), Message(), cursor)
    checkEnd(value)
    E.disposeIterator(EventValue(), Message(), cursor)
    E.disposeAssistantMessageEventStream(Arguments, DiagnosticDetails, stream)
    previous : Message() <- IO.pure(Message(), partial)
    oldUsage : T.Usage = usage
    oldContents : List<&2, T.AssistantContent<Arguments>> = contents
    previous : T.UsageCost = cost
    previous : T.TextContent = text
    previous : T.ThinkingContent = thinking
    previous : T.ToolCall<Arguments> = tool
    previous : Bool <- IO.pure(Bool, flag)
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    run(False{})
    run(True{})
    setupFailure()
    IO.print("PASS assistant stream variants, done/error extraction, ignored late pushes, and immutable typed payloads")
