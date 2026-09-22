import Base
import ../src/types.bend as T
import ../src/agent-loop.bend as Loop
import ./message-events.bend as Test
import ../../ai/src/types.bend as Ai
import ../../runtime/src/f64.bend as F
import ../../runtime/src/schema-value.bend as Schema

def Message() -> Data: T.AgentMessage<Unit, String, String>
def Messages() -> Data: T.AgentMessageArray(Unit, String, String)
def Tools() -> Data: T.AgentToolArray(String, String)
def Context() -> Data: T.AgentContext<Unit, String, String, String>
def Before() -> Data: T.BeforeToolCallContext<Unit, String, String, String>
def After() -> Data: T.AfterToolCallContext<Unit, String, String, String>
def Turn() -> Data: T.ShouldStopAfterTurnContext<Unit, String, String, String>
def Update() -> Data: T.AgentLoopTurnUpdate<Unit, String, String, String>

def sharedElement(value: Message(), expected: String) -> Bool:
  match value:
    case T.CustomMessage{text}: String.eq(text, expected)
    case _: False{}

def ordered(values: List<&2, Message()>) -> Bool:
  match values:
    case T.CustomMessage{a} <> T.CustomMessage{b} <> Nil{}: String.eq(a, "old") && String.eq(b, "prompt")
    case _: False{}

def checkedContext(value: Context()) -> Bool:
  match value:
    case T.AgentContext{messages, Some{Nil{}}}: ordered(messages)
    case _: False{}

def main() -> IO(Unit):
  do IO<Unit>:
    +messages : Messages() = T.CustomMessage{"old"} <> Nil{}
    +run : Context() = Loop.copyContextMessages(Unit, String, String, String, T.AgentContext{messages, Some{Nil{}}}, T.CustomMessage{"prompt"} <> Nil{})
    Test.assertion(checkedContext(run), "context transition must append prompt and preserve tools")
    Test.assertion(Nat.is_eq(List.length(&2, Message(), messages), 1n), "context transition changed original list")
    IO.print("PASS persistent context transition and prompt order")
