import Base
import ../types.bend as T
import ./provider-env.bend as ProviderEnv
import ../../../runtime/src/case-map.bend as CaseMap
import ../../../runtime/src/json.bend as Json
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/text.bend as Text
import ../../../runtime/src/url.bend as URL

# pi-mono utils/node-http-proxy.ts: the HTTP(S) proxy for a target URL from
# HTTP_PROXY/HTTPS_PROXY/ALL_PROXY/NO_PROXY (scoped ProviderEnv values first,
# lowercase before uppercase, then the process environment), as
# proxy-from-env resolves it. SOCKS and PAC proxies are rejected.

def UNSUPPORTED_PROXY_PROTOCOL_MESSAGE() -> String: "Unsupported proxy protocol. SOCKS and PAC proxy URLs are not supported; use an HTTP or HTTPS proxy URL."

def defaultProxyPort(+protocol: String) -> U32:
  match protocol:
    case "ftp": 21
    case "gopher": 70
    case "http": 80
    case "https": 443
    case "ws": 80
    case "wss": 443
    case _: 0

def scopedValue(env: Maybe<&2, T.ProviderEnv()>, name: String) -> Maybe<&2, String>:
  match env:
    case Some{fields}: ProviderEnv.nonempty(R.get(String, fields, name))
    case None{}: None{}

def firstOf(values: List<&2, Maybe<&2, String>>) -> Maybe<&2, String>:
  match values:
    case Nil{}: None{}
    case Some{value} <> _: Some{value}
    case None{} <> rest: firstOf(rest)

# Proxy variable names are ASCII.
def asciiUpper(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{Chr{+code}, rest}: SCon{Chr{Bool.pick(U32, U32.is_ge(code, 97) && U32.is_le(code, 122), (code - 32 : U32), code)}, asciiUpper(rest)}

# `env?.[lower] || env?.[upper] || process lower || process upper || ""`.
def getProxyEnv(+key: String, +env: Maybe<&2, T.ProviderEnv()>) -> IO(String):
  +lower = Text.asciiLower(key)
  +upper = asciiUpper(key)
  do IO<String>:
    processLower : Maybe<&2, String> <- ProviderEnv.getProviderEnvValue(lower, None{})
    processUpper : Maybe<&2, String> <- ProviderEnv.getProviderEnvValue(upper, None{})
    return Maybe.default(&2, String, firstOf([scopedValue(env, lower), scopedValue(env, upper), processLower, processUpper]), "")

def stripBrackets(host: String) -> String:
  match host:
    case SCon{'[', +rest}: Bool.pick(String, String.ends_with(rest, "]"), String.take(rest, Nat.sub(String.length(rest), 1n)), SCon{'[', rest})
    case other: other

# NO_PROXY entry ports: JavaScript parseInt, where 0 and NaN match any port
# and any other value only itself.
type EntryPort is Data:
  AnyPort{}
  OnlyPort{port: U32}
  NoPort{}

def digitsFrom(text: String, +value: Nat, +seen: Bool) -> Maybe<&2, Nat>:
  match text:
    case SCon{Chr{+code}, rest}: Bool.pick(Unit -> Maybe<&2, Nat>, U32.is_ge(code, 48) && U32.is_le(code, 57), _ => digitsFrom(rest, Nat.add(Nat.mul(value, 10n), U32.to_nat((code - 48 : U32))), True{}), _ => Bool.pick(Maybe<&2, Nat>, seen, Some{value}, None{}))(Unit{})
    case SNil{}: Bool.pick(Maybe<&2, Nat>, seen, Some{value}, None{})

def portFromDigits(negative: Bool, digits: Maybe<&2, Nat>) -> Maybe<&2, EntryPort>:
  match digits:
    case None{}: None{}
    case Some{0n}: Some{AnyPort{}}
    case Some{+value}: Some{Bool.pick(EntryPort, negative || Nat.is_gt(value, 65535n), NoPort{}, OnlyPort{U32.from_nat(value)})}

def parsedIntPort(text: String) -> Maybe<&2, EntryPort>:
  match text:
    case SCon{'-', rest}: portFromDigits(True{}, digitsFrom(rest, 0n, False{}))
    case SCon{'+', rest}: portFromDigits(False{}, digitsFrom(rest, 0n, False{}))
    case rest: portFromDigits(False{}, digitsFrom(rest, 0n, False{}))

# parseInt(text, 10): None for NaN.
def parseIntPort(text: String) -> Maybe<&2, EntryPort>: parsedIntPort(Text.trimStart(text))

type Entry is Data:
  Entry{host: String, port: EntryPort}

def indexOf(text: String, +wanted: U32, +at: Nat) -> Maybe<&2, Nat>:
  match text:
    case SNil{}: None{}
    case SCon{Chr{+code}, rest}: Bool.pick(Unit -> Maybe<&2, Nat>, U32.is_eq(code, wanted), _ => Some{at}, _ => indexOf(rest, wanted, Nat.add(at, 1n)))(Unit{})

def bracketedRest(+host: String, rest: String) -> Maybe<&2, Entry>:
  match rest:
    case SCon{':', port}: Some{Entry{host, Maybe.default(&2, EntryPort, parseIntPort(port), AnyPort{})}}
    case _: Some{Entry{host, AnyPort{}}}

def bracketedAt(+inner: String, +index: Nat) -> Maybe<&2, Entry>: bracketedRest(String.take(inner, index), String.drop(inner, Nat.add(index, 1n)))

def bracketed(+inner: String) -> Maybe<&2, Entry>: bracketedAt(inner, Maybe.default(&2, Nat, indexOf(inner, 93, 0n), String.length(inner)))

def colons(text: String) -> Nat:
  match text:
    case SNil{}: 0n
    case SCon{':', rest}: Nat.add(1n, colons(rest))
    case SCon{_, rest}: colons(rest)

def hostWithPort(trimmed: String, +index: Nat, port: Maybe<&2, EntryPort>) -> Maybe<&2, Entry>:
  match port:
    case Some{found}: Some{Entry{String.take(trimmed, index), found}}
    case None{}: Some{Entry{trimmed, AnyPort{}}}

def hostPortCounted(+trimmed: String, count: Nat) -> Maybe<&2, Entry>:
  match count:
    case 1n:
      +index = Maybe.default(&2, Nat, indexOf(trimmed, 58, 0n), 0n)
      hostWithPort(trimmed, index, parseIntPort(String.drop(trimmed, Nat.add(index, 1n))))
    case _: Some{Entry{trimmed, AnyPort{}}}

def hostPort(+trimmed: String) -> Maybe<&2, Entry>: hostPortCounted(trimmed, colons(trimmed))

def parsedEntry(text: String) -> Maybe<&2, Entry>:
  match text:
    case SNil{}: None{}
    case SCon{'[', +inner}: Bool.pick(Unit -> Maybe<&2, Entry>, String.contains(inner, "]"), _ => bracketed(inner), _ => hostPort(SCon{'[', inner}))(Unit{})
    case trimmed: hostPort(trimmed)

def parseNoProxyEntry(entry: String) -> Maybe<&2, Entry>: parsedEntry(CaseMap.lower(Text.trim(entry)))

def unwildcarded(host: String) -> String:
  match host:
    case SCon{'*', SCon{'.', rest}}: rest
    case SCon{'.', rest}: rest
    case SCon{'*', rest}: rest
    case other: other

def domainOf(host: String) -> String: unwildcarded(stripBrackets(host))

def portMatches(entry: EntryPort, +port: U32) -> Bool:
  match entry:
    case AnyPort{}: True{}
    case OnlyPort{wanted}: U32.is_eq(wanted, port)
    case NoPort{}: False{}

def domainAllows(+target: String, portMatched: Bool, domain: String) -> Bool:
  match portMatched domain:
    case False{} _: True{}
    case True{} SNil{}: True{}
    case True{} +found: Bool.not(String.eq(target, found) || String.ends_with(target, "." ++ found))

# Whether one NO_PROXY entry lets the target through.
def entryAllows(target: String, +port: U32, parsed: Maybe<&2, Entry>) -> Bool:
  match parsed:
    case None{}: True{}
    case Some{Entry{host, entryPort}}: domainAllows(target, portMatches(entryPort, port), domainOf(host))

# `noProxy.split(/[,\s]/)`.
def splitEntries(text: String, +current: String) -> List<&2, String>:
  match text:
    case SNil{}: [String.reverse(current)]
    case SCon{Chr{+code}, +rest}: Bool.pick(Unit -> List<&2, String>, U32.is_eq(code, 44) || Text.whitespace(code), _ => String.reverse(current) <> splitEntries(rest, ""), _ => splitEntries(rest, SCon{Chr{code}, current}))(Unit{})

def allAllow(+target: String, +port: U32, entries: List<&2, String>) -> Bool:
  match entries:
    case Nil{}: True{}
    case entry <> rest: entryAllows(target, port, parseNoProxyEntry(entry)) && allAllow(target, port, rest)

def noProxyAllows(+noProxy: String, target: String, +port: U32) -> Bool:
  match noProxy:
    case SNil{}: True{}
    case "*": False{}
    case entries: allAllow(target, port, splitEntries(entries, ""))

def shouldProxyHostname(hostname: String, +port: U32, env: Maybe<&2, T.ProviderEnv()>) -> IO(Bool):
  do IO<Bool>:
    value : String <- getProxyEnv("no_proxy", env)
    return noProxyAllows(CaseMap.lower(value), stripBrackets(CaseMap.lower(hostname)), port)

def withScheme(+protocol: String, +proxy: String) -> String:
  match proxy:
    case SNil{}: SNil{}
    case value: Bool.pick(String, String.contains(value, "://"), value, protocol ++ "://" ++ value)

def withoutColon(+text: String) -> String: String.take(text, Nat.sub(String.length(text), 1n))

def schemeOf(url: URL.URL) -> String: withoutColon(URL.protocol(url))

def portOf(url: URL.URL, +protocol: String) -> U32:
  match url:
    case URL.URL{_, _, _, _, Some{+port}, _, _, _}: Bool.pick(U32, U32.is_eq(port, 0), defaultProxyPort(protocol), port)
    case _: defaultProxyPort(protocol)

def proxyEnvFor(+protocol: String, +env: Maybe<&2, T.ProviderEnv()>, allowed: Bool) -> IO(String):
  match allowed:
    case False{}: IO.pure(String, "")
    case True{}:
      do IO<String>:
        +scoped : String <- getProxyEnv(protocol ++ "_proxy", env)
        all : String <- getProxyEnv("all_proxy", env)
        return withScheme(protocol, Bool.pick(String, String.is_empty(scoped), all, scoped))

def proxyForHost(url: URL.URL, +protocol: String, hostname: String, +env: Maybe<&2, T.ProviderEnv()>) -> IO(String):
  match hostname:
    case SNil{}: IO.pure(String, "")
    case +host:
      do IO<String>:
        allowed : Bool <- shouldProxyHostname(host, portOf(url, protocol), env)
        proxyEnvFor(protocol, env, allowed)

def proxyForParsed(parsed: Result<&2, &2, URL.Error, URL.URL>, env: Maybe<&2, T.ProviderEnv()>) -> IO(String):
  match parsed:
    case Fail{_}: IO.pure(String, "")
    case Done{+url}:
      proxyForHost(url, schemeOf(url), stripBrackets(URL.hostname(url)), env)

def getProxyForUrl(context: URL.Context, targetUrl: String, env: Maybe<&2, T.ProviderEnv()>) -> IO(String):
  proxyForParsed(URL.parse(context, targetUrl), env)

def supportedProxy(url: URL.URL, protocol: String) -> Result<&2, &2, String, Maybe<&2, URL.URL>>:
  match protocol:
    case "http:": Done{Some{url}}
    case "https:": Done{Some{url}}
    case other: Fail{UNSUPPORTED_PROXY_PROTOCOL_MESSAGE() ++ " Got " ++ other}

def checkedProxy(+proxy: String, parsed: Result<&2, &2, URL.Error, URL.URL>) -> Result<&2, &2, String, Maybe<&2, URL.URL>>:
  match parsed:
    case Fail{_}: Fail{"Invalid proxy URL " ++ Json.quote(proxy) ++ ": Invalid URL"}
    case Done{+url}: supportedProxy(url, URL.protocol(url))

def resolvedProxy(context: URL.Context, +proxy: String) -> Result<&2, &2, String, Maybe<&2, URL.URL>>:
  match proxy:
    case SNil{}: Done{None{}}
    case value: checkedProxy(value, URL.parse(context, value))

# The proxy URL for a target, None when it is not proxied; errors for an
# invalid or non-HTTP(S) proxy URL (upstream throws).
def resolveHttpProxyUrlForTarget(+context: URL.Context, targetUrl: String, env: Maybe<&2, T.ProviderEnv()>) -> IO(Result<&2, &2, String, Maybe<&2, URL.URL>>):
  do IO<Result<&2, &2, String, Maybe<&2, URL.URL>>>:
    proxy : String <- getProxyForUrl(context, targetUrl, env)
    return resolvedProxy(context, proxy)
