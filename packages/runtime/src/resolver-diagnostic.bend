import Base
import ./resolver-system-config.bend as System
import ./resolver-load.bend as Load
import ./resolver-environment.bend as Environment
import ./resolver-file.bend as File
import ./file-fold.bend as Fold
import ./resolver-options.bend as Options
import ./dns-udp-plan.bend as Plan
import ./utf8-strict.bend as UTF8
import ./json-string.bend as Quote

# Native configuration diagnostics retain operation, source code and position.
# The typed report remains available separately; formatting does not determine
# whether a configuration is accepted or silently drop invalid options.
def operatingSystem(operation: String, code: U32, message: String) -> String:
  operation ++ " (code " ++ Nat.show(U32.to_nat(code)) ++ "): " ++ message

def file(error: Fold.Error) -> String:
  match error:
    case Fold.InvalidReadSize{}: "Invalid resolver file read size"
    case Fold.Open{code, message}: operatingSystem("Could not open resolver configuration", code, message)
    case Fold.Read{code, message}: operatingSystem("Could not read resolver configuration", code, message)

def decoding(error: UTF8.Error) -> String:
  match error:
    case UTF8.InvalidByte{offset, value}: "Invalid resolver configuration byte " ++ Nat.show(U32.to_nat(value)) ++ " at offset " ++ Nat.show(offset)
    case UTF8.InvalidSequence{offset, value}: "Invalid resolver configuration UTF-8 sequence at offset " ++ Nat.show(offset) ++ " (byte " ++ Nat.show(U32.to_nat(value)) ++ ")"
    case UTF8.IncompleteSequence{offset}: "Incomplete resolver configuration UTF-8 sequence at offset " ++ Nat.show(offset)

def loading(error: Load.Error<UTF8.Error>) -> String:
  match error:
    case Load.Environment{Environment.Error{variable, code, message}}: operatingSystem("Could not read resolver environment variable " ++ Quote.quote(variable), code, message)
    case Load.File{File.File{cause}}: file(cause)
    case Load.File{File.TooLarge{}}: "Resolver configuration exceeds its byte limit"
    case Load.File{File.Decode{cause}}: decoding(cause)

def transport(error: Plan.Error) -> String:
  match error:
    case Plan.NoServers{}: "Resolver configuration has no name servers"
    case Plan.TooManyServers{}: "Resolver configuration exceeds the supported three name servers"
    case Plan.InvalidTimeout{seconds}: "Invalid resolver timeout in seconds: " ++ Nat.show(U32.to_nat(seconds))

def option(error: Options.Diagnostic) -> String:
  match error:
    case Options.Malformed{token}: "Malformed resolver option " ++ Quote.quote(token)
    case Options.Unknown{token}: "Unknown resolver option " ++ Quote.quote(token)

def options(errors: List<&2, Options.Diagnostic>) -> List<&2, String>:
  match errors:
    case Nil{}: Nil{}
    case first <> rest: option(first) <> options(rest)

# Keep each invalid option as its own diagnostic instead of flattening an
# arbitrary list with ambiguous separators. Provider presentation can join it.
def messages(error: System.Error<UTF8.Error>) -> List<&2, String>:
  match error:
    case System.Loading{cause}: loading(cause) <> Nil{}
    case System.InvalidTransport{_, cause}: transport(cause) <> Nil{}
    case System.InvalidOptions{_, errors}: options(errors)
