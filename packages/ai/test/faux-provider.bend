import Base
import ../src/types.bend as T
import ../src/providers/faux.bend as Faux
import ../src/utils/event-stream.bend as Events
import ../src/utils/json.bend as Wire
import ../src/utils/message-json.bend as MessageJson
import ../src/utils/schema-json.bend as Schema
import ../src/utils/transcript.bend as Transcript
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/callback.bend as C
import ../../runtime/src/f64.bend as F
import ../../runtime/src/json.bend as Parse
import ../../runtime/src/record.bend as R
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/utf16.bend as Utf16

# pi-mono f07218c4d packages/ai/test/faux-provider.test.ts. Upstream registers
# the faux in the process api registry and calls complete/stream; here each
# test creates a FauxCore and streams through it directly. 'unregisters the
# provider' has no counterpart (no api registry in the Bend ai package).
def J() -> Data: T.JsonValue
def Core() -> Data: Faux.FauxCore<Unit, Unit, String>
def Message() -> Data: T.AssistantMessage<V.Value, Unit>
def FauxEvent() -> Data: T.AssistantMessageEvent<V.Value, Unit>
def Ctx() -> Data: Faux.Context(Unit, Unit)
def Step() -> Data: Faux.FauxResponseStep<Unit, Unit, String>
def Options() -> Data: Faux.Options(String)

def fail(+name: String, detail: String) -> IO(Unit): IO.die(Unit, 1, "FAIL " ++ name ++ ": " ++ detail)

def check(ok: Bool, +name: String, detail: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: fail(name, detail)

def pass(name: String) -> IO(Unit): IO.print("PASS " ++ name)

# Contexts and options
# --------------------
def user(text: String) -> T.Message<V.Value, V.Value, Unit, Unit>: T.User{T.UserMessage{T.UserText{text}, F.fromU32(1)}}

def contextWith(system: Maybe<&2, String>, messages: List<&2, T.Message<V.Value, V.Value, Unit, Unit>>, tools: Maybe<&2, List<&2, T.Tool<V.Value>>>) -> Ctx():
  Transcript.normalizeContext(V.Value, V.Value, Unit, Unit, T.Context{system, messages, tools})

def hi() -> Ctx(): contextWith(None{}, user("hi") <> Nil{}, None{})

def sessionOptions(session: Maybe<&2, String>, retention: Maybe<&2, T.CacheRetention>, signal: Maybe<&2, Abort.AbortSignal<Unit>>) -> Options():
  T.SimpleStreamOptions{signal, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, retention, session, None{}, None{}, None{}, None{}, None{}, None{}}

def text(value: String) -> List<&2, T.AssistantContent<V.Value>>: Faux.fauxText(value) <> Nil{}

def reply(content: List<&2, T.AssistantContent<V.Value>>, stop: Maybe<&2, T.StopReason>, error: Maybe<&2, String>) -> Step():
  Faux.FauxReply{Faux.fauxAssistantMessageAt(Unit, content, Faux.FauxMessageOptions{stop, error, None{}, None{}}, F.fromU32(1))}

def plain(value: String) -> Step(): reply(text(value), None{}, None{})

def core(options: Faux.RegisterFauxProviderOptions) -> IO(Core()): Faux.createFauxCore(Unit, Unit, String, options)

def sized(+size: U32, rate: Maybe<&2, F64>) -> Faux.RegisterFauxProviderOptions:
  Faux.RegisterFauxProviderOptions{None{}, None{}, Nil{}, rate, Some{Faux.FauxTokenSize{Some{F.fromU32(size)}, Some{F.fromU32(size)}}}}

def firstModel(value: Core()) -> T.Model<J()>:
  Maybe.default(&2, T.Model<J()>, Faux.getModel(Unit, Unit, String, value, None{}), Faux.modelOf("faux", "faux", Faux.defaultDefinition()))

# Running a stream
# ----------------
type Outcome is Data:
  Outcome{events: List<&2, FauxEvent()>, message: Message()}

def eventName(event: FauxEvent()) -> String:
  match event:
    case T.Start{_}: "start"
    case T.TextStart{_, _}: "text_start"
    case T.TextDelta{_, _, _}: "text_delta"
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

def abortWhen(hit: Bool, controller: Maybe<&2, Abort.AbortController<Unit>>) -> IO(Unit):
  match hit controller:
    case True{} Some{owner}:
      do IO<Unit>:
        won : Bool <- Abort.abort(Unit, owner, None{})
        return Unit{}
    case _ _: IO.pure(Unit, Unit{})

@unsafe def collect(next: Events.Iteration<FauxEvent()>, +cursor: Events.Iterator<FauxEvent(), Message()>, +trigger: String, +controller: Maybe<&2, Abort.AbortController<Unit>>, reversed: List<&2, FauxEvent()>) -> IO(List<&2, FauxEvent()>):
  match next:
    case Events.Yield{+event}:
      do IO<List<&2, FauxEvent()>>:
        abortWhen(String.eq(eventName(event), trigger), controller)
        following : Events.Iteration<FauxEvent()> <- Events.nextValue(FauxEvent(), Message(), cursor)
        collect(following, cursor, trigger, controller, event <> reversed)
    case Events.End{}:
      do IO<List<&2, FauxEvent()>>:
        Events.disposeIterator(FauxEvent(), Message(), cursor)
        return List.reverse(&2, FauxEvent(), reversed)

def identity(value: String) -> String: value

def collected(pair: Faux.FauxStream<Unit> & Events.AssistantMessageEventStream(V.Value, Unit), trigger: String, controller: Maybe<&2, Abort.AbortController<Unit>>) -> IO(Outcome):
  match pair:
    case (owner, +events):
      do IO<Outcome>:
        +cursor : Events.Iterator<FauxEvent(), Message()> <- Events.iterator(FauxEvent(), Message(), events)
        first : Events.Iteration<FauxEvent()> <- Events.nextValue(FauxEvent(), Message(), cursor)
        emitted : List<&2, FauxEvent()> <- collect(first, cursor, trigger, controller, Nil{})
        message : Message() <- Events.resultValue(FauxEvent(), Message(), events)
        Faux.disposeStream(Unit, owner)
        return Outcome{emitted, message}

def runAborting(value: Core(), +model: T.Model<J()>, +context: Ctx(), options: Maybe<&2, Options()>, trigger: String, controller: Maybe<&2, Abort.AbortController<Unit>>) -> IO(Outcome):
  do IO<Outcome>:
    owner : Faux.FauxStream<Unit> <- Faux.stream(~Unit, ~Unit, ~String, ~identity, value, model, context, options)
    collected(Faux.borrowStream(Unit, owner), trigger, controller)

def run(value: Core(), +model: T.Model<J()>, +context: Ctx(), options: Maybe<&2, Options()>) -> IO(Outcome):
  runAborting(value, model, context, options, "(never)", None{})

def messageOf(outcome: Outcome) -> Message():
  match outcome:
    case Outcome{_, message}: message

def eventsOf(outcome: Outcome) -> List<&2, FauxEvent()>:
  match outcome:
    case Outcome{events, _}: events

def names(events: List<&2, FauxEvent()>) -> List<&2, String>:
  match events:
    case Nil{}: Nil{}
    case event <> rest: eventName(event) <> names(rest)

def shownNames(outcome: Outcome) -> String: String.join(names(eventsOf(outcome)), ",")

def contains(values: List<&2, String>, +wanted: String) -> Bool:
  match values:
    case Nil{}: False{}
    case value <> rest: String.eq(value, wanted) || contains(rest, wanted)

def count(values: List<&2, String>, +wanted: String) -> Nat:
  match values:
    case Nil{}: 0n
    case value <> rest: Bool.pick(Nat, String.eq(value, wanted), 1n, 0n) + count(rest, wanted)

def contentValues(blocks: List<&2, T.AssistantContent<V.Value>>) -> List<&2, V.Value>:
  match blocks:
    case Nil{}: Nil{}
    case block <> rest: MessageJson.assistantContent(block) <> contentValues(rest)

# Message views
# -------------
def contentJson(message: Message()) -> String:
  Maybe.default(&2, String, Wire.stringify(Schema.toJson(V.ArrayValue{contentValues(T.assistantContent(V.Value, Unit, message))})), "")

def unitDetails(value: Unit) -> V.Value: V.Null{}

def textContent(value: String) -> String: "[{\"type\":\"text\",\"text\":\"" ++ value ++ "\"}]"

def stopName(reason: T.StopReason) -> String:
  match reason:
    case T.Stop{}: "stop"
    case T.Length{}: "length"
    case T.ToolUse{}: "toolUse"
    case T.Error{}: "error"
    case T.Aborted{}: "aborted"
    case T.Pending{}: "pending"
    case T.Deferred{}: "deferred"

def stopOf(message: Message()) -> String: stopName(T.assistantStopReason(V.Value, Unit, message))

def errorOf(message: Message()) -> String: Maybe.default(&2, String, T.assistantErrorMessage(V.Value, Unit, message), "(none)")

def usageOf(message: Message()) -> T.Usage: T.assistantUsage(V.Value, Unit, message)

def natOf(value: F64) -> Nat: U32.to_nat(F64.to_u32(value))

def pickField(+field: String, input: Nat, output: Nat, read: Nat, write: Nat, total: Nat) -> Nat:
  match field:
    case "input": input
    case "output": output
    case "cacheRead": read
    case "cacheWrite": write
    case _: total

def usageNumber(usage: T.Usage, +field: String) -> Nat:
  match usage:
    case T.Usage{input, output, read, write, _, _, total, _}: pickField(field, natOf(input), natOf(output), natOf(read), natOf(write), natOf(total))

def usageField(message: Message(), +field: String) -> Nat: usageNumber(usageOf(message), field)

def stateCalls(state: Faux.FauxProviderState) -> Nat:
  match state:
    case Faux.FauxProviderState{calls, _, _}: calls

def callCount(value: Core()) -> IO(Nat):
  do IO<Nat>:
    state : Faux.FauxProviderState <- Faux.getState(Unit, Unit, String, value)
    return stateCalls(state)

def pending(value: Core()) -> IO(Nat): Faux.getPendingResponseCount(Unit, Unit, String, value)

# Factories
# ---------
def FactoryIn() -> Data: Faux.FactoryInput<Unit, Unit, String>
def FactoryOut() -> Data: Result<&2, &2, String, Message()>

def boolText(value: Bool) -> String:
  match value:
    case True{}: "true"
    case False{}: "false"

def modelAware(unused: Unit, input: FactoryIn()) -> IO(FactoryOut()):
  match input:
    case Faux.FactoryInput{_, _, _, +model}: IO.pure(FactoryOut(), Done{Faux.fauxAssistantMessageAt(Unit, text(T.modelId(model) ++ ":" ++ boolText(T.modelReasoning(model))), Faux.noOptions(), F.fromU32(1))})

def contextCount(context: Ctx()) -> Nat:
  match context:
    case T.TranscriptContext{messages}: List.length(&2, T.Message<V.Value, V.Value, Unit, Unit>, messages)

def counting(unused: Unit, input: FactoryIn()) -> IO(FactoryOut()):
  match input:
    case Faux.FactoryInput{context, _, Faux.FauxProviderState{calls, _, _}, _}: IO.pure(FactoryOut(), Done{Faux.fauxAssistantMessageAt(Unit, text(Nat.show(contextCount(context)) ++ ":" ++ Nat.show(calls)), Faux.noOptions(), F.fromU32(1))})

def throwing(unused: Unit, input: FactoryIn()) -> IO(FactoryOut()): IO.pure(FactoryOut(), Fail{"boom"})

def factory(~body: Unit -> FactoryIn() -> IO(FactoryOut())) -> IO(Step()):
  do IO<Step()>:
    callback : C.Callback<FactoryIn(), FactoryOut()> <- C.create(~Unit, ~FactoryIn(), ~FactoryOut(), ~body, Unit{})
    return Faux.FauxFactory{callback}

def definition(id: String, name: String, reasoning: Bool) -> Faux.FauxModelDefinition:
  Faux.FauxModelDefinition{id, Some{name}, Some{reasoning}, None{}, None{}, None{}, None{}, None{}}

def parsedOr(result: Result<&2, &2, Parse.ParseError, V.Value>) -> V.Value:
  match result:
    case Done{value}: value
    case Fail{_}: V.Null{}

def schema(json: String) -> V.Value: parsedOr(Parse.parse(json))

def echoTool() -> T.Tool<V.Value>: T.Tool{"echo", "Echo back text", schema("{\"type\":\"object\",\"required\":[\"text\"],\"properties\":{\"text\":{\"type\":\"string\"}}}"), None{}}

def args(json: String) -> V.Value: schema(json)

# Tests
# -----
def registersProvider() -> IO(Unit):
  +name = {"registers a custom provider and estimates usage" : String}
  do IO<Unit>:
    +faux : Core() <- core(Faux.defaultOptions())
    Faux.setResponses(Unit, Unit, String, faux, plain("hello world") <> Nil{})
    +outcome : Outcome <- run(faux, firstModel(faux), contextWith(Some{"Be concise."}, user("hi there") <> Nil{}, None{}), None{})
    +message : Message() <- IO.pure(Message(), messageOf(outcome))
    check(String.eq(contentJson(message), textContent("hello world")), name, contentJson(message))
    check(Nat.is_gt(usageField(message, "input"), 0n) && Nat.is_gt(usageField(message, "output"), 0n), name, "usage")
    check(Nat.is_eq(usageField(message, "total"), usageField(message, "input") + usageField(message, "output")), name, "total")
    +calls : Nat <- callCount(faux)
    check(Nat.is_eq(calls, 1n), name, "callCount " ++ Nat.show(calls))
    pass(name)

def helperBlocks() -> IO(Unit):
  +name = {"supports helper blocks for text, thinking, and tool calls" : String}
  do IO<Unit>:
    +faux : Core() <- core(Faux.defaultOptions())
    Faux.setResponses(Unit, Unit, String, faux, reply(Faux.fauxThinking("think") <> Faux.fauxToolCallWithId("echo", args("{\"text\":\"hi\"}"), "tool-x") <> Faux.fauxText("done") <> Nil{}, Some{T.ToolUse{}}, None{}) <> Nil{})
    +message : Message() <- IO.bind(Outcome, Message(), run(faux, firstModel(faux), hi(), None{}), outcome => IO.pure(Message(), messageOf(outcome)))
    check(String.eq(contentJson(message), "[{\"type\":\"thinking\",\"thinking\":\"think\"},{\"type\":\"toolCall\",\"id\":\"tool-x\",\"name\":\"echo\",\"arguments\":{\"text\":\"hi\"}},{\"type\":\"text\",\"text\":\"done\"}]"), name, contentJson(message))
    check(String.eq(stopOf(message), "toolUse"), name, stopOf(message))
    pass(name)

def multipleModels() -> IO(Unit):
  +name = {"supports multiple models with per-model reasoning and model-aware factories" : String}
  do IO<Unit>:
    +faux : Core() <- core(Faux.RegisterFauxProviderOptions{None{}, None{}, definition("faux-fast", "Faux Fast", False{}) <> definition("faux-thinker", "Faux Thinker", True{}) <> Nil{}, None{}, None{}})
    first : Step() <- factory(~modelAware)
    second : Step() <- factory(~modelAware)
    Faux.setResponses(Unit, Unit, String, faux, first <> second <> Nil{})
    +fast : T.Model<J()> <- IO.pure(T.Model<J()>, Maybe.default(&2, T.Model<J()>, Faux.getModel(Unit, Unit, String, faux, Some{"faux-fast"}), firstModel(faux)))
    +thinker : T.Model<J()> <- IO.pure(T.Model<J()>, Maybe.default(&2, T.Model<J()>, Faux.getModel(Unit, Unit, String, faux, Some{"faux-thinker"}), firstModel(faux)))
    check(String.eq(T.modelId(firstModel(faux)), "faux-fast") && Bool.not(T.modelReasoning(fast)) && T.modelReasoning(thinker), name, "models")
    +a : Outcome <- run(faux, fast, hi(), None{})
    b : Outcome <- run(faux, thinker, hi(), None{})
    check(String.eq(contentJson(messageOf(a)), textContent("faux-fast:false")) && String.eq(contentJson(messageOf(b)), textContent("faux-thinker:true")), name, contentJson(messageOf(a)))
    pass(name)

def rewrites() -> IO(Unit):
  +name = {"rewrites api, provider, and model on returned messages" : String}
  do IO<Unit>:
    +faux : Core() <- core(Faux.RegisterFauxProviderOptions{Some{"faux:test"}, Some{"faux-provider"}, Faux.FauxModelDefinition{"faux-model", None{}, None{}, None{}, None{}, None{}, None{}, None{}} <> Nil{}, None{}, None{}})
    Faux.setResponses(Unit, Unit, String, faux, plain("hello") <> Nil{})
    outcome : Outcome <- run(faux, firstModel(faux), hi(), None{})
    +message : Message() <- IO.pure(Message(), messageOf(outcome))
    check(String.eq(Faux.messageApi(Unit, message), "faux:test") && String.eq(T.assistantProvider(V.Value, Unit, message), "faux-provider") && String.eq(T.assistantModel(V.Value, Unit, message), "faux-model"), name, "identity")
    pass(name)

def queued() -> IO(Unit):
  +name = {"consumes queued responses in order and errors when exhausted" : String}
  do IO<Unit>:
    +faux : Core() <- core(Faux.defaultOptions())
    Faux.setResponses(Unit, Unit, String, faux, plain("first") <> plain("second") <> Nil{})
    first : Outcome <- run(faux, firstModel(faux), hi(), None{})
    second : Outcome <- run(faux, firstModel(faux), hi(), None{})
    +third : Outcome <- run(faux, firstModel(faux), hi(), None{})
    check(String.eq(contentJson(messageOf(first)), textContent("first")) && String.eq(contentJson(messageOf(second)), textContent("second")), name, "order")
    check(String.eq(stopOf(messageOf(third)), "error") && String.eq(errorOf(messageOf(third)), "No more faux responses queued"), name, errorOf(messageOf(third)))
    left : Nat <- pending(faux)
    calls : Nat <- callCount(faux)
    check(Nat.is_eq(left, 0n) && Nat.is_eq(calls, 3n), name, "counts")
    pass(name)

def replaceAppend() -> IO(Unit):
  +name = {"can replace and append queued responses" : String}
  do IO<Unit>:
    +faux : Core() <- core(Faux.defaultOptions())
    Faux.setResponses(Unit, Unit, String, faux, plain("first") <> Nil{})
    a : Outcome <- run(faux, firstModel(faux), hi(), None{})
    zero : Nat <- pending(faux)
    Faux.setResponses(Unit, Unit, String, faux, plain("second") <> Nil{})
    one : Nat <- pending(faux)
    b : Outcome <- run(faux, firstModel(faux), hi(), None{})
    Faux.appendResponses(Unit, Unit, String, faux, plain("third") <> plain("fourth") <> Nil{})
    two : Nat <- pending(faux)
    c : Outcome <- run(faux, firstModel(faux), hi(), None{})
    d : Outcome <- run(faux, firstModel(faux), hi(), None{})
    none : Nat <- pending(faux)
    check(String.eq(contentJson(messageOf(a)), textContent("first")) && String.eq(contentJson(messageOf(b)), textContent("second")) && String.eq(contentJson(messageOf(c)), textContent("third")) && String.eq(contentJson(messageOf(d)), textContent("fourth")), name, "responses")
    check(Nat.is_eq(zero, 0n) && Nat.is_eq(one, 1n) && Nat.is_eq(two, 2n) && Nat.is_eq(none, 0n), name, "pending counts")
    pass(name)

def asyncFactories() -> IO(Unit):
  +name = {"supports async response factories" : String}
  do IO<Unit>:
    +faux : Core() <- core(Faux.defaultOptions())
    step : Step() <- factory(~counting)
    Faux.setResponses(Unit, Unit, String, faux, step <> Nil{})
    +outcome : Outcome <- run(faux, firstModel(faux), hi(), None{})
    check(String.eq(contentJson(messageOf(outcome)), textContent("1:1")), name, contentJson(messageOf(outcome)))
    pass(name)

def factoryThrows() -> IO(Unit):
  +name = {"emits an error when a response factory throws" : String}
  do IO<Unit>:
    +faux : Core() <- core(Faux.defaultOptions())
    step : Step() <- factory(~throwing)
    Faux.setResponses(Unit, Unit, String, faux, step <> Nil{})
    +outcome : Outcome <- run(faux, firstModel(faux), hi(), None{})
    check(String.eq(shownNames(outcome), "error") && String.eq(stopOf(messageOf(outcome)), "error") && String.eq(errorOf(messageOf(outcome)), "boom"), name, shownNames(outcome))
    pass(name)

def pendingStop() -> IO(Unit):
  +name = {"rejects a queued response without a terminal stop reason" : String}
  do IO<Unit>:
    +faux : Core() <- core(Faux.defaultOptions())
    Faux.setResponses(Unit, Unit, String, faux, reply(text("partial"), Some{T.Pending{}}, None{}) <> Nil{})
    +outcome : Outcome <- run(faux, firstModel(faux), hi(), None{})
    +events : List<&2, String> <- IO.pure(List<&2, String>, names(eventsOf(outcome)))
    check(Bool.not(contains(events, "done")) && String.eq(Maybe.default(&2, String, List.head(&2, String, List.reverse(&2, String, events)), ""), "error"), name, shownNames(outcome))
    check(String.eq(stopOf(messageOf(outcome)), "error") && String.eq(errorOf(messageOf(outcome)), "Faux response ended without a stop reason"), name, errorOf(messageOf(outcome)))
    pass(name)

def ceil4(value: Nat) -> Nat: Nat.div(value + 3n, 4n)

def estimates() -> IO(Unit):
  +name = {"estimates prompt and output tokens from serialized context" : String}
  +toolJson = Maybe.default(&2, String, Wire.stringify(Schema.toJson(V.ArrayValue{MessageJson.tool(echoTool()) <> Nil{}})), "")
  +prompt = String.join("system:sys" <> "user:hello\n[image:image/png:4]" <> "assistant:prior" <> "toolResult:echo\ntool out" <> ("tools:" ++ toolJson) <> Nil{}, "\n\n")
  +messages = {T.User{T.UserMessage{T.UserBlocks{T.TextImageText{T.TextContent{"hello", None{}}} <> T.TextImageImage{T.ImageContent{"abcd", "image/png"}} <> Nil{}}, F.fromU32(1)}} <> T.Assistant{Faux.fauxAssistantMessageAt(Unit, text("prior"), Faux.noOptions(), F.fromU32(1))} <> T.ToolResult{T.ToolResultMessage{"tool-1", "echo", T.TextImageText{T.TextContent{"tool out", None{}}} <> Nil{}, None{}, None{}, False{}, F.fromU32(2)}} <> Nil{} : List<&2, T.Message<V.Value, V.Value, Unit, Unit>>}
  do IO<Unit>:
    +faux : Core() <- core(Faux.defaultOptions())
    Faux.setResponses(Unit, Unit, String, faux, plain("done") <> Nil{})
    outcome : Outcome <- run(faux, firstModel(faux), contextWith(Some{"sys"}, messages, Some{echoTool() <> Nil{}}), None{})
    +message : Message() <- IO.pure(Message(), messageOf(outcome))
    +expectedPrompt : Nat <- IO.pure(Nat, ceil4(Utf16.length(prompt)))
    check(Nat.is_eq(usageField(message, "input"), expectedPrompt) && Nat.is_eq(usageField(message, "output"), ceil4(4n)), name, "input " ++ Nat.show(usageField(message, "input")) ++ " expected " ++ Nat.show(expectedPrompt))
    check(Nat.is_eq(usageField(message, "cacheRead"), 0n) && Nat.is_eq(usageField(message, "cacheWrite"), 0n) && Nat.is_eq(usageField(message, "total"), expectedPrompt + ceil4(4n)), name, "cache/total")
    pass(name)

def assistantMessage(message: Message()) -> T.Message<V.Value, V.Value, Unit, Unit>: T.Assistant{message}

def followUp(first: Message(), system: Maybe<&2, String>, opening: String) -> Ctx():
  contextWith(system, user(opening) <> assistantMessage(first) <> user("follow up") <> Nil{}, None{})

def sessions() -> IO(Unit):
  +name = {"does not share cache across sessions or requests without sessionId" : String}
  do IO<Unit>:
    +faux : Core() <- core(Faux.defaultOptions())
    Faux.setResponses(Unit, Unit, String, faux, plain("first") <> plain("second") <> plain("third") <> Nil{})
    +first : Outcome <- run(faux, firstModel(faux), contextWith(None{}, user("hello") <> Nil{}, None{}), Some{sessionOptions(Some{"session-1"}, Some{T.CacheShort{}}, None{})})
    check(Nat.is_gt(usageField(messageOf(first), "cacheWrite"), 0n), name, "first write")
    +second : Outcome <- run(faux, firstModel(faux), followUp(messageOf(first), None{}, "hello"), Some{sessionOptions(Some{"session-2"}, Some{T.CacheShort{}}, None{})})
    check(Nat.is_eq(usageField(messageOf(second), "cacheRead"), 0n) && Nat.is_gt(usageField(messageOf(second), "cacheWrite"), 0n), name, "second")
    +third : Outcome <- run(faux, firstModel(faux), followUp(messageOf(first), None{}, "hello"), None{})
    check(Nat.is_eq(usageField(messageOf(third), "cacheRead"), 0n) && Nat.is_eq(usageField(messageOf(third), "cacheWrite"), 0n), name, "third")
    pass(name)

def caching() -> IO(Unit):
  +name = {"simulates prompt caching per sessionId" : String}
  do IO<Unit>:
    +faux : Core() <- core(Faux.defaultOptions())
    Faux.setResponses(Unit, Unit, String, faux, plain("first") <> plain("second") <> Nil{})
    +first : Outcome <- run(faux, firstModel(faux), contextWith(Some{"Be concise."}, user("hello") <> Nil{}, None{}), Some{sessionOptions(Some{"session-1"}, Some{T.CacheShort{}}, None{})})
    check(Nat.is_eq(usageField(messageOf(first), "cacheRead"), 0n) && Nat.is_gt(usageField(messageOf(first), "cacheWrite"), 0n), name, "first")
    +second : Outcome <- run(faux, firstModel(faux), followUp(messageOf(first), Some{"Be concise."}, "hello"), Some{sessionOptions(Some{"session-1"}, Some{T.CacheShort{}}, None{})})
    check(Nat.is_gt(usageField(messageOf(second), "cacheRead"), 0n), name, "second read")
    pass(name)

def noCaching() -> IO(Unit):
  +name = {"does not simulate caching when cacheRetention is none" : String}
  do IO<Unit>:
    +faux : Core() <- core(Faux.defaultOptions())
    Faux.setResponses(Unit, Unit, String, faux, plain("first") <> plain("second") <> Nil{})
    first : Outcome <- run(faux, firstModel(faux), contextWith(None{}, user("hello") <> Nil{}, None{}), Some{sessionOptions(Some{"session-1"}, Some{T.CacheNone{}}, None{})})
    +second : Outcome <- run(faux, firstModel(faux), followUp(Faux.fauxAssistantMessageAt(Unit, text("first"), Faux.noOptions(), F.fromU32(1)), None{}, "hello"), Some{sessionOptions(Some{"session-1"}, Some{T.CacheNone{}}, None{})})
    check(Nat.is_eq(usageField(messageOf(second), "cacheRead"), 0n) && Nat.is_eq(usageField(messageOf(second), "cacheWrite"), 0n), name, "cache")
    pass(name)

def deltaTexts(events: List<&2, FauxEvent()>) -> List<&2, String>:
  match events:
    case Nil{}: Nil{}
    case T.ToolcallDelta{_, delta, _} <> rest: delta <> deltaTexts(rest)
    case _ <> rest: deltaTexts(rest)

def sameParsed(left: Result<&2, &2, Parse.ParseError, V.Value>, right: Result<&2, &2, Parse.ParseError, V.Value>) -> Bool:
  match left right:
    case Done{a} Done{b}: V.equal(a, b)
    case _ _: False{}

def sameJson(content: String, +json: String) -> Bool: sameParsed(Parse.parse(content), Parse.parse(json))

def streamsDeltas() -> IO(Unit):
  +name = {"streams thinking, text, and partial tool call deltas" : String}
  do IO<Unit>:
    +faux : Core() <- core(Faux.defaultOptions())
    Faux.setResponses(Unit, Unit, String, faux, reply(Faux.fauxThinking("thinking text") <> Faux.fauxText("answer text") <> Faux.fauxToolCallWithId("echo", args("{\"text\":\"hi\",\"count\":12}"), "tool-1") <> Nil{}, Some{T.ToolUse{}}, None{}) <> Nil{})
    +outcome : Outcome <- run(faux, firstModel(faux), hi(), None{})
    +events : List<&2, String> <- IO.pure(List<&2, String>, names(eventsOf(outcome)))
    +deltas : List<&2, String> <- IO.pure(List<&2, String>, deltaTexts(eventsOf(outcome)))
    check(contains(events, "thinking_start") && contains(events, "thinking_delta") && contains(events, "text_start") && contains(events, "text_delta") && contains(events, "toolcall_start") && contains(events, "toolcall_delta") && contains(events, "toolcall_end"), name, shownNames(outcome))
    check(Nat.is_gt(List.length(&2, String, deltas), 1n) && sameJson(String.join(deltas, ""), "{\"text\":\"hi\",\"count\":12}"), name, String.join(deltas, "|"))
    pass(name)

def firstPending(events: List<&2, FauxEvent()>) -> Bool:
  match events:
    case T.Start{partial} <> _: String.eq(stopOf(partial), "pending")
    case _: False{}

def exactOrder() -> IO(Unit):
  +name = {"streams an exact event order for fixed-size chunks" : String}
  do IO<Unit>:
    +faux : Core() <- core(sized(1, None{}))
    Faux.setResponses(Unit, Unit, String, faux, reply(Faux.fauxThinking("go") <> Faux.fauxText("ok") <> Faux.fauxToolCallWithId("echo", args("{}"), "tool-1") <> Nil{}, Some{T.ToolUse{}}, None{}) <> Nil{})
    +outcome : Outcome <- run(faux, firstModel(faux), hi(), None{})
    check(firstPending(eventsOf(outcome)), name, "start partial")
    check(String.eq(shownNames(outcome), "start,thinking_start,thinking_delta,thinking_end,text_start,text_delta,text_end,toolcall_start,toolcall_delta,toolcall_end,done"), name, shownNames(outcome))
    pass(name)

def multipleCalls() -> IO(Unit):
  +name = {"streams multiple tool calls in one message" : String}
  do IO<Unit>:
    +faux : Core() <- core(Faux.defaultOptions())
    Faux.setResponses(Unit, Unit, String, faux, reply(Faux.fauxToolCallWithId("echo", args("{\"text\":\"one\"}"), "tool-1") <> Faux.fauxToolCallWithId("echo", args("{\"text\":\"two\"}"), "tool-2") <> Nil{}, Some{T.ToolUse{}}, None{}) <> Nil{})
    +outcome : Outcome <- run(faux, firstModel(faux), hi(), None{})
    +events : List<&2, String> <- IO.pure(List<&2, String>, names(eventsOf(outcome)))
    check(Nat.is_eq(count(events, "toolcall_start"), 2n) && Nat.is_eq(count(events, "toolcall_end"), 2n), name, shownNames(outcome))
    pass(name)

def reasonOf(last: Maybe<&2, FauxEvent()>) -> String:
  match last:
    case Some{T.StreamError{T.ErrorAborted{}, _}}: "aborted"
    case Some{T.StreamError{T.ErrorError{}, _}}: "error"
    case _: "none"

def terminalReason(events: List<&2, FauxEvent()>) -> String: reasonOf(List.head(&2, FauxEvent(), List.reverse(&2, FauxEvent(), events)))

def explicitTerminal(+name: String, stop: T.StopReason, +reason: String, +error: String) -> IO(Unit):
  do IO<Unit>:
    +faux : Core() <- core(sized(2, None{}))
    Faux.setResponses(Unit, Unit, String, faux, reply(text("partial"), Some{stop}, Some{error}) <> Nil{})
    +outcome : Outcome <- run(faux, firstModel(faux), hi(), None{})
    check(String.eq(shownNames(outcome), "start,text_start,text_delta,text_end,error"), name, shownNames(outcome))
    check(String.eq(terminalReason(eventsOf(outcome)), reason) && String.eq(stopOf(messageOf(outcome)), reason) && String.eq(errorOf(messageOf(outcome)), error), name, errorOf(messageOf(outcome)))
    pass(name)

def abortBeforeFirst() -> IO(Unit):
  +name = {"supports aborting before the first chunk" : String}
  do IO<Unit>:
    +faux : Core() <- core(sized(3, Some{F.fromU32(50)}))
    Faux.setResponses(Unit, Unit, String, faux, plain("abcdefghijklmnopqrstuvwxyz") <> Nil{})
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    won : Bool <- Abort.abort(Unit, controller, None{})
    +outcome : Outcome <- run(faux, firstModel(faux), hi(), Some{sessionOptions(None{}, None{}, Some{Abort.signal(Unit, controller)})})
    Abort.dispose(Unit, controller)
    check(String.eq(shownNames(outcome), "error") && String.eq(terminalReason(eventsOf(outcome)), "aborted") && String.eq(stopOf(messageOf(outcome)), "aborted"), name, shownNames(outcome))
    pass(name)

def abortMid(+name: String, response: Step(), +delta: String, +started: String, +ended: String) -> IO(Unit):
  do IO<Unit>:
    +faux : Core() <- core(sized(3, Some{F.fromU32(100)}))
    Faux.setResponses(Unit, Unit, String, faux, response <> Nil{})
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    +outcome : Outcome <- runAborting(faux, firstModel(faux), hi(), Some{sessionOptions(None{}, None{}, Some{Abort.signal(Unit, controller)})}, delta, Some{controller})
    Abort.dispose(Unit, controller)
    +events : List<&2, String> <- IO.pure(List<&2, String>, names(eventsOf(outcome)))
    check(Nat.is_eq(count(events, delta), 1n) && contains(events, started) && contains(events, delta) && contains(events, "error") && Bool.not(contains(events, ended)), name, shownNames(outcome))
    pass(name)

def run_all() -> IO(Unit):
  do IO<Unit>:
    registersProvider()
    helperBlocks()
    multipleModels()
    rewrites()
    queued()
    replaceAppend()
    asyncFactories()
    factoryThrows()
    pendingStop()
    estimates()
    sessions()
    caching()
    noCaching()
    streamsDeltas()
    exactOrder()
    multipleCalls()
    explicitTerminal("streams an explicit assistant error message as a terminal error", T.Error{}, "error", "upstream failed")
    explicitTerminal("streams an explicit assistant aborted message as a terminal error", T.Aborted{}, "aborted", "Request was aborted")
    abortBeforeFirst()
    abortMid("supports aborting mid-text stream when paced", plain("abcdefghijklmnopqrstuvwxyz"), "text_delta", "text_start", "text_end")
    abortMid("supports aborting mid-thinking stream when paced", reply(Faux.fauxThinking("abcdefghijklmnopqrstuvwxyz") <> Nil{}, None{}, None{}), "thinking_delta", "thinking_start", "thinking_end")
    abortMid("supports aborting mid-toolcall stream when paced", reply(Faux.fauxToolCallWithId("echo", args("{\"text\":\"abcdefghijklmnopqrstuvwxyz\",\"count\":123456789}"), "tool-1") <> Nil{}, Some{T.ToolUse{}}, None{}), "toolcall_delta", "toolcall_start", "toolcall_end")

# Differential mode (tests/faux_provider_check.py): usage estimates for the
# contexts tests/faux_provider_reference.ts runs through upstream's core.
def laterTool() -> T.Tool<V.Value>: T.Tool{"later", "Later tool", schema("{\"type\":\"object\",\"properties\":{}}"), None{}}

def diffAssistant() -> T.Message<V.Value, V.Value, Unit, Unit>:
  T.Assistant{Faux.fauxAssistantMessageAt(Unit, Faux.fauxText("prior é🙂") <> Faux.fauxToolCallWithId("echo", args("{\"text\":\"hi\",\"n\":[1,2]}"), "t1") <> Nil{}, Faux.FauxMessageOptions{Some{T.ToolUse{}}, None{}, None{}, Some{F.fromU32(1)}}, F.fromU32(1))}

def rules() -> R.Record<Maybe<&2, String>>: R.Record{R.Property{"rules", Some{"<rules>\nr\n</rules>"}} <> Nil{}}

def systemAt(content: String, sections: Maybe<&2, R.Record<Maybe<&2, String>>>, added: Maybe<&2, List<&2, T.Tool<V.Value>>>, removed: Maybe<&2, List<&2, T.ToolReference>>, time: U32) -> T.Message<V.Value, V.Value, Unit, Unit>:
  T.System{T.SystemMessage{T.SystemText{content}, sections, added, removed, F.fromU32(time)}}

type DiffCase is Data:
  DiffCase{context: Ctx(), options: Maybe<&2, Options()>}

def diffCases() -> List<&2, DiffCase>:
  DiffCase{contextWith(None{}, user("hi") <> Nil{}, None{}), None{}} <>
  DiffCase{contextWith(Some{"sys"}, T.User{T.UserMessage{T.UserBlocks{T.TextImageText{T.TextContent{"hello", None{}}} <> T.TextImageImage{T.ImageContent{"abcd", "image/png"}} <> Nil{}}, F.fromU32(1)}} <> diffAssistant() <> T.ToolResult{T.ToolResultMessage{"t1", "echo", T.TextImageText{T.TextContent{"tool out", None{}}} <> Nil{}, None{}, None{}, False{}, F.fromU32(2)}} <> Nil{}, Some{echoTool() <> Nil{}}), None{}} <>
  DiffCase{contextWith(None{}, systemAt("base", Some{rules()}, Some{echoTool() <> Nil{}}, None{}, 0) <> user("a") <> systemAt("update", None{}, Some{laterTool() <> Nil{}}, Some{T.ToolReference{"echo"} <> Nil{}}, 2) <> Nil{}, None{}), None{}} <>
  DiffCase{contextWith(None{}, user("hello 🙂 world") <> Nil{}, None{}), Some{sessionOptions(Some{"s1"}, None{}, None{})}} <>
  DiffCase{contextWith(None{}, user("hello 🙂 world") <> diffAssistant() <> user("follow up") <> Nil{}, None{}), Some{sessionOptions(Some{"s1"}, None{}, None{})}} <>
  DiffCase{contextWith(None{}, user("different") <> Nil{}, None{}), Some{sessionOptions(Some{"s1"}, Some{T.CacheNone{}}, None{})}} <>
  DiffCase{contextWith(None{}, user("x🙂 tail") <> Nil{}, None{}), Some{sessionOptions(Some{"s2"}, None{}, None{})}} <>
  DiffCase{contextWith(None{}, user("x😀 tail") <> Nil{}, None{}), Some{sessionOptions(Some{"s2"}, None{}, None{})}} <> Nil{}

def usageLine(+message: Message()) -> String:
  "D " ++ Nat.show(usageField(message, "input")) ++ "," ++ Nat.show(usageField(message, "output")) ++ "," ++ Nat.show(usageField(message, "cacheRead")) ++ "," ++ Nat.show(usageField(message, "cacheWrite"))

def diffLoop(+faux: Core(), cases: List<&2, DiffCase>) -> IO(Unit):
  match cases:
    case Nil{}: IO.pure(Unit, Unit{})
    case DiffCase{context, options} <> rest:
      do IO<Unit>:
        Faux.setResponses(Unit, Unit, String, faux, plain("done 🙂 ok") <> Nil{})
        outcome : Outcome <- run(faux, firstModel(faux), context, options)
        IO.print(usageLine(messageOf(outcome)))
        diffLoop(faux, rest)

def differential() -> IO(Unit):
  do IO<Unit>:
    +faux : Core() <- core(Faux.defaultOptions())
    diffLoop(faux, diffCases())

# Split mode (native only: a chunk boundary inside a surrogate pair yields
# lone surrogates, which the Bun backend cannot represent): UTF-16 lengths of
# the text deltas, and whether they rejoin to the streamed text.
def splitText() -> String: "a🙂🙂🙂b"

def deltasOf(events: List<&2, FauxEvent()>) -> List<&2, String>:
  match events:
    case Nil{}: Nil{}
    case T.TextDelta{_, delta, _} <> rest: delta <> deltasOf(rest)
    case _ <> rest: deltasOf(rest)

def unitLengths(deltas: List<&2, String>) -> List<&2, String>:
  match deltas:
    case Nil{}: Nil{}
    case delta <> rest: Nat.show(Utf16.length(delta)) <> unitLengths(rest)

def splitLines(+deltas: List<&2, String>) -> String:
  "S " ++ String.join(unitLengths(deltas), ",") ++ "\nJ " ++ Bool.pick(String, Utf16.equal(String.join(deltas, ""), splitText()), "true", "false")

def splitting() -> IO(Unit):
  do IO<Unit>:
    +faux : Core() <- core(sized(1, None{}))
    Faux.setResponses(Unit, Unit, String, faux, plain(splitText()) <> Nil{})
    outcome : Outcome <- run(faux, firstModel(faux), hi(), None{})
    IO.print(splitLines(deltasOf(eventsOf(outcome))))

def mode(args: List<String>) -> IO(Unit):
  match args:
    case "diff" <> Nil{}: differential()
    case "split" <> Nil{}: splitting()
    case _: run_all()

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    mode(args)
