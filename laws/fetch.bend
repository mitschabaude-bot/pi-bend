import Base
import ../packages/runtime/src/fetch.bend as Fetch
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/deadline.bend as Deadline
import ../packages/runtime/src/dns-pair-search.bend as DNS
import ../packages/runtime/src/dns-pair-setup.bend as Setup
import ../packages/runtime/src/dns-search-run.bend as Search
import ../packages/runtime/src/dns-search-response.bend as Response
import ../packages/runtime/src/dns-pair-result.bend as Pair
import ../packages/runtime/src/dns-address-lookup.bend as Lookup
import ../packages/runtime/src/dns-address-answer.bend as Answer

# Retry classification of native transport failures: only deadline expiry is
# a timeout, only the network's silence is a connection failure, and every
# explicit cancellation or terminal resolver outcome stays non-retryable.

law expired_request_deadline_is_a_timeout:
  for -Reason: Data
  {Fetch.requestAbort(Reason, Abort.Supplied{Deadline.Expired{}}) == Fetch.Timeout{} : Fetch.Category}

law parent_cancellation_is_not_retried:
  for -Reason: Data
  for why: Abort.AbortReason<Reason>
  {Fetch.requestAbort(Reason, Abort.Supplied{Deadline.ParentAbort{why}}) == Fetch.NonRetryable{} : Fetch.Category}

law default_cancellation_is_not_retried:
  for -Reason: Data
  {Fetch.requestAbort(Reason, Abort.DefaultAbort{}) == Fetch.NonRetryable{} : Fetch.Category}

law expired_dns_deadline_is_a_timeout:
  for -Reason: Data
  {Fetch.dnsAbort(Reason, Abort.Supplied{Deadline.Expired{}}) == Fetch.Timeout{} : Fetch.Category}

law dns_inherits_the_request_classification:
  for -Reason: Data
  for why: Abort.AbortReason<Deadline.Cause<Reason>>
  {Fetch.dnsAbort(Reason, Abort.Supplied{Deadline.ParentAbort{why}}) == Fetch.requestAbort(Reason, why) : Fetch.Category}

law resolver_setup_failures_are_not_retried:
  for -Reason: Data
  {Fetch.setup(Reason, Setup.NoServers{}) == Fetch.NonRetryable{} : Fetch.Category}

law unanswered_lookups_are_connection_failures:
  for -Reason: Data
  for error: Response.Error
  {Fetch.dnsReport(Reason, DNS.Report{Fail{Search.NoAnswer{error}}, None{}}) == Fetch.Connection{} : Fetch.Category}

law terminal_query_failures_are_not_retried:
  for -Reason: Data
  for reports: Pair.Reports<Result<&2, &2, Lookup.Error<Deadline.Cause<Reason>>, Answer.Selection>>
  {Fetch.dnsReport(Reason, DNS.Report{Fail{Search.Halted{DNS.QueryFailed{reports}}}, None{}}) == Fetch.NonRetryable{} : Fetch.Category}

law dns_deadline_overrides_the_report:
  for -Reason: Data
  for fallback: Fetch.Category
  for why: Abort.AbortReason<Deadline.Cause<Deadline.Cause<Reason>>>
  {Fetch.dnsDeadline(Reason, fallback, Some{why}) == Fetch.dnsAbort(Reason, why) : Fetch.Category}
