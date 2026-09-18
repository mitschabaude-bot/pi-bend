import Base
import ../src/types.bend as T
import ../src/utils/transcript.bend as Transcript
import ../../runtime/src/ref.bend as R
import ../../runtime/src/f64.bend as F

def Message() -> Data: T.Message<Unit, Unit, Unit, Unit>
def Messages() -> Data: R.Ref<List<&2, Message()>>
def Context() -> Data: T.TranscriptContext<Unit, Unit, Unit, Unit>
def assertion(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, message)

def messages(context: Context()) -> Messages():
  match context:
    case T.TranscriptContext{array}: array

def disposeHead(values: List<&2, Message()>) -> IO(Unit):
  match values:
    case T.System{head} <> _:
      do IO<Unit>:
        old : T.SystemMessage<Unit> <- R.dispose(T.SystemMessage<Unit>, head)
        return Unit{}
    case _: IO.pure(Unit, Unit{})

def changedUser(value: T.UserMessage) -> IO(Unit):
  match value:
    case T.UserMessage{T.UserText{text}, _}: assertion(String.eq(text, "changed"), "copied array lost shared element mutation")
    case _: IO.die(Unit, 1, "user shape changed")

def changed(values: List<&2, Message()>, same: Bool, expected: R.Ref<T.UserMessage>) -> IO(Unit):
  match values same:
    case Nil{} True{}: IO.pure(Unit, Unit{})
    case T.System{_} <> T.User{+user} <> Nil{} False{}:
      do IO<Unit>:
        assertion(R.same(T.UserMessage, user, expected), "normalization copied a message object")
        value : T.UserMessage <- R.read(T.UserMessage, user)
        changedUser(value)
    case _ _: IO.die(Unit, 1, "normalization array mutation visibility differs")

def optionalTools(mode: U32, tool: R.Ref<T.Tool<Unit>>) -> Maybe<&2, List<&2, R.Ref<T.Tool<Unit>>>>:
  match mode:
    case 0: None{}
    case 1: Some{Nil{}}
    case _: Some{tool <> Nil{}}

def releaseNormalized(same: Bool, array: Messages()) -> IO(Unit):
  match same:
    case True{}: IO.pure(Unit, Unit{})
    case False{}:
      do IO<Unit>:
        old : List<&2, Message()> <- R.dispose(List<&2, Message()>, array)
        disposeHead(old)

def run(prompt: Maybe<&2, String>, toolMode: U32, +same: Bool) -> IO(Unit):
  do IO<Unit>:
    +user : R.Ref<T.UserMessage> <- R.new(T.UserMessage, T.UserMessage{T.UserText{"original"}, F.fromU32(1)})
    +tool : R.Ref<T.Tool<Unit>> <- R.new(T.Tool<Unit>, T.Tool{"tool", "description", Unit{}, None{}})
    +original : Messages() <- R.new(List<&2, Message()>, T.User{user} <> Nil{})
    +normalized : Context() <- Transcript.normalizeContext(Unit, Unit, Unit, Unit, T.Context{prompt, original, optionalTools(toolMode, tool)})
    +array : Messages() = messages(normalized)
    assertion(Bool.pick(Bool, same, R.same(List<&2, Message()>, original, array), Bool.not(R.same(List<&2, Message()>, original, array))), "normalization array identity differs")
    R.write(List<&2, Message()>, original, Nil{})
    R.write(T.UserMessage, user, T.UserMessage{T.UserText{"changed"}, F.fromU32(1)})
    values : List<&2, Message()> <- R.read(List<&2, Message()>, array)
    changed(values, same, user)
    +preserved : Context() <- Transcript.resolveTranscript(Unit, Unit, Unit, Unit, normalized, Some{True{}})
    assertion(R.same(List<&2, Message()>, messages(preserved), array), "supported transcript resolution copied its array")
    +collapsed : Context() <- Transcript.collapseSystemMessages(Unit, Unit, Unit, Unit, normalized)
    assertion(Bool.not(R.same(List<&2, Message()>, messages(collapsed), array)), "collapse must always allocate its filtered array")
    collapsedValues : List<&2, Message()> <- R.dispose(List<&2, Message()>, messages(collapsed))
    disposeHead(collapsedValues)
    releaseNormalized(same, array)
    oldOriginal : List<&2, Message()> <- R.dispose(List<&2, Message()>, original)
    oldUser : T.UserMessage <- R.dispose(T.UserMessage, user)
    oldTool : T.Tool<Unit> <- R.dispose(T.Tool<Unit>, tool)
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    run(None{}, 0, True{})
    run(None{}, 1, True{})
    run(None{}, 2, False{})
    run(Some{""}, 0, True{})
    run(Some{""}, 1, True{})
    run(Some{""}, 2, False{})
    run(Some{"guidance"}, 0, False{})
    run(Some{"guidance"}, 1, False{})
    run(Some{"guidance"}, 2, False{})
    IO.print("PASS nine normalization array identity/mutation cases and resolution/collapse allocation")
