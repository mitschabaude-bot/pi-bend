import Base
import ../../runtime/src/schema-value.bend as Schema
import ../src/agent.bend as Agent
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../runtime/src/f64.bend as F
import ../../runtime/src/date.bend as Date
import ./message-events.bend as Test

# Agent's schema parameter is fixed; prompt content itself does not contain it.
def NativeMessage() -> Data: T.AgentMessage<Unit, Unit, String>
def existing() -> NativeMessage(): T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{"existing"}, F.fromU32(17)}}}
def images() -> List<&2, Ai.ImageContent>:
  Ai.ImageContent{"one", "image/png"} <> Ai.ImageContent{"two", "image/jpeg"} <> Nil{}
def input(mode: U32) -> Agent.PromptInput<Unit, Unit, String>:
  match mode:
    case 0: Agent.Text{"", Nil{}}
    case 1: Agent.Text{"hello", images()}
    case 2: Agent.Message{existing()}
    case 3: Agent.Message{T.CustomMessage{"custom"}}
    case 4: Agent.Messages{existing() <> T.CustomMessage{"custom"} <> Nil{}}
    case _: Agent.Messages{Nil{}}
def equal(value: Maybe<&2, Cmp>) -> Bool:
  match value:
    case Some{EQ{}}: True{}
    case _: False{}
def blocks(values: List<&2, Ai.TextImageContent>) -> String:
  match values:
    case Nil{}: ""
    case Ai.TextImageText{Ai.TextContent{text, _}} <> rest: "text(" ++ text ++ ")" ++ blocks(rest)
    case Ai.TextImageImage{Ai.ImageContent{data, mime}} <> rest: "image(" ++ data ++ "," ++ mime ++ ")" ++ blocks(rest)
def key(messages: List<&2, NativeMessage()>) -> IO(String):
  match messages:
    case Nil{}: IO.pure(String, "")
    case T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{text}, stamp}}} <> rest:
      do IO<String>:
        Test.assertion(equal(F.compare(stamp, F.fromU32(17))), "existing user timestamp is unchanged")
        suffix : String <- key(rest)
        return "user(" ++ text ++ ");" ++ suffix
    case T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserBlocks{content}, stamp}}} <> rest:
      do IO<String>:
        Test.assertion(equal(F.compare(stamp, F.fromU32(555))), "text input gets the supplied timestamp exactly once")
        suffix : String <- key(rest)
        return blocks(content) ++ ";" ++ suffix
    case T.CustomMessage{text} <> rest:
      do IO<String>:
        suffix : String <- key(rest)
        return "custom(" ++ text ++ ");" ++ suffix
    case _: IO.die(String, 1, "unexpected normalized message")
def scenario(mode: U32, expected: String) -> IO(Unit):
  do IO<Unit>:
    actual : String <- key(Agent.normalizePromptInputAt(Unit, Unit, String, input(mode), F.fromU32(555)))
    Test.assertion(String.eq(actual, expected), "prompt overload content and image order match the source")
def ordered(value: Maybe<&2, Cmp>) -> Bool:
  match value:
    case Some{GT{}}: False{}
    case None{}: False{}
    case _: True{}
def live(messages: List<&2, NativeMessage()>, before: F.F64, after: F.F64) -> IO(Unit):
  match messages:
    case T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserBlocks{Ai.TextImageText{Ai.TextContent{"live", _}} <> Nil{}}, +stamp}}} <> Nil{}:
      Test.assertion(ordered(F.compare(before, stamp)) && ordered(F.compare(stamp, after)), "normal text prompts use the current Unix wall clock")
    case _: Test.assertion(False{}, "unexpected live prompt content")
def wallClock() -> IO(Unit):
  do IO<Unit>:
    before : F.F64 <- Date.now()
    messages : List<&2, NativeMessage()> <- Agent.normalizePromptInput(Unit, Unit, String, Agent.Text{"live", Nil{}})
    after : F.F64 <- Date.now()
    live(messages, before, after)
