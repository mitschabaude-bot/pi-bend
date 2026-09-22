import Base
import ../packages/coding-agent/src/core/messages.bend as M
import ../packages/agent/src/types.bend as Agent
import ../packages/ai/src/types.bend as Ai
import ../packages/runtime/src/date.bend as Date
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/string.bend as S
import ../packages/runtime/test/utf8-runner.bend as W
import ./tool-truncate.bend as Text

def date(result: Result<&2,&2,Date.ParseError,F64>) -> String:
  match result:
    case Fail{_}: "error"
    case Done{number}: Maybe.default(&2,String,F.toDecimal(number),"invalid")

def branch(result: Result<&2,&2,Date.ParseError,M.BranchSummaryMessage>) -> String:
  match result:
    case Fail{_}: "error"
    case Done{M.BranchSummaryMessage{summary,from,time}}: W.showText(summary) ++ "|" ++ Maybe.default(&2,String,from,"none") ++ "|" ++ date(Done{time})

def compaction(result: Result<&2,&2,Date.ParseError,M.CompactionSummaryMessage>) -> String:
  match result:
    case Fail{_}: "error"
    case Done{M.CompactionSummaryMessage{summary,tokens,time}}: W.showText(summary) ++ "|" ++ Nat.show(tokens) ++ "|" ++ date(Done{time})

def custom(result: Result<&2,&2,Date.ParseError,M.CustomMessage<String>>) -> String:
  match result:
    case Fail{_}: "error"
    case Done{M.CustomMessage{kind,Ai.UserText{text},display,details,time}}: kind ++ "|" ++ W.showText(text) ++ "|" ++ Text.boolean(display) ++ "|" ++ Maybe.default(&2,String,details,"none") ++ "|" ++ date(Done{time})
    case _: "unexpected"

def blocks(values: List<&2,Ai.TextImageContent>, reversed: List<&2,String>) -> String:
  match values:
    case Nil{}: String.join(List.reverse(&2,String,reversed),";")
    case Ai.TextImageText{Ai.TextContent{text,_}} <> rest: blocks(rest,("t:" ++ W.showText(text)) <> reversed)
    case Ai.TextImageImage{Ai.ImageContent{data,mime}} <> rest: blocks(rest,("i:" ++ data ++ ":" ++ mime) <> reversed)

def shown(messages: List<&2,Ai.Message<V.Value,V.Value,Unit,String>>) -> IO(Unit):
  match messages:
    case Nil{}: IO.pure(Unit,Unit{})
    case Ai.User{Ai.UserMessage{Ai.UserBlocks{content},timestamp}} <> rest:
      do IO<Unit>:
        IO.print("user|" ++ blocks(content,Nil{}) ++ "|" ++ date(Done{timestamp}))
        shown(rest)
    case Ai.User{Ai.UserMessage{Ai.UserText{text},timestamp}} <> rest:
      do IO<Unit>:
        IO.print("original|" ++ W.showText(text) ++ "|" ++ date(Done{timestamp}))
        shown(rest)
    case _ <> rest:
      do IO<Unit>:
        IO.print("other")
        shown(rest)

def conversion() -> IO(Unit):
  shown(M.convertToLlm(Unit,String,String,[
    Agent.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{"original"},F.fromU32(1)}}},
    Agent.CustomMessage{M.BashExecution{M.BashExecutionMessage{"skip","secret",None{},False{},False{},None{},F.fromU32(2),Some{True{}}}}},
    Agent.CustomMessage{M.Custom{M.CustomMessage{"hidden",Ai.UserText{"hidden still in context"},False{},Some{"details"},F.fromU32(3)}}},
    Agent.CustomMessage{M.Custom{M.CustomMessage{"image",Ai.UserBlocks{[Ai.TextImageText{Ai.TextContent{"caption",None{}}},Ai.TextImageImage{Ai.ImageContent{"YWJj","image/png"}}]},True{},None{},F.fromU32(4)}}},
    Agent.CustomMessage{M.BranchSummary{M.BranchSummaryMessage{"branch",None{},F.fromU32(5)}}},
    Agent.CustomMessage{M.CompactionSummary{M.CompactionSummaryMessage{"compact",123n,F.fromU32(6)}}},
    Agent.CustomMessage{M.BashExecution{M.BashExecutionMessage{"ls","file",Some{7},False{},True{},Some{"/tmp/full"},F.fromU32(7),None{}}}}
  ]))

def run(parts: List<&2,String>) -> IO(Unit):
  match parts:
    case "d" <> timestamp <> Nil{}: IO.print(date(Date.parseIso(timestamp)))
    case "c" <> +timestamp <> Nil{}:
      do IO<Unit>:
        IO.print(branch(M.createBranchSummaryMessage("summary","id",timestamp)))
        IO.print(compaction(M.createCompactionSummaryMessage("summary",123n,timestamp)))
        IO.print(custom(M.createCustomMessage(String,"custom",Ai.UserText{"body"},False{},Some{"details"},timestamp)))
    case "b" <> command <> output <> +code <> cancelled <> truncated <> +path <> Nil{}:
      IO.print(W.showText(M.bashExecutionToText(M.BashExecutionMessage{Text.text(command),Text.text(output),Bool.pick(Maybe<&2,U32>,String.eq(code,"none"),None{},Some{W.decimal(code,0)}),String.eq(cancelled,"1"),String.eq(truncated,"1"),Bool.pick(Maybe<&2,String>,String.eq(path,"none"),None{},Some{Text.text(path)}),F.fromU32(0),None{}})))
    case "convert" <> Nil{}: conversion()
    case _: IO.die(Unit,1,"invalid command")

def all(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        run(S.split(value,'|'))
        all(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    all(arguments)
