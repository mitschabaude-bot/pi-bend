import Base
import ./connection-driver.bend as Candidates
import ./http-host-route.bend as Route
import ./hosts.bend as Hosts
import ./dns-resolver.bend as Named
import ./dns-resolver.bend as Search
import ./dns-resolver.bend as Pair
import ./dns-resolver.bend as Lookup
import ./dns-resolver.bend as Answer
import ./abortable-connect.bend as Connect

def family(-Reason: Data, report: Pair.Classified<Result<&2, &2, Lookup.AddressLookupError<Reason>, Answer.Selection>>) -> List<&2, Connect.Address>:
  match report:
    case Pair.Classified{Done{Answer.Selection{_, addresses}}, Pair.Answer{}}: Candidates.answers(addresses)
    case _: Nil{}

def network(-Original: Data, -Reason: Data, original: Original, report: Search.PairSearchReport<Reason>) -> Candidates.Plan<Original>:
  match report:
    case Search.PairSearchReport{Done{Pair.PairResultReports{ipv4, ipv6}}, _}: Candidates.paired(Original, original, family(Reason, ipv4), family(Reason, ipv6))
    case _: Candidates.NoAddresses{original}

def named(-Original: Data, -Reason: Data, -Error: Data, original: Original, report: Hosts.Report<Error, Named.PairHostsResolverDNS<Reason>>) -> Candidates.Plan<Original>:
  match report:
    case Hosts.FromHosts{first, rest}: Candidates.ordered(Original, original, Candidates.hosts(first <> rest))
    case Hosts.FromNetwork{Named.PairHostsResolverCompleted{report}}: network(Original, Reason, original, report)
    case _: Candidates.NoAddresses{original}

def project(-Original: Data, -Reason: Data, -Error: Data, original: Original, result: Result<&2, &2, Route.Error, Route.Resolution<Hosts.Report<Error, Named.PairHostsResolverDNS<Reason>>>>) -> Candidates.Plan<Original>:
  match result:
    case Done{Route.NumericAddress{address}}: Candidates.Addresses{original, Candidates.Ordered{address, Nil{}}}
    case Done{Route.Named{report}}: named(Original, Reason, Error, original, report)
    case Fail{_}: Candidates.NoAddresses{original}

# Retain the complete resolution result alongside every projection, including
# negative siblings, canonical names, TTLs and source/deadline errors. A halted
# DNS report never yields candidates, even if one family previously succeeded.
def prepare(-Reason: Data, -Error: Data, +result: Result<&2, &2, Route.Error, Route.Resolution<Hosts.Report<Error, Named.PairHostsResolverDNS<Reason>>>>) -> Candidates.Plan<Result<&2, &2, Route.Error, Route.Resolution<Hosts.Report<Error, Named.PairHostsResolverDNS<Reason>>>>>:
  project(Result<&2, &2, Route.Error, Route.Resolution<Hosts.Report<Error, Named.PairHostsResolverDNS<Reason>>>>, Reason, Error, result, result)
