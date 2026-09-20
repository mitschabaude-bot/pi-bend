import Base
import ./dns-search.bend as Search

# Resolver error classes, independent of OS errno and libc integer constants.
type Error is Data:
  NotFound{}
  NoData{}
  TryAgain{}
  NoRecovery{}

# Transport/answer adapters must classify a completed candidate explicitly.
# Refused means connection refusal, not the DNS REFUSED response code.
type Cause is Data:
  Missing{}
  EmptyAnswer{}
  ServerFailure{}
  TemporaryFailure{}
  Unrecoverable{}
  ConnectionRefused{}

type History is Data:
  History{initial: Maybe<&2, Error>, noData: Bool, serverFailure: Bool, last: Error}

type Decision is Data:
  Continue{cursor: Search.Cursor, history: History}
  Stop{error: Error}

def new() -> History: History{None{}, False{}, False{}, NotFound{}}

def error(cause: Cause) -> Error:
  match cause:
    case Missing{}: NotFound{}
    case EmptyAnswer{}: NoData{}
    case Unrecoverable{}: NoRecovery{}
    case _: TryAgain{}

def exhausted(history: History) -> Error:
  match history:
    case History{Some{value}, _, _, _}: value
    case History{None{}, True{}, _, _}: NoData{}
    case History{None{}, False{}, True{}, _}: TryAgain{}
    case History{None{}, False{}, False{}, value}: value

def suffix(cause: Cause, cursor: Search.Cursor, history: History) -> Decision:
  match cause history:
    case ConnectionRefused{} _: Stop{TryAgain{}}
    case Missing{} History{initial, noData, serverFailure, _}: Continue{cursor, History{initial, noData, serverFailure, NotFound{}}}
    case EmptyAnswer{} History{initial, _, serverFailure, _}: Continue{cursor, History{initial, True{}, serverFailure, NoData{}}}
    case ServerFailure{} History{initial, noData, _, _}: Continue{cursor, History{initial, noData, True{}, TryAgain{}}}
    case TemporaryFailure{} History{initial, noData, serverFailure, _}: Continue{Search.stopSearch(cursor), History{initial, noData, serverFailure, TryAgain{}}}
    case Unrecoverable{} History{initial, noData, serverFailure, _}: Continue{Search.stopSearch(cursor), History{initial, noData, serverFailure, NoRecovery{}}}

# Called only after failure. Success finishes immediately in the enclosing
# driver. An absolute initial name has an already exhausted continuation.
def failed(origin: Search.Origin, cause: Cause, cursor: Search.Cursor, history: History) -> Decision:
  match origin history:
    case Search.Initial{} History{_, noData, serverFailure, _}:
      +value = error(cause)
      Continue{cursor, History{Some{value}, noData, serverFailure, value}}
    case Search.Final{} History{initial, noData, serverFailure, _}: Continue{cursor, History{initial, noData, serverFailure, error(cause)}}
    case Search.Suffix{_} previous: suffix(cause, cursor, previous)
