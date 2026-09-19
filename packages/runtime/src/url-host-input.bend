import Base
import ./url-host.bend as Host
import ./url-percent.bend as Percent
import ./utf8.bend as Utf8

type Prepared is Data:
  Literal{host: Host.Host}
  DomainInput{text: String}

# WHATWG UTF-8 decode without BOM means preserve U+FEFF, not remove it.
# Percent decoding is one pass over UTF-8 bytes. '+' remains a literal plus.
# Replacement scalars from invalid UTF-8 are left for IDNA to reject.
def decode(text: String) -> String:
  Utf8.complete(Utf8.decode(Utf8.Decoder{Utf8.Ready{}, True{}}, Percent.decode(Utf8.encode(text))))

def literal(result: Result<&2, &2, Host.Error, Host.Host>) -> Result<&2, &2, Host.Error, Prepared>:
  match result:
    case Fail{error}: Fail{error}
    case Done{host}: Done{Literal{host}}

# Input is the raw special-host token after authority delimiting. A literal '['
# dispatches to IPv6 before decoding; percent-encoded brackets do not. The caller
# must process DomainInput through domain/IDNA policy and final classification.
def prepare(input: String) -> Result<&2, &2, Host.Error, Prepared>:
  match input:
    case SNil{}: Fail{Host.EmptyDomain{}}
    case SCon{'[', rest}: literal(Host.bracketed(rest))
    case text: Done{DomainInput{decode(text)}}
