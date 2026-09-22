import Base
import ./hosts.bend as Family
import ./url.bend as IPv6
import ./socket.bend as Connect
import ./resolver-config.bend as Zone
import ./ipv6-scope.bend as Scope
import ./network-interface.bend as Interface


# Parsed numeric input, not yet a resolved socket address. A retained IPv6 zone
# must be validated/resolved before connecting. No DNS fallback occurs here.
type Input is Data:
  V4{address: IPv6.Address}
  V6{address: IPv6.Ipv6Address, zone: Maybe<&2, String>}

type Error is Data:
  InvalidAddress{input: String}
  FamilyMismatch{}

def selected(family: Family.Family, input: Input) -> Result<&2, &2, Error, Input>:
  match family input:
    case Family.IPv4Only{} V6{_, _}: Fail{FamilyMismatch{}}
    case Family.IPv6Only{} V4{_}: Fail{FamilyMismatch{}}
    case _ value: Done{value}

def zoned(original: String, zone: Maybe<&2, String>, parsed: Result<&2, &2, Family.Error, Family.Address>) -> Result<&2, &2, Error, Input>:
  match zone parsed:
    case _ Fail{_}: Fail{InvalidAddress{original}}
    case None{} Done{Family.V4{address}}: Done{V4{address}}
    case Some{_} Done{Family.V4{_}}: Fail{InvalidAddress{original}}
    case Some{SNil{}} Done{Family.V6{_}}: Fail{InvalidAddress{original}}
    case scope Done{Family.V6{address}}: Done{V6{address, scope}}

def split(original: String, parts: Zone.Zoned) -> Result<&2, &2, Error, Input>:
  match parts:
    case Zone.Zoned{host, scope}: zoned(original, scope, Family.address(host))

# Strict presentation syntax: no brackets, port, whitespace, abbreviated IPv4,
# hexadecimal/octal IPv4 or leading-zero decimal octets. Zone text is retained
# verbatim, without percent decoding, for the separate scope resolver.
def parse(+text: String) -> Result<&2, &2, Error, Input>:
  split(text, Zone.splitZone(text, ""))

def accepted(family: Family.Family, parsed: Result<&2, &2, Error, Input>) -> Result<&2, &2, Error, Input>:
  match parsed:
    case Fail{error}: Fail{error}
    case Done{input}: selected(family, input)

def prepare(family: Family.Family, text: String) -> Result<&2, &2, Error, Input>:
  accepted(family, parse(text))


type ScopeError<-LookupError: Data> is Data:
  InvalidInput{error: Error}
  InvalidScope{error: Scope.Error<LookupError>}

type Plan<-LookupError: Data> is Data:
  Ready{result: Result<&2, &2, ScopeError<LookupError>, Connect.Address>}
  ResolveZone{address: IPv6.Ipv6Address, zone: String}

# Parsing/family errors and unscoped addresses require no interface lookup.
def plan(-LookupError: Data, input: Result<&2, &2, Error, Input>) -> Plan<LookupError>:
  match input:
    case Fail{error}: Ready{Fail{InvalidInput{error}}}
    case Done{V4{address}}: Ready{Done{Connect.V4{address}}}
    case Done{V6{address, None{}}}: Ready{Done{Connect.V6{address, 0}}}
    case Done{V6{address, Some{zone}}}: ResolveZone{address, zone}

# Destination failures are terminal; never silently substitute scope zero.
def resolved(-LookupError: Data, address: IPv6.Ipv6Address, result: Result<&2, &2, Scope.Error<LookupError>, U32>) -> Result<&2, &2, ScopeError<LookupError>, Connect.Address>:
  match result:
    case Fail{error}: Fail{InvalidScope{error}}
    case Done{scope}: Done{Connect.V6{address, scope}}

def execute(~LookupError: Data, ~Context: Data, ~lookup: Context -> String -> IO(Result<&2, &2, LookupError, U32>), context: Context, plan: Plan<LookupError>) -> IO(Result<&2, &2, ScopeError<LookupError>, Connect.Address>):
  match plan:
    case Ready{result}: IO.pure(Result<&2, &2, ScopeError<LookupError>, Connect.Address>, result)
    case ResolveZone{+address, zone}:
      do IO<Result<&2, &2, ScopeError<LookupError>, Connect.Address>>:
        result : Result<&2, &2, Scope.Error<LookupError>, U32> <- Scope.resolveWith(~LookupError, ~Context, ~lookup, context, address, zone)
        return resolved(LookupError, address, result)

def resolveWith(~LookupError: Data, ~Context: Data, ~lookup: Context -> String -> IO(Result<&2, &2, LookupError, U32>), context: Context, input: Result<&2, &2, Error, Input>) -> IO(Result<&2, &2, ScopeError<LookupError>, Connect.Address>):
  execute(~LookupError, ~Context, ~lookup, context, plan(LookupError, input))

def prepareWith(~LookupError: Data, ~Context: Data, ~lookup: Context -> String -> IO(Result<&2, &2, LookupError, U32>), context: Context, family: Family.Family, text: String) -> IO(Result<&2, &2, ScopeError<LookupError>, Connect.Address>):
  resolveWith(~LookupError, ~Context, ~lookup, context, prepare(family, text))


# Resolve a numeric destination through the native interface-index primitive.
# No DNS, resolver owner, hosts file, port or connection is involved.
def prepareInterface(family: Family.Family, text: String) -> IO(Result<&2, &2, ScopeError<Interface.Error>, Connect.Address>):
  prepareWith(~Interface.Error, ~Unit, ~Interface.lookup, Unit{}, family, text)
