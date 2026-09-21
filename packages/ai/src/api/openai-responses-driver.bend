import Base
import ../types.bend as T
import ./openai-responses-lifecycle.bend as Life
import ../../../runtime/src/callback.bend as C

# These handles are borrowed until run returns. close settles the event-stream
# result with the final snapshot even if terminal event delivery failed.
type Effects<-A: Data, -G: Data, -E: Data> is Data:
  Effects{emit: C.Callback<T.AssistantMessageEvent<A, G>, Result<&2, &2, E, Unit>>, aborted: C.Callback<Unit, Bool>, close: C.Callback<T.AssistantMessage<A, G>, Unit>}

def close(-A: Data, -G: Data, -E: Data, effects: Effects<A, G, E>, +terminal: Life.Terminal<A, G, E>, cleanup: Maybe<&2, E>, delivery: Maybe<&2, E>) -> IO(Life.RunResult<A, G, E>):
  match effects:
    case Effects{_, _, finish}:
      do IO<Life.RunResult<A, G, E>>:
        C.call(T.AssistantMessage<A, G>, Unit, finish, Life.message(A, G, E, terminal))
        return Life.RunResult{terminal, cleanup, delivery}

def deliveredWithContext(~E: Data, ~Environment: Data, ~render: Environment -> E -> String, -A: Data, -G: Data, +effects: Effects<A, G, E>, terminal: Life.Terminal<A, G, E>, cleanup: Maybe<&2, E>, result: Result<&2, &2, E, Unit>, +environment: Environment) -> IO(Life.RunResult<A, G, E>):
  match effects result:
    case _ Done{_}: close(A, G, E, effects, terminal, cleanup, None{})
    case Effects{_, signal, _} Fail{+cause}:
      do IO<Life.RunResult<A, G, E>>:
        aborted : Bool <- C.call(Unit, Bool, signal, Unit{})
        close(A, G, E, effects, Life.deliveryFailed(A, G, E, terminal, aborted, render(environment), cause), cleanup, Some{cause})

def delivered(~E: Data, ~render: E -> String, -A: Data, -G: Data, +effects: Effects<A, G, E>, terminal: Life.Terminal<A, G, E>, cleanup: Maybe<&2, E>, result: Result<&2, &2, E, Unit>) -> IO(Life.RunResult<A, G, E>):
  deliveredWithContext(~E, ~Unit, ~(unused => render), A, G, effects, terminal, cleanup, result, Unit{})

def finishWithContext(~E: Data, ~Environment: Data, ~render: Environment -> E -> String, -A: Data, -G: Data, +effects: Effects<A, G, E>, +terminal: Life.Terminal<A, G, E>, cleanup: Maybe<&2, E>, +environment: Environment) -> IO(Life.RunResult<A, G, E>):
  match effects:
    case Effects{sink, _, _}:
      do IO<Life.RunResult<A, G, E>>:
        result : Result<&2, &2, E, Unit> <- C.call(T.AssistantMessageEvent<A, G>, Result<&2, &2, E, Unit>, sink, Life.event(A, G, E, terminal))
        deliveredWithContext(~E, ~Environment, ~render, A, G, effects, terminal, cleanup, result, environment)

def finish(~E: Data, ~render: E -> String, -A: Data, -G: Data, +effects: Effects<A, G, E>, +terminal: Life.Terminal<A, G, E>, cleanup: Maybe<&2, E>) -> IO(Life.RunResult<A, G, E>):
  finishWithContext(~E, ~Unit, ~(unused => render), A, G, effects, terminal, cleanup, Unit{})

def concludeWithContext(~E: Data, ~Environment: Data, ~render: Environment -> E -> String, -A: Data, -G: Data, +effects: Effects<A, G, E>, output: T.AssistantMessage<A, G>, failure: Maybe<&2, Life.Failure<E>>, cleanup: Maybe<&2, E>, +environment: Environment) -> IO(Life.RunResult<A, G, E>):
  match effects:
    case Effects{_, signal, _}:
      do IO<Life.RunResult<A, G, E>>:
        aborted : Bool <- C.call(Unit, Bool, signal, Unit{})
        finishWithContext(~E, ~Environment, ~render, A, G, effects, Life.complete(A, G, E, output, aborted, render(environment), failure), cleanup, environment)

def conclude(~E: Data, ~render: E -> String, -A: Data, -G: Data, +effects: Effects<A, G, E>, output: T.AssistantMessage<A, G>, failure: Maybe<&2, Life.Failure<E>>, cleanup: Maybe<&2, E>) -> IO(Life.RunResult<A, G, E>):
  concludeWithContext(~E, ~Unit, ~(unused => render), A, G, effects, output, failure, cleanup, Unit{})

def processedWithContext(~E: Data, ~Environment: Data, ~render: Environment -> E -> String, -A: Data, -G: Data, effects: Effects<A, G, E>, value: Life.Processed<A, G, E>, +environment: Environment) -> IO(Life.RunResult<A, G, E>):
  match value:
    case Life.Processed{output, failure, +cleanup}: concludeWithContext(~E, ~Environment, ~render, A, G, effects, output, Life.processingFailure(E, failure, cleanup), cleanup, environment)

def processed(~E: Data, ~render: E -> String, -A: Data, -G: Data, effects: Effects<A, G, E>, value: Life.Processed<A, G, E>) -> IO(Life.RunResult<A, G, E>):
  processedWithContext(~E, ~Unit, ~(unused => render), A, G, effects, value, Unit{})

def cleanupFailure(-E: Data, result: Result<&2, &2, E, Unit>) -> Maybe<&2, E>:
  match result:
    case Done{_}: None{}
    case Fail{cause}: Some{cause}

def startedWithContext(~E: Data, ~Environment: Data, ~render: Environment -> E -> String, -A: Data, -G: Data, -Owner: Type, effects: Effects<A, G, E>, output: T.AssistantMessage<A, G>, process: Owner -> T.AssistantMessage<A, G> -> IO(Life.Processed<A, G, E>), release: Owner -> IO(Result<&2, &2, E, Unit>), owner: Owner, result: Result<&2, &2, E, Unit>, +environment: Environment) -> IO(Life.RunResult<A, G, E>):
  match result:
    case Fail{cause}:
      do IO<Life.RunResult<A, G, E>>:
        cleanup : Result<&2, &2, E, Unit> <- release(owner)
        concludeWithContext(~E, ~Environment, ~render, A, G, effects, output, Some{Life.StartFailure{cause}}, cleanupFailure(E, cleanup), environment)
    case Done{_}:
      do IO<Life.RunResult<A, G, E>>:
        value : Life.Processed<A, G, E> <- process(owner, output)
        processedWithContext(~E, ~Environment, ~render, A, G, effects, value, environment)

def started(~E: Data, ~render: E -> String, -A: Data, -G: Data, -Owner: Type, effects: Effects<A, G, E>, output: T.AssistantMessage<A, G>, process: Owner -> T.AssistantMessage<A, G> -> IO(Life.Processed<A, G, E>), release: Owner -> IO(Result<&2, &2, E, Unit>), owner: Owner, result: Result<&2, &2, E, Unit>) -> IO(Life.RunResult<A, G, E>):
  startedWithContext(~E, ~Unit, ~(unused => render), A, G, Owner, effects, output, process, release, owner, result, Unit{})

def acquiredWithContext(~E: Data, ~Environment: Data, ~render: Environment -> E -> String, -A: Data, -G: Data, -Owner: Type, +effects: Effects<A, G, E>, +output: T.AssistantMessage<A, G>, process: Owner -> T.AssistantMessage<A, G> -> IO(Life.Processed<A, G, E>), release: Owner -> IO(Result<&2, &2, E, Unit>), result: Result<&2, &1, E, Owner>, +environment: Environment) -> IO(Life.RunResult<A, G, E>):
  match effects result:
    case _ Fail{cause}: concludeWithContext(~E, ~Environment, ~render, A, G, effects, output, Some{Life.RequestFailure{cause}}, None{}, environment)
    case Effects{sink, _, _} Done{owner}:
      do IO<Life.RunResult<A, G, E>>:
        emitted : Result<&2, &2, E, Unit> <- C.call(T.AssistantMessageEvent<A, G>, Result<&2, &2, E, Unit>, sink, T.Start{output})
        startedWithContext(~E, ~Environment, ~render, A, G, Owner, effects, output, process, release, owner, emitted, environment)

def acquired(~E: Data, ~render: E -> String, -A: Data, -G: Data, -Owner: Type, +effects: Effects<A, G, E>, +output: T.AssistantMessage<A, G>, process: Owner -> T.AssistantMessage<A, G> -> IO(Life.Processed<A, G, E>), release: Owner -> IO(Result<&2, &2, E, Unit>), result: Result<&2, &1, E, Owner>) -> IO(Life.RunResult<A, G, E>):
  acquiredWithContext(~E, ~Unit, ~(unused => render), A, G, Owner, effects, output, process, release, result, Unit{})

# Acquisition includes request construction, hooks and retries. It owns failed
# attempts. Success transfers one owner; Start precedes processing that owner.
# Formatting captures immutable runtime data without a callback/channel.
def runWithContext(~E: Data, ~Environment: Data, ~render: Environment -> E -> String, -A: Data, -G: Data, -Owner: Type, effects: Effects<A, G, E>, output: T.AssistantMessage<A, G>, acquire: IO(Result<&2, &1, E, Owner>), process: Owner -> T.AssistantMessage<A, G> -> IO(Life.Processed<A, G, E>), release: Owner -> IO(Result<&2, &2, E, Unit>), +environment: Environment) -> IO(Life.RunResult<A, G, E>):
  do IO<Life.RunResult<A, G, E>>:
    response : Result<&2, &1, E, Owner> <- acquire
    acquiredWithContext(~E, ~Environment, ~render, A, G, Owner, effects, output, process, release, response, environment)
def run(~E: Data, ~render: E -> String, -A: Data, -G: Data, -Owner: Type, effects: Effects<A, G, E>, output: T.AssistantMessage<A, G>, acquire: IO(Result<&2, &1, E, Owner>), process: Owner -> T.AssistantMessage<A, G> -> IO(Life.Processed<A, G, E>), release: Owner -> IO(Result<&2, &2, E, Unit>)) -> IO(Life.RunResult<A, G, E>):
  runWithContext(~E, ~Unit, ~(unused => render), A, G, Owner, effects, output, acquire, process, release, Unit{})
