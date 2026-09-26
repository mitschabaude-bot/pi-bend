import Base
import ../../../runtime/src/json.bend as Decode
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/ref.bend as Ref
import ../../../runtime/src/callback.bend as Callback
import ../../../runtime/src/schema-value.bend as V
import ../../../ai/src/utils/json.bend as Json
import ../../../ai/src/utils/schema-json.bend as SchemaJson
import ../../../ai/src/utils/message-json.bend as MessageJson
import ../../../ai/src/utils/thinking-levels.bend as Levels
import ../../../ai/src/utils/model-json.bend as ModelJson
import ../../../ai/src/types.bend as Ai
import ../../../agent/src/agent.bend as Agent
import ../../../agent/src/types.bend as AgentTypes
import ../core/extensions/runner.bend as ExtensionRunner
import ../core/extensions/types.bend as ExtensionTypes
import ../core/agent-session.bend as Session
import ../core/bash-executor.bend as Bash
import ../core/agent-runtime.bend as Runtime
import ../core/model-runtime.bend as Models
import ../core/settings-manager.bend as Settings
import ../core/session-persistence.bend as Sessions
import ../core/session-manager.bend as S
import ../core/session-json.bend as SessionJson
import ../core/session-stats.bend as Stats
import ../core/export-html/index.bend as Export
import ../core/tools/index.bend as Tools
import ../core/compaction/compaction.bend as Compaction
import ./json-event.bend as Events
import ../core/agent-session-runtime.bend as SessionRuntime
import ../core/skills.bend as Skills
import ../core/prompt-templates.bend as Templates

# pi v0.87.1's headless protocol is LF-delimited JSON objects. The caller owns
# byte transport; this endpoint owns framing, dispatch and event subscriptions.
def Sink() -> Data: Callback.Callback<String,Unit>
type Submission is Data: Submission{text: String,images: List<&2,Ai.ImageContent>,behavior: Maybe<&2,Session.StreamingBehavior>}
type BashRequest is Data: BashRequest{id: Maybe<&2,String>,command: String,exclude: Maybe<&2,Bool>}
# Upstream handles the next command only when the prompt reaches its first
# awaited I/O: its user message is out and the loop has polled the steering
# queue. `Started` lets the reader wait for that point (or the prompt's end).
type Started is Data: Started{signal: Chan(Unit),sent: Ref.Ref<Bool>}
type Work is Data: PromptWork{request: Submission,started: Started} BashWork{request: BashRequest}
# One command's view of the endpoint, over the session current when it runs.
type Command is Data:
  Command{session: Session.AgentSession,sink: Sink(),buffer: Ref.Ref<String>,busy: Ref.Ref<Bool>,jobs: Chan(Work),assetsDir: Maybe<&2,String>}
# upstream runtimeHost: the host replaces the session, and the endpoint
# rebinds to the one it installs.
type Host is Data:
  Host{newSession: Callback.Callback<Maybe<&2,String>,Result<&2,&2,String,Unit>>,switchSession: Callback.Callback<String,Result<&2,&2,String,Unit>>,fork: Callback.Callback<SessionRuntime.ForkRequest,Result<&2,&2,String,Maybe<&2,String>>>}
type Handle is Data:
  Handle{current: Ref.Ref<Session.AgentSession>,sink: Sink(),buffer: Ref.Ref<String>,busy: Ref.Ref<Bool>,jobs: Chan(Work),assetsDir: Maybe<&2,String>,host: Host,listener: Session.Listener()}
type Owner is Type:
  Owner{handle: Handle,worker: Chan(Unit)}

def line(value: V.Value) -> String:
  Maybe.default(&2,String,Json.stringify(SchemaJson.toJson(value)),"null") ++ "\n"
def output(sink: Sink(),value: V.Value) -> IO(Unit):
  Callback.call(String,Unit,sink,line(value))
def response(id: Maybe<&2,String>,command: String,success: Bool,tail: List<&2,R.Property<V.Value>>) -> V.Value:
  MessageJson.object(MessageJson.optionalText("id",id,MessageJson.field("type",MessageJson.text("response"),MessageJson.field("command",MessageJson.text(command),MessageJson.field("success",V.Boolean{success},tail)))))
def ok(id: Maybe<&2,String>,command: String) -> V.Value:
  response(id,command,True{},Nil{})
def data(id: Maybe<&2,String>,command: String,value: V.Value) -> V.Value:
  response(id,command,True{},MessageJson.field("data",value,Nil{}))
def failure(id: Maybe<&2,String>,command: String,message: String) -> V.Value:
  response(id,command,False{},MessageJson.field("error",MessageJson.text(message),Nil{}))
def field(object: R.Record<V.Value>,name: String) -> Maybe<&2,V.Value>:
  R.get(V.Value,object,name)
def optionalText(value: Maybe<&2,V.Value>) -> Result<&2,&2,String,Maybe<&2,String>>:
  match value:
    case None{}: Done{None{}}
    case Some{V.Text{text}}: Done{Some{text}}
    case _: Fail{"expected string"}
def requiredTextValue(value: Maybe<&2,V.Value>,name: String) -> Result<&2,&2,String,String>:
  match value:
    case Some{V.Text{text}}: Done{text}
    case _: Fail{"Invalid command: " ++ name ++ " must be a string"}
def requiredText(object: R.Record<V.Value>,+name: String) -> Result<&2,&2,String,String>:
  requiredTextValue(field(object,name),name)
def booleanValue(value: Maybe<&2,V.Value>,name: String) -> Result<&2,&2,String,Bool>:
  match value:
    case Some{V.Boolean{value}}: Done{value}
    case _: Fail{"Invalid command: " ++ name ++ " must be a boolean"}
def requiredBoolean(object: R.Record<V.Value>,+name: String) -> Result<&2,&2,String,Bool>:
  booleanValue(field(object,name),name)
def idOf(object: R.Record<V.Value>) -> Result<&2,&2,String,Maybe<&2,String>>:
  optionalText(field(object,"id"))
def behaviorValue(value: Maybe<&2,V.Value>) -> Result<&2,&2,String,Maybe<&2,Session.StreamingBehavior>>:
  match value:
    case None{}: Done{None{}}
    case Some{V.Text{"steer"}}: Done{Some{Session.Steer{}}}
    case Some{V.Text{"followUp"}}: Done{Some{Session.FollowUp{}}}
    case _: Fail{"Invalid command: streamingBehavior must be 'steer' or 'followUp'"}
def behaviorOf(object: R.Record<V.Value>) -> Result<&2,&2,String,Maybe<&2,Session.StreamingBehavior>>:
  behaviorValue(field(object,"streamingBehavior"))
def imageFields(kind: Result<&2,&2,String,String>,data: Result<&2,&2,String,String>,mime: Result<&2,&2,String,String>) -> Result<&2,&2,String,Ai.ImageContent>:
  match kind data mime:
    case Fail{reason} _ _: Fail{reason}
    case _ Fail{reason} _: Fail{reason}
    case _ _ Fail{reason}: Fail{reason}
    case Done{"image"} Done{content} Done{mimeType}: Done{Ai.ImageContent{content,mimeType}}
    case Done{_} _ _: Fail{"Invalid command: images items must have type 'image'"}
def imageValue(value: V.Value) -> Result<&2,&2,String,Ai.ImageContent>:
  match value:
    case V.ObjectValue{+fields}: imageFields(requiredText(fields,"type"),requiredText(fields,"data"),requiredText(fields,"mimeType"))
    case _: Fail{"Invalid command: images items must be objects"}
def prependImage(head: Result<&2,&2,String,Ai.ImageContent>,tail: Result<&2,&2,String,List<&2,Ai.ImageContent>>) -> Result<&2,&2,String,List<&2,Ai.ImageContent>>:
  match head tail:
    case Fail{reason} _: Fail{reason}
    case _ Fail{reason}: Fail{reason}
    case Done{image} Done{images}: Done{image <> images}
def imageList(values: List<&2,V.Value>) -> Result<&2,&2,String,List<&2,Ai.ImageContent>>:
  match values:
    case Nil{}: Done{Nil{}}
    case value <> rest: prependImage(imageValue(value),imageList(rest))
def imagesValue(value: Maybe<&2,V.Value>) -> Result<&2,&2,String,List<&2,Ai.ImageContent>>:
  match value:
    case None{}: Done{Nil{}}
    case Some{V.ArrayValue{values}}: imageList(values)
    case _: Fail{"Invalid command: images must be an array"}
def imagesOf(object: R.Record<V.Value>) -> Result<&2,&2,String,List<&2,Ai.ImageContent>>:
  imagesValue(field(object,"images"))
def resultResponse(id: Maybe<&2,String>,command: String,result: Result<&2,&2,String,Unit>) -> V.Value:
  match result:
    case Done{_}: ok(id,command)
    case Fail{message}: failure(id,command,message)
def optionalValue(value: Maybe<&2,String>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{text}: V.Text{text}
def messageValues(messages: List<&2,Session.Message()>) -> List<&2,V.Value>:
  match messages:
    case Nil{}: Nil{}
    case message <> rest: Events.message(message) <> messageValues(rest)
def eventValue(sink: Sink(),converted: Result<&2,&2,String,V.Value>) -> IO(Unit):
  match converted:
    case Done{json}: output(sink,json)
    case Fail{reason}: IO.print_err("RPC event conversion failed: " ++ reason)
def event(sink: Sink(),value: Session.AgentSessionEvent) -> IO(Unit):
  eventValue(sink,Events.toSessionJsonEvent(value))
def observe(sink: Sink(),value: Session.AgentSessionEvent) -> IO(Unit): event(sink,value)

# A prompt response is written before waking this worker. A prompt without a
# streaming behavior is rejected while another is accepted, as upstream does.
def bashValue(result: Bash.BashResult) -> V.Value:
  match result:
    case Bash.BashResult{content,exitCode,cancelled,truncated,fullOutputPath}:
      MessageJson.object(MessageJson.field("output",V.Text{content},MessageJson.optional("exitCode",Maybe.map(&2,U32,V.Value,code => MessageJson.natural(U32.to_nat(code)),exitCode),MessageJson.field("cancelled",V.Boolean{cancelled},MessageJson.field("truncated",V.Boolean{truncated},MessageJson.optionalText("fullOutputPath",fullOutputPath,Nil{}))))))
def bashReply(sink: Sink(),id: Maybe<&2,String>,result: Result<&2,&2,String,Bash.BashResult>) -> IO(Unit):
  match result:
    case Fail{reason}: output(sink,failure(id,"bash",reason))
    case Done{value}: output(sink,data(id,"bash",bashValue(value)))
def runBash(handle: Command,request: BashRequest) -> IO(Unit):
  match handle request:
    case Command{session,sink,_,_,_,_} BashRequest{+id,command,exclude}:
      do IO<Unit>:
        result : Result<&2,&2,String,Bash.BashResult> <- Session.executeBash(session,command,None{},Session.BashOptions{exclude,id,None{}})
        bashReply(sink,id,result)
def sendSignal(signal: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    delivered : Bool <- Chan.send(Unit,signal,Unit{})
    return Unit{}
def releaseStarted(started: Started) -> IO(Unit):
  match started:
    case Started{_,sent}:
      do IO<Unit>:
        flag : Bool <- Ref.dispose(Bool,sent)
        return Unit{}
def signalOnce(started: Started) -> IO(Unit):
  match started:
    case Started{signal,sent}:
      do IO<Unit>:
        previous : Bool <- Ref.swap(Bool,sent,True{})
        Bool.pick(Unit -> IO(Unit),previous,_ => IO.pure(Unit,Unit{}),_ => sendSignal(signal))(Unit{})
def startedBy(started: Started,value: Session.AgentSessionEvent) -> IO(Unit):
  match value:
    case Session.AgentEvent{AgentTypes.MessageEnd{AgentTypes.LlmMessage{Ai.User{_}}}}: signalOnce(started)
    case _: IO.pure(Unit,Unit{})
def runJob(handle: Command,request: Submission,+started: Started) -> IO(Unit):
  match handle request:
    case Command{+session,_,_,busy,_,_} Submission{text,images,behavior}:
      do IO<Unit>:
        +watch : Session.Listener() <- Callback.create(~Started,~Session.AgentSessionEvent,~Unit,~startedBy,started)
        Session.subscribe(session,watch)
        result : Result<&2,&2,String,Unit> <- Session.prompt(session,text,images,behavior)
        Session.unsubscribe(session,watch)
        Callback.dispose(Session.AgentSessionEvent,Unit,watch)
        signalOnce(started)
        releaseStarted(started)
        Ref.write(Bool,busy,False{})
def runWork(handle: Command,work: Work) -> IO(Unit):
  match work:
    case PromptWork{request,started}: runJob(handle,request,started)
    case BashWork{request}: runBash(handle,request)
def commandOf(handle: Handle) -> IO(Command):
  match handle:
    case Handle{current,sink,buffer,busy,jobs,assetsDir,_,_}:
      do IO<Command>:
        session : Session.AgentSession <- Ref.read(Session.AgentSession,current)
        return Command{session,sink,buffer,busy,jobs,assetsDir}
def nextJob(handle: Handle) -> IO(Maybe<&1,Work>):
  match handle:
    case Handle{_,_,_,_,jobs,_,_,_}: Chan.recv(Work,jobs)
def runCurrent(+handle: Handle,work: Work) -> IO(Unit):
  do IO<Unit>:
    view : Command <- commandOf(handle)
    runWork(view,work)
type Phase is Type: Check{} Received{request: Maybe<&1,Work>}
@unsafe def worker(+handle: Handle,phase: Phase) -> IO(Unit):
  match phase:
    case Check{}:
      do IO<Unit>:
        request : Maybe<&1,Work> <- nextJob(handle)
        worker(handle,Received{request})
    case Received{None{}}: IO.pure(Unit,Unit{})
    case Received{Some{request}}:
      do IO<Unit>:
        runCurrent(handle,request)
        worker(handle,Check{})
def start(+session: Session.AgentSession,+sink: Sink(),assetsDir: Maybe<&2,String>,host: Host) -> IO(Owner & Handle):
  do IO<Owner & Handle>:
    +current : Ref.Ref<Session.AgentSession> <- Ref.new(Session.AgentSession,session)
    +buffer : Ref.Ref<String> <- Ref.new(String,"")
    +busy : Ref.Ref<Bool> <- Ref.new(Bool,False{})
    +jobs : Chan(Work) <- Chan.new(Work,64)
    +listener : Session.Listener() <- Callback.create(~Sink(),~Session.AgentSessionEvent,~Unit,~observe,sink)
    Session.subscribe(session,listener)
    +handle : Handle <- IO.pure(Handle,Handle{current,sink,buffer,busy,jobs,assetsDir,host,listener})
    task : Chan(Unit) <- IO.fork(Unit,worker(handle,Check{}))
    return (Owner{handle,task},handle)

# upstream rebindSession: later commands and events use the session the host
# installed; the replaced session's listeners went with it.
def rebind(handle: Handle,+session: Session.AgentSession) -> IO(Unit):
  match handle:
    case Handle{current,_,_,busy,_,_,_,listener}:
      do IO<Unit>:
        Ref.write(Session.AgentSession,current,session)
        Ref.write(Bool,busy,False{})
        Session.subscribe(session,listener)

def acceptedPrompt(session: Session.AgentSession,sink: Sink(),busy: Ref.Ref<Bool>,jobs: Chan(Work),id: Maybe<&2,String>,text: String,images: List<&2,Ai.ImageContent>,active: Bool,behavior: Maybe<&2,Session.StreamingBehavior>) -> IO(Unit):
  match active behavior:
    case True{} None{}: output(sink,failure(id,"prompt","Agent is already processing. Specify streamingBehavior ('steer' or 'followUp') to queue the message."))
    case True{} Some{Session.Steer{}}:
      do IO<Unit>:
        Session.steer(session,text,images)
        output(sink,ok(id,"prompt"))
    case True{} Some{Session.FollowUp{}}:
      do IO<Unit>:
        Session.followUp(session,text,images)
        output(sink,ok(id,"prompt"))
    case False{} _:
      do IO<Unit>:
        +signal : Chan(Unit) <- Chan.new(Unit,1)
        sent : Ref.Ref<Bool> <- Ref.new(Bool,False{})
        Ref.write(Bool,busy,True{})
        output(sink,ok(id,"prompt"))
        accepted : Bool <- Chan.send(Work,jobs,PromptWork{Submission{text,images,behavior},Started{signal,sent}})
        ready : Maybe<&1,Unit> <- Chan.recv(Unit,signal)
        return Unit{}

def promptChecked(handle: Command,id: Maybe<&2,String>,message: Result<&2,&2,String,String>,images: Result<&2,&2,String,List<&2,Ai.ImageContent>>,behavior: Result<&2,&2,String,Maybe<&2,Session.StreamingBehavior>>) -> IO(Unit):
  match handle:
    case Command{+session,+sink,_,+busy,+jobs,_}:
      match message images behavior:
        case Fail{error} _ _: output(sink,failure(id,"prompt",error))
        case _ Fail{error} _: output(sink,failure(id,"prompt",error))
        case _ _ Fail{error}: output(sink,failure(id,"prompt",error))
        case Done{text} Done{images} Done{behavior}:
          do IO<Unit>:
            active : Bool <- Ref.read(Bool,busy)
            streaming : Bool <- Session.isStreaming(session)
            acceptedPrompt(session,sink,busy,jobs,id,text,images,active || streaming,behavior)
def prompt(handle: Command,id: Maybe<&2,String>,+object: R.Record<V.Value>) -> IO(Unit):
  promptChecked(handle,id,requiredText(object,"message"),imagesOf(object),behaviorOf(object))
def commandFailure(handle: Command,id: Maybe<&2,String>,command: String,error: String) -> IO(Unit):
  match handle:
    case Command{_,sink,_,_,_,_}: output(sink,failure(id,command,error))
def queueText(handle: Command,id: Maybe<&2,String>,+command: String,+text: String,+images: List<&2,Ai.ImageContent>) -> IO(Unit):
  match handle:
    case Command{+session,sink,_,_,_,_}:
      do IO<Unit>:
        Bool.pick(Unit -> IO(Unit),String.eq(command,"steer"),_ => Session.steer(session,text,images),_ => Session.followUp(session,text,images))(Unit{})
        output(sink,ok(id,command))
def queued(handle: Command,id: Maybe<&2,String>,+command: String,message: Result<&2,&2,String,String>,images: Result<&2,&2,String,List<&2,Ai.ImageContent>>) -> IO(Unit):
  match message images:
    case Fail{error} _: commandFailure(handle,id,command,error)
    case _ Fail{error}: commandFailure(handle,id,command,error)
    case Done{text} Done{images}: queueText(handle,id,command,text,images)
def setCleanName(session: Session.AgentSession,sink: Sink(),id: Maybe<&2,String>,name: String) -> IO(Unit):
  match name:
    case "": output(sink,failure(id,"set_session_name","Session name cannot be empty"))
    case _:
      do IO<Unit>:
        result : Result<&2,&2,String,Unit> <- Session.setSessionName(session,name)
        output(sink,resultResponse(id,"set_session_name",result))
def setName(handle: Command,id: Maybe<&2,String>,value: Result<&2,&2,String,String>) -> IO(Unit):
  match handle value:
    case Command{_,sink,_,_,_,_} Fail{error}: output(sink,failure(id,"set_session_name",error))
    case Command{session,sink,_,_,_,_} Done{name}: setCleanName(session,sink,id,String.trim(name))
def thinking(level: String) -> Maybe<&2,Ai.ModelThinkingLevel>:
  match level:
    case "off": Some{Ai.Off{}}
    case "minimal": Some{Ai.Thinking{Ai.Minimal{}}}
    case "low": Some{Ai.Thinking{Ai.Low{}}}
    case "medium": Some{Ai.Thinking{Ai.Medium{}}}
    case "high": Some{Ai.Thinking{Ai.High{}}}
    case "xhigh": Some{Ai.Thinking{Ai.XHigh{}}}
    case "max": Some{Ai.Thinking{Ai.Max{}}}
    case _: None{}
def setChosenThinking(session: Session.AgentSession,sink: Sink(),id: Maybe<&2,String>,level: String,chosen: Maybe<&2,Ai.ModelThinkingLevel>) -> IO(Unit):
  match chosen:
    case None{}: output(sink,failure(id,"set_thinking_level","Invalid thinking level: " ++ level))
    case Some{value}:
      do IO<Unit>:
        result : Result<&2,&2,String,Unit> <- Session.setThinkingLevel(session,value,Session.ModelMutationOptions{False{}})
        output(sink,resultResponse(id,"set_thinking_level",result))

def setThinking(handle: Command,id: Maybe<&2,String>,value: Result<&2,&2,String,String>) -> IO(Unit):
  match handle value:
    case Command{_,sink,_,_,_,_} Fail{error}: output(sink,failure(id,"set_thinking_level",error))
    case Command{session,sink,_,_,_,_} Done{+level}: setChosenThinking(session,sink,id,level,thinking(level))
def reply(handle: Command,value: V.Value) -> IO(Unit):
  match handle:
    case Command{_,sink,_,_,_,_}: output(sink,value)
def abortCommand(handle: Command,id: Maybe<&2,String>,+retry: Bool) -> IO(Unit):
  match handle:
    case Command{+session,sink,_,_,_,_}:
      do IO<Unit>:
        Bool.pick(Unit -> IO(Unit),retry,_ => Session.abortRetry(session),_ => Session.abort(session))(Unit{})
        output(sink,ok(id,Bool.pick(String,retry,"abort_retry","abort")))
def currentMessages(handle: Command,id: Maybe<&2,String>) -> IO(Unit):
  match handle:
    case Command{session,sink,_,_,_,_}:
      do IO<Unit>:
        messages : List<&2,Session.Message()> <- Session.messages(session)
        output(sink,data(id,"get_messages",MessageJson.object(MessageJson.field("messages",V.ArrayValue{messageValues(messages)},Nil{}))))
def entryValue(entry: Session.Entry()) -> V.Value:
  SessionJson.entry(~Unit,~Tools.ToolDetails,~V.Value,~Session.unitValue,~Tools.detailsValue,~Session.rawValue,entry)
def entryValues(entries: List<&2,Session.Entry()>) -> List<&2,V.Value>:
  match entries:
    case Nil{}: Nil{}
    case value <> rest: entryValue(value) <> entryValues(rest)
def textValue(value: Maybe<&2,V.Value>) -> String:
  match value:
    case Some{V.Text{text}}: text
    case _: ""
def entryIdValue(value: V.Value) -> String:
  match value:
    case V.ObjectValue{fields}: textValue(R.get(V.Value,fields,"id"))
    case _: ""
def entryId(value: Session.Entry()) -> String: entryIdValue(entryValue(value))
def entriesAfter(entries: List<&2,Session.Entry()>,+since: String) -> Maybe<&2,List<&2,Session.Entry()>>:
  match entries:
    case Nil{}: None{}
    case value <> +rest:
      Bool.pick(Maybe<&2,List<&2,Session.Entry()>>,String.eq(entryId(value),since),Some{rest},entriesAfter(rest,since))
def selectedFound(id: String,found: Maybe<&2,List<&2,Session.Entry()>>) -> Result<&2,&2,String,List<&2,Session.Entry()>>:
  match found:
    case Some{rest}: Done{rest}
    case None{}: Fail{"Entry not found: " ++ id}
def selectedEntries(entries: List<&2,Session.Entry()>,since: Maybe<&2,String>) -> Result<&2,&2,String,List<&2,Session.Entry()>>:
  match since:
    case None{}: Done{entries}
    case Some{+id}: selectedFound(id,entriesAfter(entries,id))
def entriesResponse(id: Maybe<&2,String>,leaf: Maybe<&2,String>,selected: Result<&2,&2,String,List<&2,Session.Entry()>>) -> V.Value:
  match selected:
    case Fail{reason}: failure(id,"get_entries",reason)
    case Done{entries}: data(id,"get_entries",MessageJson.object(MessageJson.field("entries",V.ArrayValue{entryValues(entries)},MessageJson.field("leafId",optionalValue(leaf),Nil{}))))
def getEntries(handle: Command,id: Maybe<&2,String>,since: Result<&2,&2,String,Maybe<&2,String>>) -> IO(Unit):
  match handle since:
    case Command{_,sink,_,_,_,_} Fail{reason}: output(sink,failure(id,"get_entries",reason))
    case Command{session,sink,_,_,_,_} Done{since}:
      do IO<Unit>:
        +stored : Session.Session() <- Session.sessionOf(session)
        output(sink,entriesResponse(id,S.getLeafId(Unit,Tools.ToolDetails,V.Value,Session.stateOf(stored)),selectedEntries(S.getEntries(Unit,Tools.ToolDetails,V.Value,Session.stateOf(stored)),since)))
type TreeTask is Data:
  RenderNode{value: S.SessionTreeNode<Unit,Tools.ToolDetails,V.Value>}
  RenderNodes{values: List<&2,S.SessionTreeNode<Unit,Tools.ToolDetails,V.Value>>,built: List<&2,V.Value>}
  AppendNode{remaining: List<&2,S.SessionTreeNode<Unit,Tools.ToolDetails,V.Value>>,built: List<&2,V.Value>}
  CompleteNode{entry: V.Value,label: Maybe<&2,String>,labelTimestamp: Maybe<&2,String>}
@unsafe def renderTree(tasks: List<&2,TreeTask>,completed: V.Value) -> V.Value:
  match tasks:
    case Nil{}: completed
    case RenderNode{S.SessionTreeNode{entry,children,label,labelTimestamp}} <> rest:
      renderTree(RenderNodes{children,Nil{}} <> CompleteNode{entryValue(entry),label,labelTimestamp} <> rest,completed)
    case RenderNodes{Nil{},built} <> rest:
      renderTree(rest,V.ArrayValue{List.reverse(&2,V.Value,built)})
    case RenderNodes{head <> tail,built} <> rest:
      renderTree(RenderNode{head} <> AppendNode{tail,built} <> rest,completed)
    case AppendNode{remaining,built} <> rest:
      renderTree(RenderNodes{remaining,completed <> built} <> rest,V.Null{})
    case CompleteNode{entry,label,labelTimestamp} <> rest:
      renderTree(rest,MessageJson.object(MessageJson.field("entry",entry,MessageJson.field("children",completed,MessageJson.optionalText("label",label,MessageJson.optionalText("labelTimestamp",labelTimestamp,Nil{}))))))
def treeResponse(id: Maybe<&2,String>,leaf: Maybe<&2,String>,result: Result<&2,&2,S.Error,List<&2,S.SessionTreeNode<Unit,Tools.ToolDetails,V.Value>>>) -> V.Value:
  match result:
    case Fail{_}: failure(id,"get_tree","Session tree is invalid")
    case Done{tree}: data(id,"get_tree",MessageJson.object(MessageJson.field("tree",renderTree(RenderNodes{tree,Nil{}} <> Nil{},V.Null{}),MessageJson.field("leafId",optionalValue(leaf),Nil{}))))
def getTree(handle: Command,id: Maybe<&2,String>) -> IO(Unit):
  match handle:
    case Command{session,sink,_,_,_,_}:
      do IO<Unit>:
        +stored : Session.Session() <- Session.sessionOf(session)
        output(sink,treeResponse(id,S.getLeafId(Unit,Tools.ToolDetails,V.Value,Session.stateOf(stored)),S.getTree(Unit,Tools.ToolDetails,V.Value,Session.stateOf(stored))))
def forkText(id: String,text: Maybe<&2,String>) -> Maybe<&2,V.Value>:
  match text:
    case None{}: None{}
    case Some{""}: None{}
    case Some{content}: Some{MessageJson.object(MessageJson.field("entryId",V.Text{id},MessageJson.field("text",V.Text{content},Nil{})))}
def forkItem(entry: Session.Entry()) -> Maybe<&2,V.Value>:
  match entry:
    case S.SessionMessageEntry{S.SessionEntryBase{id,_,_},message}: forkText(id,Session.userText(message))
    case _: None{}
def includeFork(item: Maybe<&2,V.Value>,rest: List<&2,V.Value>) -> List<&2,V.Value>:
  match item:
    case None{}: rest
    case Some{value}: value <> rest
def forkItems(entries: List<&2,Session.Entry()>) -> List<&2,V.Value>:
  match entries:
    case Nil{}: Nil{}
    case entry <> rest: includeFork(forkItem(entry),forkItems(rest))
def getForkMessages(handle: Command,id: Maybe<&2,String>) -> IO(Unit):
  match handle:
    case Command{session,sink,_,_,_,_}:
      do IO<Unit>:
        stored : Session.Session() <- Session.sessionOf(session)
        output(sink,data(id,"get_fork_messages",MessageJson.object(MessageJson.field("messages",V.ArrayValue{forkItems(S.getEntries(Unit,Tools.ToolDetails,V.Value,Session.stateOf(stored)))},Nil{}))))
def compactResponse(id: Maybe<&2,String>,result: Result<&2,&2,String,Compaction.CompactionResult>) -> V.Value:
  match result:
    case Fail{reason}: failure(id,"compact",reason)
    case Done{value}: data(id,"compact",Events.compactionResult(value))
def compactCommand(handle: Command,id: Maybe<&2,String>,instructions: Result<&2,&2,String,Maybe<&2,String>>) -> IO(Unit):
  match handle instructions:
    case Command{_,sink,_,_,_,_} Fail{reason}: output(sink,failure(id,"compact",reason))
    case Command{session,sink,_,_,_,_} Done{custom}:
      do IO<Unit>:
        result : Result<&2,&2,String,Compaction.CompactionResult> <- Session.compact(session,custom)
        output(sink,compactResponse(id,result))
def lastText(handle: Command,id: Maybe<&2,String>) -> IO(Unit):
  match handle:
    case Command{session,sink,_,_,_,_}:
      do IO<Unit>:
        last : Maybe<&2,String> <- Session.getLastAssistantText(session)
        output(sink,data(id,"get_last_assistant_text",MessageJson.object(MessageJson.field("text",optionalValue(last),Nil{}))))
type Cleared is Data: Cleared{steering: List<&2,String>,followUp: List<&2,String>}
def clearState(current: Session.Shared) -> Session.Shared & Cleared:
  match current:
    case Session.Shared{stored,steering,followUp,listeners,active,last,retry,compaction, bash, pendingMessages}:
      (Session.Shared{stored,Nil{},Nil{},listeners,active,last,retry,compaction, bash, pendingMessages},Cleared{steering,followUp})
def clearedValue(value: Cleared) -> V.Value:
  match value:
    case Cleared{steering,followUp}: MessageJson.object(MessageJson.field("steering",V.ArrayValue{Events.texts(steering)},MessageJson.field("followUp",V.ArrayValue{Events.texts(followUp)},Nil{})))
def clearQueue(handle: Command,id: Maybe<&2,String>) -> IO(Unit):
  match handle:
    case Command{Session.AgentSession{agent,+shared,_,_,_,_,_,_},sink,_,_,_,_}:
      do IO<Unit>:
        Agent.clearAllQueues(Unit,Runtime.Details(),Runtime.Custom(),Runtime.Error(),Unit,agent)
        removed : Cleared <- Ref.modify(Session.Shared,Cleared,shared,clearState)
        Session.emitQueueUpdate(shared)
        output(sink,data(id,"clear_queue",clearedValue(removed)))
def mode(value: String) -> Maybe<&2,AgentTypes.QueueMode>:
  match value:
    case "all": Some{AgentTypes.All{}}
    case "one-at-a-time": Some{AgentTypes.OneAtATime{}}
    case _: None{}
def modeResponse(handle: Command,id: Maybe<&2,String>,+command: String,value: Maybe<&2,AgentTypes.QueueMode>) -> IO(Unit):
  match handle value:
    case Command{_,sink,_,_,_,_} None{}: output(sink,failure(id,command,"Invalid command: mode must be 'all' or 'one-at-a-time'"))
    case Command{+session,sink,_,_,_,_} Some{+chosen}:
      do IO<Unit>:
        persisted : Result<&2,&2,String,Unit> <- Bool.pick(Unit -> IO(Result<&2,&2,String,Unit>),String.eq(command,"set_steering_mode"),_ => Session.setSteeringMode(session,chosen),_ => Session.setFollowUpMode(session,chosen))(Unit{})
        output(sink,ok(id,command))
def setMode(handle: Command,id: Maybe<&2,String>,command: String,value: Result<&2,&2,String,String>) -> IO(Unit):
  match value:
    case Fail{reason}: commandFailure(handle,id,command,reason)
    case Done{text}: modeResponse(handle,id,command,mode(text))
def levelValues(values: List<&2,Ai.ModelThinkingLevel>) -> List<&2,V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: V.Text{Levels.name(value)} <> levelValues(rest)
def availableLevels(handle: Command,id: Maybe<&2,String>) -> IO(Unit):
  match handle:
    case Command{session,sink,_,_,_,_}:
      do IO<Unit>:
        levels : List<&2,Ai.ModelThinkingLevel> <- Session.getAvailableThinkingLevels(session)
        output(sink,data(id,"get_available_thinking_levels",MessageJson.object(MessageJson.field("levels",V.ArrayValue{levelValues(levels)},Nil{}))))
def thinkingCycled(sink: Sink(),id: Maybe<&2,String>,result: Result<&2,&2,String,Maybe<&2,Ai.ModelThinkingLevel>>) -> IO(Unit):
  match result:
    case Fail{reason}: output(sink,failure(id,"cycle_thinking_level",reason))
    case Done{None{}}: output(sink,data(id,"cycle_thinking_level",V.Null{}))
    case Done{Some{level}}: output(sink,data(id,"cycle_thinking_level",MessageJson.object(MessageJson.field("level",V.Text{Levels.name(level)},Nil{}))))
def cycleThinking(handle: Command,id: Maybe<&2,String>) -> IO(Unit):
  match handle:
    case Command{session,sink,_,_,_,_}:
      do IO<Unit>:
        result : Result<&2,&2,String,Maybe<&2,Ai.ModelThinkingLevel>> <- Session.cycleThinkingLevel(session,Session.ModelMutationOptions{False{}})
        thinkingCycled(sink,id,result)
def queueModeName(value: AgentTypes.QueueMode) -> String:
  match value:
    case AgentTypes.All{}: "all"
    case AgentTypes.OneAtATime{}: "one-at-a-time"
def pendingCount(value: Session.Shared) -> Nat:
  match value:
    case Session.Shared{_,steering,followUp,_,_,_,_,_, _, pendingMessages}: List.length(&2,String,steering) + List.length(&2,String,followUp)
def modelValue(selected: Maybe<&2,Ai.Model<Ai.JsonValue>>) -> V.Value:
  Maybe.default(&2,V.Value,Maybe.map(&2,Ai.Model<Ai.JsonValue>,V.Value,ModelJson.model,selected),V.Null{})
def stateValue(+stored: Session.Session(),+current: Session.AgentState(),shared: Session.Shared,streaming: Bool,compacting: Bool,steering: AgentTypes.QueueMode,followUp: AgentTypes.QueueMode,auto: Bool) -> V.Value:
  MessageJson.object(MessageJson.field("model",modelValue(Session.stateModel(current)),MessageJson.field("thinkingLevel",V.Text{Levels.name(Session.stateThinking(current))},MessageJson.field("isStreaming",V.Boolean{streaming},MessageJson.field("isCompacting",V.Boolean{compacting},MessageJson.field("steeringMode",V.Text{queueModeName(steering)},MessageJson.field("followUpMode",V.Text{queueModeName(followUp)},MessageJson.optionalText("sessionFile",Sessions.getSessionFile(Unit,Tools.ToolDetails,V.Value,stored),MessageJson.field("sessionId",V.Text{S.getSessionId(Unit,Tools.ToolDetails,V.Value,Session.stateOf(stored))},MessageJson.optionalText("sessionName",S.getSessionName(Unit,Tools.ToolDetails,V.Value,Session.stateOf(stored)),MessageJson.field("autoCompactionEnabled",V.Boolean{auto},MessageJson.field("messageCount",MessageJson.natural(List.length(&2,Session.Message(),Session.stateMessages(current))),MessageJson.field("pendingMessageCount",MessageJson.natural(pendingCount(shared)),Nil{})))))))))))))
def sharedSnapshot(session: Session.AgentSession) -> IO(Session.Shared):
  match session:
    case Session.AgentSession{_,shared,_,_,_,_,_,_}: Ref.read(Session.Shared,shared)
def getState(handle: Command,id: Maybe<&2,String>) -> IO(Unit):
  match handle:
    case Command{+session,sink,_,_,_,_}:
      do IO<Unit>:
        +agent : Runtime.Owner() <- IO.pure(Runtime.Owner(),Session.agentOf(session))
        stored : Session.Session() <- Session.sessionOf(session)
        current : Session.AgentState() <- Session.state(session)
        shared : Session.Shared <- sharedSnapshot(session)
        streaming : Bool <- Session.isStreaming(session)
        compacting : Bool <- Session.isCompacting(session)
        steering : AgentTypes.QueueMode <- Agent.getSteeringMode(Unit,Runtime.Details(),Runtime.Custom(),Runtime.Error(),Unit,agent)
        followUp : AgentTypes.QueueMode <- Agent.getFollowUpMode(Unit,Runtime.Details(),Runtime.Custom(),Runtime.Error(),Unit,agent)
        auto : Bool <- Session.getAutoCompactionEnabled(session)
        output(sink,data(id,"get_state",stateValue(stored,current,shared,streaming,compacting,steering,followUp,auto)))
def autoResult(sink: Sink(),id: Maybe<&2,String>,command: String,result: Result<&2,&2,String,Unit>) -> IO(Unit):
  output(sink,resultResponse(id,command,result))
def setAutoCompaction(handle: Command,id: Maybe<&2,String>,enabled: Result<&2,&2,String,Bool>) -> IO(Unit):
  match handle enabled:
    case Command{_,sink,_,_,_,_} Fail{message}: output(sink,failure(id,"set_auto_compaction",message))
    case Command{session,sink,_,_,_,_} Done{value}:
      do IO<Unit>:
        result : Result<&2,&2,String,Unit> <- Session.setAutoCompactionEnabled(session,value)
        autoResult(sink,id,"set_auto_compaction",result)
def setAutoRetry(handle: Command,id: Maybe<&2,String>,enabled: Result<&2,&2,String,Bool>) -> IO(Unit):
  match handle enabled:
    case Command{_,sink,_,_,_,_} Fail{message}: output(sink,failure(id,"set_auto_retry",message))
    case Command{session,sink,_,_,_,_} Done{value}:
      do IO<Unit>:
        result : Result<&2,&2,String,Unit> <- Session.setAutoRetryEnabled(session,value)
        autoResult(sink,id,"set_auto_retry",result)

# Model commands read the session's model runtime, so a login is visible
# without restarting. No separate registry is constructed for RPC.
def modelValues(models: List<&2,Models.Model()>) -> List<&2,V.Value>:
  match models:
    case Nil{}: Nil{}
    case model <> rest: ModelJson.model(model) <> modelValues(rest)
def availableModels(handle: Command,id: Maybe<&2,String>) -> IO(Unit):
  match handle:
    case Command{session,sink,_,_,_,_}:
      do IO<Unit>:
        available : List<&2,Models.Model()> <- Models.getAvailable(Session.modelRuntime(session))
        output(sink,data(id,"get_available_models",MessageJson.object(MessageJson.field("models",V.ArrayValue{modelValues(available)},Nil{}))))
def setModelResponse(sink: Sink(),id: Maybe<&2,String>,model: Models.Model(),result: Result<&2,&2,String,Unit>) -> IO(Unit):
  match result:
    case Done{_}: output(sink,data(id,"set_model",ModelJson.model(model)))
    case Fail{message}: output(sink,failure(id,"set_model",message))
def setFoundModel(session: Session.AgentSession,sink: Sink(),id: Maybe<&2,String>,+model: Models.Model()) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2,&2,String,Unit> <- Session.setModel(session,model,Session.ModelMutationOptions{False{}})
    setModelResponse(sink,id,model,result)
def setMatchedModel(session: Session.AgentSession,sink: Sink(),id: Maybe<&2,String>,provider: String,modelId: String,found: Maybe<&2,Models.Model()>) -> IO(Unit):
  match found:
    case None{}: output(sink,failure(id,"set_model","Model not found: " ++ provider ++ "/" ++ modelId))
    case Some{model}: setFoundModel(session,sink,id,model)
def setAvailableModel(+session: Session.AgentSession,sink: Sink(),id: Maybe<&2,String>,+provider: String,+modelId: String) -> IO(Unit):
  do IO<Unit>:
    available : List<&2,Models.Model()> <- Models.getAvailable(Session.modelRuntime(session))
    setMatchedModel(session,sink,id,provider,modelId,Models.findModel(available,provider,modelId))
def setModelParsed(handle: Command,id: Maybe<&2,String>,provider: Result<&2,&2,String,String>,modelId: Result<&2,&2,String,String>) -> IO(Unit):
  match handle provider modelId:
    case Command{_,sink,_,_,_,_} Fail{message} _: output(sink,failure(id,"set_model",message))
    case Command{_,sink,_,_,_,_} _ Fail{message}: output(sink,failure(id,"set_model",message))
    case Command{session,sink,_,_,_,_} Done{provider} Done{modelId}: setAvailableModel(session,sink,id,provider,modelId)
def setCatalogModel(handle: Command,id: Maybe<&2,String>,+object: R.Record<V.Value>) -> IO(Unit):
  setModelParsed(handle,id,requiredText(object,"provider"),requiredText(object,"modelId"))
def modelCycled(sink: Sink(),id: Maybe<&2,String>,result: Result<&2,&2,String,Maybe<&2,Session.ModelCycleResult>>) -> IO(Unit):
  match result:
    case Fail{message}: output(sink,failure(id,"cycle_model",message))
    case Done{None{}}: output(sink,data(id,"cycle_model",V.Null{}))
    case Done{Some{Session.ModelCycleResult{model,level,scoped}}}:
      output(sink,data(id,"cycle_model",MessageJson.object(MessageJson.field("model",ModelJson.model(model),MessageJson.field("thinkingLevel",V.Text{Levels.name(level)},MessageJson.field("isScoped",V.Boolean{scoped},Nil{}))))))
def cycleCatalogModel(handle: Command,id: Maybe<&2,String>) -> IO(Unit):
  match handle:
    case Command{session,sink,_,_,_,_}:
      do IO<Unit>:
        result : Result<&2,&2,String,Maybe<&2,Session.ModelCycleResult>> <- Session.cycleModel(session,Session.Forward{},Session.ModelMutationOptions{False{}})
        modelCycled(sink,id,result)
def statsResponse(id: Maybe<&2,String>,result: Result<&2,&2,S.Error,Stats.Stats>) -> V.Value:
  match result:
    case Fail{_}: failure(id,"get_session_stats","Session history is invalid")
    case Done{value}: data(id,"get_session_stats",Stats.value(value))
def getSessionStats(handle: Command,id: Maybe<&2,String>) -> IO(Unit):
  match handle:
    case Command{session,sink,_,_,_,_}:
      do IO<Unit>:
        result : Result<&2,&2,S.Error,Stats.Stats> <- Session.getSessionStats(session)
        output(sink,statsResponse(id,result))
def exported(id: Maybe<&2,String>,result: Result<&2,&2,String,String>) -> V.Value:
  match result:
    case Fail{reason}: failure(id,"export_html",reason)
    case Done{path}: data(id,"export_html",MessageJson.object(MessageJson.field("path",V.Text{path},Nil{})))
def exportWithAssets(+session: Session.AgentSession,sink: Sink(),id: Maybe<&2,String>,assets: Export.Assets,path: Maybe<&2,String>) -> IO(Unit):
  do IO<Unit>:
    stored : Session.Session() <- Session.sessionOf(session)
    current : Session.AgentState() <- Session.state(session)
    result : Result<&2,&2,String,String> <- Export.write(assets,stored,current,path)
    output(sink,exported(id,result))
def exportLoaded(session: Session.AgentSession,sink: Sink(),id: Maybe<&2,String>,path: Maybe<&2,String>,loaded: Result<&2,&2,String,Export.Assets>) -> IO(Unit):
  match loaded:
    case Fail{reason}: output(sink,failure(id,"export_html",reason))
    case Done{assets}: exportWithAssets(session,sink,id,assets,path)
def exportFromDir(session: Session.AgentSession,sink: Sink(),id: Maybe<&2,String>,path: Maybe<&2,String>,directory: String) -> IO(Unit):
  do IO<Unit>:
    loaded : Result<&2,&2,String,Export.Assets> <- Export.loadAssets(directory)
    exportLoaded(session,sink,id,path,loaded)
def exportChosen(handle: Command,id: Maybe<&2,String>,path: Maybe<&2,String>) -> IO(Unit):
  match handle:
    case Command{session,sink,_,_,_,None{}}: output(sink,failure(id,"export_html","HTML export assets are unavailable"))
    case Command{session,sink,_,_,_,Some{directory}}: exportFromDir(session,sink,id,path,directory)
def exportHtml(handle: Command,id: Maybe<&2,String>,path: Result<&2,&2,String,Maybe<&2,String>>) -> IO(Unit):
  match path:
    case Fail{reason}: commandFailure(handle,id,"export_html",reason)
    case Done{chosen}: exportChosen(handle,id,chosen)
def bashSubmitted(handle: Command,id: Maybe<&2,String>,command: Result<&2,&2,String,String>,exclude: Result<&2,&2,String,Maybe<&2,Bool>>) -> IO(Unit):
  match handle command exclude:
    case Command{_,sink,_,_,_,_} Fail{reason} _: output(sink,failure(id,"bash",reason))
    case Command{_,sink,_,_,_,_} _ Fail{reason}: output(sink,failure(id,"bash",reason))
    case Command{_,_,_,_,jobs,_} Done{text} Done{choice}:
      do IO<Unit>:
        accepted : Bool <- Chan.send(Work,jobs,BashWork{BashRequest{id,text,choice}})
        return Unit{}
def optionalBoolean(value: Maybe<&2,V.Value>) -> Result<&2,&2,String,Maybe<&2,Bool>>:
  match value:
    case None{}: Done{None{}}
    case Some{V.Boolean{choice}}: Done{Some{choice}}
    case _: Fail{"Invalid command: excludeFromContext must be a boolean"}
def abortBash(handle: Command,id: Maybe<&2,String>) -> IO(Unit):
  match handle:
    case Command{session,sink,_,_,_,_}:
      do IO<Unit>:
        Session.abortBash(session)
        output(sink,ok(id,"abort_bash"))
# Session replacement goes through the host; the rebind hook has installed
# the new session before the response.
def replacedData(fields: List<&2,R.Property<V.Value>>) -> V.Value:
  MessageJson.object(List.append(&2,R.Property<V.Value>,fields,MessageJson.field("cancelled",V.Boolean{False{}},Nil{})))
def replacedReply(sink: Sink(),id: Maybe<&2,String>,command: String,result: Result<&2,&2,String,Unit>) -> IO(Unit):
  match result:
    case Fail{message}: output(sink,failure(id,command,message))
    case Done{_}: output(sink,data(id,command,replacedData(Nil{})))
def newSessionCommand(handle: Command,host: Host,id: Maybe<&2,String>,parent: Result<&2,&2,String,Maybe<&2,String>>) -> IO(Unit):
  match handle host parent:
    case Command{_,sink,_,_,_,_} _ Fail{reason}: output(sink,failure(id,"new_session",reason))
    case Command{_,sink,_,_,_,_} Host{opening,_,_} Done{parentSession}:
      do IO<Unit>:
        result : Result<&2,&2,String,Unit> <- Callback.call(Maybe<&2,String>,Result<&2,&2,String,Unit>,opening,parentSession)
        replacedReply(sink,id,"new_session",result)
def switchSessionCommand(handle: Command,host: Host,id: Maybe<&2,String>,path: Result<&2,&2,String,String>) -> IO(Unit):
  match handle host path:
    case Command{_,sink,_,_,_,_} _ Fail{reason}: output(sink,failure(id,"switch_session",reason))
    case Command{_,sink,_,_,_,_} Host{_,switching,_} Done{sessionPath}:
      do IO<Unit>:
        result : Result<&2,&2,String,Unit> <- Callback.call(String,Result<&2,&2,String,Unit>,switching,sessionPath)
        replacedReply(sink,id,"switch_session",result)
def forkReply(sink: Sink(),id: Maybe<&2,String>,+command: String,result: Result<&2,&2,String,Maybe<&2,String>>) -> IO(Unit):
  match result:
    case Fail{message}: output(sink,failure(id,command,message))
    case Done{text}: output(sink,data(id,command,replacedData(Bool.pick(List<&2,R.Property<V.Value>>,String.eq(command,"fork"),MessageJson.optionalText("text",text,Nil{}),Nil{}))))
def forkWith(sink: Sink(),host: Host,id: Maybe<&2,String>,command: String,request: SessionRuntime.ForkRequest) -> IO(Unit):
  match host:
    case Host{_,_,forking}:
      do IO<Unit>:
        result : Result<&2,&2,String,Maybe<&2,String>> <- Callback.call(SessionRuntime.ForkRequest,Result<&2,&2,String,Maybe<&2,String>>,forking,request)
        forkReply(sink,id,command,result)
def forkCommand(handle: Command,host: Host,id: Maybe<&2,String>,entry: Result<&2,&2,String,String>) -> IO(Unit):
  match handle entry:
    case Command{_,sink,_,_,_,_} Fail{reason}: output(sink,failure(id,"fork",reason))
    case Command{_,sink,_,_,_,_} Done{target}: forkWith(sink,host,id,"fork",SessionRuntime.ForkRequest{target,SessionRuntime.ForkBefore{}})
def cloneLeaf(sink: Sink(),host: Host,id: Maybe<&2,String>,leaf: Maybe<&2,String>) -> IO(Unit):
  match leaf:
    case None{}: output(sink,failure(id,"clone","Cannot clone session: no current entry selected"))
    case Some{leafId}: forkWith(sink,host,id,"clone",SessionRuntime.ForkRequest{leafId,SessionRuntime.ForkAt{}})
def cloneCommand(handle: Command,host: Host,id: Maybe<&2,String>) -> IO(Unit):
  match handle:
    case Command{session,sink,_,_,_,_}:
      do IO<Unit>:
        stored : Session.Session() <- Session.sessionOf(session)
        cloneLeaf(sink,host,id,S.getLeafId(Unit,Tools.ToolDetails,V.Value,Session.stateOf(stored)))

# get_commands: extension commands by invocation name, prompt templates, then
# skills, each with its source metadata.
def scopeName(scope: Skills.SourceScope) -> String:
  match scope:
    case Skills.User{}: "user"
    case Skills.Project{}: "project"
    case Skills.Temporary{}: "temporary"
def originName(origin: Skills.SourceOrigin) -> String:
  match origin:
    case Skills.Package{}: "package"
    case Skills.TopLevel{}: "top-level"
def sourceInfoValue(info: Skills.SourceInfo) -> V.Value:
  match info:
    case Skills.SourceInfo{path,source,scope,origin,baseDir}:
      MessageJson.object(MessageJson.field("path",V.Text{path},MessageJson.field("source",V.Text{source},MessageJson.field("scope",V.Text{scopeName(scope)},MessageJson.field("origin",V.Text{originName(origin)},MessageJson.optionalText("baseDir",baseDir,Nil{}))))))
def commandValue(name: String,description: String,source: String,info: Skills.SourceInfo) -> V.Value:
  MessageJson.object(MessageJson.field("name",V.Text{name},MessageJson.field("description",V.Text{description},MessageJson.field("source",V.Text{source},MessageJson.field("sourceInfo",sourceInfoValue(info),Nil{})))))
def extensionCommandValue(name: String,description: Maybe<&2,String>,info: Skills.SourceInfo) -> V.Value:
  MessageJson.object(MessageJson.field("name",V.Text{name},MessageJson.optionalText("description",description,MessageJson.field("source",V.Text{"extension"},MessageJson.field("sourceInfo",sourceInfoValue(info),Nil{})))))
def extensionCommands(commands: List<&2,ExtensionTypes.ResolvedCommand>,rest: List<&2,V.Value>) -> List<&2,V.Value>:
  match commands:
    case Nil{}: rest
    case ExtensionTypes.ResolvedCommand{_,invocation,info,description,_,_} <> others: extensionCommandValue(invocation,description,info) <> extensionCommands(others,rest)
def registeredCommands(runner: Maybe<&2,ExtensionRunner.ExtensionRunner>) -> IO(List<&2,ExtensionTypes.ResolvedCommand>):
  match runner:
    case None{}: IO.pure(List<&2,ExtensionTypes.ResolvedCommand>,Nil{})
    case Some{runner}: ExtensionRunner.getRegisteredCommands(runner)
def skillCommands(skills: List<&2,Skills.Skill>) -> List<&2,V.Value>:
  match skills:
    case Nil{}: Nil{}
    case Skills.Skill{name,description,_,_,info,_} <> rest: commandValue("skill:" ++ name,description,"skill",info) <> skillCommands(rest)
def templateCommands(templates: List<&2,Templates.PromptTemplate>,skills: List<&2,Skills.Skill>) -> List<&2,V.Value>:
  match templates:
    case Nil{}: skillCommands(skills)
    case Templates.PromptTemplate{name,description,_,_,info,_} <> rest: commandValue(name,description,"prompt",info) <> templateCommands(rest,skills)
def getCommands(handle: Command,id: Maybe<&2,String>) -> IO(Unit):
  match handle:
    case Command{+session,sink,_,_,_,_}:
      do IO<Unit>:
        runner : Maybe<&2,ExtensionRunner.ExtensionRunner> <- Session.extensionRunner(session)
        extensions : List<&2,ExtensionTypes.ResolvedCommand> <- registeredCommands(runner)
        templates : List<&2,Templates.PromptTemplate> <- Session.promptTemplates(session)
        skills : List<&2,Skills.Skill> <- Session.getSkills(session)
        output(sink,data(id,"get_commands",MessageJson.object(MessageJson.field("commands",V.ArrayValue{extensionCommands(extensions,templateCommands(templates,skills))},Nil{}))))
def dispatch(handle: Command,host: Host,id: Maybe<&2,String>,+command: String,+object: R.Record<V.Value>) -> IO(Unit):
  match command:
    case "new_session": newSessionCommand(handle,host,id,optionalText(field(object,"parentSession")))
    case "switch_session": switchSessionCommand(handle,host,id,requiredText(object,"sessionPath"))
    case "fork": forkCommand(handle,host,id,requiredText(object,"entryId"))
    case "clone": cloneCommand(handle,host,id)
    case "get_commands": getCommands(handle,id)
    case "prompt": prompt(handle,id,object)
    case "steer": queued(handle,id,"steer",requiredText(object,"message"),imagesOf(object))
    case "follow_up": queued(handle,id,"follow_up",requiredText(object,"message"),imagesOf(object))
    case "abort": abortCommand(handle,id,False{})
    case "abort_retry": abortCommand(handle,id,True{})
    case "clear_queue": clearQueue(handle,id)
    case "get_messages": currentMessages(handle,id)
    case "get_state": getState(handle,id)
    case "get_available_models": availableModels(handle,id)
    case "set_model": setCatalogModel(handle,id,object)
    case "cycle_model": cycleCatalogModel(handle,id)
    case "set_auto_compaction": setAutoCompaction(handle,id,requiredBoolean(object,"enabled"))
    case "set_auto_retry": setAutoRetry(handle,id,requiredBoolean(object,"enabled"))
    case "bash": bashSubmitted(handle,id,requiredText(object,"command"),optionalBoolean(field(object,"excludeFromContext")))
    case "abort_bash": abortBash(handle,id)
    case "get_session_stats": getSessionStats(handle,id)
    case "export_html": exportHtml(handle,id,optionalText(field(object,"outputPath")))
    case "get_entries": getEntries(handle,id,optionalText(field(object,"since")))
    case "get_tree": getTree(handle,id)
    case "get_fork_messages": getForkMessages(handle,id)
    case "get_last_assistant_text": lastText(handle,id)
    case "compact": compactCommand(handle,id,optionalText(field(object,"customInstructions")))
    case "set_session_name": setName(handle,id,requiredText(object,"name"))
    case "set_thinking_level": setThinking(handle,id,requiredText(object,"level"))
    case "get_available_thinking_levels": availableLevels(handle,id)
    case "cycle_thinking_level": cycleThinking(handle,id)
    case "set_steering_mode": setMode(handle,id,"set_steering_mode",requiredText(object,"mode"))
    case "set_follow_up_mode": setMode(handle,id,"set_follow_up_mode",requiredText(object,"mode"))
    case _: reply(handle,failure(id,command,"Unknown command: " ++ command))
def identified(handle: Command,host: Host,object: R.Record<V.Value>,id: Result<&2,&2,String,Maybe<&2,String>>,kind: Result<&2,&2,String,String>) -> IO(Unit):
  match handle id kind:
    case Command{_,sink,_,_,_,_} Fail{error} _: output(sink,failure(None{},"parse",error))
    case Command{_,sink,_,_,_,_} _ Fail{error}: output(sink,failure(None{},"parse",error))
    case _ Done{id} Done{kind}: dispatch(handle,host,id,kind,object)

def parsed(handle: Command,host: Host,value: Result<&2,&2,Decode.ParseError,V.Value>) -> IO(Unit):
  match handle value:
    case Command{_,sink,_,_,_,_} Fail{_}: output(sink,failure(None{},"parse","Failed to parse command: invalid JSON"))
    case _ Done{V.ObjectValue{+object}}: identified(handle,host,object,idOf(object),requiredText(object,"type"))
    case Command{_,sink,_,_,_,_} Done{_}: output(sink,failure(None{},"parse","Invalid command: expected object"))
def hostOf(handle: Handle) -> Host:
  match handle:
    case Handle{_,_,_,_,_,_,host,_}: host
def command(+handle: Handle,text: String) -> IO(Unit):
  do IO<Unit>:
    view : Command <- commandOf(handle)
    parsed(view,hostOf(handle),Decode.parse(text))
def withoutCR(+value: String) -> String:
  Bool.pick(String,String.ends_with(value,"\r"),String.take(value,String.length(value) - 1n),value)
type Frame is Data: Frame{records: List<&2,String>,pending: String}
def prependRecord(head: String,value: Frame) -> Frame:
  match value:
    case Frame{records,pending}: Frame{withoutCR(head) <> records,pending}
def collect(parts: List<&2,String>) -> Frame:
  match parts:
    case Nil{}: Frame{Nil{},""}
    case tail <> Nil{}: Frame{Nil{},tail}
    case head <> rest: prependRecord(head,collect(rest))
def frame(buffer: String,chunk: String) -> Frame:
  collect(String.split(buffer ++ chunk,'\n'))
def storeTail(handle: Handle,part: String) -> IO(Unit):
  match handle:
    case Handle{_,_,buffer,_,_,_,_,_}: Ref.write(String,buffer,part)
def processRecords(+handle: Handle,parts: List<&2,String>) -> IO(Unit):
  match parts:
    case Nil{}: IO.pure(Unit,Unit{})
    case part <> rest:
      do IO<Unit>:
        command(handle,part)
        processRecords(handle,rest)
def receivedFrame(+handle: Handle,value: Frame) -> IO(Unit):
  match value:
    case Frame{records,pending}:
      do IO<Unit>:
        storeTail(handle,pending)
        processRecords(handle,records)
def feed(+handle: Handle,chunk: String) -> IO(Unit):
  match handle:
    case Handle{_,_,+buffer,_,_,_,_,_}:
      do IO<Unit>:
        pending : String <- Ref.read(String,buffer)
        receivedFrame(handle,frame(pending,chunk))
def finish(+handle: Handle) -> IO(Unit):
  match handle:
    case Handle{_,_,+buffer,_,_,_,_,_}:
      do IO<Unit>:
        +pending : String <- Ref.read(String,buffer)
        Ref.write(String,buffer,"")
        Bool.pick(Unit -> IO(Unit),String.is_empty(pending),_ => IO.pure(Unit,Unit{}),_ => command(handle,withoutCR(pending)))(Unit{})
def stop(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{Handle{+current,_,buffer,busy,jobs,_,_,+listener},+task}:
      do IO<Unit>:
        +session : Session.AgentSession <- Ref.read(Session.AgentSession,current)
        Session.abortBash(session)
        Chan.close(Work,jobs)
        completed : Maybe<&1,Unit> <- Chan.recv(Unit,task)
        Chan.close(Unit,task)
        live : Session.AgentSession <- Ref.dispose(Session.AgentSession,current)
        Session.unsubscribe(live,listener)
        Callback.dispose(Session.AgentSessionEvent,Unit,listener)
        oldBuffer : String <- Ref.dispose(String,buffer)
        oldBusy : Bool <- Ref.dispose(Bool,busy)
        return Unit{}
