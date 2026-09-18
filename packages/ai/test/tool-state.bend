import Base
import ../src/types.bend as T
import ../src/utils/transcript.bend as Transcript
import ../src/utils/tool-declaration.bend as D
import ../../runtime/src/schema-value.bend as S
import ../../runtime/src/utf16.bend as U
import ./tool-declaration.bend as H
import ../../runtime/src/record.bend as R

type ExpectedChanges is Data:
  ExpectedChanges{added: List<&2, String>, removed: List<&2, String>}

def addedMatches(actual: List<&2, T.Tool<S.Value>>, expected: List<&2, String>) -> Bool:
  match actual expected:
    case Nil{} Nil{}: True{}
    case head <> tail want <> rest: H.sameText(D.serializeDeclaration(D.Success{head}), D.Success{want}) && addedMatches(tail, rest)
    case _ _: False{}

def removedMatches(actual: List<&2, T.ToolReference>, expected: List<&2, String>) -> Bool:
  match actual expected:
    case Nil{} Nil{}: True{}
    case T.ToolReference{name} <> tail want <> rest: U.equal(name, want) && removedMatches(tail, rest)
    case _ _: False{}

def changesMatch(actual: D.DeclarationResult<Transcript.ToolStateChanges<S.Value>>, expected: D.DeclarationResult<ExpectedChanges>) -> Bool:
  match actual expected:
    case D.Failure{a} D.Failure{b}: H.sameError(a, b)
    case D.Success{Transcript.ToolStateChanges{added, removed}} D.Success{ExpectedChanges{wantAdded, wantRemoved}}: addedMatches(added, wantAdded) && removedMatches(removed, wantRemoved)
    case _ _: False{}

def check(previous: List<&2, T.Tool<S.Value>>, current: List<&2, T.Tool<S.Value>>, expected: D.DeclarationResult<ExpectedChanges>, label: String) -> IO(Unit):
  H.assertion(changesMatch(Transcript.getToolStateChanges(previous, current), expected), label)

# Exact empty-object data/hidden-kind shape from TypeBox 1.3.27. The builder
# library is not yet ported; differential fixtures verify this representation.
def emptyObjectSchema() -> S.Value:
  fields = R.set(S.Value, R.new(S.Value), "type", S.Text{"object"})
  S.ObjectValue{R.set(S.Value, fields, "properties", S.ObjectValue{R.new(S.Value)})}

def tool(name: String, description: String) -> T.Tool<S.Value>:
  T.Tool{name, description, emptyObjectSchema(), None{}}

def upstreamCase() -> IO(Unit):
  do IO<Unit>:
    check(tool("a", "a tool") <> tool("b", "b tool") <> Nil{}, tool("b", "changed") <> tool("c", "c tool") <> Nil{}, D.Success{ExpectedChanges{"{\"name\":\"b\",\"description\":\"changed\",\"parameters\":{\"type\":\"object\",\"properties\":{}}}" <> "{\"name\":\"c\",\"description\":\"c tool\",\"parameters\":{\"type\":\"object\",\"properties\":{}}}" <> Nil{}, "a" <> "b" <> Nil{}}}, "changed definitions must be removed and added")
    check(tool("a", "a tool") <> Nil{}, tool("a", "a tool") <> Nil{}, D.Success{ExpectedChanges{Nil{}, Nil{}}}, "identical states must have no changes")
    IO.print("PASS tool state changes treat changed definitions as removal plus addition")
