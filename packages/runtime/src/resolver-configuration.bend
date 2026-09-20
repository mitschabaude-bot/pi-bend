import Base
import ./resolver-transport.bend as Transport
import ./resolver-search.bend as Search
import ./resolver-domains.bend as Domains
import ./resolver-options.bend as Options
import ./dns-udp-plan.bend as Plan

# A complete immutable configuration. Options have one canonical home in
# transport; request/search projections use those same retained settings.
type Config<-Server: Data> is Data:
  Config{transport: Transport.Prepared<Server>, domains: Domains.Report, milliseconds: U32, maximum: U32}

def assembled(-Server: Data, domains: Domains.Report, milliseconds: U32, maximum: U32, result: Result<&2, &2, Plan.Error, Transport.Prepared<Server>>) -> Result<&2, &2, Plan.Error, Config<Server>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{transport}: Done{Config{transport, domains, milliseconds, maximum}}

def prepare(-Server: Data, servers: List<&2, Server>, milliseconds: U32, maximum: U32, search: Search.Configuration) -> Result<&2, &2, Plan.Error, Config<Server>>:
  match search:
    case Search.Configuration{options, domains}: assembled(Server, domains, milliseconds, maximum, Transport.prepare(Server, options, servers))

def search(-Server: Data, config: Config<Server>) -> Search.Configuration:
  match config:
    case Config{Transport.Prepared{options, _}, domains, _, _}: Search.Configuration{options, domains}

def rotating(-Server: Data, config: Config<Server>) -> Bool:
  match config:
    case Config{Transport.Prepared{options, _}, _, _, _}: Options.enabled(Options.Rotate{}, options)
