import Base
import ../src/api/google-generative-ai.bend as Google
import ../src/api/google-generative-ai-client.bend as Client
import ../src/api/google-generative-ai-stream.bend as Fold
import ../src/types.bend as T
import ../src/utils/event-stream.bend as Events
import ../src/utils/transcript.bend as Transcript
import ./anthropic-harness.bend as A
import ./anthropic-messages-client.bend as Network
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/callback.bend as C
import ../../runtime/src/f64.bend as F
import ../../runtime/src/fetch.bend as Fetch
import ../../runtime/src/record.bend as R
import ../../runtime/src/ref.bend as Ref
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/sse.bend as Body

# Native stand-ins for the Google suites' seams: onPayload captures the SDK
# parameters (and fails the request), a recording fetch observes the SDK's
# wire request, and a response body is streamed through the client's body
# loop (the SDK takes no injected client; upstream mocks the module or the
# global fetch). Generic JSON assertions come from the Anthropic harness.
def J() -> Data: T.JsonValue

def Options() -> Data: Client.Options(Unit, Unit, String)

def Simple() -> Data: T.SimpleStreamOptions<J(), Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), String>

def Message() -> Data: T.AssistantMessage<V.Value, Unit>

def Event() -> Data: T.AssistantMessageEvent<V.Value, Unit>

def Context() -> Data: T.TranscriptContext<V.Value, V.Value, Unit, Unit>

type Mode is Data:
  Capture{}
  Send{}
  Respond{chunks: List<&2, String>}

type Outcome is Data:
  Outcome{message: Message(), payload: Maybe<&2, J()>, request: Maybe<&2, Fetch.Input<Unit>>, events: List<&2, Event()>}

def context(messages: List<&2, T.Message<V.Value, V.Value, Unit, Unit>>) -> Context():
  Transcript.normalizeContext(V.Value, V.Value, Unit, Unit, T.Context{None{}, messages, None{}})

def user(content: String) -> T.Message<V.Value, V.Value, Unit, Unit>: T.User{T.UserMessage{T.UserText{content}, F.fromU32(1)}}

def hello() -> Context(): context(user("Hello") <> Nil{})

def simple(apiKey: Maybe<&2, String>, reasoning: Maybe<&2, T.ThinkingLevel>, budgets: Maybe<&2, T.ThinkingBudgets>, headers: Maybe<&2, T.ProviderHeaders()>) -> Simple():
  T.SimpleStreamOptions{None{}, None{}, apiKey, None{}, None{}, None{}, None{}, headers, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, reasoning, None{}, budgets}

def withHook(options: Options(), hook: Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, String)>) -> Options():
  match options:
    case Google.GoogleOptions{T.StreamOptions{signal, telemetry, key, fetch, env, previous, response, headers, timeout, retries, delay, temperature, sampling, maxTokens, transport, cache, session, ws, metadata}, choice, thinking}:
      Google.GoogleOptions{T.StreamOptions{signal, telemetry, key, fetch, env, Maybe.or(&2, T.PayloadCallback(J(), T.Model<J()>, String), hook, previous), response, headers, timeout, retries, delay, temperature, sampling, maxTokens, transport, cache, session, ws, metadata}, choice, thinking}

def optionalHook(mode: Mode, hook: T.PayloadCallback(J(), T.Model<J()>, String)) -> Maybe<&2, T.PayloadCallback(J(), T.Model<J()>, String)>:
  match mode:
    case Capture{}: Some{hook}
    case _: None{}

def chunksOf(mode: Mode) -> List<&2, String>:
  match mode:
    case Respond{chunks}: chunks
    case _: Nil{}

@unsafe def collect(next: Events.Iteration<Event()>, +cursor: Events.Iterator<Event(), Message()>, reversed: List<&2, Event()>) -> IO(List<&2, Event()>):
  match next:
    case Events.Yield{event}:
      do IO<List<&2, Event()>>:
        following : Events.Iteration<Event()> <- Events.nextValue(Event(), Message(), cursor)
        collect(following, cursor, event <> reversed)
    case Events.End{}:
      do IO<List<&2, Event()>>:
        Events.disposeIterator(Event(), Message(), cursor)
        return List.reverse(&2, Event(), reversed)

def source(chunks: Ref.Ref<List<&2, String>>) -> IO(Body.Source<String>):
  do IO<Body.Source<String>>:
    +next : C.Callback<Unit, Result<&2, &2, String, Maybe<&2, Body.Chunk>>> <- C.create(~Ref.Ref<List<&2, String>>, ~Unit, ~Result<&2, &2, String, Maybe<&2, Body.Chunk>>, ~A.nextChunk, chunks)
    +close : C.Callback<Unit, Result<&2, &2, String, Unit>> <- C.create(~Unit, ~Unit, ~Result<&2, &2, String, Unit>, ~A.closeChunks, Unit{})
    return Body.Source{next, close}

def payloadOf(outcome: Outcome) -> Maybe<&2, J()>:
  match outcome:
    case Outcome{_, payload, _, _}: payload

def requestOf(outcome: Outcome) -> Maybe<&2, Fetch.Input<Unit>>:
  match outcome:
    case Outcome{_, _, request, _}: request

def messageOf(outcome: Outcome) -> Message():
  match outcome:
    case Outcome{message, _, _, _}: message

def eventsOf(outcome: Outcome) -> List<&2, Event()>:
  match outcome:
    case Outcome{_, _, _, events}: events

def errorMessage(message: Message()) -> Maybe<&2, String>: T.assistantErrorMessage(V.Value, Unit, message)

def rawStopReason(message: Message()) -> Maybe<&2, String>:
  match message:
    case T.AssistantMessage{_, _, _, _, _, _, _, _, _, _, _, _, value, _, _}: value

def stopName(message: Message()) -> String: A.stopName(T.assistantStopReason(V.Value, Unit, message))

def equalStop(+message: Message(), +want: String) -> IO(Unit):
  +actual = stopName(message)
  A.check(String.eq(actual, want), "stopReason " ++ actual ++ " != " ++ want ++ " (" ++ A.showMaybe(errorMessage(message)) ++ ")")

def hasToolCall(blocks: List<&2, T.AssistantContent<V.Value>>) -> Bool:
  match blocks:
    case Nil{}: False{}
    case T.AssistantToolCall{_} <> _: True{}
    case _ <> rest: hasToolCall(rest)

def toolCalled(message: Message()) -> Bool: hasToolCall(T.assistantContent(V.Value, Unit, message))

# A model like the suites' makeModel.
def model(api: T.ModelApi, id: String, name: String, provider: String, base: String, images: Bool, maxTokens: U32, window: U32, levels: Maybe<&2, T.ThinkingLevelMap>) -> T.Model<J()>:
  T.Model{id, name, api, provider, base, True{}, levels, Bool.pick(List<&2, T.ModelInput>, images, T.InputText{} <> T.InputImage{} <> Nil{}, T.InputText{} <> Nil{}), None{}, A.zeroCost(), None{}, F.fromU32(window), F.fromU32(maxTokens), None{}, None{}, None{}}

def fromSimple(+model: T.Model<J()>, +context: Context(), options: Simple()) -> Result<&2, &2, String, Options()>:
  Google.streamSimpleOptions(~Unit, ~Unit, ~Abort.AbortSignal<Unit>, ~Unit, ~Fetch.Fetch(Unit), ~String, model, context, Some{options})

def produce(+model: T.Model<J()>, +context: Context(), options: Options(), mode: Mode, +events: Events.AssistantMessageEventStream(V.Value, Unit), +signal: Abort.AbortSignal<Unit>, setup: Client.Setup<Unit>, chunks: Ref.Ref<List<&2, String>>) -> IO(Unit):
  match mode:
    case Respond{_}:
      do IO<Unit>:
        +body : Body.Source<String> <- source(chunks)
        Client.streamBody(~Unit, ~String, ~Unit, ~(message => message), events, body, signal, Fold.create(Unit, model, F.fromU32(1)), None{})
    case _: Client.stream(~Unit, ~Unit, ~String, ~Unit, ~Unit, ~(message => message), events, signal, setup, model, context, options, F.fromU32(1))

# One run through the given seam; the result is the final message.
def run(+model: T.Model<J()>, +context: Context(), options: Options(), +mode: Mode) -> IO(Outcome):
  do IO<Outcome>:
    +payload : Ref.Ref<Maybe<&2, J()>> <- Ref.new(Maybe<&2, J()>, None{})
    +chunks : Ref.Ref<List<&2, String>> <- Ref.new(List<&2, String>, chunksOf(mode))
    +request : Ref.Ref<Maybe<&2, Fetch.Input<Unit>>> <- Ref.new(Maybe<&2, Fetch.Input<Unit>>, None{})
    +hook : T.PayloadCallback(J(), T.Model<J()>, String) <- C.create(~Ref.Ref<Maybe<&2, J()>>, ~T.PayloadInput<J(), T.Model<J()>>, ~Result<&2, &2, String, Maybe<&2, J()>>, ~A.capturePayload, payload)
    +fetch : Fetch.Fetch(Unit) <- C.create(~Ref.Ref<Maybe<&2, Fetch.Input<Unit>>>, ~Fetch.Input<Unit>, ~Fetch.Result_(Unit), ~A.recordFetch, request)
    +events : Events.AssistantMessageEventStream(V.Value, Unit) <- Events.createAssistantMessageEventStream(~V.Value, ~Unit)
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    agent : String <- A.piUserAgent()
    calls : Ref.Ref<Nat> <- Ref.new(Nat, 0n)
    produce(model, context, withHook(options, optionalHook(mode, hook)), mode, events, Abort.signal(Unit, controller), Client.Setup{Network.urlContext(), agent, fetch, calls}, chunks)
    +cursor : Events.Iterator<Event(), Message()> <- Events.iterator(Event(), Message(), events)
    first : Events.Iteration<Event()> <- Events.nextValue(Event(), Message(), cursor)
    emitted : List<&2, Event()> <- collect(first, cursor, Nil{})
    message : Message() <- Events.resultValue(Event(), Message(), events)
    captured : Maybe<&2, J()> <- Ref.read(Maybe<&2, J()>, payload)
    recorded : Maybe<&2, Fetch.Input<Unit>> <- Ref.read(Maybe<&2, Fetch.Input<Unit>>, request)
    Abort.dispose(Unit, controller)
    return Outcome{message, captured, recorded, emitted}

# upstream `stream` options: an API key and headers.
def direct(apiKey: Maybe<&2, String>, headers: Maybe<&2, T.ProviderHeaders()>) -> Options():
  Google.GoogleOptions{T.StreamOptions{None{}, None{}, apiKey, None{}, None{}, None{}, None{}, headers, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}, None{}, None{}}

def contextWith(systemPrompt: Maybe<&2, String>, messages: List<&2, T.Message<V.Value, V.Value, Unit, Unit>>, tools: Maybe<&2, List<&2, T.Tool<V.Value>>>) -> Context():
  Transcript.normalizeContext(V.Value, V.Value, Unit, Unit, T.Context{systemPrompt, messages, tools})

def simpleSelected(+model: T.Model<J()>, +context: Context(), selected: Result<&2, &2, String, Options()>, +mode: Mode) -> IO(Outcome):
  match selected:
    case Fail{message}: IO.die(Outcome, 1, "streamSimple threw: " ++ message)
    case Done{options}: run(model, context, options, mode)

# A streamSimple run whose options are expected to be accepted.
def runSimple(+model: T.Model<J()>, +context: Context(), options: Simple(), +mode: Mode) -> IO(Outcome):
  simpleSelected(model, context, fromSimple(model, context, options), mode)

# fetch-option: the setup's process fetch stands for globalThis.fetch; the
# request passes either that handle or a distinct custom one as options.fetch.
type FetchOutcome is Data:
  FetchOutcome{message: Message(), ambient: Maybe<&2, Fetch.Input<Unit>>, custom: Maybe<&2, Fetch.Input<Unit>>}

def withFetch(options: Options(), fetch: Fetch.Fetch(Unit)) -> Options():
  match options:
    case Google.GoogleOptions{T.StreamOptions{signal, telemetry, key, _, env, payload, response, headers, timeout, retries, delay, temperature, sampling, maxTokens, transport, cache, session, ws, metadata}, choice, thinking}:
      Google.GoogleOptions{T.StreamOptions{signal, telemetry, key, Some{fetch}, env, payload, response, headers, timeout, retries, delay, temperature, sampling, maxTokens, transport, cache, session, ws, metadata}, choice, thinking}

def fetchRun(+model: T.Model<J()>, +context: Context(), useAmbient: Bool) -> IO(FetchOutcome):
  do IO<FetchOutcome>:
    +ambientSeen : Ref.Ref<Maybe<&2, Fetch.Input<Unit>>> <- Ref.new(Maybe<&2, Fetch.Input<Unit>>, None{})
    +customSeen : Ref.Ref<Maybe<&2, Fetch.Input<Unit>>> <- Ref.new(Maybe<&2, Fetch.Input<Unit>>, None{})
    +ambient : Fetch.Fetch(Unit) <- C.create(~Ref.Ref<Maybe<&2, Fetch.Input<Unit>>>, ~Fetch.Input<Unit>, ~Fetch.Result_(Unit), ~A.recordFetch, ambientSeen)
    +custom : Fetch.Fetch(Unit) <- C.create(~Ref.Ref<Maybe<&2, Fetch.Input<Unit>>>, ~Fetch.Input<Unit>, ~Fetch.Result_(Unit), ~A.recordFetch, customSeen)
    +events : Events.AssistantMessageEventStream(V.Value, Unit) <- Events.createAssistantMessageEventStream(~V.Value, ~Unit)
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    agent : String <- A.piUserAgent()
    calls : Ref.Ref<Nat> <- Ref.new(Nat, 0n)
    Client.stream(~Unit, ~Unit, ~String, ~Unit, ~Unit, ~(message => message), events, Abort.signal(Unit, controller), Client.Setup{Network.urlContext(), agent, ambient, calls}, model, context, withFetch(direct(Some{"test-key"}, None{}), Bool.pick(Fetch.Fetch(Unit), useAmbient, ambient, custom)), F.fromU32(1))
    +cursor : Events.Iterator<Event(), Message()> <- Events.iterator(Event(), Message(), events)
    first : Events.Iteration<Event()> <- Events.nextValue(Event(), Message(), cursor)
    emitted : List<&2, Event()> <- collect(first, cursor, Nil{})
    message : Message() <- Events.resultValue(Event(), Message(), events)
    ambientRequest : Maybe<&2, Fetch.Input<Unit>> <- Ref.read(Maybe<&2, Fetch.Input<Unit>>, ambientSeen)
    customRequest : Maybe<&2, Fetch.Input<Unit>> <- Ref.read(Maybe<&2, Fetch.Input<Unit>>, customSeen)
    Abort.dispose(Unit, controller)
    return FetchOutcome{message, ambientRequest, customRequest}

# A response body streamed with a shared tool-call id counter (the process
# counter that upstream keeps in a module variable).
def respondShared(+model: T.Model<J()>, chunks: List<&2, String>, counter: Ref.Ref<Nat>) -> IO(Message()):
  do IO<Message()>:
    +pending : Ref.Ref<List<&2, String>> <- Ref.new(List<&2, String>, chunks)
    +events : Events.AssistantMessageEventStream(V.Value, Unit) <- Events.createAssistantMessageEventStream(~V.Value, ~Unit)
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    +body : Body.Source<String> <- source(pending)
    Client.streamBody(~Unit, ~String, ~Unit, ~(message => message), events, body, Abort.signal(Unit, controller), Fold.create(Unit, model, F.fromU32(1)), Some{counter})
    +cursor : Events.Iterator<Event(), Message()> <- Events.iterator(Event(), Message(), events)
    first : Events.Iteration<Event()> <- Events.nextValue(Event(), Message(), cursor)
    emitted : List<&2, Event()> <- collect(first, cursor, Nil{})
    message : Message() <- Events.resultValue(Event(), Message(), events)
    Abort.dispose(Unit, controller)
    return message
