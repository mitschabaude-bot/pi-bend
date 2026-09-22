import Base
import ../src/agent-loop.bend as Preparation
import ../src/types.bend as T
import ../src/agent-loop.bend as Loop
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/model-api.bend as Api
import ../../ai/src/utils/tool-declaration.bend as D
import ../../ai/test/model-types.bend as Model
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/f64.bend as F
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C
import ./tool-changes.bend as Tools
import ./message-events.bend as Test

def Messages() -> Data: Tools.Messages()
def Context() -> Data: T.AgentContext<V.Value, String, Unit, String, String, U32, Unit, String>
def Config() -> Data: T.AgentLoopConfig<V.Value, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit>
def Turn() -> Data: T.PrepareNextTurnContext(V.Value, String, Unit, String, String, U32, Unit, String)
def Update() -> Data: T.AgentLoopTurnUpdate<V.Value, String, Unit, String, String, U32, Unit, String, Unit>
def PrepareOutput() -> Data: Result<&2, &2, String, Maybe<&2, Update()>>
def QueueOutput() -> Data: Result<&2, &2, String, Messages()>
def Converted() -> Data: Result<&2, &2, String, List<&2, Ai.Message<V.Value, String, Unit, String>>>
def EventValue() -> Data: T.AgentEvent<V.Value, String, Unit, String, String, T.AgentToolResult<String>, T.AgentToolResult<String>>
def State() -> Data: Preparation.RequestState<String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit>
def Outcome() -> Data: Result<&2, &2, String, State()>
def Log() -> Data: R.Ref<List<&2, String>>

type Hook is Data:
  Hook{log: Log(), mode: U32, replacement: Context()}
type Queue is Data:
  Queue{log: Log(), mode: U32}
type Recording is Data:
  Recording{log: Log(), failAt: String}

def log(reference: Log(), entry: String) -> IO(Unit):
  R.modify(List<&2, String>, Unit, reference, values => (entry <> values, Unit{}))

def names(tools: Maybe<&2, List<&2, Ai.Tool<V.Value>>>) -> String:
  match tools:
    case None{}: ""
    case Some{Nil{}}: ""
    case Some{Ai.Tool{name, _, _, _} <> rest}: name ++ "," ++ names(Some{rest})

def messageName(message: Tools.Message()) -> String:
  match message:
    case T.CustomMessage{value}: value
    case T.LlmMessage{Ai.System{Ai.SystemMessage{Ai.SystemText{+text}, None{}, added, removed, timestamp}}}:
      Bool.pick(String, String.is_empty(text), "system", text) ++ ":" ++ names(added)
    case _: "unexpected"

def messages(values: Messages()) -> String:
  match values:
    case Nil{}: ""
    case message <> rest: messageName(message) ++ "|" ++ messages(rest)

def makeUpdate(context: Context()) -> Update():
  T.AgentLoopTurnUpdate{Some{context}, Some{T.CustomMessage{"prepared"} <> T.LlmMessage{Ai.System{Ai.SystemMessage{Ai.SystemText{"intent"}, None{}, Some{Ai.Tool{"bogus", "", V.Null{}, None{}} <> Nil{}}, None{}, F.fromU32(33)}}} <> Nil{}}, Some{Model.model(Ai.CustomModelApi{"replacement"}, None{})}, Some{Ai.Off{}}}

def hookResult(mode: U32, replacement: Context()) -> PrepareOutput():
  match mode:
    case 0: Done{None{}}
    case 1: Done{Some{makeUpdate(replacement)}}
    case _: Fail{"prepare failed"}

def prepare(environment: Hook, completed: Turn()) -> IO(PrepareOutput()):
  match environment completed:
    case Hook{recording, mode, replacement} T.ShouldStopAfterTurnContext{_, _, T.AgentContext{contextMessages, _}, newMessages}:
      do IO<PrepareOutput()>:
        Test.assertion(String.eq(messages(contextMessages), "old|") && String.eq(messages(newMessages), "generated|"), "prepare hook receives the completed snapshot")
        log(recording, "prepare")
        return hookResult(mode, replacement)

def queueResult(mode: U32) -> QueueOutput():
  match mode:
    case 0: Done{Nil{}}
    case 1: Done{T.CustomMessage{"queued"} <> Nil{}}
    case _: Fail{"queue failed"}

def queue(environment: Queue, unused: Unit) -> IO(QueueOutput()):
  match environment:
    case Queue{recording, mode}:
      do IO<QueueOutput()>:
        log(recording, "queue")
        return queueResult(mode)

def eventName(event: EventValue()) -> String:
  match event:
    case T.TurnStart{}: "turn_start"
    case T.MessageStart{message}: "start:" ++ messageName(message)
    case T.MessageEnd{message}: "end:" ++ messageName(message)
    case _: "unexpected"

def emit(environment: Recording, event: EventValue()) -> IO(Result<&2, &2, String, Unit>):
  match environment:
    case Recording{recording, failAt}:
      do IO<Result<&2, &2, String, Unit>>:
        +name : String = eventName(event)
        log(recording, name)
        return Bool.pick(Result<&2, &2, String, Unit>, String.eq(name, failAt), Fail{"delivery failed"}, Done{Unit{}})

def forbidden(unused: Unit, input: Messages()) -> IO(Converted()):
  IO.die(Converted(), 1, "preparation must not call convertToLlm")

def declarationError(error: D.DeclarationError) -> String: "declaration failed"

def reasoning(value: Maybe<&2, Ai.ThinkingLevel>, replaced: Bool) -> Bool:
  match value replaced:
    case None{} True{}: True{}
    case Some{Ai.High{}} False{}: True{}
    case _ _: False{}

def configMatches(config: Config(), +replaced: Bool) -> Bool:
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, thinking, _, _, model, _, _, _, _, _, _, _, _, _, _}:
      reasoning(thinking, replaced) && String.eq(Api.name(Api.modelApi(Unit, model)), Bool.pick(String, replaced, "replacement", "original"))

def check(actual: Outcome(), +replaced: Bool, +expectedMessages: String, expectedError: String) -> IO(Unit):
  match actual:
    case Fail{error}: Test.assertion(String.eq(error, expectedError), "preparation failure propagates unchanged")
    case Done{Preparation.RequestState{T.AgentContext{contextMessages, tools}, config, newMessages}}:
      Test.assertion(String.is_empty(expectedError) && configMatches(config, replaced) && String.eq(messages(contextMessages), Bool.pick(String, replaced, "compacted|", "old|") ++ expectedMessages) && String.eq(messages(newMessages), "generated|" ++ expectedMessages), "prepared context/config and generated history reach the request boundary")

def configuration(converter: C.Callback<Messages(), Converted()>, hook: C.Callback<Turn(), PrepareOutput()>, steering: C.Callback<Unit, QueueOutput()>) -> Config():
  T.AgentLoopConfig{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Some{Ai.High{}}, None{}, None{}, Model.model(Ai.CustomModelApi{"original"}, None{}), converter, None{}, None{}, None{}, Some{hook}, Some{steering}, None{}, None{}, None{}, None{}}

def run(initial: Bool, +context: Context(), config: Config(), completed: Turn(), pending: Messages(), sink: C.Callback<EventValue(), Result<&2, &2, String, Unit>>) -> IO(Outcome()):
  match initial:
    case True{}: Preparation.initialTurn(String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit, context, config, T.CustomMessage{"generated"} <> Nil{}, pending, sink, declarationError)
    case False{}: Preparation.nextTurn(String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit, context, config, completed, T.CustomMessage{"generated"} <> Nil{}, pending, sink, declarationError)

def equal(left: List<&2, String>, right: List<&2, String>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case a <> xs b <> ys: String.eq(a, b) && equal(xs, ys)
    case _ _: False{}

def scenario(+initial: Bool, +mode: U32, retained: Bool, queueMode: U32, failAt: String, expectedMessages: String, expectedError: String, expectedEvents: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    +recording : Log() <- R.new(List<&2, String>, Nil{})
    +executor : C.Callback<Tools.Input(), Tools.Output()> <- C.create(~Unit, ~Tools.Input(), ~Tools.Output(), ~Tools.forbidden, Unit{})
    +context : Context() = T.AgentContext{T.CustomMessage{"old"} <> Nil{}, Some{Tools.tools(Ai.Tool{"old", "", V.Null{}, None{}} <> Nil{}, executor)}}
    replacement : Context() = T.AgentContext{T.CustomMessage{"compacted"} <> Nil{}, Some{Tools.tools(Ai.Tool{"new", "", V.Null{}, None{}} <> Nil{}, executor)}}
    +hook : C.Callback<Turn(), PrepareOutput()> <- C.create(~Hook, ~Turn(), ~PrepareOutput(), ~prepare, Hook{recording, mode, replacement})
    +steering : C.Callback<Unit, QueueOutput()> <- C.create(~Queue, ~Unit, ~QueueOutput(), ~queue, Queue{recording, queueMode})
    +converter : C.Callback<Messages(), Converted()> <- C.create(~Unit, ~Messages(), ~Converted(), ~forbidden, Unit{})
    +sink : C.Callback<EventValue(), Result<&2, &2, String, Unit>> <- C.create(~Recording, ~EventValue(), ~Result<&2, &2, String, Unit>, ~emit, Recording{recording, failAt})
    +zero : F.F64 = F.fromU32(0)
    assistant : Ai.AssistantMessage<String, Unit> = Ai.AssistantMessage{Nil{}, "custom-api", "custom-provider", "model", None{}, None{}, None{}, None{}, Test.usage(Ai.UsageCost{zero, zero, zero, zero, zero}), Ai.Stop{}, None{}, None{}, None{}, None{}, zero}
    completed : Turn() = T.ShouldStopAfterTurnContext{assistant, Nil{}, context, T.CustomMessage{"generated"} <> Nil{}}
    pending : Messages() = Bool.pick(Messages(), retained, T.CustomMessage{"retained"} <> Nil{}, Nil{})
    result : Outcome() <- run(initial, context, configuration(converter, hook, steering), completed, pending, sink)
    check(result, Bool.not(initial) && U32.is_eq(mode, 1), expectedMessages, expectedError)
    actualEvents : List<&2, String> <- R.read(List<&2, String>, recording)
    Test.assertion(equal(List.reverse(&2, String, actualEvents), expectedEvents), "hook, queue, turn-start and message delivery ordering")
    C.dispose(Tools.Input(), Tools.Output(), executor)
    C.dispose(Turn(), PrepareOutput(), hook)
    C.dispose(Unit, QueueOutput(), steering)
    C.dispose(Messages(), Converted(), converter)
    C.dispose(EventValue(), Result<&2, &2, String, Unit>, sink)
    discarded : List<&2, String> <- R.dispose(List<&2, String>, recording)
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    scenario(False{}, 0, False{}, 0, "", "system:old,|", "", "prepare" <> "queue" <> "turn_start" <> "start:system:old," <> "end:system:old," <> Nil{})
    scenario(False{}, 0, False{}, 1, "", "system:old,|queued|", "", "prepare" <> "queue" <> "turn_start" <> "start:system:old," <> "end:system:old," <> "start:queued" <> "end:queued" <> Nil{})
    scenario(False{}, 0, False{}, 2, "", "", "queue failed", "prepare" <> "queue" <> Nil{})
    scenario(False{}, 0, True{}, 0, "", "system:old,|retained|", "", "prepare" <> "turn_start" <> "start:system:old," <> "end:system:old," <> "start:retained" <> "end:retained" <> Nil{})
    scenario(False{}, 0, True{}, 1, "", "system:old,|retained|", "", "prepare" <> "turn_start" <> "start:system:old," <> "end:system:old," <> "start:retained" <> "end:retained" <> Nil{})
    scenario(False{}, 0, True{}, 2, "", "system:old,|retained|", "", "prepare" <> "turn_start" <> "start:system:old," <> "end:system:old," <> "start:retained" <> "end:retained" <> Nil{})
    scenario(False{}, 1, False{}, 0, "", "prepared|intent:new,|", "", "prepare" <> "queue" <> "turn_start" <> "start:prepared" <> "end:prepared" <> "start:intent:new," <> "end:intent:new," <> Nil{})
    scenario(False{}, 1, False{}, 1, "", "prepared|intent:new,|queued|", "", "prepare" <> "queue" <> "turn_start" <> "start:prepared" <> "end:prepared" <> "start:intent:new," <> "end:intent:new," <> "start:queued" <> "end:queued" <> Nil{})
    scenario(False{}, 1, False{}, 2, "", "", "queue failed", "prepare" <> "queue" <> Nil{})
    scenario(False{}, 1, True{}, 0, "", "prepared|intent:new,|retained|", "", "prepare" <> "turn_start" <> "start:prepared" <> "end:prepared" <> "start:intent:new," <> "end:intent:new," <> "start:retained" <> "end:retained" <> Nil{})
    scenario(False{}, 1, True{}, 1, "", "prepared|intent:new,|retained|", "", "prepare" <> "turn_start" <> "start:prepared" <> "end:prepared" <> "start:intent:new," <> "end:intent:new," <> "start:retained" <> "end:retained" <> Nil{})
    scenario(False{}, 1, True{}, 2, "", "prepared|intent:new,|retained|", "", "prepare" <> "turn_start" <> "start:prepared" <> "end:prepared" <> "start:intent:new," <> "end:intent:new," <> "start:retained" <> "end:retained" <> Nil{})
    scenario(False{}, 2, False{}, 0, "", "", "prepare failed", "prepare" <> Nil{})
    scenario(False{}, 2, False{}, 1, "", "", "prepare failed", "prepare" <> Nil{})
    scenario(False{}, 2, False{}, 2, "", "", "prepare failed", "prepare" <> Nil{})
    scenario(False{}, 2, True{}, 0, "", "", "prepare failed", "prepare" <> Nil{})
    scenario(False{}, 2, True{}, 1, "", "", "prepare failed", "prepare" <> Nil{})
    scenario(False{}, 2, True{}, 2, "", "", "prepare failed", "prepare" <> Nil{})
    scenario(True{}, 0, False{}, 0, "", "system:old,|", "", "start:system:old," <> "end:system:old," <> Nil{})
    scenario(True{}, 0, False{}, 1, "", "system:old,|", "", "start:system:old," <> "end:system:old," <> Nil{})
    scenario(True{}, 0, False{}, 2, "", "system:old,|", "", "start:system:old," <> "end:system:old," <> Nil{})
    scenario(True{}, 0, True{}, 0, "", "system:old,|retained|", "", "start:system:old," <> "end:system:old," <> "start:retained" <> "end:retained" <> Nil{})
    scenario(True{}, 0, True{}, 1, "", "system:old,|retained|", "", "start:system:old," <> "end:system:old," <> "start:retained" <> "end:retained" <> Nil{})
    scenario(True{}, 0, True{}, 2, "", "system:old,|retained|", "", "start:system:old," <> "end:system:old," <> "start:retained" <> "end:retained" <> Nil{})
    scenario(True{}, 1, False{}, 0, "", "system:old,|", "", "start:system:old," <> "end:system:old," <> Nil{})
    scenario(True{}, 1, False{}, 1, "", "system:old,|", "", "start:system:old," <> "end:system:old," <> Nil{})
    scenario(True{}, 1, False{}, 2, "", "system:old,|", "", "start:system:old," <> "end:system:old," <> Nil{})
    scenario(True{}, 1, True{}, 0, "", "system:old,|retained|", "", "start:system:old," <> "end:system:old," <> "start:retained" <> "end:retained" <> Nil{})
    scenario(True{}, 1, True{}, 1, "", "system:old,|retained|", "", "start:system:old," <> "end:system:old," <> "start:retained" <> "end:retained" <> Nil{})
    scenario(True{}, 1, True{}, 2, "", "system:old,|retained|", "", "start:system:old," <> "end:system:old," <> "start:retained" <> "end:retained" <> Nil{})
    scenario(True{}, 2, False{}, 0, "", "system:old,|", "", "start:system:old," <> "end:system:old," <> Nil{})
    scenario(True{}, 2, False{}, 1, "", "system:old,|", "", "start:system:old," <> "end:system:old," <> Nil{})
    scenario(True{}, 2, False{}, 2, "", "system:old,|", "", "start:system:old," <> "end:system:old," <> Nil{})
    scenario(True{}, 2, True{}, 0, "", "system:old,|retained|", "", "start:system:old," <> "end:system:old," <> "start:retained" <> "end:retained" <> Nil{})
    scenario(True{}, 2, True{}, 1, "", "system:old,|retained|", "", "start:system:old," <> "end:system:old," <> "start:retained" <> "end:retained" <> Nil{})
    scenario(True{}, 2, True{}, 2, "", "system:old,|retained|", "", "start:system:old," <> "end:system:old," <> "start:retained" <> "end:retained" <> Nil{})
    scenario(False{}, 1, False{}, 1, "turn_start", "prepared|intent:new,|queued|", "delivery failed", "prepare" <> "queue" <> "turn_start" <> Nil{})
    scenario(False{}, 1, False{}, 1, "start:prepared", "prepared|intent:new,|queued|", "delivery failed", "prepare" <> "queue" <> "turn_start" <> "start:prepared" <> Nil{})
    scenario(False{}, 1, False{}, 1, "end:prepared", "prepared|intent:new,|queued|", "delivery failed", "prepare" <> "queue" <> "turn_start" <> "start:prepared" <> "end:prepared" <> Nil{})
    scenario(False{}, 1, False{}, 1, "start:intent:new,", "prepared|intent:new,|queued|", "delivery failed", "prepare" <> "queue" <> "turn_start" <> "start:prepared" <> "end:prepared" <> "start:intent:new," <> Nil{})
    scenario(False{}, 1, False{}, 1, "end:intent:new,", "prepared|intent:new,|queued|", "delivery failed", "prepare" <> "queue" <> "turn_start" <> "start:prepared" <> "end:prepared" <> "start:intent:new," <> "end:intent:new," <> Nil{})
    scenario(False{}, 1, False{}, 1, "start:queued", "prepared|intent:new,|queued|", "delivery failed", "prepare" <> "queue" <> "turn_start" <> "start:prepared" <> "end:prepared" <> "start:intent:new," <> "end:intent:new," <> "start:queued" <> Nil{})
    scenario(False{}, 1, False{}, 1, "end:queued", "prepared|intent:new,|queued|", "delivery failed", "prepare" <> "queue" <> "turn_start" <> "start:prepared" <> "end:prepared" <> "start:intent:new," <> "end:intent:new," <> "start:queued" <> "end:queued" <> Nil{})
    scenario(True{}, 0, False{}, 0, "start:system:old,", "system:old,|", "delivery failed", "start:system:old," <> Nil{})
    scenario(True{}, 0, False{}, 0, "end:system:old,", "system:old,|", "delivery failed", "start:system:old," <> "end:system:old," <> Nil{})
    IO.print("PASS 45 next-turn preparations: hook updates, steering precedence, tool declarations, histories and delivery failures")
