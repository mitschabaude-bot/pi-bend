import Base
import ../packages/runtime/src/dns-search-run.bend as Run
import ../packages/runtime/src/dns-search.bend as Search
import ../packages/runtime/src/dns-search-response.bend as Response

# Earlier failures and arbitrary remaining candidates cannot override a
# terminal failure, nor can they cause another request after an answer.
law halt_is_terminal:
  for -Failure: Data
  for -Value: Data
  for origin: Search.Origin
  for cursor: Search.Cursor
  for history: Response.History
  for +failure: Failure
  {Run.received(Failure, Value, origin, cursor, history, Run.Halt{failure}) == Run.Finished{Fail{Run.Halted{failure}}} : Run.Progress<Failure, Value>}

law answer_is_terminal:
  for -Failure: Data
  for -Value: Data
  for origin: Search.Origin
  for cursor: Search.Cursor
  for history: Response.History
  for +value: Value
  {Run.received(Failure, Value, origin, cursor, history, Run.Answer{value}) == Run.Finished{Done{value}} : Run.Progress<Failure, Value>}

law initial_failure_precedence:
  for +initial: Response.Error
  for noData: Bool
  for serverFailure: Bool
  for last: Response.Error
  {Response.exhausted(Response.History{Some{initial}, noData, serverFailure, last}) == initial : Response.Error}
