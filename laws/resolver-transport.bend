import Base
import ../packages/runtime/src/resolver-transport.bend as Transport
import ../packages/runtime/src/resolver-options.bend as Options
import ../packages/runtime/src/dns-udp-plan.bend as Plan

# Assembly must retain the full settings, including options interpreted by
# later layers, and every timed entry with its original-position metadata.
law settings_and_entries_preserved:
  for -Server: Data
  for +options: Options.Options
  for +entries: List<&2, Plan.Attempt<Server>>
  {Transport.timed(Server, options, Done{entries}) == Done{Transport.Prepared{options, entries}} : Result<&2, &2, Plan.Error, Transport.Prepared<Server>>}

law preparation_failure_retained:
  for -Server: Data
  for options: Options.Options
  for +error: Plan.Error
  {Transport.timed(Server, options, Fail{error}) == Fail{error} : Result<&2, &2, Plan.Error, Transport.Prepared<Server>>}
