import Base
import ./resolver-address.bend as Address
import ./resolver-settings.bend as Settings
import ./resolver-scope.bend as Scope
import ./ipv6-scope.bend as IPv6Scope
import ./dns-tcp-servers.bend as TCP

# Positions refer to the validated Settings.servers list, starting at zero.
# Invalid source tokens remain in Settings.diagnostics, not in this list.
type Issue<-LookupError: Data> is Data:
  Issue{position: Nat, error: IPv6Scope.Error<LookupError>}

type Report<-LookupError: Data> is Data:
  Report{servers: List<&2, TCP.Server>, issues: List<&2, Issue<LookupError>>}

type Configuration<-LookupError: Data> is Data:
  Configuration{settings: Settings.Settings, endpoints: Report<LookupError>}

type State<-LookupError: Data> is Data:
  State{position: Nat, servers: List<&2, TCP.Server>, issues: List<&2, Issue<LookupError>>}

def issues(-LookupError: Data, position: Nat, failure: Maybe<&2, IPv6Scope.Error<LookupError>>, previous: List<&2, Issue<LookupError>>) -> List<&2, Issue<LookupError>>:
  match failure:
    case None{}: previous
    case Some{error}: Issue{position, error} <> previous

def added(-LookupError: Data, state: State<LookupError>, report: Scope.Report<LookupError>) -> State<LookupError>:
  match state report:
    case State{+position, servers, previous} Scope.Report{address, failure}:
      State{(position + 1n : Nat), TCP.Server{address, 53} <> servers, issues(LookupError, position, failure, previous)}

# Resolve in configuration order. Duplicates remain distinct entries, and an
# invalid scope retains its server with scope zero plus a positional diagnostic.
def collectWith(~LookupError: Data, ~Context: Data, ~lookup: Context -> String -> IO(Result<&2, &2, LookupError, U32>), +context: Context, addresses: List<&2, Address.Address>, state: State<LookupError>) -> IO(Report<LookupError>):
  match addresses state:
    case Nil{} State{_, servers, failures}: IO.pure(Report<LookupError>, Report{List.reverse(&2, TCP.Server, servers), List.reverse(&2, Issue<LookupError>, failures)})
    case address <> rest previous:
      do IO<Report<LookupError>>:
        report : Scope.Report<LookupError> <- Scope.resolveWith(~LookupError, ~Context, ~lookup, context, address)
        collectWith(~LookupError, ~Context, ~lookup, context, rest, added(LookupError, previous, report))

def resolveWith(~LookupError: Data, ~Context: Data, ~lookup: Context -> String -> IO(Result<&2, &2, LookupError, U32>), context: Context, addresses: List<&2, Address.Address>) -> IO(Report<LookupError>):
  collectWith(~LookupError, ~Context, ~lookup, context, addresses, State{0n, Nil{}, Nil{}})

# Preserve all source settings for the subsequent search/options/reload policy.
# This phase resolves addresses only; it never applies partial option values.
def prepareWith(~LookupError: Data, ~Context: Data, ~lookup: Context -> String -> IO(Result<&2, &2, LookupError, U32>), context: Context, settings: Settings.Settings) -> IO(Configuration<LookupError>):
  match settings:
    case Settings.Settings{+servers, search, options, sortlist, diagnostics}:
      do IO<Configuration<LookupError>>:
        endpoints : Report<LookupError> <- resolveWith(~LookupError, ~Context, ~lookup, context, servers)
        return Configuration{Settings.Settings{servers, search, options, sortlist, diagnostics}, endpoints}
