import Base
import ../types.bend as T
import ../utils/event-stream.bend as Events
import ./openai-responses-driver.bend as Driver
import ./openai-responses-lifecycle.bend as Life
import ../../../runtime/src/callback.bend as C

# One producer task and one canonical event stream. The owner is affine;
# borrowed stream handles remain valid until disposal after consumer shutdown.
type Run<-A: Data, -G: Data, -E: Data> is Type:
  Running{stream: Events.AssistantMessageEventStream(A, G), task: Chan(Life.RunResult<A, G, E>)}
  Finished{stream: Events.AssistantMessageEventStream(A, G), result: Life.RunResult<A, G, E>}

def publish(-A: Data, -G: Data, -E: Data, stream: Events.AssistantMessageEventStream(A, G), event: T.AssistantMessageEvent<A, G>) -> IO(Result<&2, &2, E, Unit>):
  do IO<Result<&2, &2, E, Unit>>:
    Events.push(T.AssistantMessageEvent<A, G>, T.AssistantMessage<A, G>, stream, event)
    return Done{Unit{}}

def end(-A: Data, -G: Data, stream: Events.AssistantMessageEventStream(A, G), output: T.AssistantMessage<A, G>) -> IO(Unit):
  Events.end(T.AssistantMessageEvent<A, G>, T.AssistantMessage<A, G>, stream, Some{output})

# Only these two callbacks belong to the producer. The signal and callbacks
# captured by acquisition/processing remain caller-owned until wait completes.
def retire(-A: Data, -G: Data, -E: Data, sink: C.Callback<T.AssistantMessageEvent<A, G>, Result<&2, &2, E, Unit>>, finish: C.Callback<T.AssistantMessage<A, G>, Unit>, result: Life.RunResult<A, G, E>) -> IO(Life.RunResult<A, G, E>):
  do IO<Life.RunResult<A, G, E>>:
    C.dispose(T.AssistantMessageEvent<A, G>, Result<&2, &2, E, Unit>, sink)
    C.dispose(T.AssistantMessage<A, G>, Unit, finish)
    return result

def produceWithContext(~E: Data, ~Environment: Data, ~render: Environment -> E -> String, -A: Data, -G: Data, -Owner: Type, +sink: C.Callback<T.AssistantMessageEvent<A, G>, Result<&2, &2, E, Unit>>, signal: C.Callback<Unit, Bool>, +finish: C.Callback<T.AssistantMessage<A, G>, Unit>, output: T.AssistantMessage<A, G>, acquire: IO(Result<&2, &1, E, Owner>), process: C.Callback<T.AssistantMessageEvent<A, G>, Result<&2, &2, E, Unit>> -> Owner -> T.AssistantMessage<A, G> -> IO(Life.Processed<A, G, E>), release: Owner -> IO(Result<&2, &2, E, Unit>), environment: Environment) -> IO(Life.RunResult<A, G, E>):
  do IO<Life.RunResult<A, G, E>>:
    result : Life.RunResult<A, G, E> <- Driver.runWithContext(~E, ~Environment, ~render, A, G, Owner, Driver.Effects{sink, signal, finish}, output, acquire, process(sink), release, environment)
    retire(A, G, E, sink, finish, result)

def produce(~E: Data, ~render: E -> String, -A: Data, -G: Data, -Owner: Type, +sink: C.Callback<T.AssistantMessageEvent<A, G>, Result<&2, &2, E, Unit>>, signal: C.Callback<Unit, Bool>, +finish: C.Callback<T.AssistantMessage<A, G>, Unit>, output: T.AssistantMessage<A, G>, acquire: IO(Result<&2, &1, E, Owner>), process: C.Callback<T.AssistantMessageEvent<A, G>, Result<&2, &2, E, Unit>> -> Owner -> T.AssistantMessage<A, G> -> IO(Life.Processed<A, G, E>), release: Owner -> IO(Result<&2, &2, E, Unit>)) -> IO(Life.RunResult<A, G, E>):
  produceWithContext(~E, ~Unit, ~(unused => render), A, G, Owner, sink, signal, finish, output, acquire, process, release, Unit{})

# Finish dependency retirement before exposing the producer result to wait.
def afterCleanup(-A: Data, -G: Data, -E: Data, result: Life.RunResult<A, G, E>, cleanup: IO(Unit)) -> IO(Life.RunResult<A, G, E>):
  do IO<Life.RunResult<A, G, E>>:
    cleanup
    return result

def produceWithContextAndCleanup(~E: Data, ~Environment: Data, ~render: Environment -> E -> String, -A: Data, -G: Data, -Owner: Type, +sink: C.Callback<T.AssistantMessageEvent<A, G>, Result<&2, &2, E, Unit>>, signal: C.Callback<Unit, Bool>, +finish: C.Callback<T.AssistantMessage<A, G>, Unit>, output: T.AssistantMessage<A, G>, acquire: IO(Result<&2, &1, E, Owner>), process: C.Callback<T.AssistantMessageEvent<A, G>, Result<&2, &2, E, Unit>> -> Owner -> T.AssistantMessage<A, G> -> IO(Life.Processed<A, G, E>), release: Owner -> IO(Result<&2, &2, E, Unit>), cleanup: IO(Unit), environment: Environment) -> IO(Life.RunResult<A, G, E>):
  do IO<Life.RunResult<A, G, E>>:
    result : Life.RunResult<A, G, E> <- produceWithContext(~E, ~Environment, ~render, A, G, Owner, sink, signal, finish, output, acquire, process, release, environment)
    afterCleanup(A, G, E, result, cleanup)

def produceWithCleanup(~E: Data, ~render: E -> String, -A: Data, -G: Data, -Owner: Type, +sink: C.Callback<T.AssistantMessageEvent<A, G>, Result<&2, &2, E, Unit>>, signal: C.Callback<Unit, Bool>, +finish: C.Callback<T.AssistantMessage<A, G>, Unit>, output: T.AssistantMessage<A, G>, acquire: IO(Result<&2, &1, E, Owner>), process: C.Callback<T.AssistantMessageEvent<A, G>, Result<&2, &2, E, Unit>> -> Owner -> T.AssistantMessage<A, G> -> IO(Life.Processed<A, G, E>), release: Owner -> IO(Result<&2, &2, E, Unit>), cleanup: IO(Unit)) -> IO(Life.RunResult<A, G, E>):
  produceWithContextAndCleanup(~E, ~Unit, ~(unused => render), A, G, Owner, sink, signal, finish, output, acquire, process, release, cleanup, Unit{})

# The producer owns this finalizer and runs it exactly once after every typed
# outcome and publication callback retirement. wait also joins this cleanup.
# Returns the canonical event stream without waiting for acquisition.
# The immutable rendering environment may contain runtime provider settings.
def startWithContextAndCleanup(~A: Data, ~G: Data, ~E: Data, ~Environment: Data, ~render: Environment -> E -> String, -Owner: Type, output: T.AssistantMessage<A, G>, signal: C.Callback<Unit, Bool>, acquire: IO(Result<&2, &1, E, Owner>), process: C.Callback<T.AssistantMessageEvent<A, G>, Result<&2, &2, E, Unit>> -> Owner -> T.AssistantMessage<A, G> -> IO(Life.Processed<A, G, E>), release: Owner -> IO(Result<&2, &2, E, Unit>), cleanup: IO(Unit), environment: Environment) -> IO(Run<A, G, E>):
  do IO<Run<A, G, E>>:
    +stream : Events.AssistantMessageEventStream(A, G) <- Events.createAssistantMessageEventStream(~A, ~G)
    +sink : C.Callback<T.AssistantMessageEvent<A, G>, Result<&2, &2, E, Unit>> <- C.create(~Events.AssistantMessageEventStream(A, G), ~T.AssistantMessageEvent<A, G>, ~Result<&2, &2, E, Unit>, ~(publish(A, G, E)), stream)
    +finish : C.Callback<T.AssistantMessage<A, G>, Unit> <- C.create(~Events.AssistantMessageEventStream(A, G), ~T.AssistantMessage<A, G>, ~Unit, ~(end(A, G)), stream)
    task : Chan(Life.RunResult<A, G, E>) <- IO.fork(Life.RunResult<A, G, E>, produceWithContextAndCleanup(~E, ~Environment, ~render, A, G, Owner, sink, signal, finish, output, acquire, process, release, cleanup, environment))
    return Running{stream, task}

def startWithCleanup(~A: Data, ~G: Data, ~E: Data, ~render: E -> String, -Owner: Type, output: T.AssistantMessage<A, G>, signal: C.Callback<Unit, Bool>, acquire: IO(Result<&2, &1, E, Owner>), process: C.Callback<T.AssistantMessageEvent<A, G>, Result<&2, &2, E, Unit>> -> Owner -> T.AssistantMessage<A, G> -> IO(Life.Processed<A, G, E>), release: Owner -> IO(Result<&2, &2, E, Unit>), cleanup: IO(Unit)) -> IO(Run<A, G, E>):
  startWithContextAndCleanup(~A, ~G, ~E, ~Unit, ~(unused => render), Owner, output, signal, acquire, process, release, cleanup, Unit{})

# Existing callers retain their own dependency lifetimes.
def start(~A: Data, ~G: Data, ~E: Data, ~render: E -> String, -Owner: Type, output: T.AssistantMessage<A, G>, signal: C.Callback<Unit, Bool>, acquire: IO(Result<&2, &1, E, Owner>), process: C.Callback<T.AssistantMessageEvent<A, G>, Result<&2, &2, E, Unit>> -> Owner -> T.AssistantMessage<A, G> -> IO(Life.Processed<A, G, E>), release: Owner -> IO(Result<&2, &2, E, Unit>)) -> IO(Run<A, G, E>):
  startWithCleanup(~A, ~G, ~E, ~render, Owner, output, signal, acquire, process, release, IO.pure(Unit, Unit{}))

def borrow(-A: Data, -G: Data, -E: Data, owner: Run<A, G, E>) -> Run<A, G, E> & Events.AssistantMessageEventStream(A, G):
  match owner:
    case Running{+stream, task}: (Running{stream, task}, stream)
    case Finished{+stream, result}: (Finished{stream, result}, stream)

def completed(-A: Data, -G: Data, -E: Data, stream: Events.AssistantMessageEventStream(A, G), +result: Life.RunResult<A, G, E>) -> Run<A, G, E> & Life.RunResult<A, G, E>:
  (Finished{stream, result}, result)

# Event-stream result settlement may precede producer cleanup. wait is the
# stronger boundary: both owned publication callbacks have been retired.
def wait(-A: Data, -G: Data, -E: Data, owner: Run<A, G, E>) -> IO(Run<A, G, E> & Life.RunResult<A, G, E>):
  match owner:
    case Finished{stream, result}: IO.pure(Run<A, G, E> & Life.RunResult<A, G, E>, completed(A, G, E, stream, result))
    case Running{stream, task}:
      do IO<Run<A, G, E> & Life.RunResult<A, G, E>>:
        result : Life.RunResult<A, G, E> <- IO.join(Life.RunResult<A, G, E>, task)
        return completed(A, G, E, stream, result)

def disposeStream(-A: Data, -G: Data, -E: Data, stream: Events.AssistantMessageEventStream(A, G), result: Life.RunResult<A, G, E>) -> IO(Life.RunResult<A, G, E>):
  do IO<Life.RunResult<A, G, E>>:
    Events.disposeAssistantMessageEventStream(A, G, stream)
    return result

# Call after all consumer iterators/borrowed stream operations have finished.
# This waits for production; cancellation remains the supplied signal's policy.
def dispose(-A: Data, -G: Data, -E: Data, owner: Run<A, G, E>) -> IO(Life.RunResult<A, G, E>):
  match owner:
    case Finished{stream, result}: disposeStream(A, G, E, stream, result)
    case Running{stream, task}:
      do IO<Life.RunResult<A, G, E>>:
        result : Life.RunResult<A, G, E> <- IO.join(Life.RunResult<A, G, E>, task)
        disposeStream(A, G, E, stream, result)
