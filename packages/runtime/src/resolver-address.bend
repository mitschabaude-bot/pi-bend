import Base
import ./url-ipv4.bend as IPv4
import ./url-ipv6.bend as IPv6
import ./string-split.bend as Split

# Numeric resolver configuration is not URL host syntax. In particular, IPv4
# uses inet_aton-style parts without URL trailing-dot or empty-hex allowances.
# IPv6 scopes remain text until the OS adapter resolves an interface or index.
type Address is Data:
  V4{value: IPv4.Address}
  V6{value: IPv6.Address, zone: Maybe<&2, String>}

type Error is Data:
  InvalidAddress{}

type Zoned is Data:
  Zoned{host: String, zone: Maybe<&2, String>}

def splitZone(text: String, reversed: String) -> Zoned:
  match text:
    case SNil{}: Zoned{String.reverse(reversed), None{}}
    case SCon{'%', rest}: Zoned{String.reverse(reversed), Some{rest}}
    case SCon{char, rest}: splitZone(rest, SCon{char, reversed})

def partPresent(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case +other: Bool.not(String.eq(other, "0x") || String.eq(other, "0X"))

def validParts(parts: List<&2, String>, valid: Bool) -> Bool:
  match parts valid:
    case _ False{}: False{}
    case Nil{} True{}: True{}
    case part <> rest True{}: validParts(rest, partPresent(part))

def checkedV4(valid: Bool, parts: List<&2, String>) -> Result<&2, &2, IPv4.AddressError, IPv4.Address>:
  match valid:
    case False{}: Fail{IPv4.InvalidPart{}}
    case True{}: IPv4.scan(parts, Done{IPv4.Prefix{0, 0}})

def ipv4(text: String) -> Result<&2, &2, IPv4.AddressError, IPv4.Address>:
  +parts = Split.split(text, '.')
  checkedV4(validParts(parts, True{}), parts)

def withZone(zone: Maybe<&2, String>, parsed: Result<&2, &2, IPv6.AddressError, IPv6.Address>) -> Result<&2, &2, Error, Address>:
  match parsed:
    case Fail{_}: Fail{InvalidAddress{}}
    case Done{address}: Done{V6{address, zone}}

def ipv6(parts: Zoned) -> Result<&2, &2, Error, Address>:
  match parts:
    case Zoned{host, zone}: withZone(zone, IPv6.parse(host))

def classified(text: String, parsed: Result<&2, &2, IPv4.AddressError, IPv4.Address>) -> Result<&2, &2, Error, Address>:
  match parsed:
    case Done{address}: Done{V4{address}}
    case Fail{_}: ipv6(splitZone(text, ""))

# Parse exactly one token. Whitespace/comments belong to the configuration
# grammar. A retained zone is not yet a validated or resolved interface.
def parse(+text: String) -> Result<&2, &2, Error, Address>:
  classified(text, ipv4(text))
