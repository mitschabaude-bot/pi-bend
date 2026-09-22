import Base
import ../../../agent/src/agent.bend as Agent
import ../../../agent/src/agent-loop.bend as Loop
import ../../../agent/src/types.bend as T
import ../../../ai/src/types.bend as Ai
import ../../../ai/src/utils/json.bend as Json
import ../../../ai/src/utils/schema-json.bend as SchemaJson
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/callback.bend as C
import ../core/agent-runtime.bend as Runtime
import ../core/tools/index.bend as Tools
import ../cli/args.bend as Args
import ./json-event.bend as JsonEvent
import ../core/session-manager.bend as S
import ../core/session-json.bend as SessionJson

# Print mode (single-shot): send prompts, output the result, exit.
#   pi -p "prompt"          text output
#   pi --mode json "prompt" JSON event stream
# SIGTERM/SIGHUP exits (143/129) need a signal primitive the runtime lacks.

type PrintModeOptions is Data:
  PrintModeOptions{mode: Args.Mode, messages: List<&2, String>, initialMessage: Maybe<&2, String>, initialImages: List<&2, Ai.ImageContent>, header: S.SessionHeader}

def SessionEvent() -> Data: JsonEvent.SessionEvent()
def Emission() -> Type: Loop.Emission<Runtime.Error()>

def line(value: V.Value) -> String:
  Maybe.default(&2, String, Json.stringify(SchemaJson.toJson(value)), "null") ++ "\n"

def written(result: Result<&2, &2, String, V.Value>) -> IO(Unit):
  match result:
    case Done{value}: IO.write(line(value))
    case Fail{error}: IO.print_err(error)

def ready() -> Emission(): Loop.EmissionReady{Done{Unit{}}}

# JSON mode writes every session event as one line; text mode observes nothing.
def emit(mode: Args.Mode, input: Agent.Input<SessionEvent()>) -> IO(Emission()):
  match mode input:
    case Args.Json{} Agent.Input{event, _}:
      do IO<Emission()>:
        written(JsonEvent.toJsonEvent(event))
        return ready()
    case _ _: IO.pure(Emission(), ready())

def field(key: String, value: V.Value, rest: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<V.Value>>:
  R.Property{key, value} <> rest

# The session header line: the session manager's header, as JSON.stringify
# renders it; an in-memory session has one too.
def header(value: S.SessionHeader) -> IO(Unit):
  IO.write(line(SessionJson.header(value)))

def promptError(error: Agent.AgentError<Runtime.Error()>) -> String:
  match error:
    case Agent.ClaimFailed{message}: message
    case Agent.DeliveryFailed{Agent.OutsideRun{message}}: message
    case Agent.DeliveryFailed{Agent.ListenerFailed{cause}}: Tools.errorMessage(cause)

def settled(agent: Runtime.Owner(), result: Result<&2, &2, Agent.AgentError<Runtime.Error()>, Unit>) -> IO(Result<&2, &2, String, Unit>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, String, Unit>, Fail{promptError(error)})
    case Done{Unit{}}:
      do IO<Result<&2, &2, String, Unit>>:
        Agent.waitForIdle(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        return Done{Unit{}}

# Each prompt runs to completion before the next, as session.prompt awaits.
def send(+agent: Runtime.Owner(), text: String, images: List<&2, Ai.ImageContent>) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    result : Result<&2, &2, Agent.AgentError<Runtime.Error()>, Unit> <- Agent.prompt(~Unit, ~Runtime.Details(), ~Runtime.Custom(), ~Runtime.Error(), ~Unit, ~Runtime.render, ~Runtime.fromString, ~Runtime.declarationError, agent, Agent.Text{text, images})
    settled(agent, result)

def sendAll(+agent: Runtime.Owner(), messages: List<&2, String>, previous: Result<&2, &2, String, Unit>) -> IO(Result<&2, &2, String, Unit>):
  match messages previous:
    case _ Fail{error}: IO.pure(Result<&2, &2, String, Unit>, Fail{error})
    case Nil{} Done{Unit{}}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case message <> rest Done{Unit{}}:
      do IO<Result<&2, &2, String, Unit>>:
        result : Result<&2, &2, String, Unit> <- send(agent, message, Nil{})
        sendAll(agent, rest, result)

def sendInitial(+agent: Runtime.Owner(), initial: Maybe<&2, String>, images: List<&2, Ai.ImageContent>) -> IO(Result<&2, &2, String, Unit>):
  match initial:
    case None{}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case Some{text}: send(agent, text, images)

def Message() -> Data: T.AgentMessage<Unit, Runtime.Details(), Runtime.Custom()>

def lastAssistant(last: Maybe<&2, Message()>) -> Maybe<&2, Ai.AssistantMessage<V.Value, Unit>>:
  match last:
    case Some{T.LlmMessage{Ai.Assistant{message}}}: Some{message}
    case _: None{}

def stateMessages(state: T.AgentState<Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error()>) -> List<&2, Message()>:
  match state:
    case T.AgentState{_, _, _, messages, _, _, _, _}: messages

def texts(content: List<&2, Ai.AssistantContent<V.Value>>) -> IO(Unit):
  match content:
    case Nil{}: IO.pure(Unit, Unit{})
    case Ai.AssistantText{Ai.TextContent{text, _}} <> rest:
      do IO<Unit>:
        IO.write(text ++ "\n")
        texts(rest)
    case _ <> rest: texts(rest)

def requestFailed(reason: String, message: Maybe<&2, String>) -> IO(U32):
  do IO<U32>:
    IO.print_err(Maybe.default(&2, String, message, "Request " ++ reason))
    return 1

# Text mode prints the final assistant text; an error or abort goes to
# stderr with exit code 1.
def textOutput(message: Maybe<&2, Ai.AssistantMessage<V.Value, Unit>>) -> IO(U32):
  match message:
    case Some{Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, Ai.Error{}, _, error, _, _, _}}: requestFailed("error", error)
    case Some{Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, Ai.Aborted{}, _, error, _, _, _}}: requestFailed("aborted", error)
    case Some{Ai.AssistantMessage{content, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}:
      do IO<U32>:
        texts(content)
        return 0
    case None{}: IO.pure(U32, 0)

def finish(mode: Args.Mode, agent: Runtime.Owner(), sent: Result<&2, &2, String, Unit>) -> IO(U32):
  match mode sent:
    case _ Fail{error}:
      do IO<U32>:
        IO.print_err(error)
        return 1
    case Args.Text{} Done{Unit{}}:
      do IO<U32>:
        state : T.AgentState<Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error()> <- Agent.state(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        textOutput(lastAssistant(List.last(&2, Message(), stateMessages(state))))
    case _ Done{Unit{}}: IO.pure(U32, 0)

def writeHeader(mode: Args.Mode, value: S.SessionHeader) -> IO(Unit):
  match mode:
    case Args.Json{}: header(value)
    case _: IO.pure(Unit, Unit{})

def runPrintMode(+agent: Runtime.Owner(), options: PrintModeOptions) -> IO(U32):
  match options:
    case PrintModeOptions{+mode, messages, initialMessage, initialImages, sessionHeader}:
      do IO<U32>:
        writeHeader(mode, sessionHeader)
        +listener : Agent.Handler(SessionEvent(), Runtime.Error()) <- C.create(~Args.Mode, ~Agent.Input<SessionEvent()>, ~Emission(), ~emit, mode)
        subscription : Agent.Subscription<SessionEvent(), Runtime.Error()> <- Agent.subscribe(Unit, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent, listener)
        first : Result<&2, &2, String, Unit> <- sendInitial(agent, initialMessage, initialImages)
        sent : Result<&2, &2, String, Unit> <- sendAll(agent, messages, first)
        code : U32 <- finish(mode, agent, sent)
        Agent.unsubscribe(SessionEvent(), Runtime.Error(), subscription)
        C.dispose(Agent.Input<SessionEvent()>, Emission(), listener)
        return code
