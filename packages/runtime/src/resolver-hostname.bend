import Base
import ./resolver-config.bend as Config
import ./resolver-environment.bend as Environment

type Failure is Data:
  Failure{code: U32, message: String}

type Report is Data:
  Report{hostname: Maybe<&2, String>, failure: Maybe<&2, Failure>}

# Domain/search directives replace a search list but never erase its presence.
# One such entry is enough to know hostname fallback is unnecessary.
def fileNeedsHostname(entries: List<&2, Config.Entry>) -> Bool:
  match entries:
    case Nil{}: True{}
    case Config.Domain{_} <> _: False{}
    case Config.Search{_} <> _: False{}
    case _ <> rest: fileNeedsHostname(rest)

def needed(entries: List<&2, Config.Entry>, values: Environment.Values) -> Bool:
  match values:
    case Environment.Values{Some{_}, _}: False{}
    case Environment.Values{None{}, _}: fileNeedsHostname(entries)

# Failure leaves the fallback absent, preserving a diagnostic for the caller.
# It does not discard the valid file/environment settings or invent a domain.
def reported(result: Result<&1, &1, U32 & String, String>) -> Report:
  match result:
    case Done{name}: Report{Some{name}, None{}}
    case Fail{(code, message)}: Report{None{}, Some{Failure{code, message}}}

def required(~Context: Data, ~lookup: Context -> IO(Result<&1, &1, U32 & String, String>), context: Context, useHostname: Bool) -> IO(Report):
  match useHostname:
    case False{}: IO.pure(Report, Report{None{}, None{}})
    case True{}:
      do IO<Report>:
        result : Result<&1, &1, U32 & String, String> <- lookup(context)
        return reported(result)

def resolveWith(~Context: Data, ~lookup: Context -> IO(Result<&1, &1, U32 & String, String>), context: Context, entries: List<&2, Config.Entry>, values: Environment.Values) -> IO(Report):
  required(~Context, ~lookup, context, needed(entries, values))
