import Base
import ../packages/runtime/src/resolver-config.bend as Config
import ../packages/runtime/src/resolver-config.bend as Transport
import ../packages/runtime/src/resolver-config.bend as Search
import ../packages/runtime/src/resolver-config.bend as Options
import ../packages/runtime/src/resolver-config.bend as Domains
import ../packages/runtime/src/resolver-config.bend as Plan

# Search and transport cannot accidentally use different option snapshots.
law shared_search_settings:
  for -Server: Data
  for +options: Options.ResolverOptions
  for servers: List<&2, Plan.Attempt<Server>>
  for +domains: Domains.Report
  for milliseconds: U32
  for maximum: U32
  {Config.search(Server, Config.Config{Transport.TransportPrepared{options, servers}, domains, milliseconds, maximum}) == Search.Configuration{options, domains} : Search.Configuration}

law assembly_retains_configuration:
  for -Server: Data
  for +domains: Domains.Report
  for +milliseconds: U32
  for +maximum: U32
  for +transport: Transport.TransportPrepared<Server>
  {Config.assembled(Server, domains, milliseconds, maximum, Done{transport}) == Done{Config.Config{transport, domains, milliseconds, maximum}} : Result<&2, &2, Plan.Error, Config.Config<Server>>}

law rejects_invalid_transport:
  for -Server: Data
  for domains: Domains.Report
  for milliseconds: U32
  for maximum: U32
  for +error: Plan.Error
  {Config.assembled(Server, domains, milliseconds, maximum, Fail{error}) == Fail{error} : Result<&2, &2, Plan.Error, Config.Config<Server>>}
