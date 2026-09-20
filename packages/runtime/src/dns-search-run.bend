import Base
import ./dns-name.bend as Name
import ./dns-search.bend as Search
import ./dns-search-response.bend as Response

type Request is Data:
  Request{origin: Search.Origin, name: Name.Name}

type Outcome<-Failure: Data, -Value: Data> is Data:
  Answer{value: Value}
  Failed{cause: Response.Cause}
  Halt{failure: Failure}

type Error<-Failure: Data> is Data:
  NoAnswer{error: Response.Error}
  Halted{failure: Failure}

type Progress<-Failure: Data, -Value: Data> is Data:
  Active{cursor: Search.Cursor, history: Response.History}
  Finished{result: Result<&2, &2, Error<Failure>, Value>}

def decided(-Failure: Data, -Value: Data, decision: Response.Decision) -> Progress<Failure, Value>:
  match decision:
    case Response.Continue{cursor, history}: Active{cursor, history}
    case Response.Stop{error}: Finished{Fail{NoAnswer{error}}}

def received(-Failure: Data, -Value: Data, origin: Search.Origin, cursor: Search.Cursor, history: Response.History, outcome: Outcome<Failure, Value>) -> Progress<Failure, Value>:
  match outcome:
    case Answer{value}: Finished{Done{value}}
    case Halt{failure}: Finished{Fail{Halted{failure}}}
    case Failed{cause}: decided(Failure, Value, Response.failed(origin, cause, cursor, history))

def candidate(~Environment: Data, ~Failure: Data, ~Value: Data, ~request: Environment -> Request -> IO(Outcome<Failure, Value>), environment: Environment, +origin: Search.Origin, cursor: Search.Cursor, history: Response.History, name: Result<&2, &2, Name.Error, Name.Name>) -> IO(Progress<Failure, Value>):
  match name:
    case Fail{_}: IO.pure(Progress<Failure, Value>, decided(Failure, Value, Response.failed(origin, Response.Unrecoverable{}, cursor, history)))
    case Done{value}:
      do IO<Progress<Failure, Value>>:
        outcome : Outcome<Failure, Value> <- request(environment, Request{origin, value})
        return received(Failure, Value, origin, cursor, history, outcome)

def advance(~Environment: Data, ~Failure: Data, ~Value: Data, ~request: Environment -> Request -> IO(Outcome<Failure, Value>), environment: Environment, history: Response.History, step: Search.Step) -> IO(Progress<Failure, Value>):
  match step:
    case Search.Exhausted{}: IO.pure(Progress<Failure, Value>, Finished{Fail{NoAnswer{Response.exhausted(history)}}})
    case Search.Candidate{origin, name, next}: candidate(~Environment, ~Failure, ~Value, ~request, environment, origin, next, history, name)

# Each advance consumes a suffix or a direct-name phase; response policy can
# only discard additional suffixes. That finite progress crosses record fields
# and IO binds, hence the local annotation instead of an arbitrary retry limit.
@unsafe def drive(~Environment: Data, ~Failure: Data, ~Value: Data, ~request: Environment -> Request -> IO(Outcome<Failure, Value>), +environment: Environment, progress: Progress<Failure, Value>) -> IO(Result<&2, &2, Error<Failure>, Value>):
  match progress:
    case Finished{result}: IO.pure(Result<&2, &2, Error<Failure>, Value>, result)
    case Active{cursor, history}:
      do IO<Result<&2, &2, Error<Failure>, Value>>:
        next : Progress<Failure, Value> <- advance(~Environment, ~Failure, ~Value, ~request, environment, history, Search.next(cursor))
        drive(~Environment, ~Failure, ~Value, ~request, environment, next)

# The request function owns each exchange until it returns. The environment is
# borrowed and remains caller-owned. Halt preserves non-DNS errors immediately;
# no earlier search failure can override cancellation/entropy/cleanup failures.
def run(~Environment: Data, ~Failure: Data, ~Value: Data, ~request: Environment -> Request -> IO(Outcome<Failure, Value>), environment: Environment, cursor: Search.Cursor) -> IO(Result<&2, &2, Error<Failure>, Value>):
  drive(~Environment, ~Failure, ~Value, ~request, environment, Active{cursor, Response.new()})
