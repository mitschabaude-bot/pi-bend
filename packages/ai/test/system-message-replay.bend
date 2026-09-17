import Base
import ../src/types.bend as T
import ../src/utils/text.bend as Text
import ../src/utils/transcript.bend as Transcript
import ../../runtime/src/ref.bend as Ref
import ../../runtime/src/record.bend as Record
import ../../runtime/src/f64.bend as N
import ../../runtime/src/u64.bend as U

# Two cases ported from system-message-replay.test.ts; the other seven remain
# pending. The opaque schema fixture denotes the upstream Type.Object({}).
type Schema is Data:
  EmptyObject{}

def Message() -> Data: T.Message<Schema, Unit, Unit, Unit>
def Context() -> Data: T.Context<Schema, Unit, Unit, Unit>
def Normalized() -> Data: T.TranscriptContext<Schema, Unit, Unit, Unit>

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def sameNumber(a: N.F64, b: N.F64) -> Bool:
  match a b:
    case N.F64{bitsA} N.F64{bitsB}: U.equal(bitsA, bitsB)

def tool(name: String) -> IO(Ref.Ref<T.Tool<Schema>>):
  +toolName = name
  Ref.new(T.Tool<Schema>, T.Tool{toolName, String.join(toolName <> " tool" <> Nil{}, ""), EmptyObject{}, None{}})

def checkTool(value: T.Tool<Schema>) -> IO(Unit):
  match value:
    case T.Tool{name, description, EmptyObject{}, None{}}: assertion(String.eq(name, "a") && String.eq(description, "a tool"), "tool declaration changed")
    case _: assertion(False{}, "tool optional fields changed")

def checkHead(value: T.SystemMessage<Schema>) -> IO(Unit):
  match value:
    case T.SystemMessage{T.SystemText{prompt}, None{}, Some{reference <> Nil{}}, None{}, timestamp}:
      do IO<Unit>:
        assertion(String.eq(prompt, "be brief") && sameNumber(timestamp, N.fromU32(0)), "normalized system prompt/timestamp")
        observed : T.Tool<Schema> <- Ref.read(T.Tool<Schema>, reference)
        checkTool(observed)
    case _: assertion(False{}, "normalized head shape")

def checkUser(value: T.UserMessage, expected: String) -> IO(Unit):
  match value:
    case T.UserMessage{T.UserText{text}, timestamp}: assertion(String.eq(text, expected) && sameNumber(timestamp, N.fromU32(1)), "user message changed")
    case _: assertion(False{}, "user content variant changed")

def checkTail(messages: List<&2, Message()>, expected: String) -> IO(Unit):
  match messages:
    case T.User{reference} <> Nil{}:
      do IO<Unit>:
        value : T.UserMessage <- Ref.read(T.UserMessage, reference)
        checkUser(value, expected)
    case _: assertion(False{}, "normalized message list changed")

def checkUnchanged(value: Normalized(), expected: String) -> IO(Unit):
  match value:
    case T.TranscriptContext{messages}: checkTail(messages, expected)

def checkNormalized(value: Normalized()) -> IO(Ref.Ref<T.SystemMessage<Schema>>):
  match value:
    case T.TranscriptContext{T.System{head} <> tail}:
      do IO<Ref.Ref<T.SystemMessage<Schema>>>:
        +reference : Ref.Ref<T.SystemMessage<Schema>> = head
        observed : T.SystemMessage<Schema> <- Ref.read(T.SystemMessage<Schema>, reference)
        checkHead(observed)
        checkTail(tail, "hi")
        return reference
    case _: IO.die(Ref.Ref<T.SystemMessage<Schema>>, 1, "missing normalized system message")

def normalization() -> IO(Unit):
  do IO<Unit>:
    +user : Ref.Ref<T.UserMessage> <- Ref.new(T.UserMessage, T.UserMessage{T.UserText{"hi"}, N.fromU32(1)})
    +messages : List<&2, Message()> = T.User{user} <> Nil{}
    +plain : Normalized() <- Transcript.normalizeContext(Schema, Unit, Unit, Unit, T.Context{None{}, messages, None{}})
    checkUnchanged(plain, "hi")
    empty : Normalized() <- Transcript.normalizeContext(Schema, Unit, Unit, Unit, T.Context{Some{""}, messages, Some{Nil{}}})
    checkUnchanged(empty, "hi")
    +declaration : Ref.Ref<T.Tool<Schema>> <- tool("a")
    combined : Normalized() <- Transcript.normalizeContext(Schema, Unit, Unit, Unit, T.Context{Some{"be brief"}, messages, Some{declaration <> Nil{}}})
    head : Ref.Ref<T.SystemMessage<Schema>> <- checkNormalized(combined)
    previous : T.SystemMessage<Schema> <- Ref.dispose(T.SystemMessage<Schema>, head)
    # Supplemental identity assertion: normalization retains original messages.
    Ref.write(T.UserMessage, user, T.UserMessage{T.UserText{"changed"}, N.fromU32(1)})
    checkUnchanged(plain, "changed")
    previous : T.Tool<Schema> <- Ref.dispose(T.Tool<Schema>, declaration)
    previous : T.UserMessage <- Ref.dispose(T.UserMessage, user)
    IO.print("PASS normalizes the legacy prompt and tool fields into a leading system message")

def rendering() -> IO(Unit):
  do IO<Unit>:
    +first : Ref.Ref<T.Tool<Schema>> <- tool("first")
    +second : Ref.Ref<T.Tool<Schema>> <- tool("second")
    leadingSections : Record.Record<Maybe<&2, String>> = Record.set(Maybe<&2, String>, Record.set(Maybe<&2, String>, Record.new(Maybe<&2, String>), "a", Some{"<a>1</a>"}), "b", Some{"<b>1</b>"})
    updateSections : Record.Record<Maybe<&2, String>> = Record.set(Maybe<&2, String>, Record.set(Maybe<&2, String>, Record.set(Maybe<&2, String>, Record.new(Maybe<&2, String>), "a", Some{"<a>2</a>"}), "b", None{}), "c", Some{"<c>1</c>"})
    +leading : Ref.Ref<T.SystemMessage<Schema>> <- Ref.new(T.SystemMessage<Schema>, T.SystemMessage{T.SystemText{"base"}, Some{leadingSections}, Some{first <> Nil{}}, None{}, N.fromU32(10)})
    +update : Ref.Ref<T.SystemMessage<Schema>> <- Ref.new(T.SystemMessage<Schema>, T.SystemMessage{T.SystemText{""}, Some{updateSections}, Some{second <> Nil{}}, Some{T.ToolReference{"first"} <> Nil{}}, N.fromU32(14)})
    prompt : String <- Text.getSystemMessageText(Schema, leading)
    assertion(String.eq(prompt, "base\n\n<a>1</a>\n\n<b>1</b>"), "complete system prompt")
    framed : String <- Text.renderSystemMessageUpdate(Schema, update)
    assertion(String.eq(framed, "Updated system prompt section \"a\":\n\n<a>2</a>\n\nRemoved system prompt section \"b\".\n\nUpdated system prompt section \"c\":\n\n<c>1</c>"), "framed system update")
    previous : T.SystemMessage<Schema> <- Ref.dispose(T.SystemMessage<Schema>, leading)
    previous : T.SystemMessage<Schema> <- Ref.dispose(T.SystemMessage<Schema>, update)
    previous : T.Tool<Schema> <- Ref.dispose(T.Tool<Schema>, first)
    previous : T.Tool<Schema> <- Ref.dispose(T.Tool<Schema>, second)
    IO.print("PASS renders complete prompts and framed updates")

def main() -> IO(Unit):
  do IO<Unit>:
    normalization()
    rendering()
