import Base
import ./url-scheme.bend as Scheme
import ./url-host.bend as Host

# Internal URL value. Parsers establish normalized scheme/host/port and already
# encoded component strings. None host differs from Some{Host.Empty{}}.
type Path is Data:
  Hierarchical{segments: List<&2, String>}
  Opaque{value: String}

type URL is Data:
  URL{scheme: Scheme.Scheme, username: String, password: String, host: Maybe<&2, Host.Host>, port: Maybe<&2, U32>, path: Path, query: Maybe<&2, String>, fragment: Maybe<&2, String>}
