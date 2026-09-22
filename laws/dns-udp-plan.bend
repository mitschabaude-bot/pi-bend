import Base
import ../packages/runtime/src/resolver-config.bend as Plan
import ../packages/runtime/src/resolver-config.bend as Timeout

def values(-Server: Data, entries: List<&2, Plan.Located<Server>>) -> List<&2, Server>:
  match entries:
    case Nil{}: Nil{}
    case Plan.Located{server, _} <> rest: server <> values(Server, rest)

def payloads(-Server: Data, result: Result<&2, &2, Plan.Error, List<&2, Plan.Located<Server>>>) -> Result<&2, &2, Plan.Error, List<&2, Server>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{entries}: Done{values(Server, entries)}

# Reference acceptance domain, independent of the assigned position metadata.
def accepted(-Server: Data, +servers: List<&2, Server>) -> Result<&2, &2, Plan.Error, List<&2, Server>>:
  match servers:
    case Nil{}: Fail{Plan.NoServers{}}
    case _ <> Nil{}: Done{servers}
    case _ <> _ <> Nil{}: Done{servers}
    case _ <> _ <> _ <> Nil{}: Done{servers}
    case _ <> _ <> _ <> _ <> _: Fail{Plan.TooManyServers{}}

law assignment_preserves_payloads:
  for -Server: Data
  for +servers: List<&2, Server>
  {payloads(Server, Plan.locate(Server, servers)) == accepted(Server, servers) : Result<&2, &2, Plan.Error, List<&2, Server>>}

law timing_preserves_identity:
  for -Server: Data
  for +server: Server
  for +position: Timeout.Position
  for +duration: Timeout.Duration
  {Plan.timed(Server, server, position, Done{duration}) == Done{Plan.Attempt{server, position, duration}} : Result<&2, &2, Plan.Error, Plan.Attempt<Server>>}

law invalid_layout_stops_preparation:
  for -Server: Data
  for timeout: U32
  for +error: Plan.Error
  {Plan.located(Server, timeout, Fail{error}) == Fail{error} : Result<&2, &2, Plan.Error, List<&2, Plan.Attempt<Server>>>}
