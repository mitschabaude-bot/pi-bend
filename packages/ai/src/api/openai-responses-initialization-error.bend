import Base
import ./openai-responses-cleartext-system-runtime.bend as System
import ./openai-responses-cleartext-runtime.bend as Runtime
import ../../../runtime/src/resolver-diagnostic.bend as Resolver
import ../../../runtime/src/random-index.bend as Index
import ../../../runtime/src/random-seed.bend as Seed

# Initialization failures are native diagnostics, distinct from provider HTTP
# errors. Never substitute a seed, retry an invalid configuration, or lose the
# operating-system cause merely to produce a display string.
def resolverEntropy(error: Index.Error) -> String:
  match error:
    case Index.InvalidBound{}: "Invalid resolver random-index bound"
    case Index.InvalidBytes{}: "Resolver entropy source returned invalid bytes"
    case Index.SourceFailure{code, message}: Resolver.operatingSystem("Could not obtain resolver entropy", code, message)

def retryEntropy(error: Seed.SeedError) -> String:
  match error:
    case Seed.SourceFailure{code, message}: Resolver.operatingSystem("Could not obtain retry entropy", code, message)
    case Seed.ShortSeed{bytes}: "Retry entropy source returned " ++ Nat.show(bytes) ++ " bytes; expected 8"

def runtime(error: Runtime.Error) -> String:
  match error:
    case Runtime.ResolverFailure{cause}: resolverEntropy(cause)
    case Runtime.RetryFailure{cause}: retryEntropy(cause)

def messages(error: System.Error) -> List<&2, String>:
  match error:
    case System.ConfigurationFailure{cause}: Resolver.messages(cause)
    case System.InitializationFailure{cause}: runtime(cause) <> Nil{}

def remaining(messages: List<&2, String>) -> String:
  match messages:
    case Nil{}: ""
    case first <> rest: "; " ++ first ++ remaining(rest)

# A manually constructed empty diagnostic list gets a generic presentation;
# the typed error remains unchanged and no synthetic cause is added to it.
def display(messages: List<&2, String>) -> String:
  match messages:
    case Nil{}: "Invalid resolver configuration"
    case first <> rest: first ++ remaining(rest)

def format(error: System.Error) -> String: display(messages(error))
