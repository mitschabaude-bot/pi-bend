import Base
import ./numeric-host.bend as Host
import ./hosts.bend as Family
import ./ipv6-scope.bend as Scope
import ./url-ipv6.bend as IPv6
import ./abortable-connect.bend as Connect

type Error<-LookupError: Data> is Data:
  InvalidInput{error: Host.Error}
  InvalidScope{error: Scope.Error<LookupError>}

type Plan<-LookupError: Data> is Data:
  Ready{result: Result<&2, &2, Error<LookupError>, Connect.Address>}
  ResolveZone{address: IPv6.Address, zone: String}

# Parsing/family errors and unscoped addresses require no interface lookup.
def plan(-LookupError: Data, input: Result<&2, &2, Host.Error, Host.Input>) -> Plan<LookupError>:
  match input:
    case Fail{error}: Ready{Fail{InvalidInput{error}}}
    case Done{Host.V4{address}}: Ready{Done{Connect.V4{address}}}
    case Done{Host.V6{address, None{}}}: Ready{Done{Connect.V6{address, 0}}}
    case Done{Host.V6{address, Some{zone}}}: ResolveZone{address, zone}

# Destination failures are terminal; never silently substitute scope zero.
def resolved(-LookupError: Data, address: IPv6.Address, result: Result<&2, &2, Scope.Error<LookupError>, U32>) -> Result<&2, &2, Error<LookupError>, Connect.Address>:
  match result:
    case Fail{error}: Fail{InvalidScope{error}}
    case Done{scope}: Done{Connect.V6{address, scope}}

def execute(~LookupError: Data, ~Context: Data, ~lookup: Context -> String -> IO(Result<&2, &2, LookupError, U32>), context: Context, plan: Plan<LookupError>) -> IO(Result<&2, &2, Error<LookupError>, Connect.Address>):
  match plan:
    case Ready{result}: IO.pure(Result<&2, &2, Error<LookupError>, Connect.Address>, result)
    case ResolveZone{+address, zone}:
      do IO<Result<&2, &2, Error<LookupError>, Connect.Address>>:
        result : Result<&2, &2, Scope.Error<LookupError>, U32> <- Scope.resolveWith(~LookupError, ~Context, ~lookup, context, address, zone)
        return resolved(LookupError, address, result)

def resolveWith(~LookupError: Data, ~Context: Data, ~lookup: Context -> String -> IO(Result<&2, &2, LookupError, U32>), context: Context, input: Result<&2, &2, Host.Error, Host.Input>) -> IO(Result<&2, &2, Error<LookupError>, Connect.Address>):
  execute(~LookupError, ~Context, ~lookup, context, plan(LookupError, input))

def prepareWith(~LookupError: Data, ~Context: Data, ~lookup: Context -> String -> IO(Result<&2, &2, LookupError, U32>), context: Context, family: Family.Family, text: String) -> IO(Result<&2, &2, Error<LookupError>, Connect.Address>):
  resolveWith(~LookupError, ~Context, ~lookup, context, Host.prepare(family, text))
