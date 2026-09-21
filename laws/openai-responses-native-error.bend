import Base
import ../packages/ai/src/api/openai-responses-native-error.bend as Policy
import ../packages/ai/src/api/openai-responses-cleartext-fetch.bend as Native
import ../packages/ai/src/api/openai-responses-attempt.bend as Attempt
import ../packages/runtime/src/http-buffered-request.bend as Request
import ../packages/runtime/src/http-exchange-plan.bend as Plan
import ../packages/runtime/src/http-host-route.bend as Route
import ../packages/runtime/src/hosts-resolve.bend as Hosts
import ../packages/runtime/src/abortable-socket.bend as Socket
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/deadline.bend as Deadline
import ../packages/runtime/src/dns-pair-search.bend as DNS
import ../packages/runtime/src/dns-pair-setup.bend as Setup
import ../packages/runtime/src/dns-pair-queries.bend as Queries
import ../packages/runtime/src/dns-search-run.bend as Search
import ../packages/runtime/src/dns-search-response.bend as SearchResponse
import ../packages/runtime/src/http-response-progress.bend as Progress
import ../packages/runtime/src/http-socket-exchange.bend as Exchange

law invalid_request_never_becomes_connection_retry:
  for -Reason: Data
  for -SourceError: Data
  for cause: Request.URLRequestError
  {Policy.classify(Reason, SourceError, Native.InvalidRequest{cause}) == Attempt.NonRetryable{} : Attempt.FetchCategory}

law rejected_transport_plan_is_terminal:
  for -Reason: Data
  for -SourceError: Data
  for cause: Plan.Error
  {Policy.classify(Reason, SourceError, Native.Rejected{cause}) == Attempt.NonRetryable{} : Attempt.FetchCategory}

law failed_hosts_snapshot_is_terminal:
  for -Reason: Data
  for -SourceError: Data
  for cause: SourceError
  {Policy.resolution(Reason, SourceError, Done{Route.Named{Hosts.FailedSource{cause}}}) == Attempt.NonRetryable{} : Attempt.FetchCategory}

law socket_error_policy_ignores_platform_code_and_message:
  for -Reason: Data
  for code: U32
  for message: String
  {Policy.socket(Reason, Socket.SocketError{code, message}) == Attempt.Connection{"Connection error."} : Attempt.FetchCategory}

law explicit_parent_abort_is_terminal:
  for -Reason: Data
  for cause: Abort.AbortReason<Reason>
  {Policy.requestAbort(Reason, Abort.Supplied{Deadline.ParentAbort{cause}}) == Attempt.NonRetryable{} : Attempt.FetchCategory}

law dns_parent_retains_request_abort_policy:
  for -Reason: Data
  for cause: Abort.AbortReason<Deadline.Cause<Reason>>
  {Policy.dnsAbort(Reason, Abort.Supplied{Deadline.ParentAbort{cause}}) == Policy.requestAbort(Reason, cause) : Attempt.FetchCategory}

law exhausted_dns_network_outcomes_are_retryable:
  for -Reason: Data
  for cause: SearchResponse.Error
  {Policy.dnsReport(Reason, DNS.Report{Fail{Search.NoAnswer{cause}}, None{}}) == Attempt.Connection{"Connection error."} : Attempt.FetchCategory}

law invalid_dns_encoding_precedes_late_deadline:
  for -Reason: Data
  for cause: Queries.Error
  for why: Maybe<&2, Abort.AbortReason<Deadline.Cause<Deadline.Cause<Reason>>>>
  {Policy.dnsReport(Reason, DNS.Report{Fail{Search.Halted{DNS.SetupFailed{Setup.Encoding{cause}}}}, why}) == Attempt.NonRetryable{} : Attempt.FetchCategory}

law header_cleanup_failure_cannot_be_hidden_by_primary_classification:
  for -Reason: Data
  for primary: Progress.PrimaryError<Exchange.ReadError<Deadline.Cause<Reason>>>
  for cleanup: Exchange.ReadError<Deadline.Cause<Reason>>
  {Policy.header(Reason, Progress.FailureWithCleanup{primary, cleanup}) == Attempt.NonRetryable{} : Attempt.FetchCategory}
