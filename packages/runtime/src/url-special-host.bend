import Base
import ./url-host-input.bend as Input
import ./url-host.bend as Host
import ./idna-domain.bend as IDNA
import ./idna-label.bend as Label

type Error is Data:
  Preparation{reason: Host.Error}
  Domain{reason: IDNA.Error}
  Classification{reason: Host.Error}

def classified(result: Result<&2, &2, Host.Error, Host.Host>) -> Result<&2, &2, Error, Host.Host>:
  match result:
    case Fail{reason}: Fail{Classification{reason}}
    case Done{host}: Done{host}

def domain(result: Result<&2, &2, IDNA.Error, String>) -> Result<&2, &2, Error, Host.Host>:
  match result:
    case Fail{reason}: Fail{Domain{reason}}
    case Done{text}: classified(Host.classifyDomain(text))

def prepared(result: Result<&2, &2, Host.Error, Input.Prepared>, context: Label.Context, options: IDNA.Options) -> Result<&2, &2, Error, Host.Host>:
  match result:
    case Fail{reason}: Fail{Preparation{reason}}
    case Done{Input.Literal{host}}: Done{host}
    case Done{Input.DomainInput{text}}: domain(IDNA.toASCII(context, options, text))

# Compose the full special-host pipeline on a delimited token. IPv6 dispatch
# precedes percent decoding; numeric-host detection follows Unicode mapping.
# Callers explicitly supply IDNA policy and reusable immutable Unicode tables.
# No default Node/Unicode joiner-compatibility decision is made by this module.
def parse(context: Label.Context, options: IDNA.Options, input: String) -> Result<&2, &2, Error, Host.Host>:
  prepared(Input.prepare(input), context, options)
