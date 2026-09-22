import Base
import ../laws/connection-driver.bend as Laws
import ../packages/runtime/src/hosts.bend as Hosts
import ../packages/runtime/src/hosts.bend as File
import ../packages/runtime/src/dns-resolver.bend as DNS
import ../packages/runtime/src/connection-driver.bend as Candidates
import ../packages/runtime/src/socket.bend as Connect
import ../packages/runtime/src/connection-driver.bend as Attempt

# Connection plan

def Laws.unavailable_does_not_connect(Context, Resolution, Reason, Value, connect, context, preference, resolution): {==}


# Connection addresses

def Laws.hosts_count(entries):
  match entries:
    case Nil{}: {==}
    case first <> rest:
      %Laws.hosts_count(rest) : {Succ{List.length(&2, Connect.Address, Candidates.hosts(rest))} == Succ{_} : Nat}
      {==}

def Laws.answers_count(addresses):
  match addresses:
    case Nil{}: {==}
    case first <> rest:
      %Laws.answers_count(rest) : {Succ{List.length(&2, Connect.Address, Candidates.answers(rest))} == Succ{_} : Nat}
      {==}

def Laws.hosts_append(left, right):
  match left:
    case Nil{}: {==}
    case first <> rest:
      %Laws.hosts_append(rest, right) : {Candidates.host(first) <> Candidates.hosts(List.append(&2, Hosts.Entry<File.Address>, rest, right)) == Candidates.host(first) <> _ : List<&2, Connect.Address>}
      {==}

def Laws.answers_append(left, right):
  match left:
    case Nil{}: {==}
    case first <> rest:
      %Laws.answers_append(rest, right) : {Candidates.answer(first) <> Candidates.answers(List.append(&2, DNS.Address, rest, right)) == Candidates.answer(first) <> _ : List<&2, Connect.Address>}
      {==}

def Laws.ordered_retains_report_and_occurrences(R, report, first, rest): {==}
def Laws.empty_order_retains_report(R, report): {==}
def Laws.paired_retains_both_groups(R, report, first, rest, other): {==}
def Laws.ipv6_only_retains_group(R, report, first, rest): {==}
def Laws.empty_pair_retains_report(R, report): {==}

def Laws.ipv4_host_address_retained(address, canonical, aliases): {==}
def Laws.ipv6_host_address_retained(address, canonical, aliases): {==}
def Laws.ipv4_answer_address_retained(address, ttl): {==}
def Laws.ipv6_answer_address_retained(address, ttl): {==}


# Connection progress

def Laws.parent_abort_wins(R, outcome, reason):
  match outcome:
    case Done{_}: {==}
    case Fail{Attempt.SocketFailure{_, _}}: {==}
    case Fail{Attempt.TimedOut{}}: {==}
    case Fail{Attempt.Aborted{_}}: {==}
    case Fail{Attempt.UnexpectedDefaultAbort{}}: {==}
def Laws.socket_failure_advances(R, code, message): {==}
def Laws.expiry_advances(R): {==}
def Laws.reported_abort_stops(R, reason): {==}
def Laws.unexpected_abort_stops(R): {==}
def Laws.settled_success_accepted(R): {==}
def Laws.last_attempt_untimed(A): {==}
def Laws.nonfinal_attempt_timed(A, first, rest): {==}


# Connection attempt result

def Laws.timed_socket_failure_retained(R, code, message): {==}
def Laws.plain_socket_failure_retained(R, code, message): {==}
def Laws.timed_parent_reason_retained(R, reason): {==}
def Laws.plain_parent_reason_retained(R, reason): {==}
def Laws.expiry_distinguished(R): {==}
def Laws.unexpected_default_distinguished(R): {==}
