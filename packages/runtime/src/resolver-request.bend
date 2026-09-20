import Base
import ./resolver-options.bend as Resolver
import ./dns-query.bend as Query
import ./dns-edns.bend as Edns

# Request policy is only one projection of resolver settings. Keep all values
# for the later transport, retry, rotation, response and reload layers.
type Prepared is Data:
  Prepared{resolver: Resolver.Options, request: Query.Options}

# glibc 2.39 uses 1200 for ordinary resolver EDNS advertisement. Trust-AD
# controls the header AD bit, not DNSSEC OK; edns0 alone does not enable DO.
def selected(edns: Bool, trustAd: Bool) -> Query.Options:
  Query.Options{Bool.pick(U32, trustAd, 288, 256), Bool.pick(Maybe<&2, Edns.Query>, edns, Some{Edns.Query{1200, False{}, Nil{}}}, None{})}

def prepare(+options: Resolver.Options) -> Prepared:
  Prepared{options, selected(Resolver.enabled(Resolver.Edns{}, options), Resolver.enabled(Resolver.TrustAd{}, options))}

# Any diagnostic rejects the entire selection; no partially interpreted
# options become an executable request policy.
def checked(report: Resolver.Report) -> Result<&2, &2, List<&2, Resolver.Diagnostic>, Prepared>:
  match report:
    case Resolver.Report{options, Nil{}}: Done{prepare(options)}
    case Resolver.Report{_, issues}: Fail{issues}

def prepareStrict(tokens: List<&2, String>) -> Result<&2, &2, List<&2, Resolver.Diagnostic>, Prepared>:
  checked(Resolver.interpretStrict(tokens, Resolver.defaults()))
