import Base
import ./tool-state.bend as ToolState
import ../../runtime/src/schema-value.bend as S
import ../src/types.bend as T
import ../src/utils/transcript.bend as Tr
import ./system-message-replay.bend as F
import ../../runtime/src/ref.bend as Ref
import ../../runtime/src/record.bend as R
import ../../runtime/src/f64.bend as N

def matches(value: T.Tool<S.Value<U32>>, name: String, description: String) -> Bool:
  match value:
    case T.Tool{actualName, actualDescription, parameters, None{}}: F.sameSchema(parameters) && String.eq(actualName, name) && String.eq(actualDescription, description)
    case _: False{}

def checkTools(actual: List<&2, Ref.Ref<T.Tool<S.Value<U32>>>>, expected: List<&2, R.Property<String>>) -> IO(Unit):
  match actual expected:
    case Nil{} Nil{}: IO.pure(Unit, Unit{})
    case reference <> rest R.Property{name, description} <> remaining:
      do IO<Unit>:
        value : T.Tool<S.Value<U32>> <- Ref.read(T.Tool<S.Value<U32>>, reference)
        F.assertion(matches(value, name, description), "tool map ordering or retained definition changed")
        checkTools(rest, remaining)
    case _ _: F.assertion(False{}, "tool list length changed")

def checkResolved(value: Tr.TranscriptTools<S.Value<U32>>, expected: List<&2, R.Property<String>>, +anchors: Bool) -> IO(Unit):
  match value:
    case Tr.TranscriptTools{tools, +actual}:
      do IO<Unit>:
        F.assertion((actual && anchors) || (Bool.not(actual) && Bool.not(anchors)), "wrong tool anchoring mode")
        checkTools(tools, expected)

def main() -> IO(Unit):
  do IO<Unit>:
    +a : Ref.Ref<T.Tool<S.Value<U32>>> <- F.tool("10")
    +b : Ref.Ref<T.Tool<S.Value<U32>>> <- F.tool("2")
    +replacement : Ref.Ref<T.Tool<S.Value<U32>>> <- Ref.new(T.Tool<S.Value<U32>>, T.Tool{"10", "changed", ToolState.emptyObjectSchema(), None{}})
    +base : Ref.Ref<T.SystemMessage<S.Value<U32>>> <- Ref.new(T.SystemMessage<S.Value<U32>>, T.SystemMessage{T.SystemText{""}, None{}, Some{a <> Nil{}}, None{}, N.fromU32(0)})
    +later : Ref.Ref<T.SystemMessage<S.Value<U32>>> <- Ref.new(T.SystemMessage<S.Value<U32>>, T.SystemMessage{T.SystemText{""}, None{}, Some{b <> Nil{}}, None{}, N.fromU32(1)})
    +changed : Ref.Ref<T.SystemMessage<S.Value<U32>>> <- Ref.new(T.SystemMessage<S.Value<U32>>, T.SystemMessage{T.SystemText{""}, None{}, Some{replacement <> Nil{}}, Some{T.ToolReference{"10"} <> Nil{}}, N.fromU32(2)})
    +additive : List<&2, F.Message()> = T.System{base} <> T.System{later} <> Nil{}
    nonAdditive : Bool <- Tr.hasNonAdditiveToolChanges(S.Value<U32>, Unit, Unit, Unit, additive)
    F.assertion(Bool.not(nonAdditive), "distinct additions must remain additive")
    mode : Tr.TranscriptTools<S.Value<U32>> <- Tr.resolveTranscriptTools(S.Value<U32>, Unit, Unit, Unit, additive, True{})
    checkResolved(mode, R.Property{"10", "10 tool"} <> Nil{}, True{})
    mode : Tr.TranscriptTools<S.Value<U32>> <- Tr.resolveTranscriptTools(S.Value<U32>, Unit, Unit, Unit, additive, False{})
    checkResolved(mode, R.Property{"10", "10 tool"} <> R.Property{"2", "2 tool"} <> Nil{}, False{})
    +history : List<&2, F.Message()> = T.System{base} <> T.System{later} <> T.System{changed} <> Nil{}
    nonAdditive : Bool <- Tr.hasNonAdditiveToolChanges(S.Value<U32>, Unit, Unit, Unit, history)
    F.assertion(nonAdditive, "removal must force non-additive tool history")
    current : List<&2, Ref.Ref<T.Tool<S.Value<U32>>>> <- Tr.getCurrentTools(S.Value<U32>, Unit, Unit, Unit, history)
    checkTools(current, R.Property{"2", "2 tool"} <> R.Property{"10", "changed"} <> Nil{})
    declared : List<&2, Ref.Ref<T.Tool<S.Value<U32>>>> <- Tr.getDeclaredTools(S.Value<U32>, Unit, Unit, Unit, history)
    checkTools(declared, R.Property{"10", "changed"} <> R.Property{"2", "2 tool"} <> Nil{})
    mode : Tr.TranscriptTools<S.Value<U32>> <- Tr.resolveTranscriptTools(S.Value<U32>, Unit, Unit, Unit, history, True{})
    checkResolved(mode, R.Property{"2", "2 tool"} <> R.Property{"10", "changed"} <> Nil{}, False{})
    nonAdditive : Bool <- Tr.hasNonAdditiveToolChanges(S.Value<U32>, Unit, Unit, Unit, T.System{base} <> T.System{base} <> Nil{})
    F.assertion(nonAdditive, "even identical same-name redeclaration is non-additive")
    +user : Ref.Ref<T.UserMessage> <- Ref.new(T.UserMessage, T.UserMessage{T.UserText{"hello"}, N.fromU32(0)})
    mode : Tr.TranscriptTools<S.Value<U32>> <- Tr.resolveTranscriptTools(S.Value<U32>, Unit, Unit, Unit, T.User{user} <> T.System{base} <> Nil{}, True{})
    checkResolved(mode, Nil{}, True{})
    F.disposeMessages(history)
    F.disposeTools(a <> b <> replacement <> Nil{})
    previous : T.UserMessage <- Ref.dispose(T.UserMessage, user)
    IO.print("PASS tool map order, replacement/removal, declaration history and transport anchoring")
