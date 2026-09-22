import Base
import ../../src/api/openai-responses-shared.bend as C
import ../../src/api/constrained-sampling.bend as Sampling
import ../../src/types.bend as T
import ../../src/utils/json.bend as Json
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/utf16.bend as U
import ../../../runtime/test/schema.bend as A

def Messages() -> Data: List<&2,T.Message<V.Value,R.Record<V.Value>,Unit,Unit>>

def clock(unused: Unit) -> IO(F64): IO.pure(F64,F.fromU32(1000))

def model(reasoning: Bool, vision: Bool, developer: Maybe<&2,Bool>) -> T.Model<Unit>:
  +zero = F.fromU32(0)
  T.Model{"target","Target",T.OpenAIResponsesApi{},"openai","https://example.test",reasoning,None{},T.InputText{} <> Bool.pick(List<&2,T.ModelInput>,vision,T.InputImage{} <> Nil{},Nil{}),T.ModelCost{zero,zero,zero,zero,None{}},F.fromU32(128000),F.fromU32(4096),None{},None{},Some{T.OpenAIResponsesCompat{developer,None{},None{},None{},None{},None{},None{},None{},None{},None{}}}}

def assistantWith(~Arguments: Data, content: List<&2,T.AssistantContent<Arguments>>, api: String, provider: String, model: String, reason: T.StopReason) -> T.AssistantMessage<Arguments,Unit>:
  +zero = F.fromU32(0)
  usage = {T.Usage{zero,zero,zero,zero,None{},None{},zero,T.UsageCost{zero,zero,zero,zero,zero}} : T.Usage}
  T.AssistantMessage{content,api,provider,model,None{},None{},None{},None{},usage,reason,None{},None{},None{},None{},F.fromU32(1)}

def assistant(content: List<&2,T.AssistantContent<R.Record<V.Value>>>, api: String, provider: String, model: String, reason: T.StopReason) -> T.AssistantMessage<R.Record<V.Value>,Unit>:
  assistantWith(~R.Record<V.Value>,content,api,provider,model,reason)

def assistantJson(content: List<&2,T.AssistantContent<V.Value>>, api: String, provider: String, model: String, reason: T.StopReason) -> T.AssistantMessage<V.Value,Unit>:
  assistantWith(~V.Value,content,api,provider,model,reason)

def errorMatches(error: C.MessageError, expected: String) -> Bool:
  match error:
    case C.AssistantConversion{C.InvalidReasoningSignature{_}}: String.eq(expected,"reasoning")
    case C.AssistantConversion{C.InvalidGrammarInput{error}}: String.eq(Sampling.errorMessage(error),expected)
    case C.ToolConversion{error}: String.eq(Sampling.errorMessage(error),expected)
    case _: False{}

def encoded(actual: Maybe<&2,String>, expected: String) -> Bool:
  match actual:
    case None{}: False{}
    case Some{text}: U.equal(text,expected)

def matches(actual: Result<&2,&2,C.MessageError,List<&2,C.ResponseInputItem>>, expected: Result<&2,&2,String,String>) -> Bool:
  match actual expected:
    case Done{items} Done{text}: encoded(Json.stringify(C.inputToJson(items)),text)
    case Fail{error} Fail{text}: errorMatches(error,text)
    case _ _: False{}

def check(model: T.Model<Unit>, messages: Messages(), allowed: List<&2,String>, options: Maybe<&2,C.ConvertResponsesMessagesOptions>, expected: Result<&2,&2,String,String>, label: String) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2,&2,C.MessageError,List<&2,C.ResponseInputItem>> <- C.convertResponsesMessagesWith(~V.Value,~R.Record<V.Value>,~Unit,~Unit,~Unit,~C.parameterValue,~C.argumentRecord,~clock,model,T.TranscriptContext{messages},allowed,options)
    A.assertion(matches(result,expected),label)

# Provider-generated arguments are JSON values until tool validation.
def checkJson(model: T.Model<Unit>, messages: List<&2,T.Message<V.Value,V.Value,Unit,Unit>>, allowed: List<&2,String>, options: Maybe<&2,C.ConvertResponsesMessagesOptions>, expected: Result<&2,&2,String,String>, label: String) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2,&2,C.MessageError,List<&2,C.ResponseInputItem>> <- C.convertResponsesMessagesWith(~V.Value,~V.Value,~Unit,~Unit,~Unit,~C.parameterValue,~C.parameterValue,~clock,model,T.TranscriptContext{messages},allowed,options)
    A.assertion(matches(result,expected),label)
