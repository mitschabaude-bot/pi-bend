import Base
import ./resolver-options.bend as Options
import ./dns-udp-plan.bend as Plan

# Preserve all parsed options alongside entries timed in configuration order.
# Rotation must operate on these entries, never recompute their positions.
type Prepared<-Server: Data> is Data:
  Prepared{options: Options.Options, servers: List<&2, Plan.Attempt<Server>>}

def timed(-Server: Data, options: Options.Options, result: Result<&2, &2, Plan.Error, List<&2, Plan.Attempt<Server>>>) -> Result<&2, &2, Plan.Error, Prepared<Server>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{servers}: Done{Prepared{options, servers}}

def prepare(-Server: Data, options: Options.Options, servers: List<&2, Server>) -> Result<&2, &2, Plan.Error, Prepared<Server>>:
  match options:
    case Options.Options{ndots, +timeout, attempts, features}: timed(Server, Options.Options{ndots, timeout, attempts, features}, Plan.prepare(Server, timeout, servers))
