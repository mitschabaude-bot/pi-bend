import Base
import ./io-pair.bend as Pair
import ./dns-search.bend as Search
import ./dns-search-run.bend as Run

# One search candidate is shared by both callbacks. The caller supplies the
# protocol-aware merge over full reports; no partial result is interpreted as
# permission to advance to another suffix. The borrowed environment carries
# the shared deadline and any per-candidate transport policy.
def merged(~Left: Data, ~Right: Data, ~Failure: Data, ~Value: Data, ~merge: Left -> Right -> Run.Outcome<Failure, Value>, reports: Left & Right) -> Run.Outcome<Failure, Value>:
  match reports:
    case (left, right): merge(left, right)

def candidate(~Environment: Data, ~Left: Data, ~Right: Data, ~Failure: Data, ~Value: Data, ~left: Environment -> Run.Request -> IO(Left), ~right: Environment -> Run.Request -> IO(Right), ~merge: Left -> Right -> Run.Outcome<Failure, Value>, environment: Environment, request: Run.Request) -> IO(Run.Outcome<Failure, Value>):
  +sharedEnvironment = environment
  +sharedRequest = request
  do IO<Run.Outcome<Failure, Value>>:
    reports : Left & Right <- Pair.both(Left, Right, left(sharedEnvironment, sharedRequest), right(sharedEnvironment, sharedRequest))
    return merged(~Left, ~Right, ~Failure, ~Value, ~merge, reports)

# Search advances only after both children have returned and been joined.
# Callbacks own cleanup; a shared abort/deadline must make each one finish.
def run(~Environment: Data, ~Left: Data, ~Right: Data, ~Failure: Data, ~Value: Data, ~left: Environment -> Run.Request -> IO(Left), ~right: Environment -> Run.Request -> IO(Right), ~merge: Left -> Right -> Run.Outcome<Failure, Value>, environment: Environment, cursor: Search.Cursor) -> IO(Result<&2, &2, Run.Error<Failure>, Value>):
  Run.run(~Environment, ~Failure, ~Value, ~candidate(~Environment, ~Left, ~Right, ~Failure, ~Value, ~left, ~right, ~merge), environment, cursor)
