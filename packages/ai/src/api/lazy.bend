import Base
import ../types.bend as T
import ../utils/event-stream.bend as Events
import ../utils/model-api.bend as Api
import ../auth/resolve.bend as Resolve
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/date.bend as Date

# A native stream owns its worker and event storage. Release waits for setup,
# forwarding and the inner provider's cleanup before retiring that storage.
def Event() -> Data: T.AssistantMessageEvent<V.Value, V.Value>
def Message() -> Data: T.AssistantMessage<V.Value, V.Value>
def Stream() -> Data: Events.AssistantMessageEventStream(V.Value, V.Value)
def Released() -> Data: Result<&2, &2, Resolve.ModelsError, Unit>

type StreamLease is Type:
  StreamLease{events: Stream(), release: IO(Released())}

def OpenResult() -> Type: Result<&2, &1, Resolve.ModelsError, StreamLease>

def setupError(model: T.Model<T.JsonValue>, message: String, timestamp: F64) -> Message():
  match model:
    case T.Model{id, _, api, provider, _, _, _, _, _, _, _, _, _, _, _, _}:
      T.AssistantMessage{Nil{}, Api.name(api), provider, id, None{}, None{}, None{}, None{}, T.Usage{U32.to_f64(0), U32.to_f64(0), U32.to_f64(0), U32.to_f64(0), None{}, None{}, U32.to_f64(0), T.UsageCost{U32.to_f64(0), U32.to_f64(0), U32.to_f64(0), U32.to_f64(0), U32.to_f64(0)}}, T.Error{}, None{}, Some{message}, None{}, None{}, timestamp}

@unsafe def forward(+target: Stream(), +source: Stream(), +cursor: Events.Iterator<Event(), Message()>, step: Events.Iteration<Event()>) -> IO(Unit):
  match step:
    case Events.End{}:
      do IO<Unit>:
        message : Message() <- Events.resultValue(Event(), Message(), source)
        Events.end(Event(), Message(), target, Some{message})
        Events.disposeIterator(Event(), Message(), cursor)
    case Events.Yield{event}:
      do IO<Unit>:
        Events.push(Event(), Message(), target, event)
        next : Events.Iteration<Event()> <- Events.nextValue(Event(), Message(), cursor)
        forward(target, source, cursor, next)

def drive(+target: Stream(), model: T.Model<T.JsonValue>, opened: OpenResult()) -> IO(Released()):
  match opened:
    case Fail{error}:
      do IO<Released()>:
        now : F64 <- Date.now()
        message : Message() = setupError(model, Resolve.errorMessage(error), now)
        Events.push(Event(), Message(), target, T.StreamError{T.ErrorError{}, message})
        return Done{Unit{}}
    case Done{StreamLease{+source, release}}:
      do IO<Released()>:
        +cursor : Events.Iterator<Event(), Message()> <- Events.iterator(Event(), Message(), source)
        first : Events.Iteration<Event()> <- Events.nextValue(Event(), Message(), cursor)
        forward(target, source, cursor, first)
        release

def worker(target: Stream(), model: T.Model<T.JsonValue>, setup: IO(OpenResult())) -> IO(Released()):
  do IO<Released()>:
    opened : OpenResult() <- setup
    drive(target, model, opened)

def release(events: Stream(), task: Chan(Released())) -> IO(Released()):
  do IO<Released()>:
    result : Released() <- IO.join(Released(), task)
    Events.disposeAssistantMessageEventStream(V.Value, V.Value, events)
    return result

def lazyStream(+model: T.Model<T.JsonValue>, setup: IO(OpenResult())) -> IO(StreamLease):
  do IO<StreamLease>:
    +events : Stream() <- Events.createAssistantMessageEventStream(~V.Value, ~V.Value)
    task : Chan(Released()) <- IO.fork(Released(), worker(events, model, setup))
    return StreamLease{events, release(events, task)}

def completed(lease: StreamLease) -> IO(Message()):
  match lease:
    case StreamLease{events, release}:
      do IO<Message()>:
        message : Message() <- Events.resultValue(Event(), Message(), events)
        released : Released() <- release
        return message

def complete(opened: IO(StreamLease)) -> IO(Message()):
  do IO<Message()>:
    lease : StreamLease <- opened
    completed(lease)
