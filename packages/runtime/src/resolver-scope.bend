import Base
import ./resolver-address.bend as Address
import ./url-ipv6.bend as IPv6
import ./ipv6-scope.bend as Scope
import ./abortable-connect.bend as Connect

type Report<-LookupError: Data> is Data:
  Report{address: Connect.Address, scopeFailure: Maybe<&2, Scope.Error<LookupError>>}

# Resolver configuration follows libc's nonfatal scope policy: an unresolved
# zone retains its address with scope zero. Keep the failure available to callers.
def resolved(-LookupError: Data, address: IPv6.Address, result: Result<&2, &2, Scope.Error<LookupError>, U32>) -> Report<LookupError>:
  match result:
    case Done{scope}: Report{Connect.V6{address, scope}, None{}}
    case Fail{error}: Report{Connect.V6{address, 0}, Some{error}}

def resolveWith(~LookupError: Data, ~Context: Data, ~lookup: Context -> String -> IO(Result<&2, &2, LookupError, U32>), context: Context, address: Address.Address) -> IO(Report<LookupError>):
  match address:
    case Address.V4{value}: IO.pure(Report<LookupError>, Report{Connect.V4{value}, None{}})
    case Address.V6{value, None{}}: IO.pure(Report<LookupError>, Report{Connect.V6{value, 0}, None{}})
    case Address.V6{+value, Some{scope}}:
      do IO<Report<LookupError>>:
        result : Result<&2, &2, Scope.Error<LookupError>, U32> <- Scope.resolveWith(~LookupError, ~Context, ~lookup, context, value, scope)
        return resolved(LookupError, value, result)
