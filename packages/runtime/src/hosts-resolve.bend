import Base
import ./hosts.bend as Hosts
import ./hosts-file.bend as File
import ./hosts-family.bend as Family

# An explicit files-then-network policy over an already loaded snapshot.
# Source failures are terminal. Only absence of eligible rows permits DNS.
# Keep provenance and complete native reports instead of inventing DNS TTLs
# or wire names for local entries.
type Plan<-Error: Data> is Data:
  SourceFailure{error: Error}
  Local{first: Hosts.Entry<File.Address>, rest: List<&2, Hosts.Entry<File.Address>>}
  Query{family: Family.Family, name: String}

def selected(-Error: Data, family: Family.Family, name: String, entries: List<&2, Hosts.Entry<File.Address>>) -> Plan<Error>:
  match entries:
    case Nil{}: Query{family, name}
    case first <> rest: Local{first, rest}

def plan(-Error: Data, +family: Family.Family, +name: String, source: Result<&2, &2, Error, List<&2, Hosts.Entry<File.Address>>>) -> Plan<Error>:
  match source:
    case Fail{error}: SourceFailure{error}
    case Done{entries}: selected(Error, family, name, Family.lookup(family, name, entries))

type Report<-Error: Data, -Network: Data> is Data:
  FailedSource{error: Error}
  FromHosts{first: Hosts.Entry<File.Address>, rest: List<&2, Hosts.Entry<File.Address>>}
  FromNetwork{report: Network}

def execute(~Context: Data, ~Error: Data, ~Network: Data, ~lookup: Context -> Family.Family -> String -> IO(Network), context: Context, plan: Plan<Error>) -> IO(Report<Error, Network>):
  match plan:
    case SourceFailure{error}: IO.pure(Report<Error, Network>, FailedSource{error})
    case Local{first, rest}: IO.pure(Report<Error, Network>, FromHosts{first, rest})
    case Query{family, name}:
      do IO<Report<Error, Network>>:
        result : Network <- lookup(context, family, name)
        return FromNetwork{result}

# The callback receives the original spelling only after a hosts miss.
# DNS parsing, search suffixes and network ownership belong to that callback.
def resolveWith(~Context: Data, ~Error: Data, ~Network: Data, ~lookup: Context -> Family.Family -> String -> IO(Network), context: Context, family: Family.Family, name: String, source: Result<&2, &2, Error, List<&2, Hosts.Entry<File.Address>>>) -> IO(Report<Error, Network>):
  execute(~Context, ~Error, ~Network, ~lookup, context, plan(Error, family, name, source))
