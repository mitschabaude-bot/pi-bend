import Base
import ./url-input.bend as Input
import ./url-record.bend as Record
import ./url-scheme.bend as Scheme
import ./url-authority.bend as Authority
import ./url-host.bend as Host
import ./url-special-host.bend as SpecialHost
import ./url-port.bend as Port
import ./url-path.bend as Path
import ./url-opaque-path.bend as OpaquePath
import ./idna-domain.bend as IDNA
import ./idna-label.bend as Label

type Context is Data:
  Context{unicode: Label.Context, idna: IDNA.Options}

type Error is Data:
  MissingScheme{}
  MissingHost{}
  InvalidSpecialHost{reason: SpecialHost.Error}
  InvalidOpaqueHost{reason: Host.Error}
  InvalidPort{reason: Port.Error}

def hierarchical(scheme: Scheme.Scheme, username: String, password: String, host: Maybe<&2, Host.Host>, port: Maybe<&2, U32>, parsed: Path.Parsed) -> Record.URL:
  match parsed:
    case Path.Parsed{segments, query, fragment}: Record.URL{scheme, username, password, host, port, Record.Hierarchical{segments}, query, fragment}

def opaque(scheme: Scheme.Scheme, parsed: OpaquePath.Parsed) -> Record.URL:
  match parsed:
    case OpaquePath.Parsed{value, query, fragment}: Record.URL{scheme, "", "", None{}, None{}, Record.Opaque{value}, query, fragment}

def credentials(value: Maybe<&2, Authority.Credentials>) -> Authority.Credentials:
  match value:
    case None{}: Authority.Credentials{"", ""}
    case Some{result}: result

def authorityURL(+scheme: Scheme.Scheme, user: Authority.Credentials, host: Host.Host, port: Maybe<&2, U32>, remainder: String) -> Record.URL:
  match user:
    case Authority.Credentials{username, password}: hierarchical(scheme, username, password, Some{host}, port, Path.start(remainder, scheme, Nil{}))

def portResult(result: Result<&2, &2, Port.Error, Maybe<&2, U32>>, scheme: Scheme.Scheme, user: Authority.Credentials, host: Host.Host, remainder: String) -> Result<&2, &2, Error, Record.URL>:
  match result:
    case Fail{reason}: Fail{InvalidPort{reason}}
    case Done{value}: Done{authorityURL(scheme, user, host, value, remainder)}

def parsedPort(value: Maybe<&2, String>, scheme: Scheme.Scheme) -> Result<&2, &2, Port.Error, Maybe<&2, U32>>:
  match value:
    case None{}: Done{None{}}
    case Some{text}: Port.parse(Scheme.defaultPort(scheme), text)

def specialResult(result: Result<&2, &2, SpecialHost.Error, Host.Host>) -> Result<&2, &2, Error, Host.Host>:
  match result:
    case Fail{reason}: Fail{InvalidSpecialHost{reason}}
    case Done{value}: Done{value}

def opaqueResult(result: Result<&2, &2, Host.Error, Host.Host>) -> Result<&2, &2, Error, Host.Host>:
  match result:
    case Fail{reason}: Fail{InvalidOpaqueHost{reason}}
    case Done{value}: Done{value}

def host(special: Bool, context: Context, input: String) -> Result<&2, &2, Error, Host.Host>:
  match special context:
    case True{} Context{unicode, options}: specialResult(SpecialHost.parse(unicode, options, input))
    case False{} _: opaqueResult(Host.parseOpaque(input))

def hostResult(result: Result<&2, &2, Error, Host.Host>, +scheme: Scheme.Scheme, user: Maybe<&2, Authority.Credentials>, port: Maybe<&2, String>, remainder: String) -> Result<&2, &2, Error, Record.URL>:
  match result:
    case Fail{reason}: Fail{reason}
    case Done{value}: portResult(parsedPort(port, scheme), scheme, credentials(user), value, remainder)

def presentUser(value: Maybe<&2, Authority.Credentials>) -> Bool:
  match value:
    case None{}: False{}
    case Some{_}: True{}

def presentPort(value: Maybe<&2, String>) -> Bool:
  match value:
    case None{}: False{}
    case Some{_}: True{}

def empty(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case _: False{}

def checkedAuthority(missing: Bool, context: Context, +scheme: Scheme.Scheme, text: String, user: Maybe<&2, Authority.Credentials>, port: Maybe<&2, String>, remainder: String) -> Result<&2, &2, Error, Record.URL>:
  match missing:
    case True{}: Fail{MissingHost{}}
    case False{}: hostResult(host(Scheme.isSpecial(scheme), context, text), scheme, user, port, remainder)

def authority(context: Context, +scheme: Scheme.Scheme, prefix: Authority.Prefix) -> Result<&2, &2, Error, Record.URL>:
  match prefix:
    case Authority.Prefix{Authority.Tokens{+user, +text, +port}, remainder}: checkedAuthority(empty(text) && (Scheme.isSpecial(scheme) || presentUser(user) || presentPort(port)), context, scheme, text, user, port, remainder)

def slashes(text: String) -> String:
  match text:
    case SCon{'/', rest}: slashes(rest)
    case SCon{'\\', rest}: slashes(rest)
    case other: other

def localHost(local: Bool, value: Host.Host) -> Host.Host:
  match local:
    case True{}: Host.Empty{}
    case False{}: value

def fileHost(value: Host.Host) -> Host.Host:
  match value:
    case Host.Domain{+name}: localHost(String.eq(name, "localhost"), Host.Domain{name})
    case other: other

def fileResult(result: Result<&2, &2, Error, Host.Host>, remainder: String) -> Result<&2, &2, Error, Record.URL>:
  match result:
    case Fail{reason}: Fail{reason}
    case Done{value}: Done{hierarchical(Scheme.File{}, "", "", Some{fileHost(value)}, None{}, Path.start(remainder, Scheme.File{}, Nil{}))}

def fileDomain(context: Context, text: String) -> Result<&2, &2, Error, Host.Host>:
  match text:
    case SNil{}: Done{Host.Empty{}}
    case other: host(True{}, context, other)

def fileAuthorityDrive(drive: Bool, context: Context, text: String, remainder: String) -> Result<&2, &2, Error, Record.URL>:
  match drive:
    case True{}: Done{hierarchical(Scheme.File{}, "", "", Some{Host.Empty{}}, None{}, Path.parse(text ++ remainder, Scheme.File{}, Nil{}))}
    case False{}: fileResult(fileDomain(context, text), remainder)

def fileAuthority(context: Context, prefix: Authority.RawPrefix) -> Result<&2, &2, Error, Record.URL>:
  match prefix:
    case Authority.RawPrefix{+text, remainder}: fileAuthorityDrive(Path.drive(text), context, text, remainder)

# The first file slash has been consumed. Either kind of second slash enters
# the file-host state; a single slash enters the path state with an empty host.
def fileSlash(context: Context, text: String) -> Result<&2, &2, Error, Record.URL>:
  match text:
    case SCon{'/', rest}: fileAuthority(context, Authority.raw(rest, True{}))
    case SCon{'\\', rest}: fileAuthority(context, Authority.raw(rest, True{}))
    case other: Done{hierarchical(Scheme.File{}, "", "", Some{Host.Empty{}}, None{}, Path.parse(other, Scheme.File{}, Nil{}))}

def file(context: Context, text: String) -> Result<&2, &2, Error, Record.URL>:
  match text:
    case SCon{'/', rest}: fileSlash(context, rest)
    case SCon{'\\', rest}: fileSlash(context, rest)
    case other: Done{hierarchical(Scheme.File{}, "", "", Some{Host.Empty{}}, None{}, Path.parse(other, Scheme.File{}, Nil{}))}

# Non-special schemes only recognize forward slashes as authority delimiters.
def otherSlash(context: Context, +scheme: Scheme.Scheme, text: String) -> Result<&2, &2, Error, Record.URL>:
  match text:
    case SCon{'/', rest}: authority(context, scheme, Authority.read(rest, False{}))
    case other: Done{hierarchical(scheme, "", "", None{}, None{}, Path.parse(other, scheme, Nil{}))}

def other(context: Context, +scheme: Scheme.Scheme, text: String) -> Result<&2, &2, Error, Record.URL>:
  match text:
    case SCon{'/', rest}: otherSlash(context, scheme, rest)
    case remainder: Done{opaque(scheme, OpaquePath.parse(remainder))}

def nonFile(special: Bool, context: Context, scheme: Scheme.Scheme, text: String) -> Result<&2, &2, Error, Record.URL>:
  match special:
    case True{}: authority(context, scheme, Authority.read(slashes(text), True{}))
    case False{}: other(context, scheme, text)

def scheme(context: Context, value: Scheme.Scheme, text: String) -> Result<&2, &2, Error, Record.URL>:
  match value:
    case Scheme.File{}: file(context, text)
    case +otherScheme: nonFile(Scheme.isSpecial(otherScheme), context, otherScheme, text)

def prefixed(context: Context, prefix: Input.Prefix) -> Result<&2, &2, Error, Record.URL>:
  match prefix:
    case Input.Relative{_}: Fail{MissingScheme{}}
    case Input.Absolute{value, remainder}: scheme(context, value, remainder)

# Absolute parsing has no base URL. Relative resolution is a separate entry
# that will share these states. Domain policy remains explicit in Context.
def parse(context: Context, input: String) -> Result<&2, &2, Error, Record.URL>:
  prefixed(context, Input.prefix(Input.prepare(input)))
