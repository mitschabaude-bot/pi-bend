import Base
import ./url-record.bend as URL
import ./url-scheme.bend as Scheme
import ./url-host.bend as Host
import ./url-serialize.bend as Serialize

type Transport is Data:
  Plaintext{}
  TLS{}

type Endpoint is Data:
  Endpoint{transport: Transport, host: Host.Host, port: U32, authority: String, target: String}

type Error is Data:
  UnsupportedScheme{}
  Credentials{}
  InvalidHost{}
  InvalidPath{}

def port(value: Maybe<&2, U32>, default: U32) -> U32:
  match value:
    case None{}: default
    case Some{number}: number

# A present empty query contributes '?'. URL.search alone cannot preserve this
# distinction. Fragments never belong to an HTTP request target.
def target(parts: List<&2, String>, query: Maybe<&2, String>) -> String:
  String.reverse(Serialize.component(query, '?', Serialize.segments(parts, "")))

def withPath(transport: Transport, +host: Host.Host, +number: Maybe<&2, U32>, default: U32, urlPath: URL.Path, query: Maybe<&2, String>) -> Result<&2, &2, Error, Endpoint>:
  match urlPath:
    case URL.Hierarchical{first <> rest}: Done{Endpoint{transport, host, port(number, default), String.reverse(Serialize.port(number, Serialize.append(Host.serialize(host), ""))), target(first <> rest, query)}}
    case _: Fail{InvalidPath{}}

def withHost(transport: Transport, host: Maybe<&2, Host.Host>, number: Maybe<&2, U32>, default: U32, urlPath: URL.Path, query: Maybe<&2, String>) -> Result<&2, &2, Error, Endpoint>:
  match host:
    case None{}: Fail{InvalidHost{}}
    case Some{Host.Empty{}}: Fail{InvalidHost{}}
    case Some{Host.Opaque{_}}: Fail{InvalidHost{}}
    case Some{Host.Domain{SNil{}}}: Fail{InvalidHost{}}
    case Some{value}: withPath(transport, value, number, default, urlPath, query)

def withCredentials(transport: Transport, username: String, password: String, host: Maybe<&2, Host.Host>, number: Maybe<&2, U32>, default: U32, urlPath: URL.Path, query: Maybe<&2, String>) -> Result<&2, &2, Error, Endpoint>:
  match username password:
    case SNil{} SNil{}: withHost(transport, host, number, default, urlPath, query)
    case _ _: Fail{Credentials{}}

def withScheme(scheme: Scheme.Scheme, username: String, password: String, host: Maybe<&2, Host.Host>, number: Maybe<&2, U32>, urlPath: URL.Path, query: Maybe<&2, String>) -> Result<&2, &2, Error, Endpoint>:
  match scheme:
    case Scheme.Http{}: withCredentials(Plaintext{}, username, password, host, number, 80, urlPath, query)
    case Scheme.Https{}: withCredentials(TLS{}, username, password, host, number, 443, urlPath, query)
    case _: Fail{UnsupportedScheme{}}

# Input is a normalized URL record produced by the URL parsers. Keep the host
# typed for later DNS/socket selection; authority includes IPv6 brackets and
# only a non-default port. This projection does not open sockets, apply Fetch's
# blocked-port policy, choose proxy routing, or replace caller-supplied headers.
def prepare(value: URL.URL) -> Result<&2, &2, Error, Endpoint>:
  match value:
    case URL.URL{scheme, username, password, host, number, urlPath, query, _}: withScheme(scheme, username, password, host, number, urlPath, query)
