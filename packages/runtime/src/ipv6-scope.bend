import Base
import ./url-ipv6.bend as IPv6

# Interface names apply only to link-local unicast or node/link-local
# multicast addresses. Decimal indices remain valid for any IPv6 address.
def permitsInterface(address: IPv6.Address) -> Bool:
  match address:
    case IPv6.Address{+word, _, _, _}:
      U32.is_eq((word / 4194304 : U32), 1018) ||
        (U32.is_eq((word / 16777216 : U32), 255) &&
          (U32.is_eq((word / 65536 % 16 : U32), 1) || U32.is_eq((word / 65536 % 16 : U32), 2)))

def accumulated(valid: Bool, value: U32, digit: U32) -> Maybe<&2, U32>:
  match valid:
    case False{}: None{}
    case True{}: Some{(value * 10 + digit : U32)}

def digit(+code: U32, +value: U32) -> Maybe<&2, U32>:
  accumulated(U32.is_ge(code, 48) && U32.is_le(code, 57) &&
    (U32.is_lt(value, 429496729) || (U32.is_eq(value, 429496729) && U32.is_le(code, 53))), value, (code - 48 : U32))

def digits(text: String, state: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match text state:
    case _ None{}: None{}
    case SNil{} result: result
    case SCon{Chr{code}, rest} Some{value}: digits(rest, digit(code, value))

def decimal(text: String) -> Maybe<&2, U32>:
  match text:
    case SNil{}: None{}
    case other: digits(other, Some{0})

type Error<-LookupError: Data> is Data:
  InvalidScope{scope: String, lookupFailure: Maybe<&2, LookupError>}

def numeric(-LookupError: Data, scope: String, failure: Maybe<&2, LookupError>, index: Maybe<&2, U32>) -> Result<&2, &2, Error<LookupError>, U32>:
  match index:
    case None{}: Fail{InvalidScope{scope, failure}}
    case Some{value}: Done{value}

def found(-LookupError: Data, valid: Bool, index: U32, +scope: String) -> Result<&2, &2, Error<LookupError>, U32>:
  match valid:
    case True{}: Done{index}
    case False{}: numeric(LookupError, scope, None{}, decimal(scope))

# A failed name lookup still permits a numeric scope. Zero is never an
# interface index, but a textual numeric zero is a valid unspecified scope.
def lookedUp(-LookupError: Data, +scope: String, result: Result<&2, &2, LookupError, U32>) -> Result<&2, &2, Error<LookupError>, U32>:
  match result:
    case Fail{error}: numeric(LookupError, scope, Some{error}, decimal(scope))
    case Done{+index}: found(LookupError, Bool.not(U32.is_zero(index)), index, scope)

def permittedWith(~LookupError: Data, ~Context: Data, ~lookup: Context -> String -> IO(Result<&2, &2, LookupError, U32>), context: Context, permitted: Bool, +scope: String) -> IO(Result<&2, &2, Error<LookupError>, U32>):
  match permitted:
    case False{}: IO.pure(Result<&2, &2, Error<LookupError>, U32>, numeric(LookupError, scope, None{}, decimal(scope)))
    case True{}:
      do IO<Result<&2, &2, Error<LookupError>, U32>>:
        result : Result<&2, &2, LookupError, U32> <- lookup(context, scope)
        return lookedUp(LookupError, scope, result)

def resolveWith(~LookupError: Data, ~Context: Data, ~lookup: Context -> String -> IO(Result<&2, &2, LookupError, U32>), context: Context, address: IPv6.Address, scope: String) -> IO(Result<&2, &2, Error<LookupError>, U32>):
  permittedWith(~LookupError, ~Context, ~lookup, context, permitsInterface(address), scope)
