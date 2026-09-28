import Base
import ../../../../ai/src/utils/message-json.bend as Json
import ../../../../ai/src/utils/uuid.bend as Uuid
import ../../../../runtime/src/schema-value.bend as V
import ../../../../runtime/src/record.bend as R
import ../../../../runtime/src/abort.bend as Abort
import ../../../../runtime/src/child-process.bend as Child
import ../../../../runtime/src/utf8.bend as Utf8
import ../../../../runtime/src/text.bend as Text
import ../../../../runtime/src/filesystem.bend as FS
import ../../config.bend as Config
import ../../core/agent-session.bend as Session
import ../../core/session-export.bend as Export
import ../../core/session-json.bend as SessionJson
import ../../core/session-persistence.bend as Persistence
import ../../core/extensions/types.bend as Extensions
import ../../core/tools/index.bend as Tools

# Export-only presentation data for the pi session viewer. The original
# conversation entries and the live session are not modified.
def tool(value: Extensions.ToolInfo) -> V.Value:
  match value:
    case Extensions.ToolInfo{name,description,parameters}:
      Json.object([R.Property{"name",Json.text(name)},R.Property{"description",Json.text(description)},R.Property{"parameters",parameters}])

def tools(values: List<&2,Extensions.ToolInfo>) -> List<&2,V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: tool(value) <> tools(rest)

def createShareTrailingEntries(parent: Maybe<&2,String>,timestamp: String,id: String,systemPrompt: String,activeTools: List<&2,Extensions.ToolInfo>) -> List<&2,V.Value>:
  +data = Json.object([R.Property{"systemPrompt",Json.text(systemPrompt)},R.Property{"tools",V.ArrayValue{tools(activeTools)}}])
  [Json.object([R.Property{"type",Json.text("custom")},R.Property{"customType",Json.text("pi.share")},R.Property{"id",Json.text(String.take(id,8n))},R.Property{"parentId",SessionJson.nullableText(parent)},R.Property{"timestamp",Json.text(timestamp)},R.Property{"data",data}])]

def exported(+session: Session.AgentSession,cwd: String,path: String,timestamp: String,id: String) -> IO(Result<&2,&2,String,String>):
  do IO<Result<&2,&2,String,String>>:
    state : Session.AgentState() <- Session.state(session)
    prompt : String <- Session.systemPrompt(session)
    stored : Session.Session() <- Session.sessionOf(session)
    Export.exportSessionToJsonl(~Unit,~Tools.ToolDetails,~V.Value,~Session.unitValue,~Tools.detailsValue,~Session.rawValue,Session.stateOf(stored),cwd,path,timestamp,parent => time => createShareTrailingEntries(parent,time,id,prompt,Session.toolInfos(Session.stateTools(state))))

def withId(session: Session.AgentSession,cwd: String,path: String,time: Persistence.Outcome(String),id: Result<&2,&2,Uuid.Error,String>) -> IO(Result<&2,&2,String,String>):
  match time id:
    case Fail{error} _: IO.pure(Result<&2,&2,String,String>,Fail{Persistence.message(error)})
    case _ Fail{error}: IO.pure(Result<&2,&2,String,String>,Fail{Uuid.errorMessage(error)})
    case Done{timestamp} Done{value}: exported(session,cwd,path,timestamp,value)

def exportSessionForShare(session: Session.AgentSession,cwd: String,path: String) -> IO(Result<&2,&2,String,String>):
  do IO<Result<&2,&2,String,String>>:
    timestamp : Persistence.Outcome(String) <- Persistence.isoNow()
    id : Result<&2,&2,Uuid.Error,String> <- Uuid.randomUUID()
    withId(session,cwd,path,timestamp,id)

type GistResult is Data:
  Shared{viewerUrl: String,gistUrl: String}
  Failed{message: String}
  Cancelled{}

def output(bytes: List<&2,U32>) -> String:
  Text.trim(Result.default(&2,&2,Utf8.Error,String,Utf8.decodeStrict(bytes),""))

def lastSegment(parts: List<&2,String>) -> Maybe<&2,String>:
  match parts:
    case SNil{} <> _: None{}
    case SCon{first,rest} <> _: Some{SCon{first,rest}}
    case _: None{}

def gistId(url: String) -> Maybe<&2,String>:
  lastSegment(List.reverse(&2,String,String.split(url,'/')))

def gistUrl(+url: String,id: Maybe<&2,String>) -> IO(GistResult):
  match id:
    case None{}: IO.pure(GistResult,Failed{"Failed to parse gist ID from gh output"})
    case Some{id}:
      do IO<GistResult>:
        viewer : String <- Config.getShareViewerUrl(id)
        return Shared{viewer,url}

def gistResult(status: Child.Completed) -> IO(GistResult):
  match status:
    case Child.Completed{Done{0},stdout,_}:
      +url = output(stdout)
      gistUrl(url,gistId(url))
    case Child.Completed{_,_,stderr}:
      +reason = output(stderr)
      IO.pure(GistResult,Failed{"Failed to create gist: " ++ Bool.pick(String,String.is_empty(reason),"Unknown error",reason)})

def gistFinished(status: Child.Completed,signal: Abort.AbortSignal<Unit>) -> IO(GistResult):
  do IO<GistResult>:
    cancelled : Bool <- Abort.aborted(Unit,signal)
    Bool.pick(Unit -> IO(GistResult),cancelled,_ => IO.pure(GistResult,Cancelled{}),_ => gistResult(status))(Unit{})

def createGist(program: String,file: String,cwd: String,env: List<String>,+signal: Abort.AbortSignal<Unit>) -> IO(GistResult):
  do IO<GistResult>:
    status : Child.Completed <- Child.spawnSync(program,["gist","create","--public=false",file],cwd,env,[signal])
    gistFinished(status,signal)

def githubStatus(status: Child.Completed) -> Result<&2,&2,String,Unit>:
  match status:
    case Child.Completed{Done{0},_,_}: Done{Unit{}}
    case _: Fail{"GitHub CLI is not logged in. Run 'gh auth login' first."}

def githubProgram(cwd: String,env: List<String>,found: Maybe<&2,String>) -> IO(Result<&2,&2,String,String>):
  match found:
    case None{}: IO.pure(Result<&2,&2,String,String>,Fail{"GitHub CLI (gh) is not installed. Install it from https://cli.github.com/"})
    case Some{+program}:
      do IO<Result<&2,&2,String,String>>:
        status : Child.Completed <- Child.spawnSync(program,["auth","status"],cwd,env,Nil{})
        return Result.map(&2,&2,String,Unit,String,_ => program,githubStatus(status))

def checkGithubWith(cwd: String,paths: String & List<String>) -> IO(Result<&2,&2,String,String>):
  match paths:
    case (path,environment):
      do IO<Result<&2,&2,String,String>>:
        program : Maybe<&2,String> <- Child.resolveCommand("gh",path)
        githubProgram(cwd,environment,program)

def checkGithub(cwd: String,env: List<String>) -> IO(Result<&2,&2,String,String>):
  checkGithubWith(cwd,Child.withSearchPath(env,None{}))

def gistAfterHtml(program: String,htmlFile: String,cwd: String,signal: Abort.AbortSignal<Unit>,exported: Result<&2,&2,String,String>) -> IO(GistResult):
  match exported:
    case Fail{message}: IO.pure(GistResult,Failed{"Failed to export session: " ++ message})
    case Done{_}:
      do IO<GistResult>:
        env : List<String> <- IO.environment()
        createGist(program,htmlFile,cwd,env,signal)

def gistAfterAuth(+htmlFile: String,cwd: String,signal: Abort.AbortSignal<Unit>,writeHtml: String -> IO(Result<&2,&2,String,String>),found: Result<&2,&2,String,String>) -> IO(GistResult):
  match found:
    case Fail{message}: IO.pure(GistResult,Failed{message})
    case Done{program}:
      do IO<GistResult>:
        html : Result<&2,&2,String,String> <- writeHtml(htmlFile)
        gistAfterHtml(program,htmlFile,cwd,signal,html)

def gistAfterJsonl(+cwd: String,htmlFile: String,jsonl: Result<&2,&2,String,String>,signal: Abort.AbortSignal<Unit>,writeHtml: String -> IO(Result<&2,&2,String,String>)) -> IO(GistResult):
  match jsonl:
    case Fail{message}: IO.pure(GistResult,Failed{"Failed to export session: " ++ message})
    case Done{_}:
      do IO<GistResult>:
        env : List<String> <- IO.environment()
        found : Result<&2,&2,String,String> <- checkGithub(cwd,env)
        gistAfterAuth(htmlFile,cwd,signal,writeHtml,found)

def shareIn(session: Session.AgentSession,+cwd: String,+directory: String,signal: Abort.AbortSignal<Unit>,writeHtml: String -> IO(Result<&2,&2,String,String>)) -> IO(GistResult):
  do IO<GistResult>:
    jsonl : Result<&2,&2,String,String> <- exportSessionForShare(session,cwd,FS.child(directory,"session.jsonl"))
    result : GistResult <- gistAfterJsonl(cwd,FS.child(directory,"session.html"),jsonl,signal,writeHtml)
    cleaned : Result<&2,&2,FS.Error,Unit> <- FS.remove(directory,True{},True{})
    return result

def shareCreated(session: Session.AgentSession,cwd: String,signal: Abort.AbortSignal<Unit>,writeHtml: String -> IO(Result<&2,&2,String,String>),created: Result<&1,&1,U32 & String,String>) -> IO(GistResult):
  match created:
    case Fail{_}: IO.pure(GistResult,Failed{"Failed to create a temporary share directory"})
    case Done{directory}: shareIn(session,cwd,directory,signal,writeHtml)

def shareSession(session: Session.AgentSession,cwd: String,signal: Abort.AbortSignal<Unit>,writeHtml: String -> IO(Result<&2,&2,String,String>)) -> IO(GistResult):
  do IO<GistResult>:
    temporary : Result<&1,&1,U32 & String,String> <- IO.get_env("TMPDIR")
    directory : Result<&1,&1,U32 & String,String> <- Directory.mkdtemp(FS.child(Result.default(&1,&1,U32 & String,String,temporary,"/tmp"),"pi-share-XXXXXX"))
    shareCreated(session,cwd,signal,writeHtml,directory)
