import Base
import ../src/types.bend as T
import ../src/utils/transcript.bend as Tr
import ./system-message-replay.bend as F
import ../../runtime/src/ref.bend as Ref
import ../../runtime/src/record.bend as R
import ../../runtime/src/f64.bend as N

def matches(value: T.Tool<F.Schema>, name: String, description: String) -> Bool:
  match value:
    case T.Tool{actualName, actualDescription, F.EmptyObject{}, None{}}: String.eq(actualName, name) && String.eq(actualDescription, description)
    case _: False{}

def checkTools(actual: List<&2, Ref.Ref<T.Tool<F.Schema>>>, expected: List<&2, R.Property<String>>) -> IO(Unit):
  match actual expected:
    case Nil{} Nil{}: IO.pure(Unit, Unit{})
    case reference <> rest R.Property{name, description} <> remaining:
      do IO<Unit>:
        value : T.Tool<F.Schema> <- Ref.read(T.Tool<F.Schema>, reference)
        F.assertion(matches(value, name, description), "tool map ordering or retained definition changed")
        checkTools(rest, remaining)
    case _ _: F.assertion(False{}, "tool list length changed")

def checkResolved(value: Tr.TranscriptTools<F.Schema>, expected: List<&2, R.Property<String>>, +anchors: Bool) -> IO(Unit):
  match value:
    case Tr.TranscriptTools{tools, +actual}:
      do IO<Unit>:
        F.assertion((actual && anchors) || (Bool.not(actual) && Bool.not(anchors)), "wrong tool anchoring mode")
        checkTools(tools, expected)

def main() -> IO(Unit):
  do IO<Unit>:
    +a : Ref.Ref<T.Tool<F.Schema>> <- F.tool("10")
    +b : Ref.Ref<T.Tool<F.Schema>> <- F.tool("2")
    +replacement : Ref.Ref<T.Tool<F.Schema>> <- Ref.new(T.Tool<F.Schema>, T.Tool{"10", "changed", F.EmptyObject{}, None{}})
    +base : Ref.Ref<T.SystemMessage<F.Schema>> <- Ref.new(T.SystemMessage<F.Schema>, T.SystemMessage{T.SystemText{""}, None{}, Some{a <> Nil{}}, None{}, N.fromU32(0)})
    +later : Ref.Ref<T.SystemMessage<F.Schema>> <- Ref.new(T.SystemMessage<F.Schema>, T.SystemMessage{T.SystemText{""}, None{}, Some{b <> Nil{}}, None{}, N.fromU32(1)})
    +changed : Ref.Ref<T.SystemMessage<F.Schema>> <- Ref.new(T.SystemMessage<F.Schema>, T.SystemMessage{T.SystemText{""}, None{}, Some{replacement <> Nil{}}, Some{T.ToolReference{"10"} <> Nil{}}, N.fromU32(2)})
    +additive : List<&2, F.Message()> = T.System{base} <> T.System{later} <> Nil{}
    nonAdditive : Bool <- Tr.hasNonAdditiveToolChanges(F.Schema, Unit, Unit, Unit, additive)
    F.assertion(Bool.not(nonAdditive), "distinct additions must remain additive")
    mode : Tr.TranscriptTools<F.Schema> <- Tr.resolveTranscriptTools(F.Schema, Unit, Unit, Unit, additive, True{})
    checkResolved(mode, R.Property{"10", "10 tool"} <> Nil{}, True{})
    mode : Tr.TranscriptTools<F.Schema> <- Tr.resolveTranscriptTools(F.Schema, Unit, Unit, Unit, additive, False{})
    checkResolved(mode, R.Property{"10", "10 tool"} <> R.Property{"2", "2 tool"} <> Nil{}, False{})
    +history : List<&2, F.Message()> = T.System{base} <> T.System{later} <> T.System{changed} <> Nil{}
    nonAdditive : Bool <- Tr.hasNonAdditiveToolChanges(F.Schema, Unit, Unit, Unit, history)
    F.assertion(nonAdditive, "removal must force non-additive tool history")
    current : List<&2, Ref.Ref<T.Tool<F.Schema>>> <- Tr.getCurrentTools(F.Schema, Unit, Unit, Unit, history)
    checkTools(current, R.Property{"2", "2 tool"} <> R.Property{"10", "changed"} <> Nil{})
    declared : List<&2, Ref.Ref<T.Tool<F.Schema>>> <- Tr.getDeclaredTools(F.Schema, Unit, Unit, Unit, history)
    checkTools(declared, R.Property{"10", "changed"} <> R.Property{"2", "2 tool"} <> Nil{})
    mode : Tr.TranscriptTools<F.Schema> <- Tr.resolveTranscriptTools(F.Schema, Unit, Unit, Unit, history, True{})
    checkResolved(mode, R.Property{"2", "2 tool"} <> R.Property{"10", "changed"} <> Nil{}, False{})
    nonAdditive : Bool <- Tr.hasNonAdditiveToolChanges(F.Schema, Unit, Unit, Unit, T.System{base} <> T.System{base} <> Nil{})
    F.assertion(nonAdditive, "even identical same-name redeclaration is non-additive")
    +user : Ref.Ref<T.UserMessage> <- Ref.new(T.UserMessage, T.UserMessage{T.UserText{"hello"}, N.fromU32(0)})
    mode : Tr.TranscriptTools<F.Schema> <- Tr.resolveTranscriptTools(F.Schema, Unit, Unit, Unit, T.User{user} <> T.System{base} <> Nil{}, True{})
    checkResolved(mode, Nil{}, True{})
    F.disposeMessages(history)
    F.disposeTools(a <> b <> replacement <> Nil{})
    previous : T.UserMessage <- Ref.dispose(T.UserMessage, user)
    IO.print("PASS tool map order, replacement/removal, declaration history and transport anchoring")
