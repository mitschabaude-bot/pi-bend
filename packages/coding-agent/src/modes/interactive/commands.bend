import Base
import ../../../../ai/src/types.bend as Ai
import ../../../../ai/src/utils/thinking-levels.bend as Levels
import ../../../../runtime/src/text.bend as Text
import ../../core/agent-session.bend as Session
import ../../core/compaction/compaction.bend as Compaction

# Built-in commands are recognized before submitting to the agent. Features
# without a session operation report an error instead of becoming model input.
type Action is Data:
  Prompt{text: String}
  Exit{}
  Notice{text: String}
  CommandError{text: String}
type Command is Data:
  Send{text: String}
  Stop{}
  Help{}
  ShowModel{requested: Maybe<&2,String>}
  SetThinking{requested: Maybe<&2,String>}
  Compact{instructions: Maybe<&2,String>}
  NewSession{}
  Unsupported{text: String}

def argument(text: String,prefix: Nat) -> Maybe<&2,String>:
  +value = Text.trim(String.drop(text,prefix))
  Bool.pick(Maybe<&2,String>,String.is_empty(value),None{},Some{value})
def classify(+text: String,parts: List<&2,String>) -> Command:
  match parts:
    case "/exit" <> Nil{}: Stop{}
    case "/quit" <> Nil{}: Stop{}
    case "/help" <> Nil{}: Help{}
    case "/model" <> _: ShowModel{argument(text,6n)}
    case "/thinking" <> _: SetThinking{argument(text,9n)}
    case "/compact" <> _: Compact{argument(text,8n)}
    case "/new" <> Nil{}: NewSession{}
    case "/clear" <> Nil{}: NewSession{}
    case _:
      Bool.pick(Command,String.starts_with(text,"/") || String.starts_with(text,"!"),Unsupported{text},Send{text})
def names(levels: List<&2,Ai.ModelThinkingLevel>) -> List<&2,String>:
  match levels:
    case Nil{}: Nil{}
    case level <> rest: Levels.name(level) <> names(rest)
def available(model: Ai.Model<Ai.JsonValue>) -> List<&2,Ai.ModelThinkingLevel>:
  match model:
    case Ai.Model{_,_,_,_,_,reasoning,mapping,_,_,_,_,_,_,_,_,_}: Levels.available(reasoning,mapping)
def findLevel(levels: List<&2,Ai.ModelThinkingLevel>,+wanted: String) -> Maybe<&2,Ai.ModelThinkingLevel>:
  match levels:
    case Nil{}: None{}
    case +level <> rest:
      Bool.pick(Maybe<&2,Ai.ModelThinkingLevel>,String.eq(Levels.name(level),wanted),Some{level},findLevel(rest,wanted))
def selected(level: Ai.ModelThinkingLevel,result: Result<&2,&2,String,Unit>) -> Action:
  match result:
    case Done{_}: Notice{"Thinking level: " ++ Levels.name(level)}
    case Fail{reason}: CommandError{reason}
def choose(session: Session.AgentSession,+level: Ai.ModelThinkingLevel) -> IO(Action):
  do IO<Action>:
    result : Result<&2,&2,String,Unit> <- Session.setThinkingLevel(session,level)
    return selected(level,result)
def thinkingSelected(session: Session.AgentSession,levels: List<&2,Ai.ModelThinkingLevel>,requested: String,found: Maybe<&2,Ai.ModelThinkingLevel>) -> IO(Action):
  match found:
    case Some{level}: choose(session,level)
    case None{}: IO.pure(Action,CommandError{"Unknown thinking level \"" ++ requested ++ "\". Available levels: " ++ String.join(names(levels),", ") ++ "."})
def thinkingWith(session: Session.AgentSession,current: Session.AgentState(),+levels: List<&2,Ai.ModelThinkingLevel>,requested: Maybe<&2,String>) -> IO(Action):
  match requested:
    case None{}: IO.pure(Action,Notice{"Thinking level: " ++ Levels.name(Session.stateThinking(current)) ++ ". Available: " ++ String.join(names(levels),", ")})
    case Some{+value}: thinkingSelected(session,levels,value,findLevel(levels,String.to_lower(value)))
def thinking(+session: Session.AgentSession,requested: Maybe<&2,String>) -> IO(Action):
  do IO<Action>:
    +current : Session.AgentState() <- Session.state(session)
    thinkingWith(session,current,available(Session.stateModel(current)),requested)
def modelNotice(model: Ai.Model<Ai.JsonValue>) -> Action:
  match model:
    case Ai.Model{id,_,_,provider,_,_,_,_,_,_,_,_,_,_,_,_}: Notice{"Model: " ++ provider ++ "/" ++ id}
def showModel(session: Session.AgentSession,requested: Maybe<&2,String>) -> IO(Action):
  match requested:
    case Some{_}: IO.pure(Action,CommandError{"Model switching is not available yet"})
    case None{}:
      do IO<Action>:
        current : Session.AgentState() <- Session.state(session)
        return modelNotice(Session.stateModel(current))
def compacted(result: Result<&2,&2,String,Compaction.CompactionResult>) -> Action:
  match result:
    case Done{_}: Notice{"Session compacted"}
    case Fail{reason}: CommandError{reason}
def compact(session: Session.AgentSession,instructions: Maybe<&2,String>) -> IO(Action):
  do IO<Action>:
    result : Result<&2,&2,String,Compaction.CompactionResult> <- Session.compact(session,instructions)
    return compacted(result)
def execute(session: Session.AgentSession,command: Command) -> IO(Action):
  match command:
    case Send{text}: IO.pure(Action,Prompt{text})
    case Stop{}: IO.pure(Action,Exit{})
    case Help{}: IO.pure(Action,Notice{"Commands: /thinking [level], /compact [instructions], /exit"})
    case ShowModel{requested}: showModel(session,requested)
    case SetThinking{requested}: thinking(session,requested)
    case Compact{instructions}: compact(session,instructions)
    case NewSession{}: IO.pure(Action,CommandError{"Starting a new session is not available yet"})
    case Unsupported{text}: IO.pure(Action,CommandError{"Unknown command: " ++ text})
def parse(text: String) -> Command:
  +clean = Text.trim(text)
  classify(clean,String.split(clean,' '))
