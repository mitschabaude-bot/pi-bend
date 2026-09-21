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

def delivered(~E: Data, ~render: E -> String, -A: Data, -G: Data, +effects: Effects<A, G, E>, terminal: Life.Terminal<A, G, E>, cleanup: Maybe<&2, E>, result: Result<&2, &2, E, Unit>) -> IO(Life.RunResult<A, G, E>):
  match effects result:
    case _ Done{_}: close(A, G, E, effects, terminal, cleanup, None{})
    case Effects{_, signal, _} Fail{+cause}:
      do IO<Life.RunResult<A, G, E>>:
        aborted : Bool <- C.call(Unit, Bool, signal, Unit{})
        close(A, G, E, effects, Life.deliveryFailed(A, G, E, terminal, aborted, render, cause), cleanup, Some{cause})

def finish(~E: Data, ~render: E -> String, -A: Data, -G: Data, +effects: Effects<A, G, E>, +terminal: Life.Terminal<A, G, E>, cleanup: Maybe<&2, E>) -> IO(Life.RunResult<A, G, E>):
  match effects:
    case Effects{sink, _, _}:
      do IO<Life.RunResult<A, G, E>>:
        result : Result<&2, &2, E, Unit> <- C.call(T.AssistantMessageEvent<A, G>, Result<&2, &2, E, Unit>, sink, Life.event(A, G, E, terminal))
        delivered(~E, ~render, A, G, effects, terminal, cleanup, result)

def conclude(~E: Data, ~render: E -> String, -A: Data, -G: Data, +effects: Effects<A, G, E>, output: T.AssistantMessage<A, G>, failure: Maybe<&2, Life.Failure<E>>, cleanup: Maybe<&2, E>) -> IO(Life.RunResult<A, G, E>):
  match effects:
    case Effects{_, signal, _}:
      do IO<Life.RunResult<A, G, E>>:
        aborted : Bool <- C.call(Unit, Bool, signal, Unit{})
        finish(~E, ~render, A, G, effects, Life.complete(A, G, E, output, aborted, render, failure), cleanup)

def processed(~E: Data, ~render: E -> String, -A: Data, -G: Data, effects: Effects<A, G, E>, value: Life.Processed<A, G, E>) -> IO(Life.RunResult<A, G, E>):
  match value:
    case Life.Processed{output, failure, +cleanup}: conclude(~E, ~render, A, G, effects, output, Life.processingFailure(E, failure, cleanup), cleanup)

def cleanupFailure(-E: Data, result: Result<&2, &2, E, Unit>) -> Maybe<&2, E>:
  match result:
    case Done{_}: None{}
    case Fail{cause}: Some{cause}

def started(~E: Data, ~render: E -> String, -A: Data, -G: Data, -Owner: Type, effects: Effects<A, G, E>, output: T.AssistantMessage<A, G>, process: Owner -> T.AssistantMessage<A, G> -> IO(Life.Processed<A, G, E>), release: Owner -> IO(Result<&2, &2, E, Unit>), owner: Owner, result: Result<&2, &2, E, Unit>) -> IO(Life.RunResult<A, G, E>):
  match result:
    case Fail{cause}:
      do IO<Life.RunResult<A, G, E>>:
        cleanup : Result<&2, &2, E, Unit> <- release(owner)
        conclude(~E, ~render, A, G, effects, output, Some{Life.StartFailure{cause}}, cleanupFailure(E, cleanup))
    case Done{_}:
      do IO<Life.RunResult<A, G, E>>:
        value : Life.Processed<A, G, E> <- process(owner, output)
        processed(~E, ~render, A, G, effects, value)

def acquired(~E: Data, ~render: E -> String, -A: Data, -G: Data, -Owner: Type, +effects: Effects<A, G, E>, +output: T.AssistantMessage<A, G>, process: Owner -> T.AssistantMessage<A, G> -> IO(Life.Processed<A, G, E>), release: Owner -> IO(Result<&2, &2, E, Unit>), result: Result<&2, &1, E, Owner>) -> IO(Life.RunResult<A, G, E>):
  match effects result:
    case _ Fail{cause}: conclude(~E, ~render, A, G, effects, output, Some{Life.RequestFailure{cause}}, None{})
    case Effects{sink, _, _} Done{owner}:
      do IO<Life.RunResult<A, G, E>>:
        emitted : Result<&2, &2, E, Unit> <- C.call(T.AssistantMessageEvent<A, G>, Result<&2, &2, E, Unit>, sink, T.Start{output})
        started(~E, ~render, A, G, Owner, effects, output, process, release, owner, emitted)

# Acquisition includes request construction, hooks and retries. It owns failed
# attempts. Success transfers one owner; Start precedes processing that owner.
def run(~E: Data, ~render: E -> String, -A: Data, -G: Data, -Owner: Type, effects: Effects<A, G, E>, output: T.AssistantMessage<A, G>, acquire: IO(Result<&2, &1, E, Owner>), process: Owner -> T.AssistantMessage<A, G> -> IO(Life.Processed<A, G, E>), release: Owner -> IO(Result<&2, &2, E, Unit>)) -> IO(Life.RunResult<A, G, E>):
  do IO<Life.RunResult<A, G, E>>:
    response : Result<&2, &1, E, Owner> <- acquire
    acquired(~E, ~render, A, G, Owner, effects, output, process, release, response)
