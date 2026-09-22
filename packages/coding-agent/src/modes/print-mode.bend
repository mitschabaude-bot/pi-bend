import Base
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
import ../core/session-persistence.bend as Sessions
import ../core/agent-session.bend as Session

# Print mode (single-shot): send prompts, output the result, exit.
#   pi -p "prompt"          text output
#   pi --mode json "prompt" JSON event stream
# SIGTERM/SIGHUP exits (143/129) need a signal primitive the runtime lacks;
# the extension session_shutdown event waits for the extension runner.

type PrintModeOptions is Data:
  PrintModeOptions{mode: Args.Mode, messages: List<&2, String>, initialMessage: Maybe<&2, String>, initialImages: List<&2, Ai.ImageContent>}

def line(value: V.Value) -> String:
  Maybe.default(&2, String, Json.stringify(SchemaJson.toJson(value)), "null") ++ "\n"

def written(result: Result<&2, &2, String, V.Value>) -> IO(Unit):
  match result:
    case Done{value}: IO.write(line(value))
    case Fail{error}: IO.print_err(error)

# JSON mode writes every session event as one line; text mode observes nothing.
def emit(mode: Args.Mode, event: Session.AgentSessionEvent) -> IO(Unit):
  match mode:
    case Args.Json{}: written(JsonEvent.toSessionJsonEvent(event))
    case _: IO.pure(Unit, Unit{})

# The session header line: the session manager's header, as JSON.stringify
# renders it; an in-memory session has one too.
def header(value: S.SessionHeader) -> IO(Unit):
  IO.write(line(SessionJson.header(value)))

# Each prompt runs to completion before the next, as session.prompt awaits.
def sendAll(+session: Session.AgentSession, messages: List<&2, String>, previous: Result<&2, &2, String, Unit>) -> IO(Result<&2, &2, String, Unit>):
  match messages previous:
    case _ Fail{error}: IO.pure(Result<&2, &2, String, Unit>, Fail{error})
    case Nil{} Done{Unit{}}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case message <> rest Done{Unit{}}:
      do IO<Result<&2, &2, String, Unit>>:
        result : Result<&2, &2, String, Unit> <- Session.prompt(session, message, Nil{}, None{})
        sendAll(session, rest, result)

def sendInitial(+session: Session.AgentSession, initial: Maybe<&2, String>, images: List<&2, Ai.ImageContent>) -> IO(Result<&2, &2, String, Unit>):
  match initial:
    case None{}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case Some{text}: Session.prompt(session, text, images, None{})

def lastAssistant(last: Maybe<&2, Session.Message()>) -> Maybe<&2, Ai.AssistantMessage<V.Value, Unit>>:
  match last:
    case Some{T.LlmMessage{Ai.Assistant{message}}}: Some{message}
    case _: None{}

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

def finish(mode: Args.Mode, session: Session.AgentSession, sent: Result<&2, &2, String, Unit>) -> IO(U32):
  match mode sent:
    case _ Fail{error}:
      do IO<U32>:
        IO.print_err(error)
        return 1
    case Args.Text{} Done{Unit{}}:
      do IO<U32>:
        messages : List<&2, Session.Message()> <- Session.messages(session)
        textOutput(lastAssistant(List.last(&2, Session.Message(), messages)))
    case _ Done{Unit{}}: IO.pure(U32, 0)

def writeHeader(mode: Args.Mode, value: S.SessionHeader) -> IO(Unit):
  match mode:
    case Args.Json{}: header(value)
    case _: IO.pure(Unit, Unit{})

def headerOf(+session: Session.AgentSession) -> IO(S.SessionHeader):
  do IO<S.SessionHeader>:
    stored : Session.Session() <- Session.sessionOf(session)
    return S.getHeader(Unit, Tools.ToolDetails, V.Value, Sessions.stateOf(Unit, Tools.ToolDetails, V.Value, stored))

def observe(mode: Args.Mode, event: Session.AgentSessionEvent) -> IO(Unit): emit(mode, event)

def runPrintMode(+session: Session.AgentSession, options: PrintModeOptions) -> IO(U32):
  match options:
    case PrintModeOptions{+mode, messages, initialMessage, initialImages}:
      do IO<U32>:
        sessionHeader : S.SessionHeader <- headerOf(session)
        writeHeader(mode, sessionHeader)
        +listener : Session.Listener() <- C.create(~Args.Mode, ~Session.AgentSessionEvent, ~Unit, ~observe, mode)
        Session.subscribe(session, listener)
        first : Result<&2, &2, String, Unit> <- sendInitial(session, initialMessage, initialImages)
        sent : Result<&2, &2, String, Unit> <- sendAll(session, messages, first)
        code : U32 <- finish(mode, session, sent)
        Session.unsubscribe(session, listener)
        C.dispose(Session.AgentSessionEvent, Unit, listener)
        return code
