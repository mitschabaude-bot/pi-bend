import Base
import ./laws/provider-http-response.bend as ProviderHTTPResponse
import ./laws/provider-retry.bend as ProviderRetry
import ./laws/http-body-buffer.bend as HTTPBodyBuffer
import ./laws/http-abort-classification.bend as HTTPAbortClassification
import ./laws/http-body-source.bend as HTTPBodySource
import ./laws/http-response-progress.bend as HTTPResponseProgress
import ./laws/http-response-metadata.bend as HTTPResponseMetadata
import ./laws/http-exchange-plan.bend as HTTPExchangePlan
import ./laws/connection-plan.bend as ConnectionPlan
import ./laws/connection-progress.bend as ConnectionProgress
import ./laws/connection-attempt-result.bend as ConnectionAttemptResult
import ./laws/list-interleave.bend as ListInterleave
import ./laws/connection-addresses.bend as ConnectionAddresses
import ./laws/http-host-route.bend as HTTPHostRoute
import ./laws/numeric-scope.bend as NumericScope
import ./laws/numeric-host.bend as NumericHost
import ./laws/dns-pair-queries.bend as DNSPairQueries
import ./laws/dns-pair-result.bend as DNSPairResult
import ./laws/dns-search-text.bend as DNSSearchText
import ./laws/hosts-resolve.bend as HostsResolve
import ./laws/utf8-strict.bend as UTF8Strict
import ./laws/bounded-bytes.bend as BoundedBytes
import ./laws/hosts.bend as Hosts
import ./laws/resolver-configuration.bend as ResolverConfiguration
import ./laws/dns-search-run.bend as DNSSearchRun
import ./laws/resolver-transport.bend as ResolverTransport
import ./laws/dns-edns-response.bend as DNSEdnsResponse
import ./laws/dns-transport-choice.bend as DNSTransportChoice
import ./laws/dns-udp-policy.bend as DNSUDPPolicy
import ./laws/dns-udp-plan.bend as DNSUDPPlan
import ./laws/dns-udp-timeout.bend as DNSUDPTimeout
import ./laws/dns-udp-schedule.bend as DNSUDPSchedule
import ./laws/abort-outcome.bend as AbortOutcome
import ./laws/resolver-search.bend as ResolverSearch
import ./laws/resolver-request.bend as ResolverRequest
import ./laws/dns-query.bend as DNSQuery
import ./laws/agent-events.bend as AgentEvents
import ./laws/agent-owner.bend as AgentOwner
import ./laws/sse-decoder.bend as SSEDecoder
import ./laws/line-decoder.bend as LineDecoder
import ./laws/ordered-map.bend as OrderedMap
import ./laws/record.bend as Record
import ./laws/string-set.bend as StringSet
import ./laws/agent-queues.bend as AgentQueues
import ./laws/pending-queue.bend as Pending
import ./packages/runtime/src/fifo.bend as Fifo

# Observable list semantics, independent of the queue's two-list layout.
type Removal<-A: Data> is Data:
  Removal{remaining: List<&2, A>, value: Maybe<&2, A>}

def uncons(-A: Data, values: List<&2, A>) -> Removal<A>:
  match values:
    case Nil{}: Removal{Nil{}, None{}}
    case head <> tail: Removal{tail, Some{head}}

def observe(-A: Data, result: Fifo.Queue<A> & Maybe<&2, A>) -> Removal<A>:
  match result:
    case Tuple{remaining, value}: Removal{Fifo.drain(A, remaining), value}

law fifo_empty:
  for -A: Data
  {Fifo.drain(A, Fifo.new(A)) == Nil{} : List<&2, A>}

law fifo_enqueue:
  for -A: Data
  for +queue: Fifo.Queue<A>
  for +value: A
  {Fifo.drain(A, Fifo.enqueue(A, queue, value)) == List.append(&2, A, Fifo.drain(A, queue), value <> Nil{}) : List<&2, A>}

law fifo_dequeue:
  for -A: Data
  for +queue: Fifo.Queue<A>
  {observe(A, Fifo.dequeue(A, queue)) == uncons(A, Fifo.drain(A, queue)) : Removal<A>}
