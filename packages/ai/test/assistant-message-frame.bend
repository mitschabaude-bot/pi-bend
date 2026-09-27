import Base
import ../src/types.bend as T
import ../src/utils/assistant-message-frame.bend as AMF
import ../src/utils/diagnostics.bend as Diagnostics
import ../src/utils/json.bend as Wire
import ../src/utils/message-json.bend as MJ
import ../src/utils/schema-json.bend as Convert
import ../src/api/openai-responses-stream.bend as Stream
import ../../runtime/src/f64.bend as F
import ../../runtime/src/json.bend as Decode
import ../../runtime/src/record.bend as R
import ../../runtime/src/schema-value.bend as V

# pi-mono f07218c4d packages/ai/test/assistant-message-frame.test.ts.
# Upstream mutates one live partial between events; here each event carries
# the partial as it is when the event is encoded (events built first and
# encoded later all see the final partial). Values are compared through their
# JSON (message-json.bend for content, frameJson below for frames); thrown
# errors are the Fail messages of encode/reduce, matched by substring as
# toThrow does. Typed content blocks cannot carry provider scratch fields, and
# values are immutable, so "whitelists public block fields" and "snapshots
# mutable event data" check the values the frames and the reduction carry.

def G() -> Data: V.Value
def Message() -> Data: T.AssistantMessage<V.Value, V.Value>
def MsgEvent() -> Data: T.AssistantMessageEvent<V.Value, V.Value>
def Frame() -> Data: AMF.AssistantMessageFrame<V.Value>

def expect(+name: String, +actual: String, +expected: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.eq(actual, expected), IO.print("PASS " ++ name), IO.die(Unit, 1, "FAIL " ++ name ++ ":\n  actual   " ++ actual ++ "\n  expected " ++ expected))

def N() -> String: "assistant-message-frame.test.ts > assistant message frames > "

# Values
# ------
def zero() -> F64: F.fromU32(0)
def num(+value: U32) -> F64: F.fromU32(value)

def usage() -> T.Usage: T.Usage{zero(), zero(), zero(), zero(), None{}, None{}, zero(), T.UsageCost{zero(), zero(), zero(), zero(), zero()}}

def seed() -> Message(): T.AssistantMessage{Nil{}, "test-api", "test-provider", "test-model", None{}, None{}, None{}, None{}, usage(), T.Pending{}, None{}, None{}, None{}, None{}, num(1)}

def withBlocks(message: Message(), content: List<&2, T.AssistantContent<V.Value>>) -> Message(): AMF.withContent(V.Value, message, content)

def valueOf(result: Result<&2, &2, Decode.ParseError, V.Value>) -> V.Value:
  match result:
    case Done{value}: value
    case Fail{_}: V.Text{"<invalid test JSON>"}

def val(text: String) -> V.Value: valueOf(Decode.parse(text))

def text(value: String, signature: Maybe<&2, String>) -> T.AssistantContent<V.Value>: T.AssistantText{T.TextContent{value, signature}}
def thinking(value: String, signature: Maybe<&2, String>, redacted: Maybe<&2, Bool>) -> T.AssistantContent<V.Value>: T.AssistantThinking{T.ThinkingContent{value, signature, redacted}}
def tool(id: String, name: String, arguments: String, signature: Maybe<&2, String>, namespace: Maybe<&2, String>) -> T.ToolCall<V.Value>: T.ToolCall{id, name, val(arguments), signature, namespace}
def toolBlock(id: String, name: String, arguments: String, signature: Maybe<&2, String>, namespace: Maybe<&2, String>) -> T.AssistantContent<V.Value>: T.AssistantToolCall{tool(id, name, arguments, signature, namespace)}

# JSON
# ----
def json(value: V.Value) -> String: Maybe.default(&2, String, Wire.stringify(Convert.toJson(value)), "<unserializable>")

def contentJson(content: List<&2, T.AssistantContent<V.Value>>) -> String: json(V.ArrayValue{MJ.assistantContents(content)})

def messageJson(message: Message()) -> String: json(MJ.assistantMessage(~V.Value, ~(details => details), message))

def idx(+index: F64) -> R.Property<V.Value>: R.Property{"contentIndex", V.Number{index}}
def prop(name: String, value: V.Value) -> R.Property<V.Value>: R.Property{name, value}
def kind(name: String) -> R.Property<V.Value>: R.Property{"type", V.Text{name}}
def optionalText(name: String, value: Maybe<&2, String>) -> List<&2, R.Property<V.Value>>:
  match value:
    case Some{found}: [prop(name, V.Text{found})]
    case None{}: Nil{}
def optionalFlag(name: String, value: Maybe<&2, Bool>) -> List<&2, R.Property<V.Value>>:
  match value:
    case Some{found}: [prop(name, V.Boolean{found})]
    case None{}: Nil{}
def object(fields: List<&2, R.Property<V.Value>>) -> V.Value: V.ObjectValue{R.Record{fields}}

def frameValue(frame: Frame()) -> V.Value:
  match frame:
    case AMF.StartFrame{partial}: object([kind("start"), prop("partial", MJ.assistantMessage(~V.Value, ~(details => details), partial))])
    case AMF.TextStartFrame{index, content}: object([kind("text_start"), idx(index), prop("content", MJ.textContent(content))])
    case AMF.TextDeltaFrame{index, delta}: object([kind("text_delta"), idx(index), prop("delta", V.Text{delta})])
    case AMF.TextEndFrame{index, content, signature}: object(kind("text_end") <> idx(index) <> prop("content", V.Text{content}) <> optionalText("textSignature", signature))
    case AMF.ThinkingStartFrame{index, content}: object([kind("thinking_start"), idx(index), prop("content", MJ.thinkingContent(content))])
    case AMF.ThinkingDeltaFrame{index, delta}: object([kind("thinking_delta"), idx(index), prop("delta", V.Text{delta})])
    case AMF.ThinkingEndFrame{index, content, signature, redacted}: object(kind("thinking_end") <> idx(index) <> prop("content", V.Text{content}) <> List.append(&2, R.Property<V.Value>, optionalText("thinkingSignature", signature), optionalFlag("redacted", redacted)))
    case AMF.ToolcallStartFrame{index, call}: object([kind("toolcall_start"), idx(index), prop("toolCall", MJ.toolCall(call))])
    case AMF.ToolcallCheckpointFrame{index, body}: object([kind("toolcall_checkpoint"), idx(index), prop("json", V.Text{body})])
    case AMF.ToolcallDeltaFrame{index, delta}: object([kind("toolcall_delta"), idx(index), prop("delta", V.Text{delta})])
    case AMF.ToolcallEndFrame{index, id, name, arguments, signature, namespace}: object(kind("toolcall_end") <> idx(index) <> prop("id", V.Text{id}) <> prop("name", V.Text{name}) <> prop("arguments", arguments) <> List.append(&2, R.Property<V.Value>, optionalText("thoughtSignature", signature), optionalText("namespace", namespace)))

def frameJson(frame: Frame()) -> String: json(frameValue(frame))

def frameValues(frames: List<&2, Frame()>) -> List<&2, V.Value>:
  match frames:
    case Nil{}: Nil{}
    case frame <> rest: frameValue(frame) <> frameValues(rest)

def frameTypes(frames: List<&2, Frame()>) -> List<&2, String>:
  match frames:
    case Nil{}: Nil{}
    case frame <> rest: AMF.frameType(V.Value, frame) <> frameTypes(rest)

def framesJson(frames: List<&2, Frame()>) -> String: json(V.ArrayValue{frameValues(frames)})

def typesOf(frames: List<&2, Frame()>) -> String: String.join(frameTypes(frames), ",")

# Encoding
# --------
def Outputs() -> Data: Result<&2, &2, String, List<&2, Maybe<&2, Frame()>>>

type Encoding is Data:
  Encoding{encoder: AMF.AssistantMessageFrameEncoder, reversed: List<&2, Maybe<&2, Frame()>>}

def afterEncode(encoded: AMF.Encoded(V.Value), reversed: List<&2, Maybe<&2, Frame()>>) -> Result<&2, &2, String, Encoding>:
  match encoded:
    case Fail{message}: Fail{message}
    case Done{AMF.Encoding{encoder, frame}}: Done{Encoding{encoder, frame <> reversed}}

def stepEncoding(state: Result<&2, &2, String, Encoding>, event: MsgEvent()) -> Result<&2, &2, String, Encoding>:
  match state:
    case Fail{message}: Fail{message}
    case Done{Encoding{encoder, reversed}}: afterEncode(AMF.encode(V.Value, encoder, event), reversed)

def finished(state: Result<&2, &2, String, Encoding>) -> Outputs():
  match state:
    case Fail{message}: Fail{message}
    case Done{Encoding{_, reversed}}: Done{List.reverse(&2, Maybe<&2, Frame()>, reversed)}

def encodeFrom(events: List<&2, MsgEvent()>, state: Result<&2, &2, String, Encoding>) -> Outputs():
  match events:
    case Nil{}: finished(state)
    case event <> rest: encodeFrom(rest, stepEncoding(state, event))

# Each event's frame (None when it adds nothing), or the first error.
def encodeAll(events: List<&2, MsgEvent()>) -> Outputs(): encodeFrom(events, Done{Encoding{AMF.newEncoder(), Nil{}}})

def somes(values: List<&2, Maybe<&2, Frame()>>) -> List<&2, Frame()>:
  match values:
    case Nil{}: Nil{}
    case Some{frame} <> rest: frame <> somes(rest)
    case None{} <> rest: somes(rest)

def framesOf(outputs: Outputs()) -> List<&2, Frame()>:
  match outputs:
    case Done{values}: somes(values)
    case Fail{_}: Nil{}

def outputText(output: Maybe<&2, Frame()>) -> String:
  match output:
    case Some{frame}: frameJson(frame)
    case None{}: "undefined"

def outputTexts(values: List<&2, Maybe<&2, Frame()>>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: outputText(value) <> outputTexts(rest)

def outputsText(outputs: Outputs()) -> String:
  match outputs:
    case Fail{message}: "error: " ++ message
    case Done{values}: String.join(outputTexts(values), " ; ")

def lastOutput(outputs: Outputs()) -> String:
  match outputs:
    case Fail{message}: "error: " ++ message
    case Done{values}: Maybe.default(&2, String, Maybe.map(&2, Maybe<&2, Frame()>, String, outputText, List.last(&2, Maybe<&2, Frame()>, values)), "none")

def errorOf(outputs: Outputs()) -> String:
  match outputs:
    case Fail{message}: message
    case Done{_}: "no error"

def contains(+haystack: String, +needle: String) -> String: Bool.pick(String, String.contains(haystack, needle), "throws " ++ needle, "no match: " ++ haystack)

# Reduction
# ---------
def Reduced() -> Data: Result<&2, &2, String, Maybe<&2, Message()>>

def reduce(frames: List<&2, Frame()>) -> Reduced(): AMF.reduceAssistantMessageFrames(V.Value, frames)

def reducedContent(reduced: Reduced()) -> String:
  match reduced:
    case Fail{message}: "error: " ++ message
    case Done{None{}}: "undefined"
    case Done{Some{message}}: contentJson(T.assistantContent(V.Value, V.Value, message))

def reducedFirst(reduced: Reduced()) -> String:
  match reduced:
    case Fail{message}: "error: " ++ message
    case Done{None{}}: "undefined"
    case Done{Some{message}}: Maybe.default(&2, String, Maybe.map(&2, T.AssistantContent<V.Value>, String, block => json(MJ.assistantContent(block)), List.head(&2, T.AssistantContent<V.Value>, T.assistantContent(V.Value, V.Value, message))), "none")

def reducedError(reduced: Reduced()) -> String:
  match reduced:
    case Fail{message}: message
    case Done{_}: "no error"

def argumentsOf(block: T.AssistantContent<V.Value>) -> String:
  match block:
    case T.AssistantToolCall{T.ToolCall{_, _, arguments, _, _}}: json(arguments)
    case _: "not a tool call"

def firstArguments(reduced: Reduced()) -> String:
  match reduced:
    case Done{Some{message}}: Maybe.default(&2, String, Maybe.map(&2, T.AssistantContent<V.Value>, String, argumentsOf, List.head(&2, T.AssistantContent<V.Value>, T.assistantContent(V.Value, V.Value, message))), "none")
    case _: "no message"

# Tests
# -----
def authoritativeTextEnd() -> IO(Unit):
  +p1 = withBlocks(seed(), [text("Hello ", None{})])
  +p2 = withBlocks(seed(), [text("Hello world", Some{"sig-text"})])
  +outputs = encodeAll([T.Start{seed()}, T.TextStart{zero(), p1}, T.TextDelta{zero(), "incorrect", p2}, T.TextEnd{zero(), "Hello world", p2}])
  expect(N() ++ "uses authoritative text end content and signature", lastOutput(outputs) ++ " | " ++ reducedContent(reduce(framesOf(outputs))), frameJson(AMF.TextEndFrame{zero(), "Hello world", Some{"sig-text"}}) ++ " | " ++ contentJson([text("Hello world", Some{"sig-text"})]))

def levelOf(reduced: Reduced()) -> String:
  match reduced:
    case Done{Some{T.AssistantMessage{_, _, _, _, _, _, level, _, _, _, _, _, _, _, _}}}: Maybe.default(&2, String, level, "undefined")
    case _: "no message"

def startLevel(frames: List<&2, Frame()>) -> String:
  match frames:
    case AMF.StartFrame{T.AssistantMessage{_, _, _, _, _, _, level, _, _, _, _, _, _, _, _}} <> _: Maybe.default(&2, String, level, "undefined")
    case _: "no start"

def providerThinkingLevel() -> IO(Unit):
  +partial = {T.AssistantMessage{Nil{}, "test-api", "test-provider", "test-model", None{}, None{}, Some{"high"}, None{}, usage(), T.Pending{}, None{}, None{}, None{}, None{}, num(1)} : T.AssistantMessage<V.Value, V.Value>}
  +frames = framesOf(encodeAll([T.Start{partial}]))
  expect(N() ++ "preserves provider thinking level from the stream start", startLevel(frames) ++ " " ++ levelOf(reduce(frames)), "high high")

def thinkingMetadata() -> IO(Unit):
  +p1 = withBlocks(seed(), [thinking("[redacted]", Some{"encrypted-start"}, Some{True{}})])
  +p2 = withBlocks(seed(), [thinking("[redacted]", Some{"encrypted-final"}, Some{True{}})])
  +outputs = encodeAll([T.Start{seed()}, T.ThinkingStart{zero(), p1}, T.ThinkingEnd{zero(), "[redacted]", p2}])
  expect(N() ++ "preserves initial and final thinking metadata, including redaction", lastOutput(outputs) ++ " | " ++ reducedFirst(reduce(framesOf(outputs))), frameJson(AMF.ThinkingEndFrame{zero(), "[redacted]", Some{"encrypted-final"}, Some{True{}}}) ++ " | " ++ json(MJ.assistantContent(thinking("[redacted]", Some{"encrypted-final"}, Some{True{}}))))

def unfinishedToolJson() -> IO(Unit):
  +initial = {[AMF.StartFrame{seed()}, AMF.ToolcallStartFrame{zero(), tool("initial-id", "write", "{}", None{}, None{})}, AMF.ToolcallDeltaFrame{zero(), "{\"path\":\"READ"}] : List<&2, AMF.AssistantMessageFrame<V.Value>>}
  +complete = List.append(&2, Frame(), initial, [AMF.ToolcallDeltaFrame{zero(), "ME.md\",\"lines\":[1,2]}"}, AMF.ToolcallEndFrame{zero(), "final-id", "write_file", val("{\"path\":\"final.md\",\"lines\":[3]}"), Some{"thought"}, Some{"files"}}])
  expect(N() ++ "parses unfinished tool JSON once and uses authoritative completed arguments", firstArguments(reduce(initial)) ++ " | " ++ reducedFirst(reduce(complete)), "{\"path\":\"READ\"} | " ++ json(MJ.assistantContent(toolBlock("final-id", "write_file", "{\"path\":\"final.md\",\"lines\":[3]}", Some{"thought"}, Some{"files"}))))

# Round trip through the native processResponsesStream: its emitted events are
# encoded as they are pushed.
type Recorder is Data:
  Recorder{remaining: List<&2, Stream.ResponseStreamEvent>, events: List<&2, MsgEvent()>}

def firstEvent(events: List<&2, Stream.ResponseStreamEvent>) -> Maybe<&2, Stream.ResponseStreamEvent>: List.head(&2, Stream.ResponseStreamEvent, events)

def next(state: Recorder) -> IO(Recorder & Result<&2, &2, String, Maybe<&2, Stream.ResponseStreamEvent>>):
  match state:
    case Recorder{+remaining, events}: IO.pure(Recorder & Result<&2, &2, String, Maybe<&2, Stream.ResponseStreamEvent>>, (Recorder{List.drop(&2, Stream.ResponseStreamEvent, remaining, 1n), events}, Done{firstEvent(remaining)}))

def close(state: Recorder) -> IO(Recorder & Result<&2, &2, String, Unit>): IO.pure(Recorder & Result<&2, &2, String, Unit>, (state, Done{Unit{}}))

def emit(state: Recorder, event: MsgEvent()) -> IO(Recorder & Result<&2, &2, String, Unit>):
  match state:
    case Recorder{remaining, events}: IO.pure(Recorder & Result<&2, &2, String, Unit>, (Recorder{remaining, event <> events}, Done{Unit{}}))

def responsesModel() -> T.Model<Unit>:
  T.Model{"test-model", "Test", T.OpenAIResponsesApi{}, "openai", "https://api.openai.com/v1", False{}, None{}, [T.InputText{}], None{}, T.ModelCost{zero(), zero(), zero(), zero(), None{}}, None{}, num(1000), num(100), None{}, None{}, None{}}

def responsesEvents() -> List<&2, Stream.ResponseStreamEvent>:
  [Stream.ContentEvent{Stream.Added{zero(), Stream.MessageItem{"msg", None{}, Nil{}}}},
   Stream.ContentEvent{Stream.Changed{zero(), Stream.ItemDone{Stream.MessageItem{"msg", None{}, ["final text"]}}}},
   Stream.ContentEvent{Stream.Added{num(1), Stream.FunctionItem{"fc", "call", "lookup", "", None{}}}},
   Stream.ContentEvent{Stream.Changed{num(1), Stream.ItemDone{Stream.FunctionItem{"fc", "call", "lookup", "{\"query\":\"pi\"}", None{}}}}},
   Stream.ResponseCompleted{Stream.Response{Some{"response"}, Some{"completed"}, None{}, Nil{}, None{}, None{}}}]

def responsesOutput() -> Message(): T.AssistantMessage{Nil{}, "openai-responses", "openai", "test-model", None{}, None{}, None{}, None{}, usage(), T.Pending{}, None{}, None{}, None{}, None{}, num(1)}

def roundTripped(pair: Recorder & Stream.RunResult<V.Value, String>) -> IO(Unit):
  match pair:
    case (Recorder{_, events}, Stream.RunResult{output, _}):
      +frames = framesOf(encodeAll(T.Start{responsesOutput()} <> List.reverse(&2, MsgEvent(), events)))
      +expected = contentJson(T.assistantContent(V.Value, V.Value, output))
      expect(N() ++ "round-trips OpenAI Responses content supplied only by authoritative end events", reducedContent(reduce(frames)) ++ Bool.pick(String, String.contains(expected, "final text") && String.contains(expected, "lookup"), "", " (the stream produced no content)"), expected)

def responsesRoundTrip() -> IO(Unit):
  do IO<Unit>:
    pair : Recorder & Stream.RunResult<V.Value, String> <- Stream.processResponsesStream(~Recorder, ~String, ~Unit, ~V.Value, ~next, ~close, ~emit, ~Stream.defaultResolveServiceTier, ~(Stream.noServiceTierPricing(Unit)), Recorder{responsesEvents(), Nil{}}, responsesOutput(), responsesModel(), Stream.OpenAIResponsesStreamOptions{None{}, R.new(String)})
    roundTripped(pair)

def startContent(frames: List<&2, Frame()>) -> String:
  match frames:
    case AMF.StartFrame{+partial} <> _: contentJson(T.assistantContent(V.Value, V.Value, partial)) ++ " " ++ MJ.stopReason(T.assistantStopReason(V.Value, V.Value, partial))
    case _: "no start"

def queuedText() -> IO(Unit):
  +final = withBlocks(seed(), [text("Hello world", None{})])
  +frames = framesOf(encodeAll([T.Start{final}, T.TextStart{zero(), final}, T.TextDelta{zero(), "Hel", final}, T.TextDelta{zero(), "lo", final}, T.TextDelta{zero(), " ", final}, T.TextDelta{zero(), "world", final}]))
  expect(N() ++ "reconciles queued text events against one advanced live partial without duplicate content", typesOf(frames) ++ " | " ++ startContent(frames) ++ " | " ++ reducedContent(reduce(frames)), "start,text_start | [] pending | " ++ contentJson([text("Hello world", None{})]))

def coveredPrefix() -> IO(Unit):
  +partial = withBlocks(seed(), [text("Hel", None{})])
  +outputs = encodeAll([T.Start{seed()}, T.TextStart{zero(), partial}, T.TextDelta{zero(), "He", partial}, T.TextDelta{zero(), "llo", partial}])
  expect(N() ++ "trims only the covered prefix when a start snapshot lands inside a delta", outputsText(outputs) ++ " | " ++ reducedContent(reduce(framesOf(outputs))), frameJson(AMF.StartFrame{seed()}) ++ " ; " ++ frameJson(AMF.TextStartFrame{zero(), T.TextContent{"Hel", None{}}}) ++ " ; undefined ; " ++ frameJson(AMF.TextDeltaFrame{zero(), "lo"}) ++ " | " ++ contentJson([text("Hello", None{})]))

def queuedToolJson() -> IO(Unit):
  +final = withBlocks(seed(), [toolBlock("call", "write", "{\"path\":\"README.md\"}", None{}, None{})])
  +frames = framesOf(encodeAll([T.Start{final}, T.ToolcallStart{zero(), final}, T.ToolcallDelta{zero(), "{\"path\":\"READ", final}, T.ToolcallDelta{zero(), "ME.md\"}", final}]))
  expect(N() ++ "checkpoints queued tool JSON without replaying covered deltas", typesOf(frames) ++ " | " ++ Maybe.default(&2, String, Maybe.map(&2, Frame(), String, frameJson, List.last(&2, Frame(), frames)), "none") ++ " | " ++ reducedContent(reduce(frames)), "start,toolcall_start,toolcall_checkpoint | " ++ frameJson(AMF.ToolcallCheckpointFrame{zero(), "{\"path\":\"README.md\"}"}) ++ " | " ++ contentJson([toolBlock("call", "write", "{\"path\":\"README.md\"}", None{}, None{})]))

def legacyGrammar() -> IO(Unit):
  +outputs = encodeAll([T.Start{seed()}, T.ToolcallStart{zero(), withBlocks(seed(), [toolBlock("call", "bash", "{\"input\":\"a\"}", None{}, None{})])}, T.ToolcallDelta{zero(), "{\"input\":\"ab", withBlocks(seed(), [toolBlock("call", "bash", "{\"input\":\"ab\"}", None{}, None{})])}, T.ToolcallDelta{zero(), "c\"}", withBlocks(seed(), [toolBlock("call", "bash", "{\"input\":\"abc\"}", None{}, None{})])}])
  +frames = framesOf(outputs)
  expect(N() ++ "resumes legacy grammar tool JSON from initial arguments", framesJson(List.drop(&2, Frame(), frames, 2n)) ++ " | " ++ reducedContent(reduce(frames)), framesJson([AMF.ToolcallCheckpointFrame{zero(), "{\"input\":\"ab"}, AMF.ToolcallDeltaFrame{zero(), "c\"}"}]) ++ " | " ++ contentJson([toolBlock("call", "bash", "{\"input\":\"abc\"}", None{}, None{})]))

def compactToolJson() -> IO(Unit):
  +outputs = encodeAll([T.Start{seed()}, T.ToolcallStart{zero(), withBlocks(seed(), [toolBlock("call", "bash", "{}", None{}, None{})])}, T.ToolcallDelta{zero(), "{\"command\":\"ls -la /tmp\"}", withBlocks(seed(), [toolBlock("call", "bash", "{\"command\":\"ls -la /tmp\"}", None{}, None{})])}])
  expect(N() ++ "streams tool JSON compactly from an empty argument start", lastOutput(outputs) ++ " | " ++ firstArguments(reduce(framesOf(outputs))), frameJson(AMF.ToolcallDeltaFrame{zero(), "{\"command\":\"ls -la /tmp\"}"}) ++ " | {\"command\":\"ls -la /tmp\"}")

def failed(message: String) -> Message(): T.AssistantMessage{Nil{}, "test-api", "test-provider", "test-model", None{}, None{}, None{}, None{}, usage(), T.Error{}, None{}, Some{message}, None{}, None{}, num(1)}

def completed() -> Message(): T.AssistantMessage{Nil{}, "test-api", "test-provider", "test-model", None{}, None{}, None{}, None{}, usage(), T.Stop{}, None{}, None{}, None{}, None{}, num(1)}

def preGeneration() -> IO(Unit):
  expect(N() ++ "accepts a pre-generation error but rejects success or updates before start", outputsText(encodeAll([T.StreamError{T.ErrorError{}, failed("setup failed")}])) ++ " | " ++ contains(errorOf(encodeAll([T.StreamDone{T.DoneStop{}, completed()}])), "done event appears before start") ++ " | " ++ contains(errorOf(encodeAll([T.TextDelta{zero(), "x", seed()}])), "text_delta event appears before start"), "undefined | throws done event appears before start | throws text_delta event appears before start")

def authoritativeEndMetadata() -> IO(Unit):
  +frames = {[AMF.StartFrame{seed()}, AMF.TextStartFrame{zero(), T.TextContent{"", Some{"stale-text"}}}, AMF.TextEndFrame{zero(), "", None{}}, AMF.ThinkingStartFrame{num(1), T.ThinkingContent{"", Some{"stale-thinking"}, Some{True{}}}}, AMF.ThinkingEndFrame{num(1), "", Some{""}, Some{False{}}}, AMF.ToolcallStartFrame{num(2), tool("call", "read", "{}", Some{"stale-tool"}, Some{"stale-namespace"})}, AMF.ToolcallEndFrame{num(2), "call", "read", val("{}"), None{}, None{}}] : List<&2, AMF.AssistantMessageFrame<V.Value>>}
  expect(N() ++ "treats end signature metadata, including absence, as authoritative", reducedContent(reduce(frames)), contentJson([text("", None{}), thinking("", Some{""}, Some{False{}}), toolBlock("call", "read", "{}", None{}, None{})]))

def finalArgumentsInEnd() -> IO(Unit):
  +call = tool("call-1", "read", "{\"path\":\"README.md\"}", Some{"thought"}, Some{"files"})
  +partial = withBlocks(seed(), [T.AssistantToolCall{call}])
  expect(N() ++ "stores authoritative final arguments in toolcall_end frames", lastOutput(encodeAll([T.Start{partial}, T.ToolcallStart{zero(), partial}, T.ToolcallEnd{zero(), call, partial}])), frameJson(AMF.ToolcallEndFrame{zero(), "call-1", "read", val("{\"path\":\"README.md\"}"), Some{"thought"}, Some{"files"}}))

def publicFields() -> IO(Unit):
  +blocks = {[text("visible", Some{"text-sig"}), thinking("reasoning", Some{"thinking-sig"}, Some{False{}}), toolBlock("call", "run", "{\"value\":1}", Some{"tool-sig"}, Some{"tools"})] : List<&2, T.AssistantContent<V.Value>>}
  +partial = withBlocks(seed(), blocks)
  +outputs = encodeAll([T.Start{partial}, T.TextStart{zero(), partial}, T.ThinkingStart{num(1), partial}, T.ToolcallStart{num(2), partial}])
  expect(N() ++ "whitelists public block fields from provider-shaped partials", startContent(framesOf(outputs)) ++ " | " ++ outputsText(outputs), "[] pending | " ++ frameJson(AMF.StartFrame{seed()}) ++ " ; " ++ frameJson(AMF.TextStartFrame{zero(), T.TextContent{"visible", Some{"text-sig"}}}) ++ " ; " ++ frameJson(AMF.ThinkingStartFrame{num(1), T.ThinkingContent{"reasoning", Some{"thinking-sig"}, Some{False{}}}}) ++ " ; " ++ frameJson(AMF.ToolcallStartFrame{num(2), tool("call", "run", "{\"value\":1}", Some{"tool-sig"}, Some{"tools"})}))

def interleaved() -> IO(Unit):
  +frames = {[AMF.StartFrame{seed()}, AMF.TextStartFrame{zero(), T.TextContent{"", None{}}}, AMF.ToolcallStartFrame{num(1), tool("call", "lookup", "{}", None{}, None{})}, AMF.ThinkingStartFrame{num(2), T.ThinkingContent{"", None{}, None{}}}, AMF.TextDeltaFrame{zero(), "answer"}, AMF.ToolcallDeltaFrame{num(1), "{\"query\":\"pi\"}"}, AMF.ThinkingDeltaFrame{num(2), "check"}, AMF.ToolcallEndFrame{num(1), "call", "lookup", val("{\"query\":\"pi\"}"), None{}, None{}}, AMF.TextEndFrame{zero(), "answer", None{}}, AMF.ThinkingEndFrame{num(2), "check", None{}, None{}}] : List<&2, AMF.AssistantMessageFrame<V.Value>>}
  expect(N() ++ "supports interleaved streams by contentIndex", reducedContent(reduce(frames)), contentJson([text("answer", None{}), toolBlock("call", "lookup", "{\"query\":\"pi\"}", None{}, None{}), thinking("check", None{}, None{})]))

def diagnosed(details: String, total: F64, content: List<&2, T.AssistantContent<V.Value>>) -> Message():
  T.AssistantMessage{content, "test-api", "test-provider", "test-model", None{}, None{}, None{}, Some{[Diagnostics.AssistantMessageDiagnostic{"test", num(2), None{}, Some{val(details)}}]}, T.Usage{zero(), zero(), zero(), zero(), None{}, None{}, zero(), T.UsageCost{zero(), zero(), zero(), zero(), total}}, T.Pending{}, None{}, None{}, None{}, None{}, num(1)}

def reducedMessage(reduced: Reduced()) -> String:
  match reduced:
    case Done{Some{message}}: messageJson(message)
    case Fail{message}: "error: " ++ message
    case Done{None{}}: "undefined"

def snapshots() -> IO(Unit):
  +startPartial = diagnosed("{\"value\":\"original\"}", zero(), Nil{})
  +later = diagnosed("{\"value\":\"mutated\"}", num(99), [toolBlock("call", "run", "{\"nested\":{\"value\":\"original\"}}", None{}, None{})])
  +outputs = encodeAll([T.Start{startPartial}, T.ToolcallStart{zero(), later}])
  expect(N() ++ "snapshots mutable event data and keeps reduction pure", reducedMessage(reduce(framesOf(outputs))), messageJson(diagnosed("{\"value\":\"original\"}", zero(), [toolBlock("call", "run", "{\"nested\":{\"value\":\"original\"}}", None{}, None{})])))

def terminalEvents() -> IO(Unit):
  expect(N() ++ "omits terminal events because settlement is separate", outputsText(encodeAll([T.Start{seed()}, T.StreamDone{T.DoneStop{}, completed()}])) ++ " | " ++ outputsText(encodeAll([T.StreamError{T.ErrorError{}, failed("failed")}])), frameJson(AMF.StartFrame{seed()}) ++ " ; undefined | undefined")

def noStart() -> IO(Unit):
  expect(N() ++ "returns undefined when there is no start frame", reducedContent(reduce(Nil{})) ++ " " ++ reducedContent(reduce([AMF.TextDeltaFrame{zero(), "x"}])), "undefined undefined")

def rejections() -> IO(Unit):
  +beforeStart = reducedError(reduce([AMF.TextDeltaFrame{zero(), "x"}, AMF.StartFrame{seed()}]))
  +wrongKind = reducedError(reduce([AMF.StartFrame{seed()}, AMF.ToolcallStartFrame{zero(), tool("call", "run", "{}", None{}, None{})}, AMF.TextDeltaFrame{zero(), "wrong"}]))
  +duplicateEnd = reducedError(reduce([AMF.StartFrame{seed()}, AMF.TextStartFrame{zero(), T.TextContent{"", None{}}}, AMF.TextEndFrame{zero(), "", None{}}, AMF.TextEndFrame{zero(), "", None{}}]))
  +gap = reducedError(reduce([AMF.StartFrame{seed()}, AMF.TextStartFrame{num(1), T.TextContent{"", None{}}}]))
  expect(N() ++ "rejects frames before start, wrong block kinds, duplicate ends, and index gaps", contains(beforeStart, "before the start frame") ++ " | " ++ contains(wrongKind, "expected text block") ++ " | " ++ contains(duplicateEnd, "follows the end") ++ " | " ++ contains(gap, "would leave a gap"), "throws before the start frame | throws expected text block | throws follows the end | throws would leave a gap")

def wrongEventBlock() -> IO(Unit):
  +partial = withBlocks(seed(), [thinking("", None{}, None{})])
  expect(N() ++ "rejects conversion events whose contentIndex points to the wrong block kind", contains(errorOf(encodeAll([T.Start{seed()}, T.TextStart{zero(), partial}])), "text_start event points to thinking block"), "throws text_start event points to thinking block")

def run() -> IO(Unit):
  do IO<Unit>:
    authoritativeTextEnd()
    providerThinkingLevel()
    thinkingMetadata()
    unfinishedToolJson()
    responsesRoundTrip()
    queuedText()
    coveredPrefix()
    queuedToolJson()
    legacyGrammar()
    compactToolJson()
    preGeneration()
    authoritativeEndMetadata()
    finalArgumentsInEnd()
    publicFields()
    interleaved()
    snapshots()
    terminalEvents()
    noStart()
    rejections()
    wrongEventBlock()

def main() -> IO(Unit): run()
