import Base
import ./hosts.bend as Hosts
import ./url-ipv4.bend as IPv4
import ./url-ipv6.bend as IPv6
import ./string-split.bend as Split

type Address is Data:
  V4{value: IPv4.Address}
  V6{value: IPv6.Address}

type Error is Data:
  InvalidAddress{token: String}
  MissingName{}
  InvalidControl{code: U32}

type Failure is Data:
  Failure{line: Nat, error: Error}

# Hosts addresses use strict presentation syntax, not URL/inet_aton numbers.
# No port, brackets, abbreviated IPv4 or interface-zone suffix is accepted.
def v6(token: String, result: Result<&2, &2, IPv6.AddressError, IPv6.Address>) -> Result<&2, &2, Error, Address>:
  match result:
    case Done{value}: Done{V6{value}}
    case Fail{_}: Fail{InvalidAddress{token}}

def v4(+token: String, result: Result<&2, &2, IPv6.AddressError, List<&2, U32>>) -> Result<&2, &2, Error, Address>:
  match result:
    case Done{a <> b <> Nil{}}: Done{V4{IPv4.Address{(a * 65536 + b : U32)}}}
    case _: v6(token, IPv6.parse(token))

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

def named(canonical: String, aliases: List<&2, String>, value: Result<&2, &2, Error, Address>) -> Result<&2, &2, Error, Maybe<&2, Hosts.Entry<Address>>>:
  match value:
    case Fail{error}: Fail{error}
    case Done{value}: Done{Some{Hosts.Entry{value, canonical, aliases}}}

def entry(fields: Result<&2, &2, Error, List<&2, String>>) -> Result<&2, &2, Error, Maybe<&2, Hosts.Entry<Address>>>:
  match fields:
    case Fail{error}: Fail{error}
    case Done{Nil{}}: Done{None{}}
    case Done{_ <> Nil{}}: Fail{MissingName{}}
    case Done{token <> canonical <> aliases}: named(canonical, aliases, address(token))

def line(text: String) -> Result<&2, &2, Error, Maybe<&2, Hosts.Entry<Address>>>:
  entry(tokens(text, Done{Words{"", Nil{}}}))

# Reject a failed parse without exposing a partial database. The
# first failure retains its one-based line number; successful rows keep order.
def accepted(number: Nat, reversed: List<&2, Hosts.Entry<Address>>, result: Result<&2, &2, Error, Maybe<&2, Hosts.Entry<Address>>>) -> Result<&2, &2, Failure, List<&2, Hosts.Entry<Address>>>:
  match result:
    case Fail{error}: Fail{Failure{number, error}}
    case Done{None{}}: Done{reversed}
    case Done{Some{value}}: Done{value <> reversed}

def lines(input: List<&2, String>, +number: Nat, state: Result<&2, &2, Failure, List<&2, Hosts.Entry<Address>>>) -> Result<&2, &2, Failure, List<&2, Hosts.Entry<Address>>>:
  match input state:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{reversed}: Done{List.reverse(&2, Hosts.Entry<Address>, reversed)}
    case text <> rest Done{reversed}: lines(rest, Succ{number}, accepted(number, reversed, line(text)))

def parse(text: String) -> Result<&2, &2, Failure, List<&2, Hosts.Entry<Address>>>:
  lines(Split.split(text, '\n'), 1n, Done{Nil{}})
