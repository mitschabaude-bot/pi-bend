import Base
import ../../src/api/openai-responses-shared.bend as C
import ../../src/api/constrained-sampling.bend as Sampling
import ../../src/api/transform-messages.bend as Transform
import ../../../runtime/src/f64.bend as F
import ../../src/types.bend as T
import ../../src/utils/json.bend as Json
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/utf16.bend as U
import ../../../runtime/test/schema.bend as A

def arguments(value: V.Value) -> V.Value: value

def encoded(value: Maybe<&2,String>, expected: String) -> Bool:
  match value:
    case Some{actual}: U.equal(actual,expected)
    case None{}: False{}

def matches(result: Result<&2,&2,C.AssistantError,List<&2,C.AssistantItem>>, expected: Result<&2,&2,String,String>) -> Bool:
  match result expected:
    case Done{items} Done{text}: encoded(Json.stringify(C.itemsToJson(items)),text)
    case Fail{C.InvalidReasoningSignature{_}} Fail{"reasoning"}: True{}
    case Fail{C.InvalidGrammarInput{error}} Fail{text}: String.eq(Sampling.errorMessage(error),text)
    case _ _: False{}

def source(content: List<&2,T.AssistantContent<V.Value>>, +same: Bool, different: Bool) -> T.AssistantMessage<V.Value,Unit>:
  +zero = F.fromU32(0)
  usage = {T.Usage{zero,zero,zero,zero,None{},None{},zero,T.UsageCost{zero,zero,zero,zero,zero}} : T.Usage}
  T.AssistantMessage{content,"openai-responses",Bool.pick(String,same || different,"openai","other"),Bool.pick(String,same,"target","other"),None{},None{},None{},None{},usage,T.Stop{},None{},None{},None{},None{},zero}

def fromMessage(content: List<&2,T.AssistantContent<V.Value>>, context: C.ReplayContext) -> Result<&2,&2,C.AssistantError,List<&2,C.AssistantItem>>:
  match context:
    case C.ReplayContext{same,different,index,properties}: C.convertAssistantMessage(~V.Value,~Unit,~arguments,Transform.Target{"openai-responses","openai","target"},source(content,same,different),index,properties)

def check(+content: List<&2,T.AssistantContent<V.Value>>, +context: C.ReplayContext, +expected: Result<&2,&2,String,String>, label: String) -> IO(Unit):
  A.assertion(matches(C.convertAssistantContent(~V.Value,~arguments,content,context),expected) && matches(fromMessage(content,context),expected),label)

# Application-native arguments remain typed until the supplied pure encoder.
type Query is Data:
  Query{expression: String}

def encodeQuery(query: Query) -> V.Value:
  match query:
    case Query{text}: V.ObjectValue{R.Record{R.Property{"source",V.Text{text}} <> Nil{}}}

def nativeArguments() -> IO(Unit):
  content = {T.AssistantToolCall{T.ToolCall{"call|ctc_1","query",Query{"a + b"},None{},Some{"tools"}}} <> Nil{} : List<&2,T.AssistantContent<Query>>}
  context = {C.ReplayContext{True{},False{},0n,R.Record{R.Property{"query","source"} <> Nil{}}} : C.ReplayContext}
  A.assertion(matches(C.convertAssistantContent(~Query,~encodeQuery,content,context),Done{"[{\"type\":\"custom_tool_call\",\"id\":\"ctc_1\",\"call_id\":\"call\",\"name\":\"query\",\"input\":\"a + b\",\"namespace\":\"tools\"}]"}),"native argument record encoder")
