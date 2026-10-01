import Base
import ../../ai/src/types.bend as Ai
import ../../agent/src/types.bend as Agent
import ../../runtime/src/f64.bend as F
import ../../ai/src/providers/anthropic.models.bend as Catalog
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as R
import ../../runtime/src/filesystem.bend as FS
import ../../runtime/src/schema-value.bend as V
import ../src/utils/paths.bend as Paths
import ../src/core/agent-runtime.bend as Runtime
import ../src/core/agent-session.bend as Session
import ../src/core/session-manager.bend as Manager
import ../src/core/session-persistence.bend as Persistence
import ../src/core/sdk.bend as Sdk
import ../src/core/settings-manager.bend as Settings
import ../src/core/resource-loader.bend as Resources
import ../src/core/slash-commands.bend as Slash
import ../src/core/skills.bend as Skills
import ../src/core/tools/index.bend as Tools
import ../src/core/extensions/types.bend as Ext
import ../src/core/extensions/loader.bend as Loader

# regression #3686's named contracts, plus the bound metadata/command APIs.
# No model request runs: state, handlers and resource discovery are the real SDK.
type Env is Data:
  Env{api: R.Ref<Maybe<&2,Ext.ExtensionAPI>>, events: R.Ref<List<&2,Maybe<&2,String>>>, completed: Chan(Unit)}
def check(ok: Bool,+name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),ok,_ => IO.print("ok " ++ name),_ => IO.die(Unit,1,"FAIL " ++ name))(Unit{})
def good(result: Result<&2,&2,String,Unit>) -> Bool: Result.is_done(&2,&2,String,Unit,result)
def nameText(value: Maybe<&2,String>) -> String: Maybe.default(&2,String,value,"<unset>")
def named(value: Result<&2,&2,String,Maybe<&2,String>>) -> String:
  match value:
    case Done{name}: nameText(name)
    case Fail{_}: "<error>"
def names(values: List<&2,Maybe<&2,String>>) -> List<&2,String>:
  match values:
    case Nil{}: Nil{}
    case name <> rest: nameText(name) <> names(rest)
def equal(left: List<&2,String>,right: List<&2,String>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case a <> as b <> bs: String.eq(a,b) && equal(as,bs)
    case _ _: False{}
def append(+items: R.Ref<List<&2,Maybe<&2,String>>>,name: Maybe<&2,String>) -> IO(Unit):
  R.modify(List<&2,Maybe<&2,String>>,Unit,items,prior => (List.append(&2,Maybe<&2,String>,prior,[name]),Unit{}))
def publicName(items: R.Ref<List<&2,Maybe<&2,String>>>,event: Session.AgentSessionEvent) -> IO(Unit):
  match event:
    case Session.SessionInfoChanged{name}: append(items,name)
    case _: IO.pure(Unit,Unit{})
def extensionName(env: Env,event: Ext.HandlerCall<Ext.SessionInfoChangedEvent>) -> IO(Result<&2,&2,String,Maybe<&2,Unit>>):
  match env event:
    case Env{_,items,completed} Ext.HandlerCall{Ext.SessionInfoChangedEvent{name},_}:
      do IO<Result<&2,&2,String,Maybe<&2,Unit>>>:
        append(items,name)
        sent : Bool <- Chan.send(Unit,completed,Unit{})
        return Done{None{}}
def command(_: Unit,_: Ext.CommandCall) -> IO(Result<&2,&2,String,Unit>): IO.pure(Result<&2,&2,String,Unit>,Done{Unit{}})
def firstWith(+env: Env,+api: Ext.ExtensionAPI) -> IO(Result<&2,&2,String,Unit>):
  match env:
    case Env{slot,_,_}:
      do IO<Result<&2,&2,String,Unit>>:
        name : Result<&2,&2,String,Maybe<&2,String>> <- Loader.getSessionName(api)
        commands : Result<&2,&2,String,List<&2,Slash.SlashCommandInfo>> <- Loader.getCommands(api)
        rename : Result<&2,&2,String,Unit> <- Loader.setSessionName(api,"during loading")
        label : Result<&2,&2,String,Unit> <- Loader.setLabel(api,"unbound",Some{"label"})
        check(Result.is_fail(&2,&2,String,Maybe<&2,String>,name) && Result.is_fail(&2,&2,String,List<&2,Slash.SlashCommandInfo>,commands) && Result.is_fail(&2,&2,String,Unit,rename) && Result.is_fail(&2,&2,String,Unit,label),"metadata and command actions reject calls during loading")
        R.write(Maybe<&2,Ext.ExtensionAPI>,slot,Some{api})
        handler : Ext.ExtensionHandler(Ext.SessionInfoChangedEvent,Unit) <- C.create(~Env,~Ext.HandlerCall<Ext.SessionInfoChangedEvent>,~Result<&2,&2,String,Maybe<&2,Unit>>,~extensionName,env)
        observed : Result<&2,&2,String,Loader.Unsubscribe> <- Loader.on(api,Ext.OnSessionInfoChanged{handler})
        callback : Ext.CommandHandler() <- C.create(~Unit,~Ext.CommandCall,~Result<&2,&2,String,Unit>,~command,Unit{})
        Loader.registerCommand(api,"dupe",Ext.CommandOptions{Some{"First command"},None{},callback})
def first(env: Env,api: Ext.ExtensionAPI) -> IO(Result<&2,&2,String,Unit>): firstWith(env,api)
def second(_: Unit,api: Ext.ExtensionAPI) -> IO(Result<&2,&2,String,Unit>):
  do IO<Result<&2,&2,String,Unit>>:
    callback : Ext.CommandHandler() <- C.create(~Unit,~Ext.CommandCall,~Result<&2,&2,String,Unit>,~command,Unit{})
    Loader.registerCommand(api,"dupe",Ext.CommandOptions{None{},None{},callback})
def requiredApi(found: Maybe<&2,Ext.ExtensionAPI>) -> IO(Ext.ExtensionAPI):
  match found:
    case Some{api}: IO.pure(Ext.ExtensionAPI,api)
    case None{}: IO.die(Ext.ExtensionAPI,1,"missing extension API")
def recorded(session: Session.AgentSession) -> IO(Manager.SessionManager<V.Value,Tools.ToolDetails,V.Value>):
  do IO<Manager.SessionManager<V.Value,Tools.ToolDetails,V.Value>>:
    stored : Session.Session() <- Session.sessionOf(session)
    return Persistence.stateOf(V.Value,Tools.ToolDetails,V.Value,stored)
def next(completed: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    item : Maybe<&1,Unit> <- Chan.recv(Unit,completed)
    return Unit{}
def commandNames(items: List<&2,Slash.SlashCommandInfo>) -> List<&2,String>:
  match items:
    case Nil{}: Nil{}
    case Slash.SlashCommandInfo{name,_,_,_} <> rest: name <> commandNames(rest)
def sourceMatches(info: Skills.SourceInfo,path: String) -> Bool:
  match info: case Skills.SourceInfo{actual,_,_,_,_}: String.eq(actual,path)
def commandMetadata(commands: List<&2,Slash.SlashCommandInfo>) -> Bool:
  match commands:
    case Slash.SlashCommandInfo{_,Some{"First command"},Slash.Extension{},first} <> Slash.SlashCommandInfo{_,None{},Slash.Extension{},second} <> Slash.SlashCommandInfo{_,Some{"Review work"},Slash.Prompt{},_} <> Slash.SlashCommandInfo{_,Some{"Demo skill"},Slash.Skill{},_} <> Nil{}:
      sourceMatches(first,"<inline:metadata-first>") && sourceMatches(second,"<inline:metadata-second>")
    case _: False{}
def listed(result: Result<&2,&2,String,List<&2,Slash.SlashCommandInfo>>) -> List<&2,Slash.SlashCommandInfo>:
  match result:
    case Done{commands}: commands
    case Fail{_}: Nil{}
def checks(+session: Session.AgentSession,+api: Ext.ExtensionAPI,+public: R.Ref<List<&2,Maybe<&2,String>>>,+events: R.Ref<List<&2,Maybe<&2,String>>>,+completed: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    start : Result<&2,&2,String,Maybe<&2,String>> <- Loader.getSessionName(api)
    check(String.eq(named(start),"<unset>"),"extension getter reports an unnamed session")
    changed : Result<&2,&2,String,Unit> <- Session.setSessionName(session,"hello world")
    read : Result<&2,&2,String,Maybe<&2,String>> <- Loader.getSessionName(api)
    seen : List<&2,Maybe<&2,String>> <- R.read(List<&2,Maybe<&2,String>>,public)
    check(good(changed) && String.eq(named(read),"hello world") && equal(names(seen),["hello world"]),"emits session_info_changed when AgentSession.setSessionName is called")
    next(completed)
    R.write(List<&2,Maybe<&2,String>>,public,Nil{})
    renamed : Result<&2,&2,String,Unit> <- Loader.setSessionName(api,"from extension")
    readExtension : Result<&2,&2,String,Maybe<&2,String>> <- Loader.getSessionName(api)
    seenExtension : List<&2,Maybe<&2,String>> <- R.read(List<&2,Maybe<&2,String>>,public)
    check(good(renamed) && String.eq(named(readExtension),"from extension") && equal(names(seenExtension),["from extension"]),"emits session_info_changed when an extension calls pi.setSessionName")
    next(completed)
    R.write(List<&2,Maybe<&2,String>>,events,Nil{})
    a : Result<&2,&2,String,Unit> <- Loader.setSessionName(api,"first")
    b : Result<&2,&2,String,Unit> <- Session.setSessionName(session,"second")
    next(completed)
    next(completed)
    ordered : List<&2,Maybe<&2,String>> <- R.read(List<&2,Maybe<&2,String>>,events)
    check(good(a) && good(b) && equal(names(ordered),["first","second"]),"emits session_info_changed to extensions")
    normalized : Result<&2,&2,String,Unit> <- Loader.setSessionName(api,"  line\nname  ")
    next(completed)
    normalizedName : Result<&2,&2,String,Maybe<&2,String>> <- Loader.getSessionName(api)
    cleared : Result<&2,&2,String,Unit> <- Loader.setSessionName(api," \n ")
    next(completed)
    clearedName : Result<&2,&2,String,Maybe<&2,String>> <- Loader.getSessionName(api)
    check(good(normalized) && good(cleared) && String.eq(named(normalizedName),"line name") && String.eq(named(clearedName),"<unset>"),"extension names normalize newlines and clear whitespace-only names")
    +before : Manager.SessionManager<V.Value,Tools.ToolDetails,V.Value> <- recorded(session)
    +id : String = Maybe.default(&2,String,Manager.getLeafId(V.Value,Tools.ToolDetails,V.Value,before),"missing leaf")
    labeled : Result<&2,&2,String,Unit> <- Loader.setLabel(api,id,Some{"favorite"})
    labeledState : Manager.SessionManager<V.Value,Tools.ToolDetails,V.Value> <- recorded(session)
    removed : Result<&2,&2,String,Unit> <- Loader.setLabel(api,id,None{})
    +removedState : Manager.SessionManager<V.Value,Tools.ToolDetails,V.Value> <- recorded(session)
    check(good(labeled) && good(removed) && String.eq(nameText(Manager.getLabel(V.Value,Tools.ToolDetails,V.Value,labeledState,id)),"favorite") && Maybe.is_none(&2,String,Manager.getLabel(V.Value,Tools.ToolDetails,V.Value,removedState,id)),"extension labels update and clear the session tree")
    invalid : Result<&2,&2,String,Unit> <- Loader.setLabel(api,"missing-entry",Some{"wrong"})
    afterInvalid : Manager.SessionManager<V.Value,Tools.ToolDetails,V.Value> <- recorded(session)
    check(Result.is_fail(&2,&2,String,Unit,invalid) && Nat.is_eq(List.length(&2,Manager.SessionEntry<V.Value,Tools.ToolDetails,V.Value>,Manager.getEntries(V.Value,Tools.ToolDetails,V.Value,removedState)),List.length(&2,Manager.SessionEntry<V.Value,Tools.ToolDetails,V.Value>,Manager.getEntries(V.Value,Tools.ToolDetails,V.Value,afterInvalid))),"extension labels reject nonexistent entries without changing history")
    discovered : Result<&2,&2,String,List<&2,Slash.SlashCommandInfo>> <- Loader.getCommands(api)
    +commands : List<&2,Slash.SlashCommandInfo> = listed(discovered)
    check(equal(commandNames(commands),["dupe:1","dupe:2","review","skill:demo"]) && commandMetadata(commands),"extension command discovery preserves resolved names, order, descriptions and source metadata")
def settingsOf(pair: Settings.FileSettingsStorage & Settings.SettingsManager) -> Settings.SettingsManager:
  match pair: case (_,settings): settings
def seed(+session: Session.AgentSession) -> IO(Unit):
  do IO<Unit>:
    +zero : F64 = F.fromU32(0)
    usage : Ai.Usage = Ai.Usage{zero,zero,zero,zero,None{},None{},zero,Ai.UsageCost{zero,zero,zero,zero,zero}}
    message : Ai.AssistantMessage<V.Value,V.Value> = Ai.AssistantMessage{[Ai.AssistantText{Ai.TextContent{"fixture output",None{}}}],"anthropic-messages","anthropic","claude-sonnet-4-5",None{},None{},None{},None{},usage,Ai.Stop{},None{},None{},None{},None{},zero}
    appended : Result<&2,&2,String,Unit> <- Session.appendSessionMessage(session,Agent.LlmMessage{Ai.Assistant{message}})
    stored : Session.Session() <- Session.sessionOf(session)
    check(good(appended) && Persistence.isFlushed(V.Value,Tools.ToolDetails,V.Value,stored),"assistant output flushes the metadata journal")

def checkedSession(pair: Sdk.CreateAgentSessionResult & Session.AgentSession,env: Env,loader: Resources.DefaultResourceLoader) -> IO(Unit):
  match pair env:
    case Tuple{owner,+session} Env{+slot,+events,+completed}:
      do IO<Unit>:
        +api : Ext.ExtensionAPI <- IO.bind(Maybe<&2,Ext.ExtensionAPI>,Ext.ExtensionAPI,R.read(Maybe<&2,Ext.ExtensionAPI>,slot),requiredApi)
        seed(session)
        +public : R.Ref<List<&2,Maybe<&2,String>>> <- R.new(List<&2,Maybe<&2,String>>,Nil{})
        +listener : Session.Listener() <- C.create(~R.Ref<List<&2,Maybe<&2,String>>>,~Session.AgentSessionEvent,~Unit,~publicName,public)
        Session.subscribe(session,listener)
        checks(session,api,public,events,completed)
        Session.unsubscribe(session,listener)
        C.dispose(Session.AgentSessionEvent,Unit,listener)
        Sdk.dispose(owner)
        name : Result<&2,&2,String,Maybe<&2,String>> <- Loader.getSessionName(api)
        commands : Result<&2,&2,String,List<&2,Slash.SlashCommandInfo>> <- Loader.getCommands(api)
        rename : Result<&2,&2,String,Unit> <- Loader.setSessionName(api,"after disposal")
        label : Result<&2,&2,String,Unit> <- Loader.setLabel(api,"entry",None{})
        check(Result.is_fail(&2,&2,String,Maybe<&2,String>,name) && Result.is_fail(&2,&2,String,List<&2,Slash.SlashCommandInfo>,commands) && Result.is_fail(&2,&2,String,Unit,rename) && Result.is_fail(&2,&2,String,Unit,label),"retired metadata and command actions reject after SDK disposal")
        Resources.disposeDefaultResourceLoader(loader)
        previous : List<&2,Maybe<&2,String>> <- R.dispose(List<&2,Maybe<&2,String>>,public)
        return Unit{}
def checked(created: Sdk.Outcome(),env: Env,loader: Resources.DefaultResourceLoader) -> IO(Unit):
  match created:
    case Fail{message}: IO.die(Unit,1,message)
    case Done{owner}: checkedSession(Sdk.sessionOf(owner),env,loader)

def file(path: String,text: String) -> IO(Unit):
  do IO<Unit>:
    written : Result<&2,&2,FS.Error,Unit> <- FS.writeFile(path,text)
    return Unit{}
def mkdir(path: String) -> IO(Unit):
  do IO<Unit>:
    made : Result<&2,&2,FS.Error,Unit> <- FS.mkdir(path)
    return Unit{}
def run(+directory: String) -> IO(Unit):
  do IO<Unit>:
    +cwd : String = directory ++ "/project"
    +agentDir : String = directory ++ "/agent"
    mkdir(cwd)
    mkdir(agentDir ++ "/prompts")
    mkdir(agentDir ++ "/skills/demo")
    file(agentDir ++ "/prompts/review.md","---\ndescription: Review work\n---\nReview the code.")
    file(agentDir ++ "/skills/demo/SKILL.md","---\nname: demo\ndescription: Demo skill\n---\nDemo instructions.")
    +slot : R.Ref<Maybe<&2,Ext.ExtensionAPI>> <- R.new(Maybe<&2,Ext.ExtensionAPI>,None{})
    +events : R.Ref<List<&2,Maybe<&2,String>>> <- R.new(List<&2,Maybe<&2,String>>,Nil{})
    +completed : Chan(Unit) <- Chan.new(Unit,8)
    +env : Env = Env{slot,events,completed}
    factory : Ext.ExtensionFactory() <- C.create(~Env,~Ext.ExtensionAPI,~Result<&2,&2,String,Unit>,~first,env)
    other : Ext.ExtensionFactory() <- C.create(~Unit,~Ext.ExtensionAPI,~Result<&2,&2,String,Unit>,~second,Unit{})
    pair : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(cwd,agentDir,Settings.options())
    +settings : Settings.SettingsManager = settingsOf(pair)
    +loader : Resources.DefaultResourceLoader <- Resources.createDefaultResourceLoader(Paths.Environment{cwd,directory,Runtime.urlContext()},Resources.defaultResourceLoaderOptions(cwd,agentDir,settings),[Ext.InlineExtension{"metadata-first",factory,False{}},Ext.InlineExtension{"metadata-second",other,False{}}])
    Resources.reload(Resources.loaderOf(loader),Resources.ResourceLoaderReloadOptions{None{}})
    created : Sdk.Outcome() <- Sdk.createAgentSession(Sdk.CreateAgentSessionOptions{Some{cwd},Some{agentDir},None{},Some{Catalog.model_claude_sonnet_4_5()},Some{Ai.Off{}},Nil{},None{},None{},None{},Some{Resources.loaderOf(loader)},None{},Some{settings},Nil{},None{}})
    checked(created,env,loader)
    old : Maybe<&2,Ext.ExtensionAPI> <- R.dispose(Maybe<&2,Ext.ExtensionAPI>,slot)
    previous : List<&2,Maybe<&2,String>> <- R.dispose(List<&2,Maybe<&2,String>>,events)
    Chan.close(Unit,completed)
    return Unit{}
def arguments(args: List<String>) -> IO(Unit):
  match args:
    case directory <> Nil{}: run(directory)
    case _: IO.die(Unit,1,"expected isolated directory")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
