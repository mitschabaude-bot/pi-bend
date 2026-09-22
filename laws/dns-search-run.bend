import Base
import ../packages/runtime/src/dns-message.bend as Run
import ../packages/runtime/src/dns-message.bend as Search
import ../packages/runtime/src/dns-message.bend as Response

# Earlier failures and arbitrary remaining candidates cannot override a
# terminal failure, nor can they cause another request after an answer.
law halt_is_terminal:
  for -Failure: Data
  for -Value: Data
  for origin: Search.Origin
  for cursor: Search.SearchCursor
  for history: Response.History
  for +failure: Failure
  {Run.received(Failure, Value, origin, cursor, history, Run.SearchHalt{failure}) == Run.SearchRunFinished{Fail{Run.Halted{failure}}} : Run.Progress<Failure, Value>}

law answer_is_terminal:
  for -Failure: Data
  for -Value: Data
  for origin: Search.Origin
  for cursor: Search.SearchCursor
  for history: Response.History
  for +value: Value
  {Run.received(Failure, Value, origin, cursor, history, Run.Answer{value}) == Run.SearchRunFinished{Done{value}} : Run.Progress<Failure, Value>}

law initial_failure_precedence:
  for +initial: Response.SearchResponseError
  for noData: Bool
  for serverFailure: Bool
  for last: Response.SearchResponseError
  {Response.exhausted(Response.History{Some{initial}, noData, serverFailure, last}) == initial : Response.SearchResponseError}
