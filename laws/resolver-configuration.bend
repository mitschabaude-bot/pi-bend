import Base
import ../packages/runtime/src/resolver-configuration.bend as Config
import ../packages/runtime/src/resolver-transport.bend as Transport
import ../packages/runtime/src/resolver-search.bend as Search
import ../packages/runtime/src/resolver-options.bend as Options
import ../packages/runtime/src/resolver-domains.bend as Domains
import ../packages/runtime/src/dns-udp-plan.bend as Plan

# Search and transport cannot accidentally use different option snapshots.
law shared_search_settings:
  for -Server: Data
  for +options: Options.Options
  for servers: List<&2, Plan.Attempt<Server>>
  for +domains: Domains.Report
  for milliseconds: U32
  for maximum: U32
  {Config.search(Server, Config.Config{Transport.Prepared{options, servers}, domains, milliseconds, maximum}) == Search.Configuration{options, domains} : Search.Configuration}

law assembly_retains_configuration:
  for -Server: Data
  for +domains: Domains.Report
  for +milliseconds: U32
  for +maximum: U32
  for +transport: Transport.Prepared<Server>
  {Config.assembled(Server, domains, milliseconds, maximum, Done{transport}) == Done{Config.Config{transport, domains, milliseconds, maximum}} : Result<&2, &2, Plan.Error, Config.Config<Server>>}

law rejects_invalid_transport:
  for -Server: Data
  for domains: Domains.Report
  for milliseconds: U32
  for maximum: U32
  for +error: Plan.Error
  {Config.assembled(Server, domains, milliseconds, maximum, Fail{error}) == Fail{error} : Result<&2, &2, Plan.Error, Config.Config<Server>>}
