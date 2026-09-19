import Base
import ../../src/api/openai-responses-shared.bend as C
import ../../src/api/openai-responses-assistant.bend as Assistant
import ../../src/types.bend as T
import ../../src/utils/transcript.bend as Transcript
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/f64.bend as F
import ./responses-messages.bend as Fixture

# Explicit conversion fixtures replace generated catalog lookup; catalog
# registration/loading is outside these message-conversion contracts.
def model(api: T.ModelApi, provider: String, id: String) -> T.Model<Unit>:
  +zero = F.fromU32(0)
  T.Model{id,"Fixture",api,provider,"https://example.invalid",True{},None{},T.InputText{} <> Nil{},T.ModelCost{zero,zero,zero,zero,None{}},F.fromU32(400000),F.fromU32(128000),None{},None{},None{}}

def assistant(content: List<&2,T.AssistantContent<R.Record<V.Value>>>, api: String, provider: String, id: String, stop: T.StopReason) -> T.Message<V.Value,R.Record<V.Value>,Unit,Unit>:
  T.Assistant{Fixture.assistant(content,api,provider,id,stop)}

def user(text: String) -> T.Message<V.Value,R.Record<V.Value>,Unit,Unit>:
  T.User{T.UserMessage{T.UserText{text},F.fromU32(0)}}

def result(id: String, name: String, text: String) -> T.Message<V.Value,R.Record<V.Value>,Unit,Unit>:
  T.ToolResult{T.ToolResultMessage{id,name,T.TextImageText{T.TextContent{text,None{}}} <> Nil{},None{},None{},False{},F.fromU32(2)}}

def toolCall(id: String, name: String, property: String, value: String, namespace: Maybe<&2,String>) -> T.AssistantContent<R.Record<V.Value>>:
  T.AssistantToolCall{T.ToolCall{id,name,R.Record{R.Property{property,V.Text{value}} <> Nil{}},None{},namespace}}

def successful(value: Result<&2,&2,C.MessageError,List<&2,C.ResponseInputItem>>) -> IO(List<&2,C.ResponseInputItem>):
  match value:
    case Fail{_}: IO.die(List<&2,C.ResponseInputItem>,1,"unexpected Responses conversion error")
    case Done{items}: IO.pure(List<&2,C.ResponseInputItem>,items)

def convert(model: T.Model<Unit>, prompt: Maybe<&2,String>, messages: Fixture.Messages(), providers: List<&2,String>, options: Maybe<&2,C.ConvertResponsesMessagesOptions>) -> IO(List<&2,C.ResponseInputItem>):
  do IO<List<&2,C.ResponseInputItem>>:
    value : Result<&2,&2,C.MessageError,List<&2,C.ResponseInputItem>> <- C.convertResponsesMessages(~Unit,~Unit,~Unit,model,Transcript.normalizeContext(V.Value,R.Record<V.Value>,Unit,Unit,T.Context{prompt,messages,None{}}),providers,options)
    successful(value)

def findCall(items: List<&2,C.ResponseInputItem>, +custom: Bool) -> Maybe<&2,Assistant.Call>:
  match items:
    case Nil{}: None{}
    case C.AssistantInput{Assistant.FunctionCall{call,_}} <> rest: Bool.pick(Maybe<&2,Assistant.Call>,custom,findCall(rest,custom),Some{call})
    case C.AssistantInput{Assistant.CustomToolCall{call,_}} <> rest: Bool.pick(Maybe<&2,Assistant.Call>,custom,Some{call},findCall(rest,custom))
    case _ <> rest: findCall(rest,custom)

def withoutNamespace(call: Maybe<&2,Assistant.Call>) -> Bool:
  match call:
    case Some{Assistant.Call{_,_,_,None{}}}: True{}
    case _: False{}
