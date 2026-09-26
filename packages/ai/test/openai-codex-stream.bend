import Base
import ../src/types.bend as T
import ../src/api/openai-responses.bend as Responses
import ../src/api/openai-codex-responses.bend as Codex
import ../src/utils/event-stream.bend as Events
import ../src/utils/message-json.bend as MessageJson
import ../src/utils/schema-json.bend as Convert
import ./anthropic-harness.bend as A
import ../../runtime/src/fetch.bend as Fetch
import ../src/utils/json.bend as Wire
import ./responses-payload.bend as RP
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/f64.bend as F
import ../../runtime/src/json.bend as Decode
import ../../runtime/src/record.bend as R
import ../../runtime/src/schema-value.bend as V
import ../../runtime/test/utf8-runner.bend as Text
import ../src/utils/transcript.bend as Transcript

# The OpenAI Codex Responses stream over the native HTTP stack, for
# tests/openai_codex_stream_check.py (pi-mono f07218c4d
# packages/ai/test/openai-codex-stream.test.ts, SSE transport). The first
# argument is the base URL of the check's loopback server; each further
# argument is one JSON case (comma-separated code points):
#   {model: {id, name?, reasoning?, contextWindow?, maxTokens?}, entry,
#    options: {apiKey, transport, sessionId, cacheRetention, timeoutMs,
#    maxRetries, maxRetryDelayMs, reasoning, reasoningEffort, toolChoice},
#    systemPrompt, messages, tools, abortOnDelta?}
# Each case prints its events ("E type" or "E text_delta:<delta>") and then
# "R " with the final message as JSON.
def J() -> Data: T.JsonValue

# Case decoding (as in google-differential.bend)
# -----------------------------------------------
def field(value: V.Value, name: String) -> Maybe<&2, V.Value>:
  match value:
    case V.ObjectValue{fields}: R.get(V.Value, fields, name)
    case _: None{}

def text(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{item}}: Some{item}
    case _: None{}

def number(value: Maybe<&2, V.Value>) -> Maybe<&2, F64>:
  match value:
    case Some{V.Number{item}}: Some{item}
    case _: None{}

def flag(value: Maybe<&2, V.Value>) -> Maybe<&2, Bool>:
  match value:
    case Some{V.Boolean{item}}: Some{item}
    case _: None{}

def list(value: Maybe<&2, V.Value>) -> List<&2, V.Value>:
  match value:
    case Some{V.ArrayValue{values}}: values
    case _: Nil{}

def level(+name: String) -> Maybe<&2, T.ModelThinkingLevel>:
  match name:
    case "off": Some{T.Off{}}
    case "minimal": Some{T.Thinking{T.Minimal{}}}
    case "low": Some{T.Thinking{T.Low{}}}
    case "medium": Some{T.Thinking{T.Medium{}}}
    case "high": Some{T.Thinking{T.High{}}}
    case "xhigh": Some{T.Thinking{T.XHigh{}}}
    case "max": Some{T.Thinking{T.Max{}}}
    case _: None{}

def nullable(value: V.Value) -> T.Nullable<String>:
  match value:
    case V.Text{item}: T.PresentValue{item}
    case _: T.NullValue{}

def mapping(name: Maybe<&2, T.ModelThinkingLevel>, value: V.Value, rest: List<&2, T.ThinkingLevelMapping>) -> List<&2, T.ThinkingLevelMapping>:
  match name:
    case Some{selected}: T.ThinkingLevelMapping{selected, Some{nullable(value)}} <> rest
    case None{}: rest

def mappings(values: List<&2, R.Property<V.Value>>) -> List<&2, T.ThinkingLevelMapping>:
  match values:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: mapping(level(name), value, mappings(rest))

def levels(value: Maybe<&2, V.Value>) -> Maybe<&2, T.ThinkingLevelMap>:
  match value:
    case Some{V.ObjectValue{R.Record{values}}}: Some{T.ThinkingLevelMap{mappings(values)}}
    case _: None{}

def input(value: V.Value) -> Maybe<&2, T.ModelInput>:
  match value:
    case V.Text{"text"}: Some{T.InputText{}}
    case V.Text{"image"}: Some{T.InputImage{}}
    case _: None{}

def cost(value: Maybe<&2, V.Value>) -> T.ModelCost:
  match value:
    case Some{+prices}: T.ModelCost{Maybe.default(&2, F64, number(field(prices, "input")), F.fromU32(0)), Maybe.default(&2, F64, number(field(prices, "output")), F.fromU32(0)), Maybe.default(&2, F64, number(field(prices, "cacheRead")), F.fromU32(0)), Maybe.default(&2, F64, number(field(prices, "cacheWrite")), F.fromU32(0)), None{}}
    case None{}: A.zeroCost()

def prependInput(value: Maybe<&2, T.ModelInput>, rest: List<&2, T.ModelInput>) -> List<&2, T.ModelInput>:
  match value:
    case Some{item}: item <> rest
    case None{}: rest

def inputList(values: List<&2, V.Value>) -> List<&2, T.ModelInput>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: prependInput(input(value), inputList(rest))

def inputs(values: List<&2, V.Value>) -> List<&2, T.ModelInput>:
  match values:
    case Nil{}: T.InputText{} <> Nil{}
    case _: inputList(values)

def decodedMessage(value: MessageJson.Decoded(T.Message<V.Value, V.Value, Unit, Unit>), rest: List<&2, T.Message<V.Value, V.Value, Unit, Unit>>) -> List<&2, T.Message<V.Value, V.Value, Unit, Unit>>:
  match value:
    case Done{message}: message <> rest
    case Fail{_}: rest

def decodedTool(value: MessageJson.Decoded(T.Tool<V.Value>), rest: List<&2, T.Tool<V.Value>>) -> List<&2, T.Tool<V.Value>>:
  match value:
    case Done{tool}: tool <> rest
    case Fail{_}: rest

def toolList(values: List<&2, V.Value>) -> List<&2, T.Tool<V.Value>>:
  match values:
    case Nil{}: Nil{}
    case first <> rest: decodedTool(MessageJson.decodeTool(first), toolList(rest))

def tools(value: Maybe<&2, V.Value>) -> Maybe<&2, List<&2, T.Tool<V.Value>>>:
  match value:
    case Some{V.ArrayValue{values}}: Some{toolList(values)}
    case _: None{}

def thinking(value: Maybe<&2, String>) -> Maybe<&2, T.ThinkingLevel>:
  match value:
    case Some{"minimal"}: Some{T.Minimal{}}
    case Some{"low"}: Some{T.Low{}}
    case Some{"medium"}: Some{T.Medium{}}
    case Some{"high"}: Some{T.High{}}
    case Some{"xhigh"}: Some{T.XHigh{}}
    case Some{"max"}: Some{T.Max{}}
    case _: None{}

def nullableProperties(values: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<T.Nullable<String>>>:
  match values:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: R.Property{name, nullable(value)} <> nullableProperties(rest)

def headers(value: Maybe<&2, V.Value>) -> Maybe<&2, T.ProviderHeaders()>:
  match value:
    case Some{V.ObjectValue{R.Record{values}}}: Some{R.Record{nullableProperties(values)}}
    case _: None{}

def noDiagnostics(value: V.Value) -> MessageJson.Decoded(Unit):
  Fail{Decode.WrongType{Nil{}, "no diagnostic details"}}

def noDetails(value: V.Value) -> MessageJson.Decoded(Unit):
  Fail{Decode.WrongType{Nil{}, "no tool details"}}

def messages(values: List<&2, V.Value>) -> List<&2, T.Message<V.Value, V.Value, Unit, Unit>>:
  match values:
    case Nil{}: Nil{}
    case +first <> rest: decodedMessage(MessageJson.decodeMessage(~Unit, ~Unit, ~noDiagnostics, ~noDetails, first), messages(rest))

def simpleChoice(value: Maybe<&2, String>) -> Maybe<&2, T.ToolChoice>:
  match value:
    case Some{"auto"}: Some{T.AutoTool{}}
    case Some{"none"}: Some{T.NoTool{}}
    case _: None{}

def jsonText(value: J()) -> String: Maybe.default(&2, String, Wire.stringify(value), "null")

def StreamEvent() -> Data: T.AssistantMessageEvent<V.Value, Unit>

def Message() -> Data: T.AssistantMessage<V.Value, Unit>

def Run() -> Type: Responses.Run<Unit, Unit, String>

def model(+base: String, +value: V.Value) -> T.Model<J()>:
  +id = Maybe.default(&2, String, text(field(value, "id")), "gpt-5.1-codex")
  T.Model{id, Maybe.default(&2, String, text(field(value, "name")), id), T.OpenAICodexResponsesApi{}, "openai-codex", base, Maybe.default(&2, Bool, flag(field(value, "reasoning")), True{}), levels(field(value, "thinkingLevelMap")), inputs(list(field(value, "input"))), None{}, cost(field(value, "cost")), None{}, Maybe.default(&2, F64, number(field(value, "contextWindow")), F.fromU32(400000)), Maybe.default(&2, F64, number(field(value, "maxTokens")), F.fromU32(128000)), None{}, None{}, None{}}

def context(+value: V.Value) -> T.TranscriptContext<V.Value, V.Value, Unit, Unit>:
  Transcript.normalizeContext(V.Value, V.Value, Unit, Unit, T.Context{text(field(value, "systemPrompt")), messages(list(field(value, "messages"))), tools(field(value, "tools"))})

def transport(value: Maybe<&2, String>) -> Maybe<&2, T.Transport>:
  match value:
    case Some{"sse"}: Some{T.Sse{}}
    case Some{"websocket"}: Some{T.WebSocket{}}
    case Some{"websocket-cached"}: Some{T.WebSocketCached{}}
    case Some{"auto"}: Some{T.AutoTransport{}}
    case _: None{}

def retention(value: Maybe<&2, String>) -> Maybe<&2, T.CacheRetention>:
  match value:
    case Some{"none"}: Some{T.CacheNone{}}
    case Some{"short"}: Some{T.CacheShort{}}
    case Some{"long"}: Some{T.CacheLong{}}
    case _: None{}

def tier(value: Maybe<&2, String>) -> Maybe<&2, T.Nullable<Responses.ServiceTier>>:
  match value:
    case Some{"auto"}: Some{T.PresentValue{Responses.TierAuto{}}}
    case Some{"default"}: Some{T.PresentValue{Responses.TierDefault{}}}
    case Some{"flex"}: Some{T.PresentValue{Responses.TierFlex{}}}
    case Some{"scale"}: Some{T.PresentValue{Responses.TierScale{}}}
    case Some{"priority"}: Some{T.PresentValue{Responses.TierPriority{}}}
    case _: None{}

def jsonChoice(value: Maybe<&2, V.Value>) -> Maybe<&2, J()>: Maybe.map(&2, V.Value, J(), Convert.toJson, value)

def streamOptions(+value: V.Value, signal: Abort.AbortSignal<Unit>) -> Responses.OpenAIResponsesOptions<Unit, Unit, String>:
  Responses.OpenAIResponsesOptions{Some{signal}, None{}, text(field(value, "apiKey")), None{}, None{}, None{}, None{}, headers(field(value, "headers")), number(field(value, "timeoutMs")), number(field(value, "maxRetries")), number(field(value, "maxRetryDelayMs")), None{}, None{}, None{}, transport(text(field(value, "transport"))), retention(text(field(value, "cacheRetention"))), text(field(value, "sessionId")), number(field(value, "websocketConnectTimeoutMs")), None{}, thinking(text(field(value, "reasoningEffort"))), None{}, tier(text(field(value, "serviceTier"))), jsonChoice(field(value, "toolChoice"))}

def simpleOptions(+value: V.Value, signal: Abort.AbortSignal<Unit>) -> Responses.SimpleStreamOptions(Unit, Unit, String):
  T.SimpleStreamOptions{Some{signal}, None{}, text(field(value, "apiKey")), None{}, None{}, None{}, None{}, headers(field(value, "headers")), number(field(value, "timeoutMs")), number(field(value, "maxRetries")), number(field(value, "maxRetryDelayMs")), None{}, None{}, None{}, transport(text(field(value, "transport"))), retention(text(field(value, "cacheRetention"))), text(field(value, "sessionId")), number(field(value, "websocketConnectTimeoutMs")), None{}, simpleChoice(text(field(value, "toolChoice"))), thinking(text(field(value, "reasoning"))), None{}, None{}}

def rendered(error: String) -> String: error

def streamed(owner: Run()) -> Responses.SimpleRun(Unit, Unit, String): Done{owner}

def started(entry: Maybe<&2, String>, +model: T.Model<J()>, +context: T.TranscriptContext<V.Value, V.Value, Unit, Unit>, +options: V.Value, signal: Abort.AbortSignal<Unit>) -> IO(Responses.SimpleRun(Unit, Unit, String)):
  match entry:
    case Some{"simple"}: Codex.streamSimple(~Unit, ~Unit, ~Unit, ~Unit, ~String, ~rendered, RP.config(), model, context, Some{simpleOptions(options, signal)})
    case _:
      do IO<Responses.SimpleRun(Unit, Unit, String)>:
        owner : Run() <- Codex.stream(~Unit, ~Unit, ~Unit, ~Unit, ~String, ~rendered, RP.config(), model, context, streamOptions(options, signal))
        return streamed(owner)

def label(event: StreamEvent()) -> String:
  match event:
    case T.Start{_}: "start"
    case T.TextStart{_, _}: "text_start"
    case T.TextDelta{_, delta, _}: "text_delta:" ++ delta
    case T.TextEnd{_, _, _}: "text_end"
    case T.ThinkingStart{_, _}: "thinking_start"
    case T.ThinkingDelta{_, _, _}: "thinking_delta"
    case T.ThinkingEnd{_, _, _}: "thinking_end"
    case T.ToolcallStart{_, _}: "toolcall_start"
    case T.ToolcallDelta{_, _, _}: "toolcall_delta"
    case T.ToolcallEnd{_, _, _}: "toolcall_end"
    case T.StreamDone{_, _}: "done"
    case T.StreamError{_, _}: "error"
    case _: "other"

def abortWhen(hit: Bool, controller: Abort.AbortController<Unit>) -> IO(Unit):
  match hit:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        won : Bool <- Abort.abort(Unit, controller, None{})
        return Unit{}

@unsafe def drain(next: Events.Iteration<StreamEvent()>, +cursor: Events.Iterator<StreamEvent(), Message()>, +controller: Abort.AbortController<Unit>, +trigger: String) -> IO(Unit):
  match next:
    case Events.Yield{event}:
      +name = label(event)
      do IO<Unit>:
        IO.print("E " ++ name)
        abortWhen(String.eq(name, trigger), controller)
        following : Events.Iteration<StreamEvent()> <- Events.nextValue(StreamEvent(), Message(), cursor)
        drain(following, cursor, controller, trigger)
    case Events.End{}: Events.disposeIterator(StreamEvent(), Message(), cursor)

def unitDetails(value: Unit) -> V.Value: V.Null{}

def observed(pair: Run() & Events.AssistantMessageEventStream(V.Value, Unit), +controller: Abort.AbortController<Unit>, trigger: String) -> IO(Unit):
  match pair:
    case (owner, +events):
      do IO<Unit>:
        +cursor : Events.Iterator<StreamEvent(), Message()> <- Events.iterator(StreamEvent(), Message(), events)
        first : Events.Iteration<StreamEvent()> <- Events.nextValue(StreamEvent(), Message(), cursor)
        drain(first, cursor, controller, trigger)
        message : Message() <- Events.resultValue(StreamEvent(), Message(), events)
        result : Responses.RunResult<Unit, Unit, String> <- Responses.dispose(Unit, Unit, String, owner)
        IO.print("R " ++ Text.showText(jsonText(Convert.toJson(MessageJson.assistantMessage(~Unit, ~unitDetails, message)))))

# A streamSimple that fails before a stream exists prints "T " and the message.
def outcome(result: Responses.SimpleRun(Unit, Unit, String), +controller: Abort.AbortController<Unit>, trigger: String) -> IO(Unit):
  match result:
    case Fail{cause}: IO.print("T " ++ Responses.describePreparation(cause))
    case Done{owner}: observed(Responses.borrow(Unit, Unit, String, owner), controller, trigger)

def runCase(+base: String, +value: V.Value) -> IO(Unit):
  +options = Maybe.default(&2, V.Value, field(value, "options"), V.ObjectValue{R.new(V.Value)})
  do IO<Unit>:
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    result : Responses.SimpleRun(Unit, Unit, String) <- started(text(field(value, "entry")), model(base, Maybe.default(&2, V.Value, field(value, "model"), V.Null{})), context(value), options, Abort.signal(Unit, controller))
    outcome(result, controller, Maybe.default(&2, String, text(field(value, "abortOnEvent")), "(never)"))
    Abort.dispose(Unit, controller)

def parsed(+base: String, value: Result<&2, &2, Decode.ParseError, V.Value>) -> IO(Unit):
  match value:
    case Done{item}: runCase(base, item)
    case Fail{_}: IO.die(Unit, 1, "invalid case")

def cases(+base: String, values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case value <> rest:
      do IO<Unit>:
        parsed(base, Decode.parse(Text.fromScalars(Text.parseNumbers(value))))
        cases(base, rest)

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case base <> rest: cases(base, rest)
    case Nil{}: IO.die(Unit, 1, "base URL required")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
