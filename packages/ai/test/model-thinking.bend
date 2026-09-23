import Base
import ../src/types.bend as T
import ../src/models.bend as M
import ../src/utils/thinking-levels.bend as L
import ../../runtime/src/f64.bend as F

# Full fixture fields match max-thinking.test.ts; no model catalog substitution.
def model(id: String, name: String, reasoning: Bool, mapping: Maybe<&2, T.ThinkingLevelMap>) -> T.Model<Unit>:
  +zero = F.fromU32(0)
  T.Model{id, name, T.OpenAICompletionsApi{}, "test", "https://example.com/v1", reasoning, mapping, T.InputText{} <> Nil{}, None{}, T.ModelCost{zero, zero, zero, zero, None{}}, None{}, F.fromU32(128000), F.fromU32(4096), None{}, None{}, None{}}

def identityModel(id: String, provider: String, api: T.ModelApi) -> T.Model<Unit>:
  +zero = F.fromU32(0)
  T.Model{id, "Ignored display name", api, provider, "https://example.test", False{}, None{}, Nil{}, None{}, T.ModelCost{zero, zero, zero, zero, None{}}, None{}, zero, zero, None{}, None{}, None{}}

def assertion(ok: Bool, label: String) -> IO(Unit):
  Bool.pick(IO(Unit), ok, IO.pure(Unit, Unit{}), IO.die(Unit, 1, label))

def sameNames(levels: List<&2, T.ModelThinkingLevel>, expected: List<&2, String>) -> Bool:
  match levels expected:
    case Nil{} Nil{}: True{}
    case head <> tail name <> rest: String.eq(L.name(head), name) && sameNames(tail, rest)
    case _ _: False{}

def checkClamps(+input: T.Model<Unit>, levels: List<&2, T.ModelThinkingLevel>, expected: List<&2, String>) -> Bool:
  match levels expected:
    case Nil{} Nil{}: True{}
    case head <> tail name <> rest: String.eq(L.name(M.clampThinkingLevel(Unit, input, head)), name) && checkClamps(input, tail, rest)
    case _ _: False{}

def check(+input: T.Model<Unit>, expected: List<&2, String>, clamped: List<&2, String>, +label: String) -> IO(Unit):
  do IO<Unit>:
    assertion(sameNames(M.getSupportedThinkingLevels(Unit, input), expected), label ++ " supported levels")
    assertion(checkClamps(input, L.all(), clamped), label ++ " clamped levels")

def main() -> IO(Unit):
  do IO<Unit>:
    +ordinary : T.Model<Unit> = model("ordinary-reasoning", "Ordinary Reasoning", True{}, None{})
    assertion(sameNames(M.getSupportedThinkingLevels(Unit, ordinary), "off" <> "minimal" <> "low" <> "medium" <> "high" <> Nil{}), "ordinary model supported levels")
    assertion(String.eq(L.name(M.clampThinkingLevel(Unit, ordinary, T.Thinking{T.Max{}})), "high"), "ordinary model clamps max to high")
    IO.print("PASS is opt-in for ordinary reasoning models")
    mapping : T.ThinkingLevelMap = T.ThinkingLevelMap{T.ThinkingLevelMapping{T.Thinking{T.XHigh{}}, Some{T.NullValue{}}} <> T.ThinkingLevelMapping{T.Thinking{T.Max{}}, Some{T.PresentValue{"max"}}} <> Nil{}}
    +hole : T.Model<Unit> = model("high-and-max", "High and Max", True{}, Some{mapping})
    assertion(sameNames(M.getSupportedThinkingLevels(Unit, hole), "off" <> "minimal" <> "low" <> "medium" <> "high" <> "max" <> Nil{}), "hole in supported levels")
    assertion(String.eq(L.name(M.clampThinkingLevel(Unit, hole, T.Thinking{T.XHigh{}})), "max"), "hole must clamp upwards first")
    IO.print("PASS supports a hole between high and max")
