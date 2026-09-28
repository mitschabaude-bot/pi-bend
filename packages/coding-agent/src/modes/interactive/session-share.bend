import Base
import ../../../../ai/src/utils/message-json.bend as Json
import ../../../../ai/src/utils/uuid.bend as Uuid
import ../../../../ai/src/auth/resolve.bend as Resolve
import ../../../../ai/src/models.bend as AiModels
import ../../../../runtime/src/schema-value.bend as V
import ../../../../runtime/src/record.bend as R
import ../../../../runtime/src/abort.bend as Abort
import ../../../../runtime/src/callback.bend as Callback
import ../../../../runtime/src/child-process.bend as Child
import ../../../../runtime/src/utf8.bend as Utf8
import ../../../../runtime/src/text.bend as Text
import ../../../../runtime/src/filesystem.bend as FS
import ../../../../runtime/src/json.bend as Decode
import ../../../../runtime/src/http-message.bend as Message
import ../../../../runtime/src/f64.bend as F
import ../../../../ai/src/api/credential-http.bend as Http
import ../../cli/auth-command.bend as AuthCommand
import ../../config.bend as Config
import ../../core/agent-session.bend as Session
import ../../core/model-runtime.bend as Models
import ../../core/agent-runtime.bend as Runtime
import ../../core/settings-manager.bend as Settings
import ../../core/session-export.bend as Export
import ../../core/session-json.bend as SessionJson
import ../../core/session-persistence.bend as Persistence
import ../../core/extensions/types.bend as Extensions
import ../../core/tools/index.bend as Tools

def radiusUrl() -> String: "https://radius.pi.dev/v1/artifacts?visibility=organization&title=Pi+session"

# Export-only presentation data for the pi session viewer. The original
# conversation entries and the live session are not modified.
def tool(value: Extensions.ToolInfo) -> V.Value:
  match value:
    case Extensions.ToolInfo{name,description,parameters,_,_}:
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
    Export.exportSessionToJsonl(~Unit,~Tools.ToolDetails,~V.Value,~Session.unitValue,~Tools.detailsValue,~Session.rawValue,Session.stateOf(stored),cwd,path,timestamp,parent => time => createShareTrailingEntries(parent,time,id,prompt,Session.toolInfos(Session.stateTools(state),Nil{})))

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

type ShareResult is Data:
  GistShared{viewerUrl: String,gistUrl: String}
  RadiusShared{url: String}
  Failed{message: String}
  Cancelled{}

def stringFound(found: Maybe<&2,V.Value>) -> Maybe<&2,String>:
  match found:
    case Some{V.Text{text}}: Some{text}
    case _: None{}

def stringField(fields: R.Record<V.Value>,key: String) -> Maybe<&2,String>:
  stringFound(R.get(V.Value,fields,key))

def artifactField(found: Maybe<&2,V.Value>) -> Maybe<&2,String>:
  match found:
    case Some{V.ObjectValue{artifact}}: stringField(artifact,"canonical_url")
    case _: None{}

def artifactUrl(value: V.Value) -> Maybe<&2,String>:
  match value:
    case V.ObjectValue{fields}:
      artifactField(R.get(V.Value,fields,"artifact"))
    case _: None{}

def radiusError(value: V.Value) -> Maybe<&2,String>:
  match value:
    case V.ObjectValue{fields}: stringField(fields,"error")
    case _: None{}

def radiusArtifact(+status: U32,+value: V.Value,found: Maybe<&2,String>) -> ShareResult:
  match found:
    case Some{url}: Bool.pick(ShareResult,U32.is_ge(status,200) && U32.is_lt(status,300),RadiusShared{url},Failed{"Failed to upload Radius artifact: " ++ Maybe.default(&2,String,radiusError(value),U32.show(status))})
    case None{}: Failed{"Failed to upload Radius artifact: " ++ Maybe.default(&2,String,radiusError(value),U32.show(status))}

def radiusParsed(status: U32,parsed: Result<&2,&2,Decode.ParseError,V.Value>) -> ShareResult:
  match parsed:
    case Done{+value}: radiusArtifact(status,value,artifactUrl(value))
    case Fail{_}: Failed{"Failed to upload Radius artifact: " ++ U32.show(status)}

def radiusReply(reply: Http.Reply) -> ShareResult:
  match reply:
    case Http.Reply{status,_,body}: radiusParsed(status,Decode.parse(body))

def radiusResponse(result: Result<&2,&2,Http.Failure,Http.Reply>) -> ShareResult:
  match result:
    case Done{reply}: radiusReply(reply)
    case Fail{failure}: Failed{"Failed to upload Radius artifact: " ++ Http.failureText(failure)}

def uploadRadius(transport: Http.Transport<Unit>,token: String,+bytes: List<&2,U32>,url: String) -> IO(ShareResult):
  do IO<ShareResult>:
    response : Result<&2,&2,Http.Failure,Http.Reply> <- Http.request(~Unit,transport,"POST",url,[R.Property{"Authorization","Bearer " ++ token},R.Property{"Content-Type","application/x-ndjson"},R.Property{"Content-Length",Nat.show(List.length(&2,U32,bytes))}],Message.Bytes{bytes},Http.NO_TIMEOUT())
    return radiusResponse(response)

def radiusWithTransport(transport: Runtime.Transport,token: String,bytes: List<&2,U32>,+signal: Abort.AbortSignal<Unit>) -> IO(ShareResult):
  match transport:
    case Runtime.Transport{authorizer,runtime,+fetch,codexSessions}:
      do IO<ShareResult>:
        result : ShareResult <- uploadRadius(Http.Transport{fetch,Runtime.urlContext(),signal},token,bytes,radiusUrl())
        Runtime.disposeTransport(Runtime.Transport{authorizer,runtime,fetch,codexSessions})
        cancelled : Bool <- Abort.aborted(Unit,signal)
        return Bool.pick(ShareResult,cancelled,Cancelled{},result)

def radiusTransport(created: Runtime.Outcome(Runtime.Transport),token: String,bytes: List<&2,U32>,signal: Abort.AbortSignal<Unit>) -> IO(ShareResult):
  match created:
    case Fail{message}: IO.pure(ShareResult,Failed{"Failed to upload Radius artifact: " ++ message})
    case Done{transport}: radiusWithTransport(transport,token,bytes,signal)

def radiusBytes(session: Session.AgentSession,token: String,signal: Abort.AbortSignal<Unit>,read: Result<&2,&2,FS.Error,List<&2,U32>>) -> IO(ShareResult):
  match read:
    case Fail{error}: IO.pure(ShareResult,Failed{"Failed to upload Radius artifact: " ++ FS.errorMessage(error)})
    case Done{bytes}:
      do IO<ShareResult>:
        settings : Settings.SettingsManager <- Session.getSettings(session)
        bundle : Result<&1,&1,U32 & String,String> <- IO.get_env("SSL_CERT_FILE")
        created : Runtime.Outcome(Runtime.Transport) <- Runtime.createTransportWith(Result.default(&1,&1,U32 & String,String,bundle,"/etc/ssl/certs/ca-certificates.crt"),Runtime.globalHttpProxy(settings))
        radiusTransport(created,token,bytes,signal)

def radiusCredential(session: Session.AgentSession,path: String,signal: Abort.AbortSignal<Unit>,progress: Callback.Callback<String,Unit>,credential: Maybe<&2,String>) -> IO(Maybe<&2,ShareResult>):
  match credential:
    case None{}: IO.pure(Maybe<&2,ShareResult>,None{})
    case Some{token}:
      do IO<Maybe<&2,ShareResult>>:
        Callback.call(String,Unit,progress,"Uploading to Radius...")
        read : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(path)
        result : ShareResult <- radiusBytes(session,token,signal,read)
        return Some{result}

def radiusAuthenticated(session: Session.AgentSession,path: String,signal: Abort.AbortSignal<Unit>,progress: Callback.Callback<String,Unit>,resolution: Resolve.Resolution()) -> IO(Maybe<&2,ShareResult>):
  match resolution:
    case Fail{error}: IO.pure(Maybe<&2,ShareResult>,Some{Failed{Resolve.errorMessage(error)}})
    case Done{auth}: radiusCredential(session,path,signal,progress,AuthCommand.getAuthCredential(auth))

def radiusProvider(+session: Session.AgentSession,path: String,signal: Abort.AbortSignal<Unit>,progress: Callback.Callback<String,Unit>,provider: Maybe<&2,AiModels.Provider>) -> IO(Maybe<&2,ShareResult>):
  match provider:
    case None{}: IO.pure(Maybe<&2,ShareResult>,None{})
    case Some{_}:
      do IO<Maybe<&2,ShareResult>>:
        resolution : Resolve.Resolution() <- Models.getAuth(Session.modelRuntime(session),"radius",Resolve.AuthResolutionOverrides{None{},None{},Some{F.fromU32(300000)},None{}})
        radiusAuthenticated(session,path,signal,progress,resolution)

def tryRadius(+session: Session.AgentSession,path: String,signal: Abort.AbortSignal<Unit>,progress: Callback.Callback<String,Unit>) -> IO(Maybe<&2,ShareResult>):
  do IO<Maybe<&2,ShareResult>>:
    provider : Maybe<&2,AiModels.Provider> <- Models.getProvider(Session.modelRuntime(session),"radius")
    radiusProvider(session,path,signal,progress,provider)

def output(bytes: List<&2,U32>) -> String:
  Text.trim(Result.default(&2,&2,Utf8.Error,String,Utf8.decodeStrict(bytes),""))

def lastSegment(parts: List<&2,String>) -> Maybe<&2,String>:
  match parts:
    case SNil{} <> _: None{}
    case SCon{first,rest} <> _: Some{SCon{first,rest}}
    case _: None{}

def gistId(url: String) -> Maybe<&2,String>:
  lastSegment(List.reverse(&2,String,String.split(url,'/')))

def gistUrl(+url: String,id: Maybe<&2,String>) -> IO(ShareResult):
  match id:
    case None{}: IO.pure(ShareResult,Failed{"Failed to parse gist ID from gh output"})
    case Some{id}:
      do IO<ShareResult>:
        viewer : String <- Config.getShareViewerUrl(id)
        return GistShared{viewer,url}

def gistResult(status: Child.Completed) -> IO(ShareResult):
  match status:
    case Child.Completed{Done{0},stdout,_}:
      +url = output(stdout)
      gistUrl(url,gistId(url))
    case Child.Completed{_,_,stderr}:
      +reason = output(stderr)
      IO.pure(ShareResult,Failed{"Failed to create gist: " ++ Bool.pick(String,String.is_empty(reason),"Unknown error",reason)})

def gistFinished(status: Child.Completed,signal: Abort.AbortSignal<Unit>) -> IO(ShareResult):
  do IO<ShareResult>:
    cancelled : Bool <- Abort.aborted(Unit,signal)
    Bool.pick(Unit -> IO(ShareResult),cancelled,_ => IO.pure(ShareResult,Cancelled{}),_ => gistResult(status))(Unit{})

def createGist(program: String,file: String,cwd: String,env: List<String>,+signal: Abort.AbortSignal<Unit>) -> IO(ShareResult):
  do IO<ShareResult>:
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

def gistAfterHtml(program: String,htmlFile: String,cwd: String,signal: Abort.AbortSignal<Unit>,progress: Callback.Callback<String,Unit>,exported: Result<&2,&2,String,String>) -> IO(ShareResult):
  match exported:
    case Fail{message}: IO.pure(ShareResult,Failed{"Failed to export session: " ++ message})
    case Done{_}:
      do IO<ShareResult>:
        Callback.call(String,Unit,progress,"Creating gist...")
        env : List<String> <- IO.environment()
        createGist(program,htmlFile,cwd,env,signal)

def gistAfterAuth(+htmlFile: String,cwd: String,signal: Abort.AbortSignal<Unit>,writeHtml: String -> IO(Result<&2,&2,String,String>),progress: Callback.Callback<String,Unit>,found: Result<&2,&2,String,String>) -> IO(ShareResult):
  match found:
    case Fail{message}: IO.pure(ShareResult,Failed{message})
    case Done{program}:
      do IO<ShareResult>:
        html : Result<&2,&2,String,String> <- writeHtml(htmlFile)
        gistAfterHtml(program,htmlFile,cwd,signal,progress,html)

def gistAfterJsonl(+cwd: String,htmlFile: String,jsonl: Result<&2,&2,String,String>,signal: Abort.AbortSignal<Unit>,writeHtml: String -> IO(Result<&2,&2,String,String>),progress: Callback.Callback<String,Unit>) -> IO(ShareResult):
  match jsonl:
    case Fail{message}: IO.pure(ShareResult,Failed{"Failed to export session: " ++ message})
    case Done{_}:
      do IO<ShareResult>:
        env : List<String> <- IO.environment()
        found : Result<&2,&2,String,String> <- checkGithub(cwd,env)
        gistAfterAuth(htmlFile,cwd,signal,writeHtml,progress,found)

def selectedShare(cwd: String,htmlFile: String,signal: Abort.AbortSignal<Unit>,writeHtml: String -> IO(Result<&2,&2,String,String>),progress: Callback.Callback<String,Unit>,radius: Maybe<&2,ShareResult>) -> IO(ShareResult):
  match radius:
    case Some{result}: IO.pure(ShareResult,result)
    case None{}: gistAfterJsonl(cwd,htmlFile,Done{""},signal,writeHtml,progress)

def shareExported(session: Session.AgentSession,cwd: String,+directory: String,+signal: Abort.AbortSignal<Unit>,writeHtml: String -> IO(Result<&2,&2,String,String>),+progress: Callback.Callback<String,Unit>,jsonl: Result<&2,&2,String,String>) -> IO(ShareResult):
  match jsonl:
    case Fail{message}: IO.pure(ShareResult,Failed{"Failed to export session: " ++ message})
    case Done{_}:
      do IO<ShareResult>:
        radius : Maybe<&2,ShareResult> <- tryRadius(session,FS.child(directory,"session.jsonl"),signal,progress)
        selectedShare(cwd,FS.child(directory,"session.html"),signal,writeHtml,progress,radius)

def shareIn(+session: Session.AgentSession,+cwd: String,+directory: String,signal: Abort.AbortSignal<Unit>,writeHtml: String -> IO(Result<&2,&2,String,String>),progress: Callback.Callback<String,Unit>) -> IO(ShareResult):
  do IO<ShareResult>:
    jsonl : Result<&2,&2,String,String> <- exportSessionForShare(session,cwd,FS.child(directory,"session.jsonl"))
    result : ShareResult <- shareExported(session,cwd,directory,signal,writeHtml,progress,jsonl)
    cleaned : Result<&2,&2,FS.Error,Unit> <- FS.remove(directory,True{},True{})
    return result

def shareCreated(session: Session.AgentSession,cwd: String,signal: Abort.AbortSignal<Unit>,writeHtml: String -> IO(Result<&2,&2,String,String>),progress: Callback.Callback<String,Unit>,created: Result<&1,&1,U32 & String,String>) -> IO(ShareResult):
  match created:
    case Fail{_}: IO.pure(ShareResult,Failed{"Failed to create a temporary share directory"})
    case Done{directory}: shareIn(session,cwd,directory,signal,writeHtml,progress)

def shareSession(session: Session.AgentSession,cwd: String,signal: Abort.AbortSignal<Unit>,writeHtml: String -> IO(Result<&2,&2,String,String>),progress: Callback.Callback<String,Unit>) -> IO(ShareResult):
  do IO<ShareResult>:
    temporary : Result<&1,&1,U32 & String,String> <- IO.get_env("TMPDIR")
    directory : Result<&1,&1,U32 & String,String> <- Directory.mkdtemp(FS.child(Result.default(&1,&1,U32 & String,String,temporary,"/tmp"),"pi-share-XXXXXX"))
    shareCreated(session,cwd,signal,writeHtml,progress,directory)
