import Base
import ./dns-udp-timeout.bend as Timeout

type Error is Data:
  NoServers{}
  TooManyServers{}
  InvalidTimeout{seconds: U32}

type Located<-Server: Data> is Data:
  Located{server: Server, position: Timeout.Position}

type Attempt<-Server: Data> is Data:
  Attempt{server: Server, position: Timeout.Position, duration: Timeout.Duration}

# Assign once in configuration order, before a rotation owner sees the entries.
# This checked UDP boundary accepts the supported one-to-three-server layouts.
# It never silently discards an excess entry or merges duplicate endpoints.
def locate(-Server: Data, servers: List<&2, Server>) -> Result<&2, &2, Error, List<&2, Located<Server>>>:
  match servers:
    case Nil{}: Fail{NoServers{}}
    case first <> Nil{}: Done{Located{first, Timeout.First{}} <> Nil{}}
    case first <> second <> Nil{}: Done{Located{first, Timeout.First{}} <> Located{second, Timeout.SecondOfTwo{}} <> Nil{}}
    case first <> second <> third <> Nil{}: Done{Located{first, Timeout.First{}} <> Located{second, Timeout.SecondOfThree{}} <> Located{third, Timeout.ThirdOfThree{}} <> Nil{}}
    case _ <> _ <> _ <> _ <> _: Fail{TooManyServers{}}

def timed(-Server: Data, server: Server, position: Timeout.Position, result: Result<&2, &2, Timeout.Error, Timeout.Duration>) -> Result<&2, &2, Error, Attempt<Server>>:
  match result:
    case Fail{Timeout.InvalidTimeout{seconds}}: Fail{InvalidTimeout{seconds}}
    case Done{duration}: Done{Attempt{server, position, duration}}

def entry(-Server: Data, timeout: U32, value: Located<Server>) -> Result<&2, &2, Error, Attempt<Server>>:
  match value:
    case Located{server, +position}: timed(Server, server, position, Timeout.budget(timeout, position))

def appended(-Server: Data, accumulated: Result<&2, &2, Error, List<&2, Attempt<Server>>>, result: Result<&2, &2, Error, Attempt<Server>>) -> Result<&2, &2, Error, List<&2, Attempt<Server>>>:
  match accumulated result:
    case Fail{error} _: Fail{error}
    case Done{_} Fail{error}: Fail{error}
    case Done{reversed} Done{attempt}: Done{attempt <> reversed}

def budgets(-Server: Data, values: List<&2, Located<Server>>, +timeout: U32, accumulated: Result<&2, &2, Error, List<&2, Attempt<Server>>>) -> Result<&2, &2, Error, List<&2, Attempt<Server>>>:
  match values accumulated:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{reversed}: Done{List.reverse(&2, Attempt<Server>, reversed)}
    case first <> rest previous: budgets(Server, rest, timeout, appended(Server, previous, entry(Server, timeout, first)))

def located(-Server: Data, timeout: U32, result: Result<&2, &2, Error, List<&2, Located<Server>>>) -> Result<&2, &2, Error, List<&2, Attempt<Server>>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{values}: budgets(Server, values, timeout, Done{Nil{}})

# Success returns only complete timed entries, suitable for rotation and the
# generic retry cursor. Failure exposes no partially accepted plan.
def prepare(-Server: Data, timeout: U32, servers: List<&2, Server>) -> Result<&2, &2, Error, List<&2, Attempt<Server>>>:
  located(Server, timeout, locate(Server, servers))
