import Base
import ../src/types.bend as T
import ../src/agent-loop.bend as Loop
import ./context.bend as H
import ./message-events.bend as Test
import ../../ai/src/types.bend as Ai
import ../../ai/test/model-types.bend as Model
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C

def Config() -> Data: T.AgentLoopConfig<Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit>
def Update() -> Data: H.Update()
def State() -> Data: Loop.PreparedTurnState<Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit>
def Output() -> Data: Result<&2, &2, String, R.Ref<List<&2, Ai.Message<Unit, String, Unit, String>>>>
def Converter() -> Data: C.Callback<H.Messages(), Output()>

def forbidden(unused: Unit, input: H.Messages()) -> IO(Output()):
  IO.die(Output(), 1, "turn update must not invoke conversion")

def config(model: R.Ref<Ai.Model<Unit>>, reasoning: Maybe<&2, Ai.ThinkingLevel>, convert: Converter()) -> Config():
  T.AgentLoopConfig{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Some{"keep"}, None{}, None{}, None{}, reasoning, None{}, None{}, model, convert, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}

def thinking(value: Maybe<&2, Ai.ThinkingLevel>) -> String:
  match value:
    case None{}: "none"
    case Some{Ai.Minimal{}}: "minimal"
    case Some{Ai.Low{}}: "low"
    case Some{Ai.Medium{}}: "medium"
    case Some{Ai.High{}}: "high"
    case Some{Ai.XHigh{}}: "xhigh"
    case Some{Ai.Max{}}: "max"

def boolean(value: Bool) -> String:
  match value:
    case True{}: "true"
    case False{}: "false"

def view(value: Config(), expectedModel: R.Ref<Ai.Model<Unit>>, expectedConvert: Converter()) -> IO(String):
  match value:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, Some{sessionId}, _, _, _, reasoning, _, _, model, convert, _, _, _, _, _, _, _, _, _}:
      do IO<String>:
        Test.assertion(String.eq(sessionId, "keep") && C.same(H.Messages(), Output(), convert, expectedConvert), "turn update changed unrelated fields/callback identity")
        return thinking(reasoning) ++ "|" ++ boolean(R.same(Ai.Model<Unit>, model, expectedModel))
    case _: IO.die(String, 1, "session field omitted by update")

def releaseNew(-Value: Data, same: Bool, reference: R.Ref<Value>) -> IO(Unit):
  match same:
    case True{}: IO.pure(Unit, Unit{})
    case False{}:
      do IO<Unit>:
        old : Value <- R.dispose(Value, reference)
        return Unit{}

def empty(values: List<&2, H.Message()>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case _: IO.die(Unit, 1, "empty update messages changed")

def check(state: State(), originalContext: R.Ref<H.Context()>, originalConfig: R.Ref<Config()>, originalModel: R.Ref<Ai.Model<Unit>>, supplied: H.Messages(), convert: Converter(), expected: String) -> IO(Unit):
  match state:
    case Loop.PreparedTurnState{context, +configValue, +messages}:
      do IO<Unit>:
        +sameConfig : Bool = R.same(Config(), configValue, originalConfig)
        +sameMessages : Bool = R.same(List<&2, H.Message()>, messages, supplied)
        value : Config() <- R.read(Config(), configValue)
        suffix : String <- view(value, originalModel, convert)
        actual : String = boolean(sameConfig) ++ "|" ++ boolean(R.same(H.Context(), context, originalContext)) ++ "|" ++ boolean(sameMessages) ++ "|" ++ suffix
        Test.assertion(String.eq(actual, expected), "next-turn update differs from upstream")
        contents : List<&2, H.Message()> <- R.read(List<&2, H.Message()>, messages)
        empty(contents)
        releaseNew(Config(), sameConfig, configValue)
        releaseNew(List<&2, H.Message()>, sameMessages, messages)

def selected(-Value: Data, yes: Bool, value: Value) -> Maybe<&2, Value>:
  Bool.pick(Maybe<&2, Value>, yes, Some{value}, None{})

def bit(mask: U32, flag: U32) -> Bool: Bool.not(U32.is_eq(U32.and(mask, flag), 0))

def run(+previous: Maybe<&2, Ai.ThinkingLevel>, requested: Maybe<&2, T.ThinkingLevel()>, +mask: U32, present: Bool, expected: String) -> IO(Unit):
  do IO<Unit>:
    +messages : H.Messages() <- R.new(List<&2, H.Message()>, Nil{})
    +supplied : H.Messages() <- R.new(List<&2, H.Message()>, Nil{})
    +context : R.Ref<H.Context()> <- R.new(H.Context(), T.AgentContext{messages, None{}})
    +replacementContext : R.Ref<H.Context()> <- R.new(H.Context(), T.AgentContext{messages, None{}})
    +model : R.Ref<Ai.Model<Unit>> <- R.new(Ai.Model<Unit>, Model.model(Ai.CustomModelApi{"old"}, None{}))
    +replacementModel : R.Ref<Ai.Model<Unit>> <- R.new(Ai.Model<Unit>, Model.model(Ai.CustomModelApi{"new"}, None{}))
    +convert : Converter() <- C.create(~Unit, ~H.Messages(), ~Output(), ~forbidden, Unit{})
    +originalConfig : R.Ref<Config()> <- R.new(Config(), config(model, previous, convert))
    +update : R.Ref<Update()> <- R.new(Update(), T.AgentLoopTurnUpdate{selected(R.Ref<H.Context()>, bit(mask, 1), replacementContext), selected(H.Messages(), bit(mask, 4), supplied), selected(R.Ref<Ai.Model<Unit>>, bit(mask, 2), replacementModel), requested})
    state : State() <- Loop.applyTurnUpdate(Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit, context, originalConfig, selected(R.Ref<Update()>, present, update))
    check(state, context, originalConfig, model, supplied, convert, expected)
    unchanged : Config() <- R.read(Config(), originalConfig)
    originalView : String <- view(unchanged, model, convert)
    Test.assertion(String.eq(originalView, thinking(previous) ++ "|true"), "turn update mutated original configuration")
    oldUpdate : Update() <- R.dispose(Update(), update)
    oldConfig : Config() <- R.dispose(Config(), originalConfig)
    oldContext : H.Context() <- R.dispose(H.Context(), context)
    newContext : H.Context() <- R.dispose(H.Context(), replacementContext)
    oldModel : Ai.Model<Unit> <- R.dispose(Ai.Model<Unit>, model)
    newModel : Ai.Model<Unit> <- R.dispose(Ai.Model<Unit>, replacementModel)
    oldMessages : List<&2, H.Message()> <- R.dispose(List<&2, H.Message()>, messages)
    suppliedMessages : List<&2, H.Message()> <- R.dispose(List<&2, H.Message()>, supplied)
    C.dispose(H.Messages(), Output(), convert)
