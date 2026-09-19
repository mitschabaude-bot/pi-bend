import Base
import ./url-record.bend as Record
import ./url-scheme.bend as Scheme
import ./url-host.bend as Host

# Append to reversed output with constant machine-stack use. Components are
# already encoded by the parser; serialization must not encode '%' a second time.
def append(text: String, reversed: String) -> String:
  match text:
    case SNil{}: reversed
    case SCon{char, rest}: append(rest, SCon{char, reversed})

def segments(parts: List<&2, String>, reversed: String) -> String:
  match parts:
    case Nil{}: reversed
    case head <> rest: segments(rest, append(head, SCon{'/', reversed}))

def pathOutput(path: Record.Path, reversed: String) -> String:
  match path:
    case Record.Hierarchical{parts}: segments(parts, reversed)
    case Record.Opaque{value}: append(value, reversed)

def path(path: Record.Path) -> String:
  String.reverse(pathOutput(path, ""))

# Prevent a hostless path beginning '//' from reparsing as an authority.
def hostless(path: Record.Path, reversed: String) -> String:
  match path:
    case Record.Hierarchical{SNil{} <> next <> rest}: segments("" <> next <> rest, append("/.", reversed))
    case other: pathOutput(other, reversed)

def credentials(username: String, password: String, reversed: String) -> String:
  match username password:
    case SNil{} SNil{}: reversed
    case user SNil{}: SCon{'@', append(user, reversed)}
    case user pass: SCon{'@', append(pass, SCon{':', append(user, reversed)})}

def port(value: Maybe<&2, U32>, reversed: String) -> String:
  match value:
    case None{}: reversed
    case Some{number}: append(U32.show(number), SCon{':', reversed})

def body(host: Maybe<&2, Host.Host>, path: Record.Path, username: String, password: String, number: Maybe<&2, U32>, reversed: String) -> String:
  match host:
    case None{}: hostless(path, reversed)
    case Some{value}: pathOutput(path, port(number, append(Host.serialize(value), credentials(username, password, append("//", reversed)))))

def component(value: Maybe<&2, String>, delimiter: Char, reversed: String) -> String:
  match value:
    case None{}: reversed
    case Some{value}: append(value, SCon{delimiter, reversed})

def fragment(exclude: Bool, value: Maybe<&2, String>, reversed: String) -> String:
  match exclude:
    case True{}: reversed
    case False{}: component(value, '#', reversed)

def suffix(reversed: String, query: Maybe<&2, String>, hash: Maybe<&2, String>, excludeFragment: Bool) -> String:
  String.reverse(fragment(excludeFragment, hash, component(query, '?', reversed)))

def serialize(value: Record.URL, excludeFragment: Bool) -> String:
  match value:
    case Record.URL{scheme, username, password, host, number, urlPath, query, hash}: suffix(body(host, urlPath, username, password, number, SCon{':', append(Scheme.serialize(scheme), "")}), query, hash, excludeFragment)
