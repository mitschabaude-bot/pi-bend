import Base
import ./dns-query.bend as Request
import ./dns-message.bend as Message
import ./dns-name.bend as Name
import ./dns-edns.bend as Edns

type Family is Data:
  IPv4{}
  IPv6{}

type Queries is Data:
  Queries{ipv4: Request.Request, ipv6: Request.Request}

type Error is Data:
  Encoding{family: Family, error: Edns.Error}

def create(+options: Request.Options, id4: U32, id6: U32, +name: Name.Name) -> Queries:
  Queries{Request.create(options, id4, Message.Question{name, 1, 1}), Request.create(options, id6, Message.Question{name, 28, 1})}

def checked(queries: Queries, first: Result<&2, &2, Edns.Error, List<&2, U32>>, second: Result<&2, &2, Edns.Error, List<&2, U32>>) -> Result<&2, &2, Error, Queries>:
  match first second:
    case Fail{error} _: Fail{Encoding{IPv4{}, error}}
    case Done{_} Fail{error}: Fail{Encoding{IPv6{}, error}}
    case Done{_} Done{_}: Done{queries}

# Validate both exact requests before a caller commits shared server rotation.
# Encoded bytes are temporary validation evidence, not a second query intent.
def validate(queries: Queries) -> Result<&2, &2, Error, Queries>:
  match queries:
    case Queries{+ipv4, +ipv6}: checked(Queries{ipv4, ipv6}, Request.encode(ipv4), Request.encode(ipv6))
