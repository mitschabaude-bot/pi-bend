import Base
import ../packages/runtime/src/connection-driver.bend as HTTP
import ../packages/runtime/src/connection-driver.bend as Driver
import ../packages/runtime/src/connection-driver.bend as Candidates
import ../packages/runtime/src/connection-driver.bend as Order
import ../packages/runtime/src/socket.bend as Connect
import ../packages/runtime/src/url.bend as IPv4
import ../packages/runtime/src/url.bend as IPv6
import ../packages/runtime/src/hosts.bend as Hosts
import ../packages/runtime/src/hosts.bend as File
import ../packages/runtime/src/dns-resolver.bend as DNS
import ../packages/runtime/src/connection-driver.bend as Progress
import ../packages/runtime/src/connection-driver.bend as Attempt
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/connection-driver.bend as Result
import ../packages/runtime/src/deadline.bend as Deadline

# Connection plan

# Equality of IO programs for arbitrary connectors: an unavailable resolution
# returns immediately, with its complete report, and cannot invoke a connector.
law unavailable_does_not_connect:
  for -Context: Data
  for -Resolution: Data
  for -Reason: Data
  for -Value: Type
  for connect: Context -> List<&2, Connect.Address> -> IO(Driver.Report<Reason, Value>)
  for context: Context
  for preference: Order.Preference
  for +resolution: Resolution
  {HTTP.executeWith(Context, Resolution, Reason, Value, connect, context, preference, Candidates.NoAddresses{resolution}) == IO.pure(HTTP.PlanReport<Resolution, Reason, Value>, HTTP.Unresolved{resolution}) : IO(HTTP.PlanReport<Resolution, Reason, Value>)}


# Connection addresses

law hosts_count:
  for +entries: List<&2, Hosts.Entry<File.Address>>
  {List.length(&2, Connect.Address, Candidates.hosts(entries)) == List.length(&2, Hosts.Entry<File.Address>, entries) : Nat}

law answers_count:
  for +addresses: List<&2, DNS.Address>
  {List.length(&2, Connect.Address, Candidates.answers(addresses)) == List.length(&2, DNS.Address, addresses) : Nat}

law hosts_append:
  for +left: List<&2, Hosts.Entry<File.Address>>
  for +right: List<&2, Hosts.Entry<File.Address>>
  {Candidates.hosts(List.append(&2, Hosts.Entry<File.Address>, left, right)) == List.append(&2, Connect.Address, Candidates.hosts(left), Candidates.hosts(right)) : List<&2, Connect.Address>}

law answers_append:
  for +left: List<&2, DNS.Address>
  for +right: List<&2, DNS.Address>
  {Candidates.answers(List.append(&2, DNS.Address, left, right)) == List.append(&2, Connect.Address, Candidates.answers(left), Candidates.answers(right)) : List<&2, Connect.Address>}

law ordered_retains_report_and_occurrences:
  for -R: Data
  for +report: R
  for +first: Connect.Address
  for +rest: List<&2, Connect.Address>
  {Candidates.ordered(R, report, first <> rest) == Candidates.Addresses{report, Candidates.Ordered{first, rest}} : Candidates.Plan<R>}

law empty_order_retains_report:
  for -R: Data
  for +report: R
  {Candidates.ordered(R, report, Nil{}) == Candidates.NoAddresses{report} : Candidates.Plan<R>}

law paired_retains_both_groups:
  for -R: Data
  for +report: R
  for +first: Connect.Address
  for +rest: List<&2, Connect.Address>
  for +other: List<&2, Connect.Address>
  {Candidates.paired(R, report, first <> rest, other) == Candidates.Addresses{report, Candidates.Paired{first <> rest, other}} : Candidates.Plan<R>}

law ipv6_only_retains_group:
  for -R: Data
  for +report: R
  for +first: Connect.Address
  for +rest: List<&2, Connect.Address>
  {Candidates.paired(R, report, Nil{}, first <> rest) == Candidates.Addresses{report, Candidates.Paired{Nil{}, first <> rest}} : Candidates.Plan<R>}

law empty_pair_retains_report:
  for -R: Data
  for +report: R
  {Candidates.paired(R, report, Nil{}, Nil{}) == Candidates.NoAddresses{report} : Candidates.Plan<R>}

law ipv4_host_address_retained:
  for +address: IPv4.Address
  for canonical: String
  for aliases: List<&2, String>
  {Candidates.host(Hosts.Entry{File.V4{address}, canonical, aliases}) == Connect.V4{address} : Connect.Address}

law ipv6_host_address_retained:
  for +address: IPv6.Ipv6Address
  for canonical: String
  for aliases: List<&2, String>
  {Candidates.host(Hosts.Entry{File.V6{address}, canonical, aliases}) == Connect.V6{address, 0} : Connect.Address}

law ipv4_answer_address_retained:
  for +address: IPv4.Address
  for ttl: U32
  {Candidates.answer(DNS.V4{address, ttl}) == Connect.V4{address} : Connect.Address}

law ipv6_answer_address_retained:
  for +address: IPv6.Ipv6Address
  for ttl: U32
  {Candidates.answer(DNS.V6{address, ttl}) == Connect.V6{address, 0} : Connect.Address}


# Connection progress

law parent_abort_wins:
  for -R: Data
  for outcome: Result<&2, &2, Attempt.Error<R>, Unit>
  for +reason: Abort.AbortReason<R>
  {Progress.decide(R, outcome, Some{reason}) == Progress.Stop{Progress.ProgressAborted{reason}} : Progress.Decision<R>}

law socket_failure_advances:
  for -R: Data
  for code: U32
  for message: String
  {Progress.decide(R, Fail{Attempt.SocketFailure{code, message}}, None{}) == Progress.Advance{} : Progress.Decision<R>}

law expiry_advances:
  for -R: Data
  {Progress.decide(R, Fail{Attempt.TimedOut{}}, None{}) == Progress.Advance{} : Progress.Decision<R>}

law reported_abort_stops:
  for -R: Data
  for +reason: Abort.AbortReason<R>
  {Progress.decide(R, Fail{Attempt.Aborted{reason}}, None{}) == Progress.Stop{Progress.ProgressAborted{reason}} : Progress.Decision<R>}

law unexpected_abort_stops:
  for -R: Data
  {Progress.decide(R, Fail{Attempt.UnexpectedDefaultAbort{}}, None{}) == Progress.Stop{Progress.ProgressUnexpectedDefaultAbort{}} : Progress.Decision<R>}

law settled_success_accepted:
  for -R: Data
  {Progress.decide(R, Done{Unit{}}, None{}) == Progress.Accept{} : Progress.Decision<R>}

law last_attempt_untimed:
  for -A: Data
  {Progress.mode(A, Nil{}) == Progress.Final{} : Progress.Mode}

law nonfinal_attempt_timed:
  for -A: Data
  for first: A
  for rest: List<&2, A>
  {Progress.mode(A, first <> rest) == Progress.NonFinal{} : Progress.Mode}


# Connection attempt result

law timed_socket_failure_retained:
  for -R: Data
  for +code: U32
  for +message: String
  {Result.timedError(R, Connect.SocketError{code, message}) == Result.SocketFailure{code, message} : Result.Error<R>}

law plain_socket_failure_retained:
  for -R: Data
  for +code: U32
  for +message: String
  {Result.plainError(R, Connect.SocketError{code, message}) == Result.SocketFailure{code, message} : Result.Error<R>}

law timed_parent_reason_retained:
  for -R: Data
  for +reason: Abort.AbortReason<R>
  {Result.timedError(R, Connect.Aborted{Abort.Supplied{Deadline.ParentAbort{reason}}}) == Result.Aborted{reason} : Result.Error<R>}

law plain_parent_reason_retained:
  for -R: Data
  for +reason: Abort.AbortReason<R>
  {Result.plainError(R, Connect.Aborted{reason}) == Result.Aborted{reason} : Result.Error<R>}

law expiry_distinguished:
  for -R: Data
  {Result.timedError(R, Connect.Aborted{Abort.Supplied{Deadline.Expired{}}}) == Result.TimedOut{} : Result.Error<R>}

law unexpected_default_distinguished:
  for -R: Data
  {Result.timedError(R, Connect.Aborted{Abort.DefaultAbort{}}) == Result.UnexpectedDefaultAbort{} : Result.Error<R>}
