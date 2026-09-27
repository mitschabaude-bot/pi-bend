import Base
import ./base64.bend as Base64
import ./case-map.bend as CaseMap
import ./socket.bend as Connect
import ./text.bend as Text
import ./url.bend as URL
import ./utf8.bend as Utf8

# HTTP proxies for fetch, as pi's coding agent installs them: undici's
# EnvHttpProxyAgent (http_proxy/HTTP_PROXY, https_proxy/HTTPS_PROXY,
# no_proxy/NO_PROXY) over ProxyAgent with `proxyTunnel: true`, so every
# proxied origin, http or https, is reached through a CONNECT tunnel.
#
# The configuration is an explicit value given to Fetch.createWithProxy;
# plain Fetch.create stays proxy-free, as pi-ai's global fetch is. Proxies are
# http:// URLs: TLS to the proxy itself (https:// proxies, which would carry
# TLS inside TLS) and SOCKS proxies are rejected when the configuration is
# built.

type Proxy is Data:
  Proxy{host: URL.Host, port: U32, authorization: Maybe<&2, String>}

type NoProxyEntry is Data:
  NoProxyEntry{hostname: String, port: Nat}

type Config is Data:
  Config{http: Maybe<&2, Proxy>, https: Maybe<&2, Proxy>, noProxyValue: String, noProxy: List<&2, NoProxyEntry>}

def none() -> Config: Config{None{}, None{}, "", Nil{}}

# Proxy URLs
# ----------
def hexValue(+code: U32) -> Maybe<&2, U32>:
  Bool.pick(Maybe<&2, U32>, U32.is_ge(code, 48) && U32.is_le(code, 57), Some{(code - 48 : U32)}, Bool.pick(Maybe<&2, U32>, U32.is_ge(code, 65) && U32.is_le(code, 70), Some{(code - 55 : U32)}, Bool.pick(Maybe<&2, U32>, U32.is_ge(code, 97) && U32.is_le(code, 102), Some{(code - 87 : U32)}, None{})))

def escaped(high: Maybe<&2, U32>, low: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match high low:
    case Some{h} Some{l}: Some{(h * 16 + l : U32)}
    case _ _: None{}

# decodeURIComponent: strict percent-decoding of UTF-8.
def percentBytes(text: List<&2, U32>, reversed: List<&2, U32>) -> Result<&2, &2, String, List<&2, U32>>:
  match text:
    case Nil{}: Done{List.reverse(&2, U32, reversed)}
    case 37 <> +high <> +low <> rest: Maybe.default(&2, Result<&2, &2, String, List<&2, U32>>, Maybe.map(&2, U32, Result<&2, &2, String, List<&2, U32>>, byte => percentBytes(rest, byte <> reversed), escaped(hexValue(high), hexValue(low))), Fail{"URI malformed"})
    case 37 <> _: Fail{"URI malformed"}
    case byte <> rest: percentBytes(rest, byte <> reversed)

def utf8Text(result: Result<&2, &2, Utf8.Error, String>) -> Result<&2, &2, String, String>:
  match result:
    case Done{text}: Done{text}
    case Fail{_}: Fail{"URI malformed"}

def decodedBytes(result: Result<&2, &2, String, List<&2, U32>>) -> Result<&2, &2, String, String>:
  match result:
    case Fail{message}: Fail{message}
    case Done{bytes}: utf8Text(Utf8.decodeStrict(bytes))

def decodeURIComponent(text: String) -> Result<&2, &2, String, String>: decodedBytes(percentBytes(Utf8.encode(text), Nil{}))

def resultText(result: Result<&2, &2, Base64.Error, String>) -> Maybe<&2, String>:
  match result:
    case Done{text}: Some{text}
    case Fail{_}: None{}

def basic(result: Result<&2, &2, String, String>) -> Result<&2, &2, String, Maybe<&2, String>>:
  match result:
    case Fail{message}: Fail{message}
    case Done{credentials}: Done{Some{"Basic " ++ Maybe.default(&2, String, resultText(Base64.encode(Utf8.encode(credentials))), "")}}

def joined(user: Result<&2, &2, String, String>, password: Result<&2, &2, String, String>) -> Result<&2, &2, String, String>:
  match user password:
    case Fail{message} _: Fail{message}
    case _ Fail{message}: Fail{message}
    case Done{name} Done{secret}: Done{name ++ ":" ++ secret}

# `Basic base64(user:password)` from the URL's credentials (ProxyAgent).
def authorization(+user: String, +password: String) -> Result<&2, &2, String, Maybe<&2, String>>:
  match user password:
    case SNil{} _: Done{None{}}
    case name SNil{}: basic(joined(decodeURIComponent(name), Done{""}))
    case name secret: basic(joined(decodeURIComponent(name), decodeURIComponent(secret)))

def proxyPort(port: Maybe<&2, U32>) -> U32:
  match port:
    case Some{value}: value
    case None{}: 80

def proxyWith(protocol: String, url: URL.URL) -> Result<&2, &2, String, Proxy>:
  match protocol url:
    case "http:" URL.URL{_, user, password, Some{host}, port, _, _, _}: Result.map(&2, &2, String, Maybe<&2, String>, Proxy, found => Proxy{host, proxyPort(port), found}, authorization(user, password))
    case "https:" _: Fail{"HTTPS proxies are not supported; use an http:// proxy URL"}
    case other _: Fail{"Unsupported proxy protocol " ++ other}

def parsedProxy(+url: URL.URL) -> Result<&2, &2, String, Proxy>: proxyWith(URL.protocol(url), url)

def proxyOf(parsed: Result<&2, &2, URL.Error, URL.URL>) -> Result<&2, &2, String, Proxy>:
  match parsed:
    case Fail{_}: Fail{"Invalid URL"}
    case Done{url}: parsedProxy(url)

# A truthy proxy variable becomes a proxy.
def configured(context: URL.Context, value: Maybe<&2, String>) -> Result<&2, &2, String, Maybe<&2, Proxy>>:
  match value:
    case Some{SCon{c, cs}}: Result.map(&2, &2, String, Proxy, Maybe<&2, Proxy>, proxy => Some{proxy}, proxyOf(URL.parse(context, SCon{c, cs})))
    case _: Done{None{}}

# NO_PROXY
# --------
def allDigits(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+code}, rest}: U32.is_ge(code, 48) && U32.is_le(code, 57) && allDigits(rest)

def isDigits(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case chars: allDigits(chars)

def digitsValue(text: String, +value: Nat) -> Nat:
  match text:
    case SNil{}: value
    case SCon{Chr{+code}, rest}: digitsValue(rest, Nat.add(Nat.mul(value, 10n), U32.to_nat((code - 48 : U32))))

def colons(text: String) -> Nat:
  match text:
    case SNil{}: 0n
    case SCon{':', rest}: Nat.add(1n, colons(rest))
    case SCon{_, rest}: colons(rest)

def lastIndexOf(text: String, +wanted: U32, +at: Nat, found: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match text:
    case SNil{}: found
    case SCon{Chr{+code}, rest}: lastIndexOf(rest, wanted, Nat.add(at, 1n), Bool.pick(Maybe<&2, Nat>, U32.is_eq(code, wanted), Some{at}, found))

# `^\[(.+)\]$` and `^\[(.+)\]:(\d+)$`.
def unbracketed(text: String) -> Maybe<&2, String>:
  match text:
    case SCon{'[', +rest}: Bool.pick(Maybe<&2, String>, String.ends_with(rest, "]") && Nat.is_gt(String.length(rest), 1n), Some{String.take(rest, Nat.sub(String.length(rest), 1n))}, None{})
    case _: None{}

type Parts is Data:
  Parts{left: String, right: String}

def splitAt(+text: String, +index: Nat) -> Parts: Parts{String.take(text, index), String.drop(text, Nat.add(index, 1n))}

def hostWithPort(+pair: Parts) -> Maybe<&2, NoProxyEntry>:
  match pair:
    case Parts{host, port}: Bool.pick(Maybe<&2, NoProxyEntry>, isDigits(port) && Nat.is_gt(String.length(host), 0n), Some{NoProxyEntry{host, digitsValue(port, 0n)}}, None{})

def bracketedParts(pair: Parts) -> Maybe<&2, NoProxyEntry>:
  match pair:
    case Parts{host, +port}: Maybe.bind(&2, String, NoProxyEntry, unbracketed(host), inner => Bool.pick(Maybe<&2, NoProxyEntry>, isDigits(port), Some{NoProxyEntry{inner, digitsValue(port, 0n)}}, None{}))

def bracketedAt(+text: String, index: Maybe<&2, Nat>) -> Maybe<&2, NoProxyEntry>:
  match text index:
    case SCon{'[', rest} Some{at}: bracketedParts(splitAt(SCon{'[', rest}, at))
    case _ _: None{}

def bracketedWithPort(+text: String) -> Maybe<&2, NoProxyEntry>: bracketedAt(text, lastIndexOf(text, 58, 0n, None{}))

def plainEntry(+text: String) -> NoProxyEntry:
  +inner = Maybe.default(&2, String, unbracketed(text), text)
  Maybe.default(&2, NoProxyEntry, Bool.pick(Maybe<&2, NoProxyEntry>, Nat.is_eq(colons(inner), 1n), Maybe.bind(&2, Nat, NoProxyEntry, lastIndexOf(inner, 58, 0n, None{}), index => hostWithPort(splitAt(inner, index))), None{}), NoProxyEntry{inner, 0n})

# `.replace(/^\*?\./, '').replace(/^(.+)\.$/, '$1').toLowerCase()`.
def withoutLeadingDot(text: String) -> String:
  match text:
    case SCon{'*', SCon{'.', rest}}: rest
    case SCon{'.', rest}: rest
    case other: other

def withoutTrailingDot(+text: String) -> String:
  Bool.pick(String, String.ends_with(text, ".") && Nat.is_gt(String.length(text), 1n), String.take(text, Nat.sub(String.length(text), 1n)), text)

def normalizedEntry(entry: NoProxyEntry) -> NoProxyEntry:
  match entry:
    case NoProxyEntry{host, port}: NoProxyEntry{CaseMap.lower(withoutTrailingDot(withoutLeadingDot(host))), port}

def parseEntry(+text: String) -> NoProxyEntry:
  normalizedEntry(Maybe.default(&2, NoProxyEntry, bracketedWithPort(text), plainEntry(text)))

def finishEntry(+piece: String, rest: List<&2, NoProxyEntry>) -> List<&2, NoProxyEntry>:
  match piece:
    case SNil{}: rest
    case text: parseEntry(text) <> rest

# `noProxyValue.split(/[,\s]/)`, empty pieces skipped.
def entries(text: String, +current: String) -> List<&2, NoProxyEntry>:
  match text:
    case SNil{}: finishEntry(String.reverse(current), Nil{})
    case SCon{Chr{+code}, +rest}: Bool.pick(Unit -> List<&2, NoProxyEntry>, U32.is_eq(code, 44) || Text.whitespace(code), _ => finishEntry(String.reverse(current), entries(rest, "")), _ => entries(rest, SCon{Chr{code}, current}))(Unit{})

# The configuration
# -----------------
def assembled(http: Result<&2, &2, String, Maybe<&2, Proxy>>, https: Result<&2, &2, String, Maybe<&2, Proxy>>, +noProxy: String) -> Result<&2, &2, String, Config>:
  match http https:
    case Fail{message} _: Fail{message}
    case _ Fail{message}: Fail{message}
    case Done{plain} Done{Some{secure}}: Done{Config{plain, Some{secure}, noProxy, entries(noProxy, "")}}
    case Done{+plain} Done{None{}}: Done{Config{plain, plain, noProxy, entries(noProxy, "")}}

# EnvHttpProxyAgent's configuration from the values of http_proxy ??
# HTTP_PROXY, https_proxy ?? HTTPS_PROXY and no_proxy ?? NO_PROXY; https
# falls back to the http proxy. An invalid or unsupported proxy URL is an
# error, as undici throws while constructing the agent.
def fromValues(+context: URL.Context, http: Maybe<&2, String>, https: Maybe<&2, String>, noProxy: Maybe<&2, String>) -> Result<&2, &2, String, Config>:
  assembled(configured(context, http), configured(context, https), Maybe.default(&2, String, noProxy, ""))

def firstDefined(first: Result<&1, &1, U32 & String, String>, second: Result<&1, &1, U32 & String, String>) -> Maybe<&2, String>:
  match first second:
    case Done{value} _: Some{value}
    case _ Done{value}: Some{value}
    case _ _: None{}

def variable(+lower: String, +upper: String) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    first : Result<&1, &1, U32 & String, String> <- IO.get_env(lower)
    second : Result<&1, &1, U32 & String, String> <- IO.get_env(upper)
    return firstDefined(first, second)

def nonEmpty(text: String) -> Maybe<&2, String>:
  match text:
    case SNil{}: None{}
    case other: Some{other}

def trimmedSetting(value: Maybe<&2, String>) -> Maybe<&2, String>:
  match value:
    case Some{text}: nonEmpty(Text.trim(text))
    case None{}: None{}

def orSetting(value: Maybe<&2, String>, setting: Maybe<&2, String>) -> Maybe<&2, String>:
  match value:
    case Some{found}: Some{found}
    case None{}: setting

# With the coding agent's `httpProxy` setting (applyHttpProxySettings): the
# trimmed setting stands in for an unset HTTP_PROXY/HTTPS_PROXY.
def fromEnvironmentWith(context: URL.Context, setting: Maybe<&2, String>) -> IO(Result<&2, &2, String, Config>):
  +proxy = trimmedSetting(setting)
  do IO<Result<&2, &2, String, Config>>:
    http : Maybe<&2, String> <- variable("http_proxy", "HTTP_PROXY")
    https : Maybe<&2, String> <- variable("https_proxy", "HTTPS_PROXY")
    noProxy : Maybe<&2, String> <- variable("no_proxy", "NO_PROXY")
    return fromValues(context, orSetting(http, proxy), orSetting(https, proxy), noProxy)

# The configuration from the process environment.
def fromEnvironment(context: URL.Context) -> IO(Result<&2, &2, String, Config>): fromEnvironmentWith(context, None{})

# Routing
# -------
def entryExcludes(+hostname: String, +port: U32, entry: NoProxyEntry) -> Bool:
  match entry:
    case NoProxyEntry{+name, +wanted}: (Nat.is_eq(wanted, 0n) || Nat.is_eq(wanted, U32.to_nat(port))) && (String.eq(hostname, name) || String.ends_with(hostname, "." ++ name))

def excluded(+hostname: String, +port: U32, entries: List<&2, NoProxyEntry>) -> Bool:
  match entries:
    case Nil{}: False{}
    case entry <> rest: entryExcludes(hostname, port, entry) || excluded(hostname, port, rest)

def shouldProxy(+hostname: String, +port: U32, value: String, entries: List<&2, NoProxyEntry>) -> Bool:
  match entries:
    case Nil{}: True{}
    case list: Bool.not(String.eq(value, "*")) && Bool.not(excluded(hostname, port, list))

# The host as #getProxyAgentForUrl compares it: brackets stripped,
# lowercase, without a trailing dot.
def comparedHost(host: URL.Host) -> String:
  match host:
    case URL.IPv6{address}: URL.serializeIpv6(address)
    case other: withoutTrailingDot(CaseMap.lower(URL.serializeHost(other)))

# The proxy for an origin, None when it is reached directly.
def proxyFor(config: Config, secure: Bool, host: URL.Host, +port: U32) -> Maybe<&2, Proxy>:
  match config:
    case Config{http, https, value, list}: Bool.pick(Maybe<&2, Proxy>, shouldProxy(comparedHost(host), port, value, list), Bool.pick(Maybe<&2, Proxy>, secure, https, http), None{})

# The tunnel
# ----------
# ProxyAgent's CONNECT request: the target always carries its port, the host
# header only a non-default one; the proxy client writes `connection: close`
# for CONNECT and the headers follow in ProxyAgent's order.
def hostHeader(host: URL.Host, +port: U32, secure: Bool) -> String:
  URL.serializeHost(host) ++ Bool.pick(String, U32.is_eq(port, Bool.pick(U32, secure, 443, 80)), "", ":" ++ U32.show(port))

def authorizationLine(value: Maybe<&2, String>) -> String:
  match value:
    case Some{credentials}: "proxy-authorization: " ++ credentials ++ "\r\n"
    case None{}: ""

def connectRequest(proxy: Proxy, +host: URL.Host, +port: U32, secure: Bool) -> List<&2, U32>:
  match proxy:
    case Proxy{_, _, credentials}: Utf8.encode("CONNECT " ++ URL.serializeHost(host) ++ ":" ++ U32.show(port) ++ " HTTP/1.1\r\nhost: " ++ hostHeader(host, port, secure) ++ "\r\nconnection: close\r\n" ++ authorizationLine(credentials) ++ "proxy-connection: keep-alive\r\n\r\n")

type TunnelError<-Reason: Data> is Data:
  TunnelSocket{error: Connect.Error<Reason>}
  TunnelRefused{status: U32}
  TunnelMalformed{message: String}

def tunnelMessage(-Reason: Data, error: TunnelError<Reason>) -> String:
  match error:
    case TunnelSocket{Connect.SocketError{_, message}}: message
    case TunnelSocket{Connect.Aborted{_}}: "This operation was aborted"
    case TunnelRefused{status}: "Proxy response (" ++ U32.show(status) ++ ") !== 200 when HTTP Tunneling"
    case TunnelMalformed{message}: message

def TunnelResult(-Reason: Data) -> Type: Connect.Owner<Reason> & Result<&2, &2, TunnelError<Reason>, Unit>

# The response head ends at the first empty line.
def headEnd(bytes: List<&2, U32>, +at: Nat) -> Maybe<&2, Nat>:
  match bytes:
    case 13 <> 10 <> 13 <> 10 <> _: Some{Nat.add(at, 4n)}
    case _ <> rest: headEnd(rest, Nat.add(at, 1n))
    case Nil{}: None{}

def startsLine(rest: List<&2, U32>) -> Bool:
  match rest:
    case 32 <> _: True{}
    case 13 <> _: True{}
    case _: False{}

def statusCode(line: List<&2, U32>) -> Maybe<&2, U32>:
  match line:
    case 72 <> 84 <> 84 <> 80 <> 47 <> _ <> 46 <> _ <> 32 <> +a <> +b <> +c <> rest: Bool.pick(Maybe<&2, U32>, (U32.is_ge(a, 48) && U32.is_le(a, 57) && U32.is_ge(b, 48) && U32.is_le(b, 57) && U32.is_ge(c, 48) && U32.is_le(c, 57)) && startsLine(rest), Some{((a - 48) * 100 + (b - 48) * 10 + (c - 48) : U32)}, None{})
    case _: None{}

def statusResult(-Reason: Data, owner: Connect.Owner<Reason>, status: Maybe<&2, U32>, +length: Nat, +total: Nat) -> TunnelResult(Reason):
  match status:
    case None{}: (owner, Fail{TunnelMalformed{"Invalid proxy response to CONNECT"}})
    case Some{200}: (owner, Bool.pick(Result<&2, &2, TunnelError<Reason>, Unit>, Nat.is_eq(length, total), Done{Unit{}}, Fail{TunnelMalformed{"The proxy sent data before the tunnel was used"}}))
    case Some{status}: (owner, Fail{TunnelRefused{status}})

def headResult(-Reason: Data, owner: Connect.Owner<Reason>, head: List<&2, U32>, +length: Nat, +total: Nat) -> TunnelResult(Reason): statusResult(Reason, owner, statusCode(head), length, total)

def MAX_HEAD() -> Nat: 16384n

# Reading the CONNECT response head.
type Reading<-Reason: Data> is Type:
  Received{owner: Connect.Owner<Reason>, bytes: List<&2, U32>}
  Checked{owner: Connect.Owner<Reason>, bytes: List<&2, U32>, end: Maybe<&2, Nat>}
  Bounded{owner: Connect.Owner<Reason>, bytes: List<&2, U32>, tooLarge: Bool}
  Chunk{bytes: List<&2, U32>, pair: Connect.Owner<Reason> & Result<&2, &2, Connect.Error<Reason>, List<&2, U32>>}

@unsafe def reading(-Reason: Data, step: Reading<Reason>) -> IO(TunnelResult(Reason)):
  match step:
    case Received{owner, +bytes}: reading(Reason, Checked{owner, bytes, headEnd(bytes, 0n)})
    case Checked{owner, +bytes, Some{length}}: IO.pure(TunnelResult(Reason), headResult(Reason, owner, bytes, length, List.length(&2, U32, bytes)))
    case Checked{owner, +bytes, None{}}: reading(Reason, Bounded{owner, bytes, Nat.is_gt(List.length(&2, U32, bytes), MAX_HEAD())})
    case Bounded{owner, _, True{}}: IO.pure(TunnelResult(Reason), (owner, Fail{TunnelMalformed{"The proxy response head is too large"}}))
    case Bounded{owner, bytes, False{}}:
      do IO<TunnelResult(Reason)>:
        pair : Connect.Owner<Reason> & Result<&2, &2, Connect.Error<Reason>, List<&2, U32>> <- Connect.recvSocket(Reason, owner, 4096)
        reading(Reason, Chunk{bytes, pair})
    case Chunk{_, (owner, Fail{error})}: IO.pure(TunnelResult(Reason), (owner, Fail{TunnelSocket{error}}))
    case Chunk{_, (owner, Done{Nil{}})}: IO.pure(TunnelResult(Reason), (owner, Fail{TunnelMalformed{"The proxy closed the connection during CONNECT"}}))
    case Chunk{bytes, (owner, Done{chunk})}: reading(Reason, Received{owner, List.append(&2, U32, bytes, chunk)})

def sentConnect(-Reason: Data, pair: Connect.Owner<Reason> & Result<&2, &2, Connect.Error<Reason>, Unit>) -> IO(TunnelResult(Reason)):
  match pair:
    case (owner, Fail{error}): IO.pure(TunnelResult(Reason), (owner, Fail{TunnelSocket{error}}))
    case (owner, Done{_}): reading(Reason, Received{owner, Nil{}})

# Opens the tunnel over a connection to the proxy; the owner is returned on
# every path for the caller to use or close.
def tunnel(-Reason: Data, owner: Connect.Owner<Reason>, request: List<&2, U32>) -> IO(TunnelResult(Reason)):
  do IO<TunnelResult(Reason)>:
    pair : Connect.Owner<Reason> & Result<&2, &2, Connect.Error<Reason>, Unit> <- Connect.sendSocket(Reason, owner, request)
    sentConnect(Reason, pair)
