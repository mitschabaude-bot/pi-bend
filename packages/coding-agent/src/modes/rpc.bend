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
import ../../../ai/src/types.bend as Ai
import ../core/agent-session.bend as Session
import ./json-event.bend as Events

# pi v0.87.1's headless protocol is LF-delimited JSON objects. The caller owns
# byte transport; this endpoint owns framing, dispatch and event subscriptions.
def Sink() -> Data: Callback.Callback<String,Unit>
type Submission is Data: Submission{text: String,behavior: Maybe<&2,Session.StreamingBehavior>}
type Handle is Data:
  Handle{session: Session.AgentSession,sink: Sink(),buffer: Ref.Ref<String>,busy: Ref.Ref<Bool>,jobs: Chan(Submission)}
type Owner is Type:
  Owner{handle: Handle,worker: Chan(Unit),listener: Session.Listener()}

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
def imagesValue(value: Maybe<&2,V.Value>) -> Result<&2,&2,String,Unit>:
  match value:
    case None{}: Done{Unit{}}
    case Some{V.ArrayValue{Nil{}}}: Done{Unit{}}
    case _: Fail{"Image input is not supported by the native RPC endpoint"}
def noImages(object: R.Record<V.Value>) -> Result<&2,&2,String,Unit>:
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
    case Fail{_}: IO.pure(Unit,Unit{})
def event(sink: Sink(),value: Session.AgentSessionEvent) -> IO(Unit):
  eventValue(sink,Events.toSessionJsonEvent(value))
def observe(sink: Sink(),value: Session.AgentSessionEvent) -> IO(Unit): event(sink,value)

# A prompt response is written before waking this worker. A prompt without a
# streaming behavior is rejected while another is accepted, as upstream does.
def nextJob(handle: Handle) -> IO(Maybe<&1,Submission>):
  match handle:
    case Handle{_,_,_,_,jobs}: Chan.recv(Submission,jobs)
def runJob(handle: Handle,request: Submission) -> IO(Unit):
  match handle request:
    case Handle{session,_,_,busy,_} Submission{text,behavior}:
      do IO<Unit>:
        result : Result<&2,&2,String,Unit> <- Session.prompt(session,text,Nil{},behavior)
        Ref.write(Bool,busy,False{})
type Phase is Type: Check{} Received{request: Maybe<&1,Submission>}
@unsafe def worker(+handle: Handle,phase: Phase) -> IO(Unit):
  match phase:
    case Check{}:
      do IO<Unit>:
        request : Maybe<&1,Submission> <- nextJob(handle)
        worker(handle,Received{request})
    case Received{None{}}: IO.pure(Unit,Unit{})
    case Received{Some{request}}:
      do IO<Unit>:
        runJob(handle,request)
        worker(handle,Check{})
def start(+session: Session.AgentSession,+sink: Sink()) -> IO(Owner & Handle):
  do IO<Owner & Handle>:
    +buffer : Ref.Ref<String> <- Ref.new(String,"")
    +busy : Ref.Ref<Bool> <- Ref.new(Bool,False{})
    +jobs : Chan(Submission) <- Chan.new(Submission,64)
    +handle : Handle <- IO.pure(Handle,Handle{session,sink,buffer,busy,jobs})
    +listener : Session.Listener() <- Callback.create(~Sink(),~Session.AgentSessionEvent,~Unit,~observe,sink)
    Session.subscribe(session,listener)
    task : Chan(Unit) <- IO.fork(Unit,worker(handle,Check{}))
    return (Owner{handle,task,listener},handle)

def acceptedPrompt(session: Session.AgentSession,sink: Sink(),busy: Ref.Ref<Bool>,jobs: Chan(Submission),id: Maybe<&2,String>,text: String,active: Bool,behavior: Maybe<&2,Session.StreamingBehavior>) -> IO(Unit):
  match active behavior:
    case True{} None{}: output(sink,failure(id,"prompt","Agent is already processing. Specify streamingBehavior ('steer' or 'followUp') to queue the message."))
    case True{} Some{Session.Steer{}}:
      do IO<Unit>:
        Session.steer(session,text,Nil{})
        output(sink,ok(id,"prompt"))
    case True{} Some{Session.FollowUp{}}:
      do IO<Unit>:
        Session.followUp(session,text,Nil{})
        output(sink,ok(id,"prompt"))
    case False{} _:
      do IO<Unit>:
        Ref.write(Bool,busy,True{})
        output(sink,ok(id,"prompt"))
        accepted : Bool <- Chan.send(Submission,jobs,Submission{text,behavior})
        return Unit{}

def promptChecked(handle: Handle,id: Maybe<&2,String>,message: Result<&2,&2,String,String>,images: Result<&2,&2,String,Unit>,behavior: Result<&2,&2,String,Maybe<&2,Session.StreamingBehavior>>) -> IO(Unit):
  match handle:
    case Handle{+session,+sink,_,+busy,+jobs}:
      match message images behavior:
        case Fail{error} _ _: output(sink,failure(id,"prompt",error))
        case _ Fail{error} _: output(sink,failure(id,"prompt",error))
        case _ _ Fail{error}: output(sink,failure(id,"prompt",error))
        case Done{text} Done{_} Done{behavior}:
          do IO<Unit>:
            active : Bool <- Ref.read(Bool,busy)
            streaming : Bool <- Session.isStreaming(session)
            acceptedPrompt(session,sink,busy,jobs,id,text,active || streaming,behavior)
def prompt(handle: Handle,id: Maybe<&2,String>,+object: R.Record<V.Value>) -> IO(Unit):
  promptChecked(handle,id,requiredText(object,"message"),noImages(object),behaviorOf(object))
def commandFailure(handle: Handle,id: Maybe<&2,String>,command: String,error: String) -> IO(Unit):
  match handle:
    case Handle{_,sink,_,_,_}: output(sink,failure(id,command,error))
def queueText(handle: Handle,id: Maybe<&2,String>,+command: String,+text: String) -> IO(Unit):
  match handle:
    case Handle{+session,sink,_,_,_}:
      do IO<Unit>:
        Bool.pick(Unit -> IO(Unit),String.eq(command,"steer"),_ => Session.steer(session,text,Nil{}),_ => Session.followUp(session,text,Nil{}))(Unit{})
        output(sink,ok(id,command))
def queued(handle: Handle,id: Maybe<&2,String>,+command: String,message: Result<&2,&2,String,String>,images: Result<&2,&2,String,Unit>) -> IO(Unit):
  match message images:
    case Fail{error} _: commandFailure(handle,id,command,error)
    case _ Fail{error}: commandFailure(handle,id,command,error)
    case Done{text} Done{_}: queueText(handle,id,command,text)
def setCleanName(session: Session.AgentSession,sink: Sink(),id: Maybe<&2,String>,name: String) -> IO(Unit):
  match name:
    case "": output(sink,failure(id,"set_session_name","Session name cannot be empty"))
    case _:
      do IO<Unit>:
        result : Result<&2,&2,String,Unit> <- Session.setSessionName(session,name)
        output(sink,resultResponse(id,"set_session_name",result))
def setName(handle: Handle,id: Maybe<&2,String>,value: Result<&2,&2,String,String>) -> IO(Unit):
  match handle value:
    case Handle{_,sink,_,_,_} Fail{error}: output(sink,failure(id,"set_session_name",error))
    case Handle{session,sink,_,_,_} Done{name}: setCleanName(session,sink,id,String.trim(name))
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
        result : Result<&2,&2,String,Unit> <- Session.setThinkingLevel(session,value)
        output(sink,resultResponse(id,"set_thinking_level",result))

def setThinking(handle: Handle,id: Maybe<&2,String>,value: Result<&2,&2,String,String>) -> IO(Unit):
  match handle value:
    case Handle{_,sink,_,_,_} Fail{error}: output(sink,failure(id,"set_thinking_level",error))
    case Handle{session,sink,_,_,_} Done{+level}: setChosenThinking(session,sink,id,level,thinking(level))
def reply(handle: Handle,value: V.Value) -> IO(Unit):
  match handle:
    case Handle{_,sink,_,_,_}: output(sink,value)
def abortCommand(handle: Handle,id: Maybe<&2,String>,+retry: Bool) -> IO(Unit):
  match handle:
    case Handle{+session,sink,_,_,_}:
      do IO<Unit>:
        Bool.pick(Unit -> IO(Unit),retry,_ => Session.abortRetry(session),_ => Session.abort(session))(Unit{})
        output(sink,ok(id,Bool.pick(String,retry,"abort_retry","abort")))
def currentMessages(handle: Handle,id: Maybe<&2,String>) -> IO(Unit):
  match handle:
    case Handle{session,sink,_,_,_}:
      do IO<Unit>:
        messages : List<&2,Session.Message()> <- Session.messages(session)
        output(sink,data(id,"get_messages",MessageJson.object(MessageJson.field("messages",V.ArrayValue{messageValues(messages)},Nil{}))))
def lastText(handle: Handle,id: Maybe<&2,String>) -> IO(Unit):
  match handle:
    case Handle{session,sink,_,_,_}:
      do IO<Unit>:
        last : Maybe<&2,String> <- Session.getLastAssistantText(session)
        output(sink,data(id,"get_last_assistant_text",MessageJson.object(MessageJson.field("text",optionalValue(last),Nil{}))))
def dispatch(handle: Handle,id: Maybe<&2,String>,+command: String,+object: R.Record<V.Value>) -> IO(Unit):
  match command:
    case "prompt": prompt(handle,id,object)
    case "steer": queued(handle,id,"steer",requiredText(object,"message"),noImages(object))
    case "follow_up": queued(handle,id,"follow_up",requiredText(object,"message"),noImages(object))
    case "abort": abortCommand(handle,id,False{})
    case "abort_retry": abortCommand(handle,id,True{})
    case "get_messages": currentMessages(handle,id)
    case "get_last_assistant_text": lastText(handle,id)
    case "set_session_name": setName(handle,id,requiredText(object,"name"))
    case "set_thinking_level": setThinking(handle,id,requiredText(object,"level"))
    case _: reply(handle,failure(id,command,"Unknown command: " ++ command))
def identified(handle: Handle,object: R.Record<V.Value>,id: Result<&2,&2,String,Maybe<&2,String>>,kind: Result<&2,&2,String,String>) -> IO(Unit):
  match handle id kind:
    case Handle{_,sink,_,_,_} Fail{error} _: output(sink,failure(None{},"parse",error))
    case Handle{_,sink,_,_,_} _ Fail{error}: output(sink,failure(None{},"parse",error))
    case _ Done{id} Done{kind}: dispatch(handle,id,kind,object)

def parsed(handle: Handle,value: Result<&2,&2,Decode.ParseError,V.Value>) -> IO(Unit):
  match handle value:
    case Handle{_,sink,_,_,_} Fail{_}: output(sink,failure(None{},"parse","Failed to parse command: invalid JSON"))
    case _ Done{V.ObjectValue{+object}}: identified(handle,object,idOf(object),requiredText(object,"type"))
    case Handle{_,sink,_,_,_} Done{_}: output(sink,failure(None{},"parse","Invalid command: expected object"))
def command(handle: Handle,text: String) -> IO(Unit):
  parsed(handle,Decode.parse(text))
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
    case Handle{_,_,buffer,_,_}: Ref.write(String,buffer,part)
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
    case Handle{_,_,+buffer,_,_}:
      do IO<Unit>:
        pending : String <- Ref.read(String,buffer)
        receivedFrame(handle,frame(pending,chunk))
def finish(+handle: Handle) -> IO(Unit):
  match handle:
    case Handle{_,_,+buffer,_,_}:
      do IO<Unit>:
        +pending : String <- Ref.read(String,buffer)
        Ref.write(String,buffer,"")
        Bool.pick(Unit -> IO(Unit),String.is_empty(pending),_ => IO.pure(Unit,Unit{}),_ => command(handle,withoutCR(pending)))(Unit{})
def stop(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{Handle{session,_,buffer,busy,jobs},+task,+listener}:
      do IO<Unit>:
        Chan.close(Submission,jobs)
        completed : Maybe<&1,Unit> <- Chan.recv(Unit,task)
        Chan.close(Unit,task)
        Session.unsubscribe(session,listener)
        Callback.dispose(Session.AgentSessionEvent,Unit,listener)
        oldBuffer : String <- Ref.dispose(String,buffer)
        oldBusy : Bool <- Ref.dispose(Bool,busy)
        return Unit{}
