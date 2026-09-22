import Base
import ../packages/runtime/src/dns-message.bend as Query
import ../packages/runtime/src/dns-message.bend as Message
import ../packages/runtime/src/dns-message.bend as Option
import ../packages/runtime/src/dns-message.bend as Edns
import ../packages/runtime/src/dns-message.bend as Name
import ../packages/runtime/src/dns-message.bend as Pair
import ../packages/runtime/src/dns-message.bend as Request
import ../packages/runtime/src/dns-resolver.bend as Resolver
import ../packages/runtime/src/dns-message.bend as Run
import ../packages/runtime/src/dns-message.bend as Response
import ../packages/runtime/src/dns-message.bend as Text
import ../packages/runtime/src/dns-message.bend as Presentation
import ../packages/runtime/src/dns-message.bend as Search

# Dns query

type Intent is Data:
  Intent{options: Query.QueryOptions, id: U32, question: Message.Question}

def intent(request: Query.Request) -> Intent:
  match request:
    case Query.Request{id, flags, question, extension}: Intent{Query.QueryOptions{flags, extension}, id, question}

# Constructing a new question retains every caller option, independently of ID
# and question contents. Validation and transmission are separate obligations.
law creation_preserves_intent:
  for +options: Query.QueryOptions
  for +id: U32
  for +question: Message.Question
  {intent(Query.createQuery(options, id, question)) == Intent{options, id, question} : Intent}


# Dns edns response

law scan_failure_retained:
  for packet: Name.Packet
  for records: List<&2, Message.Record>
  for +error: Edns.EdnsResponseError
  {Edns.scan(packet, records, Fail{error}) == Fail{error} : Result<&2, &2, Edns.EdnsResponseError, Maybe<&2, Edns.Response>>}

law ordinary_record_preserves_selection:
  for packet: Name.Packet
  for record: Message.Record
  for +prior: Result<&2, &2, Edns.EdnsResponseError, Maybe<&2, Edns.Response>>
  {Edns.selected(False{}, packet, record, prior) == prior : Result<&2, &2, Edns.EdnsResponseError, Maybe<&2, Edns.Response>>}

law second_opt_rejected:
  for packet: Name.Packet
  for record: Message.Record
  for prior: Edns.Response
  {Edns.selected(True{}, packet, record, Done{Some{prior}}) == Fail{Edns.Duplicate{}} : Result<&2, &2, Edns.EdnsResponseError, Maybe<&2, Edns.Response>>}

law misplaced_opt_rejected:
  for packet: Name.Packet
  for additional: List<&2, Message.Record>
  {Edns.placement(True{}, packet, additional) == Fail{Edns.Misplaced{}} : Result<&2, &2, Edns.EdnsResponseError, Maybe<&2, Edns.Response>>}

# Only the header's low code and OPT's extended code determine the result;
# version, flags, advertised size and opaque options cannot change its meaning.
law response_code_metadata_independent:
  for +header: Message.Header
  for +upper: U32
  for payload: U32
  for version: U32
  for flags: U32
  for options: List<&2, Option.Option>
  for otherPayload: U32
  for otherVersion: U32
  for otherFlags: U32
  for otherOptions: List<&2, Option.Option>
  {Edns.responseCode(header, Some{Edns.Response{payload, upper, version, flags, options}}) == Edns.responseCode(header, Some{Edns.Response{otherPayload, upper, otherVersion, otherFlags, otherOptions}}) : U32}


# Dns pair queries

law shared_query_intent:
  for +options: Request.QueryOptions
  for +id4: U32
  for +id6: U32
  for +name: Name.Name
  {Pair.create(options, id4, id6, name) == Pair.Queries{Request.createQuery(options, id4, Message.Question{name, 1, 1}), Request.createQuery(options, id6, Message.Question{name, 28, 1})} : Pair.Queries}

law first_encoding_failure:
  for queries: Pair.Queries
  for +error: Edns.EdnsError
  for second: Result<&2, &2, Edns.EdnsError, List<&2, U32>>
  {Pair.checked(queries, Fail{error}, second) == Fail{Pair.Encoding{Pair.IPv4{}, error}} : Result<&2, &2, Pair.PairQueriesError, Pair.Queries>}

law second_encoding_failure:
  for queries: Pair.Queries
  for bytes: List<&2, U32>
  for +error: Edns.EdnsError
  {Pair.checked(queries, Done{bytes}, Fail{error}) == Fail{Pair.Encoding{Pair.IPv6{}, error}} : Result<&2, &2, Pair.PairQueriesError, Pair.Queries>}

law valid_queries_retained:
  for +ipv4: Request.Request
  for +ipv6: Request.Request
  for +first: List<&2, U32>
  for +second: List<&2, U32>
  for encoded4: {Request.encodeQuery(ipv4) == Done{first} : Result<&2, &2, Edns.EdnsError, List<&2, U32>>}
  for encoded6: {Request.encodeQuery(ipv6) == Done{second} : Result<&2, &2, Edns.EdnsError, List<&2, U32>>}
  {Pair.validate(Pair.Queries{ipv4, ipv6}) == Done{Pair.Queries{ipv4, ipv6}} : Result<&2, &2, Pair.PairQueriesError, Pair.Queries>}


# Dns pair result

law left_terminal_retains_both:
  for -Report: Data
  for +priority: Resolver.Priority
  for +left: Report
  for +right: Report
  for +other: Resolver.Disposition
  {Resolver.merge(Report, priority, Resolver.Classified{left, Resolver.Terminal{}}, Resolver.Classified{right, other}) == Run.SearchHalt{Resolver.PairResultReports{Resolver.Classified{left, Resolver.Terminal{}}, Resolver.Classified{right, other}}} : Run.Outcome<Resolver.PairResultReports<Report>, Resolver.PairResultReports<Report>>}

law right_terminal_retains_both:
  for -Report: Data
  for +priority: Resolver.Priority
  for +left: Report
  for +right: Report
  for +other: Resolver.Disposition
  {Resolver.merge(Report, priority, Resolver.Classified{left, other}, Resolver.Classified{right, Resolver.Terminal{}}) == Run.SearchHalt{Resolver.PairResultReports{Resolver.Classified{left, other}, Resolver.Classified{right, Resolver.Terminal{}}}} : Run.Outcome<Resolver.PairResultReports<Report>, Resolver.PairResultReports<Report>>}

law answer_and_reply_retained:
  for -Report: Data
  for +priority: Resolver.Priority
  for +left: Report
  for +right: Report
  for +code: U32
  {Resolver.merge(Report, priority, Resolver.Classified{left, Resolver.Answer{}}, Resolver.Classified{right, Resolver.Reply{code}}) == Run.Answer{Resolver.PairResultReports{Resolver.Classified{left, Resolver.Answer{}}, Resolver.Classified{right, Resolver.Reply{code}}}} : Run.Outcome<Resolver.PairResultReports<Report>, Resolver.PairResultReports<Report>>}

law unavailable_and_answer_retained:
  for -Report: Data
  for +priority: Resolver.Priority
  for +left: Report
  for +right: Report
  for +cause: Response.Cause
  {Resolver.merge(Report, priority, Resolver.Classified{left, Resolver.Unavailable{cause}}, Resolver.Classified{right, Resolver.Answer{}}) == Run.Answer{Resolver.PairResultReports{Resolver.Classified{left, Resolver.Unavailable{cause}}, Resolver.Classified{right, Resolver.Answer{}}}} : Run.Outcome<Resolver.PairResultReports<Report>, Resolver.PairResultReports<Report>>}

law empty_reply_defers_to_other_code:
  for +code: U32
  {Resolver.replies(0, code) == Resolver.response(code) : Response.Cause}

law unavailable_does_not_override_reply:
  for +code: U32
  for cause: Response.Cause
  {Resolver.decide(Resolver.Unavailable{cause}, Resolver.Reply{code}) == Resolver.Failed{Resolver.response(code)} : Resolver.Decision}

law same_failure_is_stable:
  for +cause: Response.Cause
  {Resolver.decide(Resolver.Unavailable{cause}, Resolver.Unavailable{cause}) == Resolver.Failed{cause} : Resolver.Decision}


# Dns search text

law dots_append:
  for +left: String
  for +right: String
  {Text.dots(left ++ right) == Nat.add(Text.dots(left), Text.dots(right)) : Nat}

law leading_dot_counted:
  for +text: String
  {Text.dots("." ++ text) == Succ{Text.dots(text)} : Nat}

law dots_empty:
  {Text.dots("") == 0n : Nat}

law invalid_input_is_terminal:
  for text: String
  for +error: Presentation.PresentationError
  {Text.parsedSearchText(text, Fail{error}) == Fail{error} : Result<&2, &2, Presentation.PresentationError, Text.Input>}

law prepared_fields_retained:
  for +text: String
  for +name: Name.Name
  for +absolute: Bool
  {Text.parsedSearchText(text, Done{Presentation.PresentationParsed{name, absolute}}) == Done{Text.Input{name, U32.from_nat(Text.dots(text)), absolute}} : Result<&2, &2, Presentation.PresentationError, Text.Input>}


# Dns search run

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
