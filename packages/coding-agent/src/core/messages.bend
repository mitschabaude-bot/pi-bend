import Base
import ../../../agent/src/types.bend as Agent
import ../../../ai/src/types.bend as Ai
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/schema-value.bend as Value

def COMPACTION_SUMMARY_PREFIX() -> String: "The conversation history before this point was compacted into the following summary:\n\n<summary>\n"
def COMPACTION_SUMMARY_SUFFIX() -> String: "\n</summary>"
def BRANCH_SUMMARY_PREFIX() -> String: "The following is a summary of a branch that this conversation came back from:\n\n<summary>\n"
def BRANCH_SUMMARY_SUFFIX() -> String: "</summary>"

type BashExecutionMessage is Data:
  BashExecutionMessage{command: String, output: String, exitCode: Maybe<&2,U32>, cancelled: Bool, truncated: Bool, fullOutputPath: Maybe<&2,String>, timestamp: F64, excludeFromContext: Maybe<&2,Bool>}
type CustomMessage<-Details: Data> is Data:
  CustomMessage{customType: String, content: Ai.UserContent, display: Bool, details: Maybe<&2,Details>, timestamp: F64}
type BranchSummaryMessage is Data:
  BranchSummaryMessage{summary: String, fromId: Maybe<&2,String>, timestamp: F64}
type CompactionSummaryMessage is Data:
  CompactionSummaryMessage{summary: String, tokensBefore: Nat, timestamp: F64}
type CodingMessage<-Details: Data> is Data:
  BashExecution{value: BashExecutionMessage}
  Custom{value: CustomMessage<Details>}
  BranchSummary{value: BranchSummaryMessage}
  CompactionSummary{value: CompactionSummaryMessage}

def exitText(code: Maybe<&2,U32>) -> String:
  match code:
    case None{}: ""
    case Some{0}: ""
    case Some{code}: "\n\nCommand exited with code " ++ U32.show(code)

def pathText(truncated: Bool, path: Maybe<&2,String>) -> String:
  match truncated path:
    case True{} Some{SCon{first,rest}}: "\n\n[Output truncated. Full output: " ++ SCon{first,rest} ++ "]"
    case _ _: ""

def bashExecutionToText(message: BashExecutionMessage) -> String:
  match message:
    case BashExecutionMessage{command,+output,code,cancelled,truncated,path,_,_}:
      "Ran `" ++ command ++ "`\n" ++ Bool.pick(String,String.eq(output,""),"(no output)","```\n" ++ output ++ "\n```") ++
        Bool.pick(String,cancelled,"\n\n(command cancelled)",exitText(code)) ++ pathText(truncated,path)

def createBranchSummaryMessage(summary: String, fromId: String, timestamp: String) -> Result<&2,&2,Date.ParseError,BranchSummaryMessage>:
  Result.map(&2,&2,Date.ParseError,F64,BranchSummaryMessage,time => BranchSummaryMessage{summary,Some{fromId},time},Date.parseIso(timestamp))

def createCompactionSummaryMessage(summary: String, tokensBefore: Nat, timestamp: String) -> Result<&2,&2,Date.ParseError,CompactionSummaryMessage>:
  Result.map(&2,&2,Date.ParseError,F64,CompactionSummaryMessage,time => CompactionSummaryMessage{summary,tokensBefore,time},Date.parseIso(timestamp))

def createCustomMessage(-Details: Data, customType: String, content: Ai.UserContent, display: Bool, details: Maybe<&2,Details>, timestamp: String) -> Result<&2,&2,Date.ParseError,CustomMessage<Details>>:
  Result.map(&2,&2,Date.ParseError,F64,CustomMessage<Details>,time => CustomMessage{customType,content,display,details,time},Date.parseIso(timestamp))

def contentBlocks(content: Ai.UserContent) -> List<&2,Ai.TextImageContent>:
  match content:
    case Ai.UserText{text}: [Ai.TextImageText{Ai.TextContent{text,None{}}}]
    case Ai.UserBlocks{blocks}: blocks

def bashUser(-D: Data, -T: Data, +message: BashExecutionMessage) -> Maybe<&2,Ai.Message<Value.Value,Value.Value,D,T>>:
  match message:
    case BashExecutionMessage{_,_,_,_,_,_,timestamp,exclude}:
      Bool.pick(Unit -> Maybe<&2,Ai.Message<Value.Value,Value.Value,D,T>>,Maybe.default(&2,Bool,exclude,False{}),_ => None{},
        _ => Some{Ai.User{Ai.UserMessage{Ai.UserBlocks{[Ai.TextImageText{Ai.TextContent{bashExecutionToText(message),None{}}}]},timestamp}}})(Unit{})

def convertedCustom(-D: Data, -T: Data, -C: Data, message: CodingMessage<C>) -> Maybe<&2,Ai.Message<Value.Value,Value.Value,D,T>>:
  match message:
    case BashExecution{value}: bashUser(D,T,value)
    case Custom{CustomMessage{_,content,_,_,timestamp}}: Some{Ai.User{Ai.UserMessage{Ai.UserBlocks{contentBlocks(content)},timestamp}}}
    case BranchSummary{BranchSummaryMessage{summary,_,timestamp}}:
      Some{Ai.User{Ai.UserMessage{Ai.UserBlocks{[Ai.TextImageText{Ai.TextContent{BRANCH_SUMMARY_PREFIX() ++ summary ++ BRANCH_SUMMARY_SUFFIX(),None{}}}]},timestamp}}}
    case CompactionSummary{CompactionSummaryMessage{summary,_,timestamp}}:
      Some{Ai.User{Ai.UserMessage{Ai.UserBlocks{[Ai.TextImageText{Ai.TextContent{COMPACTION_SUMMARY_PREFIX() ++ summary ++ COMPACTION_SUMMARY_SUFFIX(),None{}}}]},timestamp}}}

def convertToLlmFrom(-D: Data, -T: Data, -C: Data, messages: List<&2,Agent.AgentMessage<D,T,CodingMessage<C>>>, +reversed: List<&2,Ai.Message<Value.Value,Value.Value,D,T>>) -> List<&2,Ai.Message<Value.Value,Value.Value,D,T>>:
  match messages:
    case Nil{}: List.reverse(&2,Ai.Message<Value.Value,Value.Value,D,T>,reversed)
    case Agent.LlmMessage{value} <> rest: convertToLlmFrom(D,T,C,rest,value <> reversed)
    case Agent.CustomMessage{value} <> rest: convertToLlmFrom(D,T,C,rest,Maybe.default(&2,List<&2,Ai.Message<Value.Value,Value.Value,D,T>>,Maybe.map(&2,Ai.Message<Value.Value,Value.Value,D,T>,List<&2,Ai.Message<Value.Value,Value.Value,D,T>>,value => value <> reversed,convertedCustom(D,T,C,value)),reversed))

def convertToLlm(-D: Data, -T: Data, -C: Data, messages: List<&2,Agent.AgentMessage<D,T,CodingMessage<C>>>) -> List<&2,Ai.Message<Value.Value,Value.Value,D,T>>:
  convertToLlmFrom(D,T,C,messages,Nil{})
