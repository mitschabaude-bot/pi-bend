import Base
import ../src/types.bend as T
import ../src/agent-loop.bend as Loop
import ./message-events.bend as Test
import ../../ai/src/types.bend as Ai
import ../../runtime/src/ref.bend as R
import ../../runtime/src/f64.bend as F

def Message() -> Data: T.AgentMessage<Unit, String, Unit, String, String>
def Messages() -> Data: T.AgentMessageArray(Unit, String, Unit, String, String)
def Tools() -> Data: T.AgentToolArray(Unit, U32, String, String, Unit, String)
def Context() -> Data: T.AgentContext<Unit, String, Unit, String, String, U32, Unit, String>
def Before() -> Data: T.BeforeToolCallContext<Unit, String, Unit, String, String, U32, Unit, String>
def After() -> Data: T.AfterToolCallContext<Unit, String, Unit, String, String, U32, Unit, String>
def Turn() -> Data: T.ShouldStopAfterTurnContext<Unit, String, Unit, String, String, U32, Unit, String>
def Update() -> Data: T.AgentLoopTurnUpdate<Unit, String, Unit, String, String, U32, Unit, String, Unit>

def copiedMessages(value: Context(), +old: Messages(), expectedTools: Tools()) -> IO(Messages()):
  match value:
    case T.AgentContext{+messages, Some{tools}}:
      do IO<Messages()>:
        Test.assertion(Bool.not(R.same(List<&2, Message()>, messages, old)), "run must copy the top-level message array")
        Test.assertion(R.same(List<&2, R.Ref<T.AgentTool<Unit, U32, String, String, Unit, String>>>, tools, expectedTools), "run must retain tools array identity")
        return messages
    case _: IO.die(Messages(), 1, "optional tools lost")

def sharedElement(value: Message(), expected: R.Ref<String>) -> Bool:
  match value:
    case T.CustomMessage{actual}: R.same(String, actual, expected)
    case _: False{}

def ordered(values: List<&2, Message()>, old: R.Ref<String>, prompt: R.Ref<String>) -> IO(Unit):
  match values:
    case a <> b <> Nil{}: Test.assertion(sharedElement(a, old) && sharedElement(b, prompt), "copied transcript must preserve old-before-prompt order and object identity")
    case _: IO.die(Unit, 1, "run transcript shape differs from source spread")

def checkBefore(value: Before(), expected: R.Ref<Context()>) -> IO(Unit):
  match value:
    case T.BeforeToolCallContext{_, call, args, context}:
      do IO<Unit>:
        Test.assertion(U32.is_eq(args, 7) && R.same(Context(), context, expected), "before hook lost validated arguments/context")
        raw : Ai.ToolCall<String> <- R.read(Ai.ToolCall<String>, call)
        Test.assertion(String.eq(Loop.callArguments(String, raw), "raw"), "before hook replaced raw call arguments")

def checkAfter(value: After(), expected: R.Ref<Context()>, expectedResult: R.Ref<T.AgentToolResult<String>>) -> IO(Unit):
  match value:
    case T.AfterToolCallContext{_, _, args, result, isError, context}:
      Test.assertion(U32.is_eq(args, 7) && isError && R.same(Context(), context, expected) && R.same(T.AgentToolResult<String>, result, expectedResult), "after hook lost executed result/context identity")

def checkUpdate(value: Update(), expected: R.Ref<Context()>, expectedMessages: Messages()) -> IO(Unit):
  match value:
    case T.AgentLoopTurnUpdate{Some{context}, Some{messages}, None{}, Some{Ai.Off{}}}:
      Test.assertion(R.same(Context(), context, expected) && R.same(List<&2, Message()>, messages, expectedMessages), "next-turn replacement must preserve supplied identities and off thinking level")
    case _: IO.die(Unit, 1, "turn-update optional fields changed")

def checkTurn(value: T.PrepareNextTurnContext(Unit, String, Unit, String, String, U32, Unit, String), expected: R.Ref<Context()>, expectedMessages: Messages()) -> IO(Unit):
  match value:
    case T.ShouldStopAfterTurnContext{_, _, context, messages}:
      Test.assertion(R.same(Context(), context, expected) && R.same(List<&2, Message()>, messages, expectedMessages), "prepare-next-turn alias changed completed context")

def main() -> IO(Unit):
  do IO<Unit>:
    +old : R.Ref<String> <- R.new(String, "old")
    +prompt : R.Ref<String> <- R.new(String, "prompt")
    +messages : Messages() <- R.new(List<&2, Message()>, T.CustomMessage{old} <> Nil{})
    +tools : Tools() <- R.new(List<&2, R.Ref<T.AgentTool<Unit, U32, String, String, Unit, String>>>, Nil{})
    +run : R.Ref<Context()> <- Loop.copyContextMessages(Unit, String, Unit, String, String, U32, Unit, String, T.AgentContext{messages, Some{tools}}, T.CustomMessage{prompt} <> Nil{})
    value : Context() <- R.read(Context(), run)
    +copied : Messages() <- copiedMessages(value, messages, tools)
    R.write(List<&2, Message()>, messages, Nil{})
    transcript : List<&2, Message()> <- R.read(List<&2, Message()>, copied)
    ordered(transcript, old, prompt)
    R.write(String, old, "changed")
    +zero : F.F64 = F.fromU32(0)
    +cost : R.Ref<Ai.UsageCost> <- R.new(Ai.UsageCost, Ai.UsageCost{zero, zero, zero, zero, zero})
    +assistantUsage : R.Ref<Ai.Usage> <- R.new(Ai.Usage, Test.usage(cost))
    +assistantContent : R.Ref<List<&2, Ai.AssistantContent<String>>> <- R.new(List<&2, Ai.AssistantContent<String>>, Nil{})
    +assistant : R.Ref<Ai.AssistantMessage<String, Unit>> <- R.new(Ai.AssistantMessage<String, Unit>, Test.assistant(assistantContent, assistantUsage, Ai.Stop{}))
    +call : T.AgentToolCall(String) <- R.new(Ai.ToolCall<String>, Ai.ToolCall{"id", "tool", "raw", None{}, None{}})
    +result : R.Ref<T.AgentToolResult<String>> <- R.new(T.AgentToolResult<String>, T.AgentToolResult{Nil{}, "details", None{}, None{}})
    checkBefore(T.BeforeToolCallContext{assistant, call, 7, run}, run)
    checkAfter(T.AfterToolCallContext{assistant, call, 7, result, True{}, run}, run, result)
    +toolResults : R.Ref<List<&2, R.Ref<Ai.ToolResultMessage<String>>>> <- R.new(List<&2, R.Ref<Ai.ToolResultMessage<String>>>, Nil{})
    completed : Turn() = T.ShouldStopAfterTurnContext{assistant, toolResults, run, copied}
    checkTurn(completed, run, copied)
    checkUpdate(T.AgentLoopTurnUpdate{Some{run}, Some{copied}, None{}, Some{Ai.Off{}}}, run, copied)
    oldRun : Context() <- R.dispose(Context(), run)
    oldMessages : List<&2, Message()> <- R.dispose(List<&2, Message()>, messages)
    oldCopied : List<&2, Message()> <- R.dispose(List<&2, Message()>, copied)
    oldTools : List<&2, R.Ref<T.AgentTool<Unit, U32, String, String, Unit, String>>> <- R.dispose(List<&2, R.Ref<T.AgentTool<Unit, U32, String, String, Unit, String>>>, tools)
    oldResults : List<&2, R.Ref<Ai.ToolResultMessage<String>>> <- R.dispose(List<&2, R.Ref<Ai.ToolResultMessage<String>>>, toolResults)
    oldAssistant : Ai.AssistantMessage<String, Unit> <- R.dispose(Ai.AssistantMessage<String, Unit>, assistant)
    oldAssistantContent : List<&2, Ai.AssistantContent<String>> <- R.dispose(List<&2, Ai.AssistantContent<String>>, assistantContent)
    oldCall : Ai.ToolCall<String> <- R.dispose(Ai.ToolCall<String>, call)
    oldResult : T.AgentToolResult<String> <- R.dispose(T.AgentToolResult<String>, result)
    oldAssistantUsage : Ai.Usage <- R.dispose(Ai.Usage, assistantUsage)
    oldCost : Ai.UsageCost <- R.dispose(Ai.UsageCost, cost)
    retained : String <- R.read(String, old)
    Test.assertion(String.eq(retained, "changed"), "context disposal must not own supplied message objects")
    oldText : String <- R.dispose(String, old)
    promptText : String <- R.dispose(String, prompt)
    IO.print("PASS context copies, shared arrays/elements and typed hook/turn contracts")
