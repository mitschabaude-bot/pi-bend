import Base
import ../src/types.bend as T
import ../src/agent-loop.bend as Loop
import ./tool-batch-policy.bend as B
import ../../ai/src/types.bend as Ai
import ../../ai/test/model-types.bend as Model
import ../../runtime/src/callback.bend as C
import ../../runtime/src/f64.bend as F
import ../../runtime/src/schema-value.bend as Schema
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/fetch.bend as Fetch

def Message() -> Data: Ai.AssistantMessage<Schema.Value, Unit>
def Context() -> Data: T.AgentContext<Unit, Unit, String, String>
def Config() -> Data: T.AgentLoopConfig<Unit, Unit, String, String, Unit>
def Messages() -> Data: T.AgentMessageArray(Unit, Unit, String)
def ConvertOutput() -> Data: Result<&2, &2, String, List<&2, Ai.Message<Schema.Value, Schema.Value, Unit, Unit>>>
def Converter() -> Data: C.Callback<Messages(), ConvertOutput()>

def forbidden(unused: Unit, messages: Messages()) -> IO(ConvertOutput()):
  IO.die(ConvertOutput(), 1, "tool selection must not convert messages")

def config(model: Ai.Model<Ai.JsonValue>, converter: Converter(), configured: Maybe<&2, T.ToolExecutionMode>) -> Config():
  T.AgentLoopConfig{Ai.emptySimpleStreamOptions(Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), String), model, converter, None{}, None{}, None{}, None{}, None{}, None{}, None{}, configured, None{}, None{}}

def contents(tags: List<&2, String>, +a: T.AgentToolCall, +b: T.AgentToolCall, +text: Ai.TextContent, +thinking: Ai.ThinkingContent) -> List<&2, Ai.AssistantContent<Schema.Value>>:
  match tags:
    case Nil{}: Nil{}
    case +tag <> rest:
      Bool.pick(Ai.AssistantContent<Schema.Value>, String.eq(tag, "a"), Ai.AssistantToolCall{a}, Bool.pick(Ai.AssistantContent<Schema.Value>, String.eq(tag, "b"), Ai.AssistantToolCall{b}, Bool.pick(Ai.AssistantContent<Schema.Value>, String.eq(tag, "text"), Ai.AssistantText{text}, Ai.AssistantThinking{thinking}))) <> contents(rest, a, b, text, thinking)

def callId(value: Ai.ToolCall<Schema.Value>, actual: T.AgentToolCall, a: T.AgentToolCall, b: T.AgentToolCall) -> IO(String):
  match value:
    case Ai.ToolCall{+id, name, _, _, _}:
      do IO<String>:
        expected : T.AgentToolCall = Bool.pick(T.AgentToolCall, String.eq(id, "a"), a, b)
        B.assertion(String.eq(name, Bool.pick(String, String.eq(id, "a"), "a", "b")), "selection changed call names")
        return id

def ids(values: List<&2, T.AgentToolCall>, +a: T.AgentToolCall, +b: T.AgentToolCall) -> IO(String):
  match values:
    case Nil{}: IO.pure(String, "")
    case +call <> rest:
      do IO<String>:
        value : Ai.ToolCall<Schema.Value> = call
        id : String <- callId(value, call, a, b)
        tail : String <- ids(rest, a, b)
        return id ++ "|" ++ tail

def check(batch: Loop.PreparedToolCallBatch, expectedMode: String, expectedIds: String, a: T.AgentToolCall, b: T.AgentToolCall, another: List<&2, T.AgentToolCall>) -> IO(Unit):
  match batch:
    case Loop.PreparedToolCallBatch{+calls, mode}:
      do IO<Unit>:
        B.assertion(String.eq(B.modeName(mode), expectedMode), "prepared batch mode differs from upstream")
        values : List<&2, T.AgentToolCall> = calls
        observed : String <- ids(values, a, b)
        B.assertion(String.eq(observed, expectedIds), "tool filtering changed order, duplicates or array independence")

def optionalTools(present: Bool, tools: T.AgentToolArray(Unit, String)) -> Maybe<&2, T.AgentToolArray(Unit, String)>:
  match present:
    case True{}: Some{tools}
    case False{}: None{}

def run(tags: List<&2, String>, specs: List<&2, B.ToolSpec>, present: Bool, configured: Maybe<&2, T.ToolExecutionMode>, expectedMode: String, expectedIds: String) -> IO(Unit):
  do IO<Unit>:
    +a : T.AgentToolCall = Ai.ToolCall{"a", "a", Schema.Null{}, None{}, None{}}
    +b : T.AgentToolCall = Ai.ToolCall{"b", "b", Schema.Null{}, None{}, None{}}
    +text : Ai.TextContent = Ai.TextContent{"text", None{}}
    +thinking : Ai.ThinkingContent = Ai.ThinkingContent{"thinking", None{}, None{}}
    +content : List<&2, Ai.AssistantContent<Schema.Value>> = contents(tags, a, b, text, thinking)
    +zero : F64 = F.fromU32(0)
    +cost : Ai.UsageCost = Ai.UsageCost{zero, zero, zero, zero, zero}
    +usage : Ai.Usage = Ai.Usage{zero, zero, zero, zero, None{}, None{}, zero, cost}
    +assistant : Message() = Ai.AssistantMessage{content, "custom", "provider", "model", None{}, None{}, None{}, None{}, usage, Ai.ToolUse{}, None{}, None{}, None{}, None{}, zero}
    +execute : C.Callback<B.ExecuteInput(), B.ExecuteOutput()> <- C.create(~Unit, ~B.ExecuteInput(), ~B.ExecuteOutput(), ~B.forbidden, Unit{})
    +tools : List<&2, B.ToolValue()> <- B.makeTools(specs, execute)
    +toolArray : T.AgentToolArray(Unit, String) = tools
    +messages : Messages() = Nil{}
    +context : Context() = T.AgentContext{messages, optionalTools(present, toolArray)}
    +converter : Converter() <- C.create(~Unit, ~Messages(), ~ConvertOutput(), ~forbidden, Unit{})
    +model : Ai.Model<Ai.JsonValue> = Model.model(Ai.CustomModelApi{"custom"}, None{})
    +configuration : Config() = config(model, converter, configured)
    batch : Loop.PreparedToolCallBatch = Loop.prepareToolCallBatch(Unit, Unit, String, String, Unit, context, assistant, configuration)
    +another : List<&2, T.AgentToolCall> = Loop.collectAssistantToolCalls(Unit, assistant)
    check(batch, expectedMode, expectedIds, a, b, another)
    oldAnother : List<&2, T.AgentToolCall> = another
    C.dispose(Messages(), ConvertOutput(), converter)
    C.dispose(B.ExecuteInput(), B.ExecuteOutput(), execute)
    oldModel : Ai.Model<Ai.JsonValue> = model
    oldMessages : List<&2, T.AgentMessage<Unit, Unit, String>> = messages
    oldContent : List<&2, Ai.AssistantContent<Schema.Value>> = content
    oldUsage : Ai.Usage = usage
    oldCost : Ai.UsageCost = cost
    oldText : Ai.TextContent = text
    oldThinking : Ai.ThinkingContent = thinking
    oldA : Ai.ToolCall<Schema.Value> = a
    oldB : Ai.ToolCall<Schema.Value> = b
    return Unit{}
