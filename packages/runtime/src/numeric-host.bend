import Base
import ./hosts-file.bend as Literal
import ./hosts-family.bend as Family
import ./resolver-address.bend as Zone
import ./url-ipv4.bend as IPv4
import ./url-ipv6.bend as IPv6

# Parsed numeric input, not yet a resolved socket address. A retained IPv6 zone
# must be validated/resolved before connecting. No DNS fallback occurs here.
type Input is Data:
  V4{address: IPv4.Address}
  V6{address: IPv6.Address, zone: Maybe<&2, String>}

type Error is Data:
  InvalidAddress{input: String}
  FamilyMismatch{}

def selected(family: Family.Family, input: Input) -> Result<&2, &2, Error, Input>:
  match family input:
    case Family.IPv4Only{} V6{_, _}: Fail{FamilyMismatch{}}
    case Family.IPv6Only{} V4{_}: Fail{FamilyMismatch{}}
    case _ value: Done{value}

def zoned(original: String, zone: Maybe<&2, String>, parsed: Result<&2, &2, Literal.Error, Literal.Address>) -> Result<&2, &2, Error, Input>:
  match zone parsed:
    case _ Fail{_}: Fail{InvalidAddress{original}}
    case None{} Done{Literal.V4{address}}: Done{V4{address}}
    case Some{_} Done{Literal.V4{_}}: Fail{InvalidAddress{original}}
    case Some{SNil{}} Done{Literal.V6{_}}: Fail{InvalidAddress{original}}
    case scope Done{Literal.V6{address}}: Done{V6{address, scope}}

def split(original: String, parts: Zone.Zoned) -> Result<&2, &2, Error, Input>:
  match parts:
    case Zone.Zoned{host, scope}: zoned(original, scope, Literal.address(host))

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
