import Base
import ../src/http-message.bend as HTTP
import ../src/url.bend as URL
import ../src/url.bend as Scheme
import ../src/url.bend as Host
import ../src/string-split.bend as Split
import ./utf8-runner.bend as Scalar

def scalarText(parts: List<&2, String>, reversed: String) -> String:
  match parts:
    case Nil{}: String.reverse(reversed)
    case SNil{} <> rest: scalarText(rest, reversed)
    case value <> rest: scalarText(rest, SCon{Chr{Scalar.decimal(value, 0)}, reversed})

def text(value: String) -> String: scalarText(Split.split(value, ','), "")

def optional(value: String) -> Maybe<&2, String>:
  match value:
    case SCon{'+', rest}: Some{text(rest)}
    case _: None{}

def port(value: String) -> Maybe<&2, U32>:
  match value:
    case SNil{}: None{}
    case rest: Some{Scalar.decimal(rest, 0)}

def hostResult(value: Result<&2, &2, Host.HostError, Host.Host>) -> Host.Host:
  match value:
    case Done{parsed}: parsed
    case Fail{_}: Host.Empty{}

def host(value: String) -> Host.Host:
  match value:
    case SCon{'[', rest}: hostResult(Host.bracketed(rest))
    case SNil{}: Host.Empty{}
    case rest: hostResult(Host.classifyDomain(rest))

def path(value: String) -> URL.RecordPath:
  match value:
    case SCon{'/', rest}: URL.Hierarchical{Split.split(rest, '/')}
    case rest: URL.RecordOpaque{rest}

def transport(value: HTTP.Transport) -> String:
  match value:
    case HTTP.Plaintext{}: "plain"
    case HTTP.TLS{}: "tls"

def show(value: Result<&2, &2, HTTP.EndpointError, HTTP.Endpoint>) -> String:
  match value:
    case Fail{HTTP.UnsupportedScheme{}}: "scheme"
    case Fail{HTTP.Credentials{}}: "credentials"
    case Fail{HTTP.InvalidHost{}}: "host"
    case Fail{HTTP.InvalidPath{}}: "path"
    case Done{HTTP.Endpoint{kind, domain, number, authority, target}}: transport(kind) ++ "|" ++ Scalar.showText(Host.serializeHost(domain)) ++ "|" ++ U32.show(number) ++ "|" ++ Scalar.showText(authority) ++ "|" ++ Scalar.showText(target)

def cases(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case scheme <> username <> password <> hostname <> number <> pathname <> query <> hash <> rest:
      do IO<Unit>:
        IO.print(show(HTTP.urlPrepare(URL.URL{Scheme.classify(scheme), text(username), text(password), Some{host(text(hostname))}, port(number), path(text(pathname)), optional(query), optional(hash)})))
        cases(rest)
    case _: IO.die(Unit, 1, "expected eight normalized URL fields")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)
