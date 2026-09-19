import Base
import ./url-ipv4.bend as V4
import ./url-ipv6.bend as V6
import ./url-percent.bend as Percent

type Host is Data:
  Domain{name: String}
  IPv4{address: V4.Address}
  IPv6{address: V6.Address}
  Opaque{value: String}
  Empty{}

type Error is Data:
  EmptyDomain{}
  NonASCII{code: U32}
  Forbidden{code: U32}
  UnclosedIPv6{}
  InvalidIPv4{reason: V4.AddressError}
  InvalidIPv6{reason: V6.AddressError}

def forbiddenHost(code: U32) -> Bool:
  match code:
    case 0: True{}
    case 9: True{}
    case 10: True{}
    case 13: True{}
    case 32: True{}
    case 35: True{}
    case 47: True{}
    case 58: True{}
    case 60: True{}
    case 62: True{}
    case 63: True{}
    case 64: True{}
    case 91: True{}
    case 92: True{}
    case 93: True{}
    case 94: True{}
    case 124: True{}
    case _: False{}

def forbiddenDomain(+code: U32) -> Bool:
  forbiddenHost(code) || U32.is_lt(code, 32) || U32.is_eq(code, 37) || U32.is_eq(code, 127)

def codeFailure(forbidden: Bool, nonASCII: Bool, code: U32) -> Maybe<&2, Error>:
  match forbidden nonASCII:
    case True{} _: Some{Forbidden{code}}
    case False{} True{}: Some{NonASCII{code}}
    case _ _: None{}

def checkCode(opaque: Bool, +code: U32) -> Maybe<&2, Error>:
  match opaque:
    case True{}: codeFailure(forbiddenHost(code), False{}, code)
    case False{}: codeFailure(forbiddenDomain(code), U32.is_gt(code, 127), code)

def scan(text: String, +opaque: Bool, error: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match text error:
    case _ Some{failure}: Some{failure}
    case SNil{} None{}: None{}
    case SCon{Chr{code}, rest} None{}: scan(rest, opaque, checkCode(opaque, code))

def ipv4Result(value: Result<&2, &2, V4.AddressError, V4.Address>) -> Result<&2, &2, Error, Host>:
  match value:
    case Fail{error}: Fail{InvalidIPv4{error}}
    case Done{address}: Done{IPv4{address}}

def numericDomain(numeric: Bool, text: String) -> Result<&2, &2, Error, Host>:
  match numeric:
    case True{}: ipv4Result(V4.parse(text))
    case False{}: Done{Domain{text}}

def checkedDomain(error: Maybe<&2, Error>, +text: String) -> Result<&2, &2, Error, Host>:
  match error text:
    case Some{failure} _: Fail{failure}
    case None{} SNil{}: Fail{EmptyDomain{}}
    case None{} _: numericDomain(V4.endsInNumber(text), text)

# Final special-host classification AFTER percent decoding and domain processing.
# The supplied domain must already be normalized; this stage does not perform
# IDNA, lowercase text, decode escapes, or select a compatibility policy.
def classifyDomain(+asciiDomain: String) -> Result<&2, &2, Error, Host>:
  checkedDomain(scan(asciiDomain, False{}, None{}), asciiDomain)

def ipv6Result(value: Result<&2, &2, V6.AddressError, V6.Address>) -> Result<&2, &2, Error, Host>:
  match value:
    case Fail{error}: Fail{InvalidIPv6{error}}
    case Done{address}: Done{IPv6{address}}

def closedIPv6(reversed: String) -> Result<&2, &2, Error, Host>:
  match reversed:
    case SCon{']', rest}: ipv6Result(V6.parse(String.reverse(rest)))
    case _: Fail{UnclosedIPv6{}}

# The opening bracket was consumed by the caller. Brackets dispatch to IPv6
# before either opaque parsing or domain preparation; no percent decoding occurs.
def bracketed(tail: String) -> Result<&2, &2, Error, Host>:
  closedIPv6(String.reverse(tail))

def checkedOpaque(error: Maybe<&2, Error>, text: String) -> Result<&2, &2, Error, Host>:
  match error text:
    case Some{failure} _: Fail{failure}
    case None{} SNil{}: Done{Empty{}}
    case None{} other: Done{Opaque{Percent.encode(Percent.Controls{}, other)}}

# Non-special schemes preserve case and literal percent sequences. Nonfatal URL
# unit/escape warnings do not cause rejection and are not exposed by this API.
def parseOpaque(+input: String) -> Result<&2, &2, Error, Host>:
  match input:
    case SCon{'[', tail}: bracketed(tail)
    case _: checkedOpaque(scan(input, True{}, None{}), input)

def serialize(host: Host) -> String:
  match host:
    case Domain{name}: name
    case IPv4{address}: V4.serialize(address)
    case IPv6{address}: "[" ++ V6.serialize(address) ++ "]"
    case Opaque{value}: value
    case Empty{}: ""
