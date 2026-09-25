import Base
import ../../../../ai/src/types.bend as Ai
import ../../../../ai/src/utils/thinking-levels.bend as Levels
import ../../../../runtime/src/text.bend as Text
import ../../../../runtime/src/json.bend as Json
import ../../../../runtime/src/schema-value.bend as Schema
import ../../core/agent-session.bend as Session
import ../../core/compaction/compaction.bend as Compaction
import ../../core/model-runtime.bend as Models
import ../../core/session-manager.bend as Tree
import ../../core/tools/index.bend as Tools

# Built-in commands are recognized before submitting to the agent. Features
# without a session operation report an error instead of becoming model input.
type Action is Data:
  Prompt{text: String}
  Exit{}
  Notice{text: String}
  CommandError{text: String}
  OpenModelPicker{search: Maybe<&2,String>}
  OpenThinkingPicker{}
  OpenScopedModels{}
  ThinkingSelected{level: Ai.ModelThinkingLevel,persist: Bool}
  ModelSelected{model: Ai.Model<Ai.JsonValue>,persist: Bool}
  ExportSession{path: Maybe<&2,String>}
  ImportSession{path: Maybe<&2,String>}
  ResumeSession{}
  OpenTree{}
  OpenFork{}
  CopyLastAssistant{}
  OpenSettings{}
  OpenTrust{}
  NewSessionStarted{}
  ClonedSession{}
  ShowChangelog{}
  ShowSessionInfo{}
  ShowHotkeys{}
  ReloadResources{}
  RunBash{command: String,excluded: Bool}
type CredentialCommand is Data:
  BeginLogin{provider: Maybe<&2,String>}
  BeginLogout{}
type Command is Data:
  Send{text: String}
  Stop{}
  ShowModel{requested: Maybe<&2,String>}
  SwitchModel{model: Ai.Model<Ai.JsonValue>,persist: Bool}
  SetThinking{requested: Maybe<&2,String>}
  SelectThinking{level: Ai.ModelThinkingLevel,persist: Bool}
  ScopedModels{}
  Compact{instructions: Maybe<&2,String>}
  NewSession{}
  Clone{}
  Name{requested: Maybe<&2,String>}
  Login{provider: Maybe<&2,String>}
  Logout{}
  Export{path: Maybe<&2,String>}
  Import{path: Maybe<&2,String>}
  Resume{}
  Tree{}
  Fork{}
  Copy{}
  Settings{}
  Trust{}
  Changelog{}
  Session{}
  Hotkeys{}
  Reload{}
  Bash{command: String,excluded: Bool}
  Unsupported{text: String}

def argument(text: String,prefix: Nat) -> Maybe<&2,String>:
  +value = Text.trim(String.drop(text,prefix))
  Bool.pick(Maybe<&2,String>,String.is_empty(value),None{},Some{value})
def bashCommand(+text: String,prefix: Nat,excluded: Bool) -> Command:
  +command = Text.trim(String.drop(text,prefix))
  Bool.pick(Command,String.is_empty(command),Send{text},Bash{command,excluded})
# upstream's built-in commands that are not ported yet; they report so
# instead of reaching the model.
def unported(parts: List<&2,String>) -> Bool:
  match parts:
    case "/share" <> Nil{}: True{}
    case "/bug" <> _: True{}
    case "/debug" <> Nil{}: True{}
    case _: False{}

# upstream interactive-mode's built-in commands; any other text, including an
# unknown /name, is submitted, so prompt templates and /skill: commands expand
# in the session.
def classify(+text: String,+parts: List<&2,String>) -> Command:
  match parts:
    case "/quit" <> Nil{}: Stop{}
    case "/model" <> _: ShowModel{argument(text,6n)}
    case "/thinking" <> _: SetThinking{argument(text,9n)}
    case "/scoped-models" <> Nil{}: ScopedModels{}
    case "/compact" <> _: Compact{argument(text,8n)}
    case "/new" <> Nil{}: NewSession{}
    case "/clone" <> Nil{}: Clone{}
    case "/name" <> _: Name{argument(text,5n)}
    case "/login" <> _: Login{argument(text,6n)}
    case "/logout" <> Nil{}: Logout{}
    case "/export" <> _: Export{argument(text,7n)}
    case "/import" <> _: Import{argument(text,7n)}
    case "/resume" <> Nil{}: Resume{}
    case "/tree" <> Nil{}: Tree{}
    case "/fork" <> Nil{}: Fork{}
    case "/copy" <> Nil{}: Copy{}
    case "/session" <> Nil{}: Session{}
    case "/hotkeys" <> Nil{}: Hotkeys{}
    case "/settings" <> Nil{}: Settings{}
    case "/trust" <> Nil{}: Trust{}
    case "/changelog" <> Nil{}: Changelog{}
    case "/reload" <> Nil{}: Reload{}
    case _:
      Bool.pick(Command,String.starts_with(text,"!!"),bashCommand(text,2n,True{}),
        Bool.pick(Command,String.starts_with(text,"!"),bashCommand(text,1n,False{}),
          Bool.pick(Command,unported(parts),Unsupported{text},Send{text})))
def names(levels: List<&2,Ai.ModelThinkingLevel>) -> List<&2,String>:
  match levels:
    case Nil{}: Nil{}
    case level <> rest: Levels.name(level) <> names(rest)
def available(selected: Maybe<&2,Ai.Model<Ai.JsonValue>>) -> List<&2,Ai.ModelThinkingLevel>:
  match selected:
    case None{}: Ai.Off{} <> Nil{}
    case Some{Ai.Model{_,_,_,_,_,reasoning,mapping,_,_,_,_,_,_,_,_,_}}: Levels.available(reasoning,mapping)
def findLevel(levels: List<&2,Ai.ModelThinkingLevel>,+wanted: String) -> Maybe<&2,Ai.ModelThinkingLevel>:
  match levels:
    case Nil{}: None{}
    case +level <> rest:
      Bool.pick(Maybe<&2,Ai.ModelThinkingLevel>,String.eq(Levels.name(level),wanted),Some{level},findLevel(rest,wanted))
def selected(level: Ai.ModelThinkingLevel,persist: Bool,result: Result<&2,&2,String,Unit>) -> Action:
  match result:
    case Done{_}: ThinkingSelected{level,persist}
    case Fail{reason}: CommandError{reason}
def choose(session: Session.AgentSession,+level: Ai.ModelThinkingLevel,+persist: Bool) -> IO(Action):
  do IO<Action>:
    result : Result<&2,&2,String,Unit> <- Session.setThinkingLevel(session,level,Session.ModelMutationOptions{persist})
    return selected(level,persist,result)
def thinkingSelected(session: Session.AgentSession,levels: List<&2,Ai.ModelThinkingLevel>,requested: String,found: Maybe<&2,Ai.ModelThinkingLevel>) -> IO(Action):
  match found:
    case Some{level}: choose(session,level,False{})
    case None{}: IO.pure(Action,CommandError{"Unknown thinking level \"" ++ requested ++ "\". Available levels: " ++ String.join(names(levels),", ") ++ "."})
def thinkingWith(session: Session.AgentSession,current: Session.AgentState(),+levels: List<&2,Ai.ModelThinkingLevel>,requested: Maybe<&2,String>) -> IO(Action):
  match requested:
    case None{}: IO.pure(Action,OpenThinkingPicker{})
    case Some{+value}: thinkingSelected(session,levels,value,findLevel(levels,String.to_lower(value)))
def thinking(+session: Session.AgentSession,requested: Maybe<&2,String>) -> IO(Action):
  do IO<Action>:
    +current : Session.AgentState() <- Session.state(session)
    thinkingWith(session,current,available(Session.stateModel(current)),requested)
def switched(model: Ai.Model<Ai.JsonValue>,persist: Bool,result: Result<&2,&2,String,Unit>) -> Action:
  match result:
    case Done{_}: ModelSelected{model,persist}
    case Fail{reason}: CommandError{reason}
def switchModel(session: Session.AgentSession,+model: Ai.Model<Ai.JsonValue>,+persist: Bool) -> IO(Action):
  do IO<Action>:
    result : Result<&2,&2,String,Unit> <- Session.setModel(session,model,Session.ModelMutationOptions{persist})
    return switched(model,persist,result)
def matchingModels(models: List<&2,Models.Model()>,+query: String,+reference: Bool) -> List<&2,Models.Model()>:
  match models:
    case Nil{}: Nil{}
    case +model <> +rest:
      +candidate = Bool.pick(String,reference,Models.reference(model),Models.modelId(model))
      Bool.pick(Unit -> List<&2,Models.Model()>,String.eq(String.to_lower(candidate),query),_ => model <> matchingModels(rest,query,reference),_ => matchingModels(rest,query,reference))(Unit{})
def uniqueModel(models: List<&2,Models.Model()>) -> Maybe<&2,Models.Model()>:
  match models:
    case model <> Nil{}: Some{model}
    case _: None{}
def matchId(canonical: Maybe<&2,Models.Model()>,models: List<&2,Models.Model()>,query: String) -> Maybe<&2,Models.Model()>:
  match canonical:
    case Some{model}: Some{model}
    case None{}: uniqueModel(matchingModels(models,query,False{}))
def exactModel(+models: List<&2,Models.Model()>,+query: String) -> Maybe<&2,Models.Model()>:
  +normalized = String.to_lower(query)
  matchId(uniqueModel(matchingModels(models,normalized,True{})),models,normalized)
def matchedModel(session: Session.AgentSession,query: String,found: Maybe<&2,Models.Model()>) -> IO(Action):
  match found:
    case Some{model}: switchModel(session,model,False{})
    case None{}: IO.pure(Action,OpenModelPicker{Some{query}})
def showModel(session: Session.AgentSession,models: List<&2,Models.Model()>,requested: Maybe<&2,String>) -> IO(Action):
  match requested:
    case None{}: IO.pure(Action,OpenModelPicker{None{}})
    case Some{+query}: matchedModel(session,query,exactModel(models,query))
def compacted(result: Result<&2,&2,String,Compaction.CompactionResult>) -> Action:
  match result:
    case Done{_}: Notice{"Session compacted"}
    case Fail{reason}: CommandError{reason}
def compact(session: Session.AgentSession,instructions: Maybe<&2,String>) -> IO(Action):
  do IO<Action>:
    result : Result<&2,&2,String,Compaction.CompactionResult> <- Session.compact(session,instructions)
    return compacted(result)
def currentName(session: Session.AgentSession) -> IO(Maybe<&2,String>):
  do IO<Maybe<&2,String>>:
    stored : Session.Session() <- Session.sessionOf(session)
    return Tree.getSessionName(Unit,Tools.ToolDetails,Schema.Value,Session.stateOf(stored))
def showName(current: Maybe<&2,String>) -> Action:
  match current:
    case Some{name}: Notice{"Session name: " ++ name}
    case None{}: CommandError{"Usage: /name <name>"}
def namedStored(+requested: String,value: Maybe<&2,String>) -> Action:
  match value:
    case Some{+actual}:
      Bool.pick(Action,String.eq(requested,actual),Notice{"Session name set: " ++ actual},Notice{"Session name was normalized from " ++ Json.quote(requested) ++ " to " ++ Json.quote(actual) ++ ". Session name set: " ++ actual})
    case None{}: Notice{"Session name cleared"}
def named(requested: String,stored: Maybe<&2,String>,result: Result<&2,&2,String,Unit>) -> Action:
  match result:
    case Fail{message}: CommandError{message}
    case Done{_}: namedStored(requested,stored)
def setName(+session: Session.AgentSession,+name: String) -> IO(Action):
  do IO<Action>:
    outcome : Result<&2,&2,String,Unit> <- Session.setSessionName(session,name)
    current : Maybe<&2,String> <- currentName(session)
    return named(name,current,outcome)
def nameCommand(session: Session.AgentSession,requested: Maybe<&2,String>) -> IO(Action):
  match requested:
    case None{}:
      do IO<Action>:
        current : Maybe<&2,String> <- currentName(session)
        return showName(current)
    case Some{name}: setName(session,name)
def execute(session: Session.AgentSession,models: List<&2,Models.Model()>,command: Command) -> IO(Action):
  match command:
    case Send{text}: IO.pure(Action,Prompt{text})
    case Stop{}: IO.pure(Action,Exit{})
    case ShowModel{requested}: showModel(session,models,requested)
    case SwitchModel{model,persist}: switchModel(session,model,persist)
    case SetThinking{requested}: thinking(session,requested)
    case SelectThinking{level,persist}: choose(session,level,persist)
    case ScopedModels{}: IO.pure(Action,OpenScopedModels{})
    case Compact{instructions}: compact(session,instructions)
    case NewSession{}: IO.pure(Action,CommandError{"Starting a new session is not available yet"})
    case Clone{}: IO.pure(Action,CommandError{"Cloning is not available"})
    case Name{requested}: nameCommand(session,requested)
    case Login{_}: IO.pure(Action,CommandError{"Login is available in interactive mode only"})
    case Logout{}: IO.pure(Action,CommandError{"Logout is available in interactive mode only"})
    case Export{path}: IO.pure(Action,ExportSession{path})
    case Import{path}: IO.pure(Action,ImportSession{path})
    case Resume{}: IO.pure(Action,ResumeSession{})
    case Tree{}: IO.pure(Action,OpenTree{})
    case Fork{}: IO.pure(Action,OpenFork{})
    case Copy{}: IO.pure(Action,CopyLastAssistant{})
    case Session{}: IO.pure(Action,ShowSessionInfo{})
    case Hotkeys{}: IO.pure(Action,ShowHotkeys{})
    case Settings{}: IO.pure(Action,OpenSettings{})
    case Trust{}: IO.pure(Action,OpenTrust{})
    case Changelog{}: IO.pure(Action,ShowChangelog{})
    case Reload{}: IO.pure(Action,ReloadResources{})
    case Bash{command,excluded}: IO.pure(Action,RunBash{command,excluded})
    case Unsupported{text}: IO.pure(Action,CommandError{text ++ " is not available in pi-bend yet"})
def parse(text: String) -> Command:
  +clean = Text.trim(text)
  classify(clean,String.split(clean,' '))
