import Base
import ../packages/runtime/src/resolver-config.bend as Transport
import ../packages/runtime/src/resolver-config.bend as Options
import ../packages/runtime/src/resolver-config.bend as Plan

# Assembly must retain the full settings, including options interpreted by
# later layers, and every timed entry with its original-position metadata.
law settings_and_entries_preserved:
  for -Server: Data
  for +options: Options.OptionsOptions
  for +entries: List<&2, Plan.Attempt<Server>>
  {Transport.timedTransport(Server, options, Done{entries}) == Done{Transport.TransportPrepared{options, entries}} : Result<&2, &2, Plan.Error, Transport.TransportPrepared<Server>>}

law preparation_failure_retained:
  for -Server: Data
  for options: Options.OptionsOptions
  for +error: Plan.Error
  {Transport.timedTransport(Server, options, Fail{error}) == Fail{error} : Result<&2, &2, Plan.Error, Transport.TransportPrepared<Server>>}
