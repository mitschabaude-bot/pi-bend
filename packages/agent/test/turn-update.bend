import Base
import ../src/types.bend as T
import ../src/agent-loop.bend as Loop
import ./context.bend as H
import ./message-events.bend as Test
import ../../ai/src/types.bend as Ai
import ../../ai/test/model-types.bend as Model
import ../../ai/src/utils/model-api.bend as Api
import ../../runtime/src/callback.bend as C

def Config() -> Data: T.AgentLoopConfig<Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit>
def Update() -> Data: H.Update()
def State() -> Data: Loop.PreparedTurnState<Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit>
def Output() -> Data: Result<&2, &2, String, List<&2, Ai.Message<Unit, String, Unit, String>>>
def Converter() -> Data: C.Callback<H.Messages(), Output()>

def forbidden(unused: Unit, input: H.Messages()) -> IO(Output()):
  IO.die(Output(), 1, "turn update must not invoke conversion")

def config(model: Ai.Model<Unit>, reasoning: Maybe<&2, Ai.ThinkingLevel>, convert: Converter()) -> Config():
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

def sameModel(left: Ai.Model<Unit>, right: Ai.Model<Unit>) -> Bool:
  String.eq(Api.name(Api.modelApi(Unit, left)), Api.name(Api.modelApi(Unit, right)))

def view(value: Config(), expectedModel: Ai.Model<Unit>, expectedConvert: Converter()) -> IO(String):
  match value:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, Some{sessionId}, _, _, _, reasoning, _, _, model, convert, _, _, _, _, _, _, _, _, _}:
      do IO<String>:
        Test.assertion(String.eq(sessionId, "keep") && C.same(H.Messages(), Output(), convert, expectedConvert), "turn update changed unrelated fields/callback")
        return thinking(reasoning) ++ "|" ++ boolean(sameModel(model, expectedModel))
    case _: IO.die(String, 1, "session field omitted by update")

def check(state: State(), originalModel: Ai.Model<Unit>, convert: Converter(), expected: String) -> IO(Unit):
  match state:
    case Loop.PreparedTurnState{_, configValue, _}:
      do IO<Unit>:
        actual : String <- view(configValue, originalModel, convert)
        Test.assertion(String.eq(actual, expected), "next-turn reasoning/model update differs")

def selected(-Value: Data, yes: Bool, value: Value) -> Maybe<&2, Value>:
  Bool.pick(Maybe<&2, Value>, yes, Some{value}, None{})

def bit(mask: U32, flag: U32) -> Bool: Bool.not(U32.is_eq(U32.and(mask, flag), 0))

def run(+previous: Maybe<&2, Ai.ThinkingLevel>, requested: Maybe<&2, T.ThinkingLevel()>, +mask: U32, present: Bool, expected: String) -> IO(Unit):
  do IO<Unit>:
    +context : H.Context() = T.AgentContext{Nil{}, None{}}
    +replacementContext : H.Context() = T.AgentContext{Nil{}, Some{Nil{}}}
    +model : Ai.Model<Unit> = Model.model(Ai.CustomModelApi{"old"}, None{})
    +replacementModel : Ai.Model<Unit> = Model.model(Ai.CustomModelApi{"new"}, None{})
    +convert : Converter() <- C.create(~Unit, ~H.Messages(), ~Output(), ~forbidden, Unit{})
    +originalConfig : Config() = config(model, previous, convert)
    update : Update() = T.AgentLoopTurnUpdate{selected(H.Context(), bit(mask, 1), replacementContext), selected(H.Messages(), bit(mask, 4), Nil{}), selected(Ai.Model<Unit>, bit(mask, 2), replacementModel), requested}
    state : State() = Loop.applyTurnUpdate(Unit, String, Unit, String, String, U32, Unit, String, Unit, Unit, Unit, context, originalConfig, selected(Update(), present, update))
    check(state, model, convert, expected)
    originalView : String <- view(originalConfig, model, convert)
    Test.assertion(String.eq(originalView, thinking(previous) ++ "|true"), "turn update mutated original configuration")
    C.dispose(H.Messages(), Output(), convert)
