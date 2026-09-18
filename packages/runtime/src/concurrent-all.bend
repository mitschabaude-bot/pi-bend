import Base
import ./callback.bend as C
import ./deferred.bend as D
import ./ref.bend as R

# Ordered concurrent results with prompt first-failure settlement. A failed
# result does not cancel sibling operations. The owner must drain before
# retiring callbacks or resources captured by them.
type Run<-Error: Data, -Value: Data> is Data:
  Run{outcome: D.Deferred<Result<&2, &2, Error, List<&2, Value>>>, drained: Chan(Unit)}

def reportFailure(-Error: Data, -Value: Data, outcome: D.Deferred<Result<&2, &2, Error, List<&2, Value>>>, result: Result<&2, &2, Error, Value>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{error}:
      do IO<Unit>:
        won : Bool <- D.resolve(Result<&2, &2, Error, List<&2, Value>>, outcome, Fail{error})
        return Unit{}

def worker(-Input: Data, -Error: Data, -Value: Data, callback: C.Callback<Input, Result<&2, &2, Error, Value>>, input: Input, outcome: D.Deferred<Result<&2, &2, Error, List<&2, Value>>>, reply: Chan(Result<&2, &2, Error, Value>)) -> IO(Unit):
  do IO<Unit>:
    +result : Result<&2, &2, Error, Value> <- C.call(Input, Result<&2, &2, Error, Value>, callback, input)
    reportFailure(Error, Value, outcome, result)
    sent : Bool <- Chan.send(Result<&2, &2, Error, Value>, reply, result)
    R.requireSent(sent)

# Each worker owns its final send; after it, no shared run resource is touched.
def launch(-Input: Data, -Error: Data, -Value: Data, inputs: List<&2, Input>, +callback: C.Callback<Input, Result<&2, &2, Error, Value>>, +outcome: D.Deferred<Result<&2, &2, Error, List<&2, Value>>>) -> IO(List<&2, Chan(Result<&2, &2, Error, Value>)>):
  match inputs:
    case Nil{}: IO.pure(List<&2, Chan(Result<&2, &2, Error, Value>)>, Nil{})
    case input <> rest:
      do IO<List<&2, Chan(Result<&2, &2, Error, Value>)>>:
        +reply : Chan(Result<&2, &2, Error, Value>) <- Chan.new(Result<&2, &2, Error, Value>, 1)
        IO.spawn(Unit, worker(Input, Error, Value, callback, input, outcome, reply))
        replies : List<&2, Chan(Result<&2, &2, Error, Value>)> <- launch(Input, Error, Value, rest, callback, outcome)
        return reply <> replies

def accumulate(-Error: Data, -Value: Data, previous: Result<&2, &2, Error, List<&2, Value>>, next: Result<&2, &2, Error, Value>) -> Result<&2, &2, Error, List<&2, Value>>:
  match previous next:
    case Fail{error} _: Fail{error}
    case Done{_} Fail{error}: Fail{error}
    case Done{values} Done{value}: Done{value <> values}

def ordered(-Error: Data, -Value: Data, result: Result<&2, &2, Error, List<&2, Value>>) -> Result<&2, &2, Error, List<&2, Value>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{values}: Done{List.reverse(&2, Value, values)}

# Consume every reply even after failure. Only the shared outcome chooses the
# first observed failure; the ordered collector cannot replace that choice.
def collect(-Error: Data, -Value: Data, replies: List<&2, Chan(Result<&2, &2, Error, Value>)>, reversed: Result<&2, &2, Error, List<&2, Value>>, outcome: D.Deferred<Result<&2, &2, Error, List<&2, Value>>>, drained: Chan(Unit)) -> IO(Unit):
  match replies:
    case Nil{}:
      do IO<Unit>:
        won : Bool <- D.resolve(Result<&2, &2, Error, List<&2, Value>>, outcome, ordered(Error, Value, reversed))
        sent : Bool <- Chan.send(Unit, drained, Unit{})
        R.requireSent(sent)
    case reply <> rest:
      do IO<Unit>:
        result : Result<&2, &2, Error, Value> <- IO.join(Result<&2, &2, Error, Value>, reply)
        collect(Error, Value, rest, accumulate(Error, Value, reversed, result), outcome, drained)

def start(-Input: Data, -Error: Data, -Value: Data, inputs: List<&2, Input>, callback: C.Callback<Input, Result<&2, &2, Error, Value>>) -> IO(Run<Error, Value>):
  do IO<Run<Error, Value>>:
    +outcome : D.Deferred<Result<&2, &2, Error, List<&2, Value>>> <- D.new(Result<&2, &2, Error, List<&2, Value>>)
    +drained : Chan(Unit) <- Chan.new(Unit, 1)
    replies : List<&2, Chan(Result<&2, &2, Error, Value>)> <- launch(Input, Error, Value, inputs, callback, outcome)
    IO.spawn(Unit, collect(Error, Value, replies, Done{Nil{}}, outcome, drained))
    return Run{outcome, drained}

def result(-Error: Data, -Value: Data, run: Run<Error, Value>) -> IO(Result<&2, &2, Error, List<&2, Value>>):
  match run:
    case Run{outcome, _}: D.result(Result<&2, &2, Error, List<&2, Value>>, outcome)

# Single-owner boundary: retire result observers before disposal. This waits
# for siblings even if result has already returned a failure.
def dispose(-Error: Data, -Value: Data, run: Run<Error, Value>) -> IO(Unit):
  match run:
    case Run{outcome, drained}:
      do IO<Unit>:
        done : Unit <- IO.join(Unit, drained)
        D.dispose(Result<&2, &2, Error, List<&2, Value>>, outcome)
