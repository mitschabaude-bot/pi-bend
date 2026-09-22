import Base
import ./dns-message.bend as Case
import ./url.bend as IPv4
import ./url.bend as IPv6
import ./string-split.bend as Split
import ./utf8-strict.bend as UTF8
import ./bounded-file.bend as File

# A hosts entry retains the file's canonical spelling and aliases. Address
# values are generic so name matching and ordering laws need no socket IO.
type Entry<-Address: Data> is Data:
  Entry{addressLocal: Address, canonical: String, aliases: List<&2, String>}

def same(left: String, right: String) -> Bool:
  match left right:
    case SNil{} SNil{}: True{}
    case SCon{Chr{a}, xs} SCon{Chr{b}, ys}: U32.is_eq(Case.fold(a), Case.fold(b)) && same(xs, ys)
    case _ _: False{}

def alias(+name: String, names: List<&2, String>) -> Bool:
  match names:
    case Nil{}: False{}
    case first <> rest: same(name, first) || alias(name, rest)

def matches(-Address: Data, +name: String, entry: Entry<Address>) -> Bool:
  match entry:
    case Entry{_, canonical, aliases}: same(name, canonical) || alias(name, aliases)

def selected(-Address: Data, matches: Bool, entry: Entry<Address>, rest: List<&2, Entry<Address>>) -> List<&2, Entry<Address>>:
  match matches:
    case True{}: entry <> rest
    case False{}: rest

# Preserve all matching occurrences, including duplicates, in source order.
# Address-family policy and canonical-name selection belong to the caller.
def lookup(-Address: Data, +name: String, entries: List<&2, Entry<Address>>) -> List<&2, Entry<Address>>:
  match entries:
    case Nil{}: Nil{}
    case +first <> rest: selected(Address, matches(Address, name, first), first, lookup(Address, name, rest))

type Address is Data:
  V4{value: IPv4.Address}
  V6{value: IPv6.Ipv6Address}

type Error is Data:
  InvalidAddress{token: String}
  MissingName{}
  InvalidControl{code: U32}

type Failure is Data:
  Failure{line: Nat, error: Error}

# Hosts addresses use strict presentation syntax, not URL/inet_aton numbers.
# No port, brackets, abbreviated IPv4 or interface-zone suffix is accepted.
def v6(token: String, result: Result<&2, &2, IPv6.Ipv6AddressError, IPv6.Ipv6Address>) -> Result<&2, &2, Error, Address>:
  match result:
    case Done{value}: Done{V6{value}}
    case Fail{_}: Fail{InvalidAddress{token}}

def v4(+token: String, result: Result<&2, &2, IPv6.Ipv6AddressError, List<&2, U32>>) -> Result<&2, &2, Error, Address>:
  match result:
    case Done{a <> b <> Nil{}}: Done{V4{IPv4.Address{(a * 65536 + b : U32)}}}
    case _: v6(token, IPv6.parseIpv6(token))

def address(+token: String) -> Result<&2, &2, Error, Address>:
  v4(token, IPv6.embedded(Split.split(token, '.')))

def push(part: String, fields: List<&2, String>) -> List<&2, String>:
  match part:
    case SNil{}: fields
    case other: String.reverse(other) <> fields

def space(+code: U32) -> Bool:
  U32.is_eq(code, 32) || (U32.is_ge(code, 9) && U32.is_le(code, 13))

type Words is Data:
  Words{part: String, fields: List<&2, String>}

def stepped(whitespace: Bool, invalid: Bool, code: U32, state: Words) -> Result<&2, &2, Error, Words>:
  match whitespace invalid state:
    case True{} _ Words{part, fields}: Done{Words{"", push(part, fields)}}
    case False{} True{} _: Fail{InvalidControl{code}}
    case False{} False{} Words{part, fields}: Done{Words{SCon{Chr{code}, part}, fields}}

def finish(state: Words) -> Result<&2, &2, Error, List<&2, String>>:
  match state:
    case Words{part, fields}: Done{List.reverse(&2, String, push(part, fields))}

def advance(char: Char, words: Words) -> Result<&2, &2, Error, Words>:
  match char:
    case Chr{+code}: stepped(space(code), U32.is_lt(code, 32) || U32.is_eq(code, 127), code, words)

def tokens(text: String, state: Result<&2, &2, Error, Words>) -> Result<&2, &2, Error, List<&2, String>>:
  match text state:
    case _ Fail{error}: Fail{error}
    case SNil{} Done{words}: finish(words)
    case SCon{'#', _} Done{words}: finish(words)
    case SCon{char, rest} Done{words}: tokens(rest, advance(char, words))

def named(canonical: String, aliases: List<&2, String>, value: Result<&2, &2, Error, Address>) -> Result<&2, &2, Error, Maybe<&2, Entry<Address>>>:
  match value:
    case Fail{error}: Fail{error}
    case Done{value}: Done{Some{Entry{value, canonical, aliases}}}

def entry(fields: Result<&2, &2, Error, List<&2, String>>) -> Result<&2, &2, Error, Maybe<&2, Entry<Address>>>:
  match fields:
    case Fail{error}: Fail{error}
    case Done{Nil{}}: Done{None{}}
    case Done{_ <> Nil{}}: Fail{MissingName{}}
    case Done{token <> canonical <> aliases}: named(canonical, aliases, address(token))

def line(text: String) -> Result<&2, &2, Error, Maybe<&2, Entry<Address>>>:
  entry(tokens(text, Done{Words{"", Nil{}}}))

# Reject a failed parse without exposing a partial database. The
# first failure retains its one-based line number; successful rows keep order.
def accepted(number: Nat, reversed: List<&2, Entry<Address>>, result: Result<&2, &2, Error, Maybe<&2, Entry<Address>>>) -> Result<&2, &2, Failure, List<&2, Entry<Address>>>:
  match result:
    case Fail{error}: Fail{Failure{number, error}}
    case Done{None{}}: Done{reversed}
    case Done{Some{value}}: Done{value <> reversed}

def lines(input: List<&2, String>, +number: Nat, state: Result<&2, &2, Failure, List<&2, Entry<Address>>>) -> Result<&2, &2, Failure, List<&2, Entry<Address>>>:
  match input state:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{reversed}: Done{List.reverse(&2, Entry<Address>, reversed)}
    case text <> rest Done{reversed}: lines(rest, Succ{number}, accepted(number, reversed, line(text)))

def parse(text: String) -> Result<&2, &2, Failure, List<&2, Entry<Address>>>:
  lines(Split.split(text, '\n'), 1n, Done{Nil{}})

# Filtering never maps addresses or sorts/deduplicates source entries.
type Family is Data:
  Any{}
  IPv4Only{}
  IPv6Only{}

def accepts(family: Family, addressLocal: Address) -> Bool:
  match family addressLocal:
    case Any{} _: True{}
    case IPv4Only{} V4{_}: True{}
    case IPv6Only{} V6{_}: True{}
    case _ _: False{}

def select(+family: Family, entries: List<&2, Entry<Address>>) -> List<&2, Entry<Address>>:
  match entries:
    case Nil{}: Nil{}
    case Entry{+addressLocal, canonical, aliases} <> rest: selected(Address, accepts(family, addressLocal), Entry{addressLocal, canonical, aliases}, select(family, rest))

def lookupFamily(family: Family, name: String, entries: List<&2, Entry<Address>>) -> List<&2, Entry<Address>>:
  select(family, lookup(Address, name, entries))

type LoadError<-DecodeError: Data> is Data:
  Loading{error: File.Error<DecodeError>}
  Parsing{error: Failure}

def parsed(-DecodeError: Data, result: Result<&2, &2, Failure, List<&2, Entry<Address>>>) -> Result<&2, &2, LoadError<DecodeError>, List<&2, Entry<Address>>>:
  match result:
    case Fail{error}: Fail{Parsing{error}}
    case Done{entries}: Done{entries}

def loaded(-DecodeError: Data, result: Result<&2, &2, File.Error<DecodeError>, String>) -> Result<&2, &2, LoadError<DecodeError>, List<&2, Entry<Address>>>:
  match result:
    case Fail{error}: Fail{Loading{error}}
    case Done{text}: parsed(DecodeError, parse(text))

# Keep missing-file, IO, decoding, bounds and syntax failures distinct. The
# caller chooses source-order/fallback policy; none implies an empty database.
def readWith(~DecodeError: Data, ~decode: List<&2, U32> -> Result<&2, &2, DecodeError, String>, path: String, chunkSize: U32, byteLimit: Nat) -> IO(Result<&2, &2, LoadError<DecodeError>, List<&2, Entry<Address>>>):
  do IO<Result<&2, &2, LoadError<DecodeError>, List<&2, Entry<Address>>>>:
    text : Result<&2, &2, File.Error<DecodeError>, String> <- File.readWith(~DecodeError, ~decode, path, chunkSize, byteLimit)
    return loaded(DecodeError, text)

# The standard entry point rejects malformed UTF-8 and strips one leading BOM.
# readWith remains available for an explicitly selected decoding policy.
def read(path: String, chunkSize: U32, byteLimit: Nat) -> IO(Result<&2, &2, LoadError<UTF8.Error>, List<&2, Entry<Address>>>):
  readWith(~UTF8.Error, ~UTF8.decode, path, chunkSize, byteLimit)

# An explicit files-then-network policy over an already loaded snapshot.
# Source failures are terminal. Only absence of eligible rows permits DNS.
# Keep provenance and complete native reports instead of inventing DNS TTLs
# or wire names for local entries.
type Plan<-Error: Data> is Data:
  SourceFailure{error: Error}
  Local{first: Entry<Address>, rest: List<&2, Entry<Address>>}
  Query{family: Family, name: String}

def selectedResolve(-Error: Data, family: Family, name: String, entries: List<&2, Entry<Address>>) -> Plan<Error>:
  match entries:
    case Nil{}: Query{family, name}
    case first <> rest: Local{first, rest}

def plan(-Error: Data, +family: Family, +name: String, source: Result<&2, &2, Error, List<&2, Entry<Address>>>) -> Plan<Error>:
  match source:
    case Fail{error}: SourceFailure{error}
    case Done{entries}: selectedResolve(Error, family, name, lookupFamily(family, name, entries))

type Report<-Error: Data, -Network: Data> is Data:
  FailedSource{error: Error}
  FromHosts{first: Entry<Address>, rest: List<&2, Entry<Address>>}
  FromNetwork{report: Network}

def execute(~Context: Data, ~Error: Data, ~Network: Data, ~lookup: Context -> Family -> String -> IO(Network), context: Context, plan: Plan<Error>) -> IO(Report<Error, Network>):
  match plan:
    case SourceFailure{error}: IO.pure(Report<Error, Network>, FailedSource{error})
    case Local{first, rest}: IO.pure(Report<Error, Network>, FromHosts{first, rest})
    case Query{family, name}:
      do IO<Report<Error, Network>>:
        result : Network <- lookup(context, family, name)
        return FromNetwork{result}

# The callback receives the original spelling only after a hosts miss.
# DNS parsing, search suffixes and network ownership belong to that callback.
def resolveWith(~Context: Data, ~Error: Data, ~Network: Data, ~lookup: Context -> Family -> String -> IO(Network), context: Context, family: Family, name: String, source: Result<&2, &2, Error, List<&2, Entry<Address>>>) -> IO(Report<Error, Network>):
  execute(~Context, ~Error, ~Network, ~lookup, context, plan(Error, family, name, source))
