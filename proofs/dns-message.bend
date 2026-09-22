import Base
import ../laws/dns-message.bend as Laws
import ../packages/runtime/src/dns-message.bend as Query
import ../packages/runtime/src/dns-message.bend as Message
import ../packages/runtime/src/dns-message.bend as Pair
import ../packages/runtime/src/dns-message.bend as Request
import ../packages/runtime/src/dns-message.bend as Edns
import ../packages/runtime/src/dns-resolver.bend as Resolver
import ../packages/runtime/src/dns-message.bend as Text

# Dns query

def Laws.creation_preserves_intent(options, id, question):
  match options:
    case Query.QueryOptions{_, _}: {==}


# Dns edns response

def Laws.scan_failure_retained(packet, records, error):
  match records:
    case Nil{}: {==}
    case _ <> _: {==}
def Laws.ordinary_record_preserves_selection(packet, record, prior):
  match prior:
    case Fail{_}: {==}
    case Done{_}: {==}
def Laws.second_opt_rejected(packet, record, prior): {==}
def Laws.misplaced_opt_rejected(packet, additional): {==}

def Laws.response_code_metadata_independent(header, upper, payload, version, flags, options, otherPayload, otherVersion, otherFlags, otherOptions):
  match header:
    case Message.Header{_, _, _, _, _, _}: {==}


# Dns pair queries

def Laws.shared_query_intent(options, id4, id6, name): {==}
def Laws.first_encoding_failure(queries, error, second):
  match second:
    case Fail{other}: {==}
    case Done{bytes}: {==}
def Laws.second_encoding_failure(queries, bytes, error): {==}

def Laws.valid_queries_retained(ipv4, ipv6, first, second, encoded4, encoded6):
  %Equal.sym(Result<&2, &2, Edns.EdnsError, List<&2, U32>>, Request.encodeQuery(ipv4), Done{first}, encoded4) : {Pair.checked(Pair.Queries{ipv4, ipv6}, _, Request.encodeQuery(ipv6)) == Done{Pair.Queries{ipv4, ipv6}} : Result<&2, &2, Pair.PairQueriesError, Pair.Queries>}
  %Equal.sym(Result<&2, &2, Edns.EdnsError, List<&2, U32>>, Request.encodeQuery(ipv6), Done{second}, encoded6) : {Pair.checked(Pair.Queries{ipv4, ipv6}, Done{first}, _) == Done{Pair.Queries{ipv4, ipv6}} : Result<&2, &2, Pair.PairQueriesError, Pair.Queries>}
  {==}


# Dns pair result

def Laws.left_terminal_retains_both(Report, priority, left, right, other):
  match priority:
    case Resolver.IPv4First{}:
      match other:
        case Resolver.Answer{}: {==}
        case Resolver.Reply{code}: {==}
        case Resolver.Unavailable{cause}: {==}
        case Resolver.Terminal{}: {==}
    case Resolver.IPv6First{}:
      match other:
        case Resolver.Answer{}: {==}
        case Resolver.Reply{code}: {==}
        case Resolver.Unavailable{cause}: {==}
        case Resolver.Terminal{}: {==}

def Laws.right_terminal_retains_both(Report, priority, left, right, other):
  match priority:
    case Resolver.IPv4First{}:
      match other:
        case Resolver.Answer{}: {==}
        case Resolver.Reply{code}: {==}
        case Resolver.Unavailable{cause}: {==}
        case Resolver.Terminal{}: {==}
    case Resolver.IPv6First{}:
      match other:
        case Resolver.Answer{}: {==}
        case Resolver.Reply{code}: {==}
        case Resolver.Unavailable{cause}: {==}
        case Resolver.Terminal{}: {==}

def Laws.answer_and_reply_retained(Report, priority, left, right, code):
  match priority:
    case Resolver.IPv4First{}: {==}
    case Resolver.IPv6First{}: {==}
def Laws.unavailable_and_answer_retained(Report, priority, left, right, cause):
  match priority:
    case Resolver.IPv4First{}: {==}
    case Resolver.IPv6First{}: {==}
def Laws.empty_reply_defers_to_other_code(code): {==}
def Laws.unavailable_does_not_override_reply(code, cause): {==}
def Laws.same_failure_is_stable(cause): {==}


# Dns search text

law counted_append:
  for +dot: Bool
  for +left: Nat
  for +right: Nat
  {Text.countedSearchText(dot, Nat.add(left, right)) == Nat.add(Text.countedSearchText(dot, left), right) : Nat}

def counted_append(dot, left, right):
  match dot:
    case True{}: {==}
    case False{}: {==}

def Laws.dots_append(left, right):
  match left:
    case SNil{}: {==}
    case SCon{Chr{code}, rest}:
      %Equal.sym(Nat, Text.dots(rest ++ right), Nat.add(Text.dots(rest), Text.dots(right)), Laws.dots_append(rest, right)) : {Text.countedSearchText(U32.is_eq(code, 46), _) == Nat.add(Text.countedSearchText(U32.is_eq(code, 46), Text.dots(rest)), Text.dots(right)) : Nat}
      counted_append(U32.is_eq(code, 46), Text.dots(rest), Text.dots(right))

def Laws.leading_dot_counted(text): {==}
def Laws.dots_empty(): {==}
def Laws.invalid_input_is_terminal(text, error): {==}
def Laws.prepared_fields_retained(text, name, absolute): {==}


# Dns search run

def Laws.halt_is_terminal(Failure, Value, origin, cursor, history, failure): {==}
def Laws.answer_is_terminal(Failure, Value, origin, cursor, history, value): {==}
def Laws.initial_failure_precedence(initial, noData, serverFailure, last): {==}
