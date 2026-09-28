import Base
import ../packages/agent/src/types.bend as T
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/providers/anthropic.models.bend as CatalogAnthropic
import ../packages/ai/src/utils/uuid.bend as Uuid
import ../packages/ai/src/utils/thinking-levels.bend as Levels
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/posix-path.bend as Path
import ../packages/runtime/src/record.bend as Rec
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/text.bend as Text
import ../packages/coding-agent/src/core/agent-session.bend as Session
import ../packages/coding-agent/src/core/extensions/types.bend as Ext
import ../packages/coding-agent/src/core/skills.bend as Skills
import ../packages/coding-agent/src/core/session-persistence.bend as Sessions
import ../packages/coding-agent/src/core/sdk.bend as Sdk
import ../packages/coding-agent/src/core/tools/index.bend as Tools

# upstream test/sdk-session-manager.test.ts ("createAgentSession session
# manager defaults"). Each test gets its own directory under the one the check
# script passes (upstream's beforeEach temp dir with project/ and agent/).
# The session record is a value, so upstream's identity check
# (`session.sessionManager` is the given manager) compares its id and
# persistence; the built-in bash tool runs through the agent's tool list.

def check(ok: Bool, +name: String, +detail: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), ok, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name ++ "\n  " ++ detail))(Unit{})

# The Bun lane has no process primitive (spawn answers ENOSYS), so a check
# that runs bash reports SKIP there once its other assertions hold; the check
# script accepts that only on Bun.
def noProcesses(+output: String) -> Bool: String.starts_with(output, "error: spawn: Function not implemented")

def checkRun(+ok: Bool, +output: String, +name: String, +detail: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), noProcesses(output), _ => Bool.pick(Unit -> IO(Unit), ok, _ => IO.print("SKIP " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name ++ "\n  " ++ detail))(Unit{}), _ => check(ok, name, detail))(Unit{})

def Created() -> Type: Result<&2, &1, String, Sdk.CreateAgentSessionResult>

def model() -> Ai.Model<Ai.JsonValue>: CatalogAnthropic.model_claude_sonnet_4_5()

def mkdirs(+path: String) -> IO(Unit):
  do IO<Unit>:
    made : Result<&2, &2, FS.Error, Unit> <- FS.mkdir(path)
    return Unit{}

def required(created: Created(), +name: String) -> IO(Sdk.CreateAgentSessionResult):
  match created:
    case Done{result}: IO.pure(Sdk.CreateAgentSessionResult, result)
    case Fail{message}: IO.die(Sdk.CreateAgentSessionResult, 1, "FAIL " ++ name ++ "\n  createAgentSession: " ++ message)

def requiredSession(result: Sessions.Outcome(Session.Session())) -> IO(Session.Session()):
  match result:
    case Done{session}: IO.pure(Session.Session(), session)
    case Fail{error}: IO.die(Session.Session(), 1, Sessions.message(error))

def memorySession(+cwd: String) -> IO(Session.Session()):
  do IO<Session.Session()>:
    ids : Uuid.Generator <- Uuid.generator()
    created : Sessions.Outcome(Session.Session()) <- Session.memorySession(ids, cwd, Sessions.noOptions())
    requiredSession(created)

def options(cwd: Maybe<&2, String>, +agentDir: String, thinking: Maybe<&2, Ai.ModelThinkingLevel>, session: Maybe<&2, Session.Session()>) -> Sdk.CreateAgentSessionOptions:
  Sdk.CreateAgentSessionOptions{cwd, Some{agentDir}, None{}, Some{model()}, thinking, Nil{}, None{}, None{}, None{}, None{}, session, None{}, Nil{}}

def recordOf(+session: Session.AgentSession) -> IO(Session.Session()): Session.sessionOf(session)

def fileOr(file: Maybe<&2, String>) -> String: Maybe.default(&2, String, file, "undefined")

# upstream: `--${cwd without its leading slash, / \ : as -}--`.
def safeChar(char: Char) -> Char:
  match char:
    case '/': '-'
    case '\\': '-'
    case ':': '-'
    case other: other

def safeChars(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{char, rest}: SCon{safeChar(char), safeChars(rest)}

def safePath(cwd: String) -> String:
  match cwd:
    case SCon{'/', rest}: "--" ++ safeChars(rest) ++ "--"
    case other: "--" ++ safeChars(other) ++ "--"

# Tools
# -----

def toolName(tool: Tools.Tool()) -> String:
  match tool:
    case T.AgentTool{name, _, _, _, _, _, _, _, _}: name

def findTool(tools: List<&2, Tools.Tool()>, +name: String) -> Maybe<&2, Tools.Tool()>:
  match tools:
    case Nil{}: None{}
    case +tool <> rest: Bool.pick(Maybe<&2, Tools.Tool()>, String.eq(toolName(tool), name), Some{tool}, findTool(rest, name))

def stateTools(state: Session.AgentState()) -> List<&2, Tools.Tool()>:
  match state:
    case T.AgentState{_, _, tools, _, _, _, _, _}: tools

def texts(content: List<&2, Ai.TextImageContent>) -> String:
  match content:
    case Nil{}: ""
    case Ai.TextImageText{Ai.TextContent{text, _}} <> rest: text ++ texts(rest)
    case _ <> rest: texts(rest)

def outputOf(result: Tools.Output()) -> String:
  match result:
    case Done{T.AgentToolResult{content, _, _, _}}: texts(content)
    case Fail{error}: "error: " ++ Tools.errorMessage(error)

def ranBash(tool: Maybe<&2, Tools.Tool()>, +command: String) -> IO(String):
  match tool:
    case None{}: IO.pure(String, "no bash tool")
    case Some{T.AgentTool{_, _, _, _, _, _, execute, _, _}}:
      do IO<String>:
        result : Tools.Output() <- C.call(Tools.Input(), Tools.Output(), execute, T.ToolExecutionInput{"test", V.ObjectValue{Rec.Record{[Rec.Property{"command", V.Text{command}}]}}, None{}, None{}})
        return outputOf(result)

def runBash(+session: Session.AgentSession, +command: String) -> IO(String):
  do IO<String>:
    state : Session.AgentState() <- Session.state(session)
    ranBash(findTool(stateTools(state), "bash"), command)

def realOr(+path: String) -> IO(String):
  do IO<String>:
    real : Result<&2, &2, FS.Error, String> <- FS.realpath(path)
    return Result.default(&2, &2, FS.Error, String, real, path)

# Tests
# -----

def SessionPair() -> Type: Sdk.CreateAgentSessionResult & Session.AgentSession

# 1. The default session is persisted under agentDir.
def defaultPathChecked(+name: String, +cwd: String, +agentDir: String, pair: SessionPair()) -> IO(Unit):
  match pair:
    case Tuple{result, session}:
      do IO<Unit>:
        +record : Session.Session() <- Session.sessionOf(session)
        Sdk.dispose(result)
        +expected : String = Path.join(Path.join(agentDir, "sessions"), safePath(cwd))
        +dir : String = Sessions.getSessionDir(Unit, Tools.ToolDetails, V.Value, record)
        +file : String = fileOr(Sessions.getSessionFile(Unit, Tools.ToolDetails, V.Value, record))
        check(String.eq(dir, expected) && String.starts_with(file, expected ++ "/"), name, dir ++ " / " ++ file ++ " expected " ++ expected)

def usesAgentDirForTheDefaultPersistedSessionPath(+base: String) -> IO(Unit):
  +name = {"uses agentDir for the default persisted session path" : String}
  +cwd = Path.join(base, "project")
  +agentDir = Path.join(base, "agent")
  do IO<Unit>:
    mkdirs(cwd)
    mkdirs(agentDir)
    created : Created() <- Sdk.createAgentSession(options(Some{cwd}, agentDir, None{}, None{}))
    result : Sdk.CreateAgentSessionResult <- required(created, name)
    defaultPathChecked(name, cwd, agentDir, Sdk.sessionOf(result))

# 2. An explicit in-memory session manager is used as given.
def overrideChecked(+name: String, +id: String, pair: SessionPair()) -> IO(Unit):
  match pair:
    case Tuple{result, session}:
      do IO<Unit>:
        +record : Session.Session() <- Session.sessionOf(session)
        Sdk.dispose(result)
        +actual : String = Sessions.getSessionId(Unit, Tools.ToolDetails, V.Value, record)
        +persisted : Bool = Sessions.isPersisted(Unit, Tools.ToolDetails, V.Value, record)
        check(String.eq(actual, id) && Bool.not(persisted), name, actual ++ " persisted " ++ Bool.show(persisted))

def keepsAnExplicitSessionManagerOverride(+base: String) -> IO(Unit):
  +name = {"keeps an explicit sessionManager override" : String}
  +cwd = Path.join(base, "project")
  +agentDir = Path.join(base, "agent")
  do IO<Unit>:
    mkdirs(cwd)
    mkdirs(agentDir)
    +manager : Session.Session() <- memorySession(cwd)
    created : Created() <- Sdk.createAgentSession(options(Some{cwd}, agentDir, None{}, Some{manager}))
    result : Sdk.CreateAgentSessionResult <- required(created, name)
    overrideChecked(name, Sessions.getSessionId(Unit, Tools.ToolDetails, V.Value, manager), Sdk.sessionOf(result))

# 3. Without cwd, the session manager's cwd is the session's: the system
# prompt names it and bash runs in it.
def derivedChecked(+name: String, +id: String, +sessionCwd: String, pair: SessionPair()) -> IO(Unit):
  match pair:
    case Tuple{result, +session}:
      do IO<Unit>:
        +record : Session.Session() <- Session.sessionOf(session)
        +prompt : String <- Session.systemPrompt(session)
        +output : String <- runBash(session, "pwd")
        +actual : String <- realOr(Text.trim(output))
        +expected : String <- realOr(sessionCwd)
        Sdk.dispose(result)
        +same : Bool = String.eq(Sessions.getSessionId(Unit, Tools.ToolDetails, V.Value, record), id)
        +before : Bool = same && String.contains(prompt, "<cwd>\n" ++ sessionCwd ++ "\n</cwd>")
        checkRun(Bool.pick(Bool, noProcesses(output), before, before && String.eq(actual, expected)), output, name, "same session " ++ Bool.show(same) ++ ", pwd " ++ actual ++ " expected " ++ expected)

def derivesCwdFromAnExplicitSessionManager(+base: String) -> IO(Unit):
  +name = {"derives cwd from an explicit sessionManager when cwd is omitted" : String}
  +agentDir = Path.join(base, "agent")
  +sessionCwd = Path.join(base, "session-project")
  do IO<Unit>:
    mkdirs(agentDir)
    mkdirs(sessionCwd)
    +manager : Session.Session() <- memorySession(sessionCwd)
    created : Created() <- Sdk.createAgentSession(options(None{}, agentDir, None{}, Some{manager}))
    result : Sdk.CreateAgentSessionResult <- required(created, name)
    derivedChecked(name, Sessions.getSessionId(Unit, Tools.ToolDetails, V.Value, manager), sessionCwd, Sdk.sessionOf(result))

# 4. The bash tool sees the session's PI_* variables.
def levelName(level: Ai.ModelThinkingLevel) -> String: Levels.name(level)

def exposedChecked(+name: String, pair: SessionPair()) -> IO(Unit):
  match pair:
    case Tuple{result, +session}:
      do IO<Unit>:
        +record : Session.Session() <- Session.sessionOf(session)
        +prompt : String <- Session.systemPrompt(session)
        +state : Session.AgentState() <- Session.state(session)
        +output : String <- runBash(session, "printf '%s\\n' \"$PI_SESSION_ID\" \"$PI_SESSION_FILE\" \"$PI_PROVIDER\" \"$PI_MODEL\" \"$PI_REASONING_LEVEL\"")
        Sdk.dispose(result)
        +file : Maybe<&2, String> = Sessions.getSessionFile(Unit, Tools.ToolDetails, V.Value, record)
        +expected : String = String.join([Sessions.getSessionId(Unit, Tools.ToolDetails, V.Value, record), fileOr(file), Ai.modelProvider(model()), Ai.modelId(model()), levelName(Session.stateThinking(state))], "\n")
        +before : Bool = Maybe.is_some(&2, String, file) && String.contains(prompt, "You can inspect PI_* environment variables for current model and session details.")
        checkRun(Bool.pick(Bool, noProcesses(output), before, before && String.eq(Text.trim(output), expected)), output, name, "output " ++ Text.trim(output) ++ "\n  expected " ++ expected)

def exposesCurrentSessionStateToTheBuiltInBashTool(+base: String) -> IO(Unit):
  +name = {"exposes current session state to the built-in bash tool" : String}
  +cwd = Path.join(base, "project")
  +agentDir = Path.join(base, "agent")
  do IO<Unit>:
    mkdirs(cwd)
    mkdirs(agentDir)
    created : Created() <- Sdk.createAgentSession(options(Some{cwd}, agentDir, Some{Ai.Thinking{Ai.High{}}}, None{}))
    result : Sdk.CreateAgentSessionResult <- required(created, name)
    exposedChecked(name, Sdk.sessionOf(result))

def sdkTool(_: Unit,_: Ext.ToolCallInput) -> IO(Tools.Output()):
  IO.pure(Tools.Output(),Done{T.AgentToolResult{Ai.TextImageText{Ai.TextContent{"sdk-ok",None{}}} <> Nil{},None{},None{},None{}}})
def definition(name: String,execute: Ext.ToolExecute()) -> Ext.ToolDefinition:
  Ext.ToolDefinition{name,"SDK Tool","Run the SDK tool",Some{"Run the SDK tool"},["Prefer the SDK tool when asked"],V.ObjectValue{Rec.Record{Nil{}}},None{},execute,Ext.DefaultShell{},None{},None{}}
def namesContain(names: List<&2,String>,+name: String) -> Bool:
  match names:
    case Nil{}: False{}
    case found <> rest: String.eq(found,name) || namesContain(rest,name)
def infoSource(infos: List<&2,Session.ToolInfo()>,+name: String,+path: String,+source: String,+guideline: Maybe<&2,String>) -> Bool:
  match infos:
    case Nil{}: False{}
    case Ext.ToolInfo{found,_,_,rules,Skills.SourceInfo{location,kind,Skills.Temporary{},Skills.TopLevel{},None{}}} <> rest:
      +matches = String.eq(found,name) && String.eq(location,path) && String.eq(kind,source) && Maybe.default(&2,Bool,Maybe.map(&2,String,Bool,rule => namesContain(rules,rule),guideline),True{})
      matches || infoSource(rest,name,path,source,guideline)
    case _ <> rest: infoSource(rest,name,path,source,guideline)
def customChecked(+name: String,pair: SessionPair()) -> IO(Unit):
  match pair:
    case Tuple{result,+session}:
      do IO<Unit>:
        +active : List<&2,String> <- Session.getActiveToolNames(session)
        +all : List<&2,Session.ToolInfo()> <- Session.getAllTools(session)
        +state : Session.AgentState() <- Session.state(session)
        +prompt : String <- Session.systemPrompt(session)
        sdkOutput : String <- ranBash(findTool(stateTools(state),"sdk_tool"),"unused")
        readOutput : String <- ranBash(findTool(stateTools(state),"read"),"unused")
        Sdk.dispose(result)
        check(namesContain(active,"sdk_tool") && namesContain(active,"read") && infoSource(all,"sdk_tool","<sdk:sdk_tool>","sdk",Some{"Prefer the SDK tool when asked"}) && infoSource(all,"read","<sdk:read>","sdk",None{}) && infoSource(all,"bash","<builtin:bash>","builtin",None{}) && String.eq(sdkOutput,"sdk-ok") && String.eq(readOutput,"sdk-ok") && String.contains(prompt,"Prefer the SDK tool when asked"),name,"SDK tool not active, executable, overriding read, or reporting its source and prompt")
def acceptsSdkCustomTools(+base: String) -> IO(Unit):
  +name = {"registers SDK custom tools through the session registry" : String}
  +cwd = Path.join(base,"project")
  +agentDir = Path.join(base,"agent")
  do IO<Unit>:
    mkdirs(cwd)
    mkdirs(agentDir)
    +execute : Ext.ToolExecute() <- C.create(~Unit,~Ext.ToolCallInput,~Tools.Output(),~sdkTool,Unit{})
    created : Created() <- Sdk.createAgentSession(Sdk.CreateAgentSessionOptions{Some{cwd},Some{agentDir},None{},Some{model()},None{},Nil{},None{},None{},None{},None{},None{},None{},[definition("sdk_tool",execute),definition("read",execute)]})
    result : Sdk.CreateAgentSessionResult <- required(created,name)
    customChecked(name,Sdk.sessionOf(result))
    C.dispose(Ext.ToolCallInput,Tools.Output(),execute)

def runIn(+base: String) -> IO(Unit):
  do IO<Unit>:
    usesAgentDirForTheDefaultPersistedSessionPath(Path.join(base, "1"))
    keepsAnExplicitSessionManagerOverride(Path.join(base, "2"))
    derivesCwdFromAnExplicitSessionManager(Path.join(base, "3"))
    exposesCurrentSessionStateToTheBuiltInBashTool(Path.join(base, "4"))
    acceptsSdkCustomTools(Path.join(base,"5"))

def run(args: List<String>) -> IO(Unit):
  match args:
    case base <> Nil{}: runIn(base)
    case _: IO.die(Unit, 1, "usage: sdk-session-manager <temp-dir>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
