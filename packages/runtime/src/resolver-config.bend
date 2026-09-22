import Base
import ./dns-message.bend as Search
import ./string.bend as Split
import ./url.bend as IPv4
import ./url.bend as IPv6
import ./file-fold.bend as FileFold
import ./ipv6-scope.bend as Scope
import ./socket.bend as Connect
import ./bounded.bend as Bounded

# Numeric resolver configuration is not URL host syntax. In particular, IPv4
# uses inet_aton-style parts without URL trailing-dot or empty-hex allowances.
# IPv6 scopes remain text until the OS adapter resolves an interface or index.
type Address is Data:
  V4{value: IPv4.Address}
  V6{value: IPv6.Ipv6Address, zone: Maybe<&2, String>}

type AddressError is Data:
  InvalidAddress{}

type Zoned is Data:
  Zoned{host: String, zone: Maybe<&2, String>}

def splitZone(text: String, reversed: String) -> Zoned:
  match text:
    case SNil{}: Zoned{String.reverse(reversed), None{}}
    case SCon{'%', rest}: Zoned{String.reverse(reversed), Some{rest}}
    case SCon{char, rest}: splitZone(rest, SCon{char, reversed})

def partPresent(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case +other: Bool.not(String.eq(other, "0x") || String.eq(other, "0X"))

def validParts(parts: List<&2, String>, valid: Bool) -> Bool:
  match parts valid:
    case _ False{}: False{}
    case Nil{} True{}: True{}
    case part <> rest True{}: validParts(rest, partPresent(part))

def checkedV4(valid: Bool, parts: List<&2, String>) -> Result<&2, &2, IPv4.AddressError, IPv4.Address>:
  match valid:
    case False{}: Fail{IPv4.InvalidPart{}}
    case True{}: IPv4.scanIpv4(parts, Done{IPv4.Ipv4Prefix{0, 0}})

def ipv4(text: String) -> Result<&2, &2, IPv4.AddressError, IPv4.Address>:
  +parts = Split.split(text, '.')
  checkedV4(validParts(parts, True{}), parts)

def withZone(zone: Maybe<&2, String>, parsed: Result<&2, &2, IPv6.Ipv6AddressError, IPv6.Ipv6Address>) -> Result<&2, &2, AddressError, Address>:
  match parsed:
    case Fail{_}: Fail{InvalidAddress{}}
    case Done{address}: Done{V6{address, zone}}

def ipv6(parts: Zoned) -> Result<&2, &2, AddressError, Address>:
  match parts:
    case Zoned{host, zone}: withZone(zone, IPv6.parseIpv6(host))

def classified(text: String, parsed: Result<&2, &2, IPv4.AddressError, IPv4.Address>) -> Result<&2, &2, AddressError, Address>:
  match parsed:
    case Done{address}: Done{V4{address}}
    case Fail{_}: ipv6(splitZone(text, ""))

# Parse exactly one token. Whitespace/comments belong to the configuration
# grammar. A retained zone is not yet a validated or resolved interface.
def parseAddress(+text: String) -> Result<&2, &2, AddressError, Address>:
  classified(text, ipv4(text))

# An immutable syntax tree, before resolver policy and OS scope resolution.
# Keep unknown directives and invalid server tokens available to diagnostics;
# parsing never invents default servers or silently applies only some options.
type Entry is Data:
  Nameserver{token: String, address: Result<&2, &2, AddressError, Address>}
  Domain{name: String}
  Search{names: List<&2, String>}
  Options{values: List<&2, String>}
  Sortlist{values: List<&2, String>}
  Unknown{lineConfig: String}

type Keyword is Data:
  ServerKey{}
  DomainKey{}
  SearchKey{}
  OptionsKey{}
  SortKey{}
  OtherKey{}

def keywordFlags(server: Bool, domain: Bool, searchLocal: Bool, options: Bool, sort: Bool) -> Keyword:
  match server domain searchLocal options sort:
    case True{} _ _ _ _: ServerKey{}
    case _ True{} _ _ _: DomainKey{}
    case _ _ True{} _ _: SearchKey{}
    case _ _ _ True{} _: OptionsKey{}
    case _ _ _ _ True{}: SortKey{}
    case _ _ _ _ _: OtherKey{}

def keyword(+text: String) -> Keyword:
  keywordFlags(String.eq(text, "nameserver"), String.eq(text, "domain"), String.eq(text, "search"), String.eq(text, "options"), String.eq(text, "sortlist"))

def pushed(part: String, fields: List<&2, String>) -> List<&2, String>:
  match part:
    case SNil{}: fields
    case text: String.reverse(text) <> fields

type Words is Data:
  Words{part: String, fields: List<&2, String>}

def stepped(space: Bool, char: Char, state: Words) -> Words:
  match space state:
    case True{} Words{part, fields}: Words{"", pushed(part, fields)}
    case False{} Words{part, fields}: Words{SCon{char, part}, fields}

def words(text: String, state: Words) -> List<&2, String>:
  match text state:
    case SNil{} Words{part, fields}: List.reverse(&2, String, pushed(part, fields))
    case SCon{+char, rest} previous: words(rest, stepped(Char.is_eq(char, ' ') || Char.is_eq(char, '\t'), char, previous))

def entryConfig(kind: Keyword, fields: List<&2, String>, original: String) -> Maybe<&2, Entry>:
  match kind fields:
    case ServerKey{} Nil{}: Some{Nameserver{"", Fail{InvalidAddress{}}}}
    case ServerKey{} +token <> _: Some{Nameserver{token, parseAddress(token)}}
    case DomainKey{} Nil{}: None{}
    case DomainKey{} first <> _: Some{Domain{first}}
    case SearchKey{} Nil{}: None{}
    case SearchKey{} names: Some{Search{names}}
    case OptionsKey{} values: Some{Options{values}}
    case SortKey{} values: Some{Sortlist{values}}
    case OtherKey{} _: Some{Unknown{original}}

# A directive keyword starts in column zero and requires a space/tab delimiter.
# Nameserver/domain consume one token; other known directives retain all tokens.
def header(text: String, original: String, reversed: String) -> Maybe<&2, Entry>:
  match text:
    case SNil{}: Some{Unknown{original}}
    case SCon{' ', rest}: entryConfig(keyword(String.reverse(reversed)), words(rest, Words{"", Nil{}}), original)
    case SCon{'\t', rest}: entryConfig(keyword(String.reverse(reversed)), words(rest, Words{"", Nil{}}), original)
    case SCon{char, rest}: header(rest, original, SCon{char, reversed})

def lineConfig(+text: String) -> Maybe<&2, Entry>:
  match text:
    case SNil{}: None{}
    case SCon{'#', _}: None{}
    case SCon{';', _}: None{}
    case other: header(other, other, "")

def appended(value: Maybe<&2, Entry>, reversed: List<&2, Entry>) -> List<&2, Entry>:
  match value:
    case None{}: reversed
    case Some{item}: item <> reversed

def lines(input: List<&2, String>, reversed: List<&2, Entry>) -> List<&2, Entry>:
  match input:
    case Nil{}: List.reverse(&2, Entry, reversed)
    case text <> rest: lines(rest, appended(lineConfig(text), reversed))

# Input is decoded configuration text. File loading, byte-decoding policy,
# environment overrides, defaults and applying the entries are separate layers.
def parse(text: String) -> List<&2, Entry>:
  lines(Split.split(text, '\n'), Nil{})

# Native option values are independent of libc's bit layout.
type Feature is Data:
  Rotate{}
  Edns{}
  SingleRequestReopen{}
  SingleRequest{}
  NoTldQuery{}
  NoReload{}
  UseTcp{}
  TrustAd{}
  NoAAAA{}

type Numeric is Data:
  Ndots{}
  Timeout{}
  Attempts{}

type Option is Data:
  Number{kind: Numeric, value: U32}
  Enable{feature: Feature}

type Diagnostic is Data:
  Malformed{token: String}
  OptionsUnknown{token: String}

type OptionsOptions is Data:
  OptionsOptions{ndots: U32, timeoutSeconds: U32, attempts: U32, features: List<&2, Feature>}

type OptionsReport is Data:
  OptionsReport{values: OptionsOptions, diagnostics: List<&2, Diagnostic>}

def defaults() -> OptionsOptions: OptionsOptions{1, 5, 2, Nil{}}

def featureKey(feature: Feature) -> U32:
  match feature:
    case Rotate{}: 0
    case Edns{}: 1
    case SingleRequestReopen{}: 2
    case SingleRequest{}: 3
    case NoTldQuery{}: 4
    case NoReload{}: 5
    case UseTcp{}: 6
    case TrustAd{}: 7
    case NoAAAA{}: 8

def contains(+key: U32, values: List<&2, Feature>, found: Bool) -> Bool:
  match values found:
    case _ True{}: True{}
    case Nil{} False{}: False{}
    case item <> rest False{}: contains(key, rest, U32.is_eq(key, featureKey(item)))

def enabled(feature: Feature, options: OptionsOptions) -> Bool:
  match options:
    case OptionsOptions{_, _, _, features}: contains(featureKey(feature), features, False{})

def inserted(present: Bool, feature: Feature, values: List<&2, Feature>) -> List<&2, Feature>:
  match present:
    case True{}: values
    case False{}: feature <> values

def enable(+feature: Feature, +values: List<&2, Feature>) -> List<&2, Feature>:
  inserted(contains(featureKey(feature), values, False{}), feature, values)

def apply(option: Option, values: OptionsOptions) -> OptionsOptions:
  match option values:
    case Number{Ndots{}, value} OptionsOptions{_, timeout, attempts, features}: OptionsOptions{value, timeout, attempts, features}
    case Number{Timeout{}, value} OptionsOptions{ndots, _, attempts, features}: OptionsOptions{ndots, value, attempts, features}
    case Number{Attempts{}, value} OptionsOptions{ndots, timeout, _, features}: OptionsOptions{ndots, timeout, value, features}
    case Enable{feature} OptionsOptions{ndots, timeout, attempts, features}: OptionsOptions{ndots, timeout, attempts, enable(feature, features)}

# Prefix matching is only for numeric key delimiters, never flag names.
def strip(text: String, prefix: String, equal: Bool) -> Maybe<&2, String>:
  match text prefix equal:
    case _ _ False{}: None{}
    case rest SNil{} True{}: Some{rest}
    case SNil{} _ True{}: None{}
    case SCon{a, rest} SCon{b, remaining} True{}: strip(rest, remaining, Char.is_eq(a, b))

def digit(valid: Bool, code: U32, value: U32, limit: U32) -> Maybe<&2, U32>:
  match valid:
    case False{}: None{}
    case True{}: Some{U32.min(limit, (value * 10 + code - 48 : U32))}

# Saturate at the documented cap while continuing to validate every character.
# Limits are 5/15/30, so neither long inputs nor accumulation can overflow.
def digits(text: String, +limit: U32, state: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match text state:
    case _ None{}: None{}
    case SNil{} result: result
    case SCon{Chr{+code}, rest} Some{value}: digits(rest, limit, digit(U32.is_ge(code, 48) && U32.is_le(code, 57), code, value, limit))

def decimal(text: String, limit: U32) -> Maybe<&2, U32>:
  match text:
    case SNil{}: None{}
    case other: digits(other, limit, Some{0})

def numberResult(kind: Numeric, token: String, value: Maybe<&2, U32>) -> Result<&2, &2, Diagnostic, Option>:
  match value:
    case None{}: Fail{Malformed{token}}
    case Some{number}: Done{Number{kind, number}}

type FeatureName is Data:
  FeatureName{text: String, feature: Feature}

def featureNames() -> List<&2, FeatureName>:
  FeatureName{"rotate", Rotate{}} <> FeatureName{"edns0", Edns{}} <> FeatureName{"single-request-reopen", SingleRequestReopen{}} <> FeatureName{"single-request", SingleRequest{}} <> FeatureName{"no_tld_query", NoTldQuery{}} <> FeatureName{"no-tld-query", NoTldQuery{}} <> FeatureName{"no-reload", NoReload{}} <> FeatureName{"use-vc", UseTcp{}} <> FeatureName{"trust-ad", TrustAd{}} <> FeatureName{"no-aaaa", NoAAAA{}} <> Nil{}

def findFeature(+token: String, names: List<&2, FeatureName>, found: Maybe<&2, Feature>) -> Result<&2, &2, Diagnostic, Option>:
  match names found:
    case _ Some{feature}: Done{Enable{feature}}
    case Nil{} None{}: Fail{OptionsUnknown{token}}
    case FeatureName{name, feature} <> rest None{}: findFeature(token, rest, Bool.pick(Maybe<&2, Feature>, String.eq(token, name), Some{feature}, None{}))

def numericChoice(token: String, ndots: Maybe<&2, String>, timeout: Maybe<&2, String>, attempts: Maybe<&2, String>) -> Result<&2, &2, Diagnostic, Option>:
  match ndots timeout attempts:
    case Some{text} _ _: numberResult(Ndots{}, token, decimal(text, 15))
    case None{} Some{text} _: numberResult(Timeout{}, token, decimal(text, 30))
    case None{} None{} Some{text}: numberResult(Attempts{}, token, decimal(text, 5))
    case None{} None{} None{}: findFeature(token, featureNames(), None{})

# Exact flag names and complete unsigned decimal tokens. Diagnostics stay
# explicit; this parser does not decide whether callers ignore or reject them.
def parseStrict(+token: String) -> Result<&2, &2, Diagnostic, Option>:
  numericChoice(token, strip(token, "ndots:", True{}), strip(token, "timeout:", True{}), strip(token, "attempts:", True{}))

def applied(result: Result<&2, &2, Diagnostic, Option>, report: OptionsReport) -> OptionsReport:
  match result report:
    case Done{option} OptionsReport{values, diagnostics}: OptionsReport{apply(option, values), diagnostics}
    case Fail{diagnostic} OptionsReport{values, diagnostics}: OptionsReport{values, diagnostic <> diagnostics}

def scan(tokens: List<&2, String>, report: OptionsReport) -> OptionsReport:
  match tokens report:
    case Nil{} OptionsReport{values, diagnostics}: OptionsReport{values, List.reverse(&2, Diagnostic, diagnostics)}
    case token <> rest previous: scan(rest, applied(parseStrict(token), previous))

# Reports with diagnostics are unresolved configuration. No resolver consumes
# the partial values until its diagnostic policy has been selected explicitly.
def interpretStrict(tokens: List<&2, String>, initial: OptionsOptions) -> OptionsReport:
  scan(tokens, OptionsReport{initial, Nil{}})

type ScopeReport<-LookupError: Data> is Data:
  ScopeReport{address: Connect.Address, scopeFailure: Maybe<&2, Scope.Error<LookupError>>}

# Resolver configuration follows libc's nonfatal scope policy: an unresolved
# zone retains its address with scope zero. Keep the failure available to callers.
def resolved(-LookupError: Data, address: IPv6.Ipv6Address, result: Result<&2, &2, Scope.Error<LookupError>, U32>) -> ScopeReport<LookupError>:
  match result:
    case Done{scope}: ScopeReport{Connect.V6{address, scope}, None{}}
    case Fail{error}: ScopeReport{Connect.V6{address, 0}, Some{error}}

def resolveWithScope(~LookupError: Data, ~Context: Data, ~lookup: Context -> String -> IO(Result<&2, &2, LookupError, U32>), context: Context, address: Address) -> IO(ScopeReport<LookupError>):
  match address:
    case V4{value}: IO.pure(ScopeReport<LookupError>, ScopeReport{Connect.V4{value}, None{}})
    case V6{value, None{}}: IO.pure(ScopeReport<LookupError>, ScopeReport{Connect.V6{value, 0}, None{}})
    case V6{+value, Some{scope}}:
      do IO<ScopeReport<LookupError>>:
        result : Result<&2, &2, Scope.Error<LookupError>, U32> <- Scope.resolveWith(~LookupError, ~Context, ~lookup, context, value, scope)
        return resolved(LookupError, value, result)

# Inputs are already decoded. Supplying Some for localDomains explicitly
# overrides file searchLocal/domain directives, including an empty supplied list.
type Overrides is Data:
  Overrides{hostname: Maybe<&2, String>, localDomains: Maybe<&2, List<&2, String>>, options: List<&2, String>}

type Diagnostics is Data:
  Diagnostics{invalidServers: List<&2, String>, unknownLines: List<&2, String>}

type Settings is Data:
  Settings{servers: List<&2, Address>, searchLocal: List<&2, String>, options: List<&2, String>, sortlist: List<&2, String>, diagnostics: Diagnostics}

type Collected is Data:
  Collected{servers: List<&2, Address>, searchLocal: Maybe<&2, List<&2, String>>, options: List<&2, String>, sortlist: List<&2, String>, diagnostics: Diagnostics}

# All accumulated lists except the replacing searchLocal list are reversed.
def prepend(values: List<&2, String>, reversed: List<&2, String>) -> List<&2, String>:
  match values:
    case Nil{}: reversed
    case value <> rest: prepend(rest, value <> reversed)

def serverSettings(token: String, value: Result<&2, &2, AddressError, Address>, state: Collected) -> Collected:
  match value state:
    case Done{address} Collected{servers, searchLocal, options, sort, diagnostics}: Collected{address <> servers, searchLocal, options, sort, diagnostics}
    case Fail{_} Collected{servers, searchLocal, options, sort, Diagnostics{invalid, unknown}}: Collected{servers, searchLocal, options, sort, Diagnostics{token <> invalid, unknown}}

def applyEntry(entry: Entry, state: Collected) -> Collected:
  match entry state:
    case Nameserver{token, parsed} previous: serverSettings(token, parsed, previous)
    case Domain{name} Collected{servers, _, options, sort, diagnostics}: Collected{servers, Some{name <> Nil{}}, options, sort, diagnostics}
    case Search{names} Collected{servers, _, options, sort, diagnostics}: Collected{servers, Some{names}, options, sort, diagnostics}
    case Options{values} Collected{servers, searchLocal, options, sort, diagnostics}: Collected{servers, searchLocal, prepend(values, options), sort, diagnostics}
    case Sortlist{values} Collected{servers, searchLocal, options, sort, diagnostics}: Collected{servers, searchLocal, options, prepend(values, sort), diagnostics}
    case Unknown{line} Collected{servers, searchLocal, options, sort, Diagnostics{invalid, unknown}}: Collected{servers, searchLocal, options, sort, Diagnostics{invalid, line <> unknown}}

def collectSettings(entries: List<&2, Entry>, state: Collected) -> Collected:
  match entries:
    case Nil{}: state
    case entry <> rest: collectSettings(rest, applyEntry(entry, state))

# The default searchLocal domain is the suffix after the hostname's first dot.
# No dot means no local searchLocal suffix; an explicit final dot retains root.
def hostnameDomain(text: String) -> List<&2, String>:
  match text:
    case SNil{}: Nil{}
    case SCon{'.', rest}: rest <> Nil{}
    case SCon{_, rest}: hostnameDomain(rest)

def hostnameSearch(hostname: Maybe<&2, String>) -> List<&2, String>:
  match hostname:
    case None{}: Nil{}
    case Some{text}: hostnameDomain(text)

def searchList(hostname: Maybe<&2, String>, environment: Maybe<&2, List<&2, String>>, file: Maybe<&2, List<&2, String>>) -> List<&2, String>:
  match environment file:
    case Some{names} _: names
    case None{} Some{names}: names
    case None{} None{}: hostnameSearch(hostname)

def nameservers(reversed: List<&2, Address>) -> List<&2, Address>:
  match reversed:
    case Nil{}: V4{IPv4.Address{2130706433}} <> Nil{}
    case entries: List.reverse(&2, Address, entries)

def finalized(overrides: Overrides, state: Collected) -> Settings:
  match overrides state:
    case Overrides{hostname, local, environmentOptions} Collected{servers, searchLocal, options, sort, Diagnostics{invalid, unknown}}:
      Settings{nameservers(servers), searchList(hostname, local, searchLocal), List.reverse(&2, String, prepend(environmentOptions, options)), List.reverse(&2, String, sort), Diagnostics{List.reverse(&2, String, invalid), List.reverse(&2, String, unknown)}}

# Resolve source precedence only. Option/sort interpretation, serverSettings limits,
# IPv6 scope resolution and network scheduling are subsequent typed layers.
def configure(entries: List<&2, Entry>, overrides: Overrides) -> Settings:
  finalized(overrides, collectSettings(entries, Collected{Nil{}, None{}, Nil{}, Nil{}, Diagnostics{Nil{}, Nil{}}}))

type Issue is Data:
  Issue{position: Nat, text: String, error: Search.PresentationError}

type Report is Data:
  Report{domains: List<&2, Search.Domain>, issues: List<&2, Issue>}

# The system searchLocal loop removes one leading dot before appending a suffix.
# Empty and "." both mean root. A remaining leading dot would create an
# empty label after the base name and must not become another root alias.
def withoutLeadingDot(text: String) -> String:
  match text:
    case SCon{'.', rest}: rest
    case other: other

def suffix(text: String) -> Result<&2, &2, Search.PresentationError, Search.PresentationParsed>:
  match text:
    case SCon{'.', _}: Fail{Search.EmptyLabel{}}
    case other: Search.parsePresentation(other)

def wireError(error: Search.PresentationError) -> Search.NameErrorOfMessage:
  match error:
    case Search.PresentationInvalidByte{}: Search.NameInvalidByte{}
    case Search.RawNul{}: Search.NameInvalidByte{}
    case Search.PresentationNameTooLong{}: Search.NameTooLong{}
    case _: Search.InvalidLabel{}

def added(position: Nat, text: String, result: Result<&2, &2, Search.PresentationError, Search.PresentationParsed>, report: Report) -> Report:
  match result report:
    case Done{Search.PresentationParsed{name, _}} Report{domains, issues}: Report{Search.Valid{name} <> domains, issues}
    case Fail{+error} Report{domains, issues}: Report{Search.Invalid{wireError(error)} <> domains, Issue{position, text, error} <> issues}

def collect(values: List<&2, String>, +position: Nat, report: Report) -> Report:
  match values report:
    case Nil{} Report{domains, issues}: Report{List.reverse(&2, Search.Domain, domains), List.reverse(&2, Issue, issues)}
    case +text <> rest previous: collect(rest, (position + 1n : Nat), added(position, text, suffix(withoutLeadingDot(text)), previous))

# Retain every entry, including duplicates and invalid suffixes. No query is
# issued here and no searchLocal option or error-recovery policy is inferred.
def prepareDomains(values: List<&2, String>) -> Report:
  collect(values, 0n, Report{Nil{}, Nil{}})

type Values is Data:
  Values{localDomain: Maybe<&2, String>, options: Maybe<&2, String>}

type EnvironmentError is Data:
  EnvironmentError{variable: String, code: U32, message: String}

def failed(variable: String, code: U32, message: String, missing: Bool) -> Result<&2, &2, EnvironmentError, Maybe<&2, String>>:
  match missing:
    case True{}: Done{None{}}
    case False{}: Fail{EnvironmentError{variable, code, message}}

# The current Linux and JS get_env primitives use ENOENT (2) for absence.
# Keep this platform classification at the boundary; other errors survive.
def normalized(variable: String, result: Result<&1, &1, U32 & String, String>) -> Result<&2, &2, EnvironmentError, Maybe<&2, String>>:
  match result:
    case Done{text}: Done{Some{text}}
    case Fail{(+code, message)}: failed(variable, code, message, U32.is_eq(code, 2))

def combined(local: Result<&2, &2, EnvironmentError, Maybe<&2, String>>, options: Result<&2, &2, EnvironmentError, Maybe<&2, String>>) -> Result<&2, &2, EnvironmentError, Values>:
  match local options:
    case Fail{error} _: Fail{error}
    case Done{_} Fail{error}: Fail{error}
    case Done{domain} Done{tokens}: Done{Values{domain, tokens}}

# Both names are fixed and valid environment keys. The caller owns an injected
# lookup environment. Each variable is read once, in the order shown.
def captureWith(~Environment: Data, ~lookup: Environment -> String -> IO(Result<&1, &1, U32 & String, String>), +environment: Environment) -> IO(Result<&2, &2, EnvironmentError, Values>):
  do IO<Result<&2, &2, EnvironmentError, Values>>:
    local : Result<&1, &1, U32 & String, String> <- lookup(environment, "LOCALDOMAIN")
    options : Result<&1, &1, U32 & String, String> <- lookup(environment, "RES_OPTIONS")
    return combined(normalized("LOCALDOMAIN", local), normalized("RES_OPTIONS", options))

def lookup(unused: Unit, name: String) -> IO(Result<&1, &1, U32 & String, String>):
  IO.get_env(name)

def capture() -> IO(Result<&2, &2, EnvironmentError, Values>):
  captureWith(~Unit, ~lookup, Unit{})

# LOCALDOMAIN ends at the first newline. An initial empty field denotes the
# root suffix and must survive: it can put a bare-name query before other suffixes.
def firstLine(text: String, reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{'\n', _}: String.reverse(reversed)
    case SCon{char, rest}: firstLine(rest, SCon{char, reversed})

def initialRoot(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{' ', _}: True{}
    case SCon{'\t', _}: True{}
    case SCon{'\n', _}: True{}
    case _: False{}

def rooted(root: Bool, words: List<&2, String>) -> List<&2, String>:
  match root:
    case True{}: "" <> words
    case False{}: words

def domainWords(+text: String) -> List<&2, String>:
  rooted(initialRoot(text), words(firstLine(text, ""), Words{"", Nil{}}))

def domainOverride(value: Maybe<&2, String>) -> Maybe<&2, List<&2, String>>:
  match value:
    case None{}: None{}
    case Some{text}: Some{domainWords(text)}

def optionWords(value: Maybe<&2, String>) -> List<&2, String>:
  match value:
    case None{}: Nil{}
    case Some{text}: words(text, Words{"", Nil{}})

# Options remain tokens: selecting a diagnostic policy is a separate step.
def overrides(hostname: Maybe<&2, String>, values: Values) -> Overrides:
  match values:
    case Values{local, options}: Overrides{hostname, domainOverride(local), optionWords(options)}

# Decoding policy is supplied explicitly. This layer never substitutes missing
# files, decodes a partial read, or applies an incomplete configuration.
type FileError<-DecodeError: Data> is Data:
  File{error: FileFold.Error}
  TooLarge{}
  Decode{error: DecodeError}

def decoded(-DecodeError: Data, result: Result<&2, &2, DecodeError, String>) -> Result<&2, &2, FileError<DecodeError>, List<&2, Entry>>:
  match result:
    case Fail{error}: Fail{Decode{error}}
    case Done{text}: Done{parse(text)}

def parsedFile(-DecodeError: Data, result: Result<&2, &2, Bounded.FileError<DecodeError>, String>) -> Result<&2, &2, FileError<DecodeError>, List<&2, Entry>>:
  match result:
    case Fail{Bounded.File{error}}: Fail{File{error}}
    case Fail{Bounded.TooLarge{}}: Fail{TooLarge{}}
    case Fail{Bounded.Decode{error}}: Fail{Decode{error}}
    case Done{text}: Done{parse(text)}

def readWith(~DecodeError: Data, ~decode: List<&2, U32> -> Result<&2, &2, DecodeError, String>, path: String, chunkSize: U32, byteLimit: Nat) -> IO(Result<&2, &2, FileError<DecodeError>, List<&2, Entry>>):
  do IO<Result<&2, &2, FileError<DecodeError>, List<&2, Entry>>>:
    text : Result<&2, &2, Bounded.FileError<DecodeError>, String> <- Bounded.readWith(~DecodeError, ~decode, path, chunkSize, byteLimit)
    return parsedFile(DecodeError, text)

def configured(-DecodeError: Data, overrides: Overrides, result: Result<&2, &2, FileError<DecodeError>, List<&2, Entry>>) -> Result<&2, &2, FileError<DecodeError>, Settings>:
  match result:
    case Fail{error}: Fail{error}
    case Done{entries}: Done{configure(entries, overrides)}

def loadWith(~DecodeError: Data, ~decode: List<&2, U32> -> Result<&2, &2, DecodeError, String>, path: String, chunkSize: U32, byteLimit: Nat, overrides: Overrides) -> IO(Result<&2, &2, FileError<DecodeError>, Settings>):
  do IO<Result<&2, &2, FileError<DecodeError>, Settings>>:
    entries : Result<&2, &2, FileError<DecodeError>, List<&2, Entry>> <- readWith(~DecodeError, ~decode, path, chunkSize, byteLimit)
    return configured(DecodeError, overrides, entries)

type Failure is Data:
  Failure{code: U32, message: String}

type HostnameReport is Data:
  HostnameReport{hostname: Maybe<&2, String>, failure: Maybe<&2, Failure>}

# Domain/searchLocal directives replace a searchLocal list but never erase its presence.
# One such entry is enough to know hostname fallback is unnecessary.
def fileNeedsHostname(entries: List<&2, Entry>) -> Bool:
  match entries:
    case Nil{}: True{}
    case Domain{_} <> _: False{}
    case Search{_} <> _: False{}
    case _ <> rest: fileNeedsHostname(rest)

def needed(entries: List<&2, Entry>, values: Values) -> Bool:
  match values:
    case Values{Some{_}, _}: False{}
    case Values{None{}, _}: fileNeedsHostname(entries)

# Failure leaves the fallback absent, preserving a diagnostic for the caller.
# It does not discard the valid file/environment settings or invent a domain.
def reported(result: Result<&1, &1, U32 & String, String>) -> HostnameReport:
  match result:
    case Done{name}: HostnameReport{Some{name}, None{}}
    case Fail{(code, message)}: HostnameReport{None{}, Some{Failure{code, message}}}

def required(~Context: Data, ~lookup: Context -> IO(Result<&1, &1, U32 & String, String>), context: Context, useHostname: Bool) -> IO(HostnameReport):
  match useHostname:
    case False{}: IO.pure(HostnameReport, HostnameReport{None{}, None{}})
    case True{}:
      do IO<HostnameReport>:
        result : Result<&1, &1, U32 & String, String> <- lookup(context)
        return reported(result)

def resolveWith(~Context: Data, ~lookup: Context -> IO(Result<&1, &1, U32 & String, String>), context: Context, entries: List<&2, Entry>, values: Values) -> IO(HostnameReport):
  required(~Context, ~lookup, context, needed(entries, values))

type LoadError<-DecodeError: Data> is Data:
  Environment{error: EnvironmentError}
  LoadFile{error: FileError<DecodeError>}

def loaded(-DecodeError: Data, result: Result<&2, &2, FileError<DecodeError>, Settings>) -> Result<&2, &2, LoadError<DecodeError>, Settings>:
  match result:
    case Fail{error}: Fail{LoadFile{error}}
    case Done{settings}: Done{settings}

# An injected environment captureLocal can use the same file-loading path. A failed
# captureLocal never opens the file or substitutes missing-variable defaults.
def captured(~DecodeError: Data, ~decode: List<&2, U32> -> Result<&2, &2, DecodeError, String>, hostname: Maybe<&2, String>, path: String, chunkSize: U32, byteLimit: Nat, captureLocal: Result<&2, &2, EnvironmentError, Values>) -> IO(Result<&2, &2, LoadError<DecodeError>, Settings>):
  match captureLocal:
    case Fail{error}: IO.pure(Result<&2, &2, LoadError<DecodeError>, Settings>, Fail{Environment{error}})
    case Done{values}:
      do IO<Result<&2, &2, LoadError<DecodeError>, Settings>>:
        result : Result<&2, &2, FileError<DecodeError>, Settings> <- loadWith(~DecodeError, ~decode, path, chunkSize, byteLimit, overrides(hostname, values))
        return loaded(DecodeError, result)

# Capture environment before reading the file. Hostname discovery and decoding
# policy remain explicit inputs; errors do not become an incomplete config.
def loadWithLoad(~DecodeError: Data, ~decode: List<&2, U32> -> Result<&2, &2, DecodeError, String>, hostname: Maybe<&2, String>, path: String, chunkSize: U32, byteLimit: Nat) -> IO(Result<&2, &2, LoadError<DecodeError>, Settings>):
  do IO<Result<&2, &2, LoadError<DecodeError>, Settings>>:
    captureLocal : Result<&2, &2, EnvironmentError, Values> <- capture()
    captured(~DecodeError, ~decode, hostname, path, chunkSize, byteLimit, captureLocal)

# Request policy is only one projection of resolver settings. Keep all values
# for the later transport, retry, rotation, response and reload layers.
type Prepared is Data:
  Prepared{resolver: OptionsOptions, request: Search.QueryOptions}

# glibc 2.39 uses 1200 for ordinary resolver EDNS advertisement. Trust-AD
# controls the header AD bit, not DNSSEC OK; edns0 alone does not enable DO.
def selected(edns: Bool, trustAd: Bool) -> Search.QueryOptions:
  Search.QueryOptions{Bool.pick(U32, trustAd, 288, 256), Bool.pick(Maybe<&2, Search.Query>, edns, Some{Search.Query{1200, False{}, Nil{}}}, None{})}

def prepareRequest(+options: OptionsOptions) -> Prepared:
  Prepared{options, selected(enabled(Edns{}, options), enabled(TrustAd{}, options))}

# Any diagnostic rejects the entire selection; no partially interpreted
# options become an executable request policy.
def checkedRequest(report: OptionsReport) -> Result<&2, &2, List<&2, Diagnostic>, Prepared>:
  match report:
    case OptionsReport{options, Nil{}}: Done{prepareRequest(options)}
    case OptionsReport{_, issues}: Fail{issues}

def prepareStrict(tokens: List<&2, String>) -> Result<&2, &2, List<&2, Diagnostic>, Prepared>:
  checkedRequest(interpretStrict(tokens, defaults()))

# ---- from resolver-searchLocal.bend ----
# Search consumes ndotsSearch/no-TLD only. Keep the complete selected options for
# transport, response, retry and reload layers rather than discarding flags.
type Configuration is Data:
  Configuration{options: OptionsOptions, domains: Report}

def ndotsSearch(options: OptionsOptions) -> U32:
  match options:
    case OptionsOptions{value, _, _, _}: value

def policy(+options: OptionsOptions) -> Search.Policy:
  Search.Policy{ndotsSearch(options), True{}, True{}, enabled(NoTldQuery{}, options)}

# Callers supplying explicit option values have already selected their policy.
def prepareSearch(options: OptionsOptions, domains: List<&2, String>) -> Configuration:
  Configuration{options, prepareDomains(domains)}

def checkedSearch(report: OptionsReport, domains: List<&2, String>) -> Result<&2, &2, List<&2, Diagnostic>, Configuration>:
  match report:
    case OptionsReport{options, Nil{}}: Done{prepareSearch(options, domains)}
    case OptionsReport{_, diagnostics}: Fail{diagnostics}

# Strictness is explicit in the API, not a default OS compatibility decision.
# Every option diagnostic is returned; no partial values produce a cursor.
def prepareStrictSearch(tokens: List<&2, String>, domains: List<&2, String>) -> Result<&2, &2, List<&2, Diagnostic>, Configuration>:
  checkedSearch(interpretStrict(tokens, defaults()), domains)

def fromSettingsStrict(settings: Settings) -> Result<&2, &2, List<&2, Diagnostic>, Configuration>:
  match settings:
    case Settings{_, domains, options, _, _}: prepareStrictSearch(options, domains)

def startSearch(configuration: Configuration, base: Search.Name, dots: U32, absolute: Bool) -> Search.SearchCursor:
  match configuration:
    case Configuration{options, Report{domains, _}}: Search.startDomains(base, dots, absolute, domains, policy(options))

# Both projections come from the same immutable, already-validated settings.
# Retry/rotation/transport settings remain available in Configuration.options.
type Plan is Data:
  Plan{request: Search.QueryOptions, cursor: Search.SearchCursor}

def preparedRequest(prepared: Prepared) -> Search.QueryOptions:
  match prepared:
    case Prepared{_, request}: request

def requestOptions(configuration: Configuration) -> Search.QueryOptions:
  match configuration:
    case Configuration{options, _}: preparedRequest(prepareRequest(options))

def plan(+configuration: Configuration, base: Search.Name, dots: U32, absolute: Bool) -> Plan:
  Plan{requestOptions(configuration), startSearch(configuration, base, dots, absolute)}

type SystemReport is Data:
  SystemReport{settings: Settings, hostnameFailure: Maybe<&2, Failure>}

def configuredSystem(entries: List<&2, Entry>, values: Values, hostnameSystem: HostnameReport) -> SystemReport:
  match hostnameSystem:
    case HostnameReport{name, failure}: SystemReport{configure(entries, overrides(name, values)), failure}

def parsedSystem(~DecodeError: Data, ~Context: Data, ~lookup: Context -> IO(Result<&1, &1, U32 & String, String>), context: Context, +values: Values, result: Result<&2, &2, FileError<DecodeError>, List<&2, Entry>>) -> IO(Result<&2, &2, LoadError<DecodeError>, SystemReport>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, LoadError<DecodeError>, SystemReport>, Fail{LoadFile{error}})
    case Done{+entries}:
      do IO<Result<&2, &2, LoadError<DecodeError>, SystemReport>>:
        hostnameSystem : HostnameReport <- resolveWith(~Context, ~lookup, context, entries, values)
        return Done{configuredSystem(entries, values, hostnameSystem)}

# Hostname fallback is lazy: captureLocal errors and file errors return first, and
# an environment/file searchLocal list suppresses the hostnameSystem call entirely.
def capturedWith(~DecodeError: Data, ~decode: List<&2, U32> -> Result<&2, &2, DecodeError, String>, ~Context: Data, ~lookup: Context -> IO(Result<&1, &1, U32 & String, String>), context: Context, path: String, chunkSize: U32, byteLimit: Nat, captureLocal: Result<&2, &2, EnvironmentError, Values>) -> IO(Result<&2, &2, LoadError<DecodeError>, SystemReport>):
  match captureLocal:
    case Fail{error}: IO.pure(Result<&2, &2, LoadError<DecodeError>, SystemReport>, Fail{Environment{error}})
    case Done{values}:
      do IO<Result<&2, &2, LoadError<DecodeError>, SystemReport>>:
        entries : Result<&2, &2, FileError<DecodeError>, List<&2, Entry>> <- readWith(~DecodeError, ~decode, path, chunkSize, byteLimit)
        parsedSystem(~DecodeError, ~Context, ~lookup, context, values, entries)

def hostnameSystem(unused: Unit) -> IO(Result<&1, &1, U32 & String, String>):
  IO.get_hostname()

def loadWithSystem(~DecodeError: Data, ~decode: List<&2, U32> -> Result<&2, &2, DecodeError, String>, path: String, chunkSize: U32, byteLimit: Nat) -> IO(Result<&2, &2, LoadError<DecodeError>, SystemReport>):
  do IO<Result<&2, &2, LoadError<DecodeError>, SystemReport>>:
    captureLocal : Result<&2, &2, EnvironmentError, Values> <- capture()
    capturedWith(~DecodeError, ~decode, ~Unit, ~hostnameSystem, Unit{}, path, chunkSize, byteLimit, captureLocal)

# Linux errno values are confined to this platform policy. Only persistent
# open failures permit defaults; read/resource/decoder failures stay fatal.
type Unavailable is Data:
  Unavailable{code: U32, message: String}

type Selected is Data:
  Selected{entries: List<&2, Entry>, unavailable: Maybe<&2, Unavailable>}

type SystemLinuxReport is Data:
  SystemLinuxReport{configuration: SystemReport, unavailable: Maybe<&2, Unavailable>}

def permitsDefaults(+code: U32) -> Bool:
  U32.is_eq(code, 1) || U32.is_eq(code, 2) || U32.is_eq(code, 13) || U32.is_eq(code, 20) || U32.is_eq(code, 21) || U32.is_eq(code, 40)

def opened(-DecodeError: Data, allowed: Bool, code: U32, message: String) -> Result<&2, &2, FileError<DecodeError>, Selected>:
  match allowed:
    case False{}: Fail{File{FileFold.Open{code, message}}}
    case True{}: Done{Selected{Nil{}, Some{Unavailable{code, message}}}}

def select(-DecodeError: Data, result: Result<&2, &2, FileError<DecodeError>, List<&2, Entry>>) -> Result<&2, &2, FileError<DecodeError>, Selected>:
  match result:
    case Done{entries}: Done{Selected{entries, None{}}}
    case Fail{File{FileFold.Open{+code, message}}}: opened(DecodeError, permitsDefaults(code), code, message)
    case Fail{error}: Fail{error}

def reportedSystemLinux(-DecodeError: Data, unavailable: Maybe<&2, Unavailable>, result: Result<&2, &2, LoadError<DecodeError>, SystemReport>) -> Result<&2, &2, LoadError<DecodeError>, SystemLinuxReport>:
  match result:
    case Fail{error}: Fail{error}
    case Done{configuration}: Done{SystemLinuxReport{configuration, unavailable}}

def selectedWith(~DecodeError: Data, ~Context: Data, ~lookup: Context -> IO(Result<&1, &1, U32 & String, String>), context: Context, values: Values, result: Result<&2, &2, FileError<DecodeError>, Selected>) -> IO(Result<&2, &2, LoadError<DecodeError>, SystemLinuxReport>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, LoadError<DecodeError>, SystemLinuxReport>, Fail{LoadFile{error}})
    case Done{Selected{entries, unavailable}}:
      do IO<Result<&2, &2, LoadError<DecodeError>, SystemLinuxReport>>:
        configuration : Result<&2, &2, LoadError<DecodeError>, SystemReport> <- parsedSystem(~DecodeError, ~Context, ~lookup, context, values, Done{entries})
        return reportedSystemLinux(DecodeError, unavailable, configuration)

def parsedWith(~DecodeError: Data, ~Context: Data, ~lookup: Context -> IO(Result<&1, &1, U32 & String, String>), context: Context, values: Values, result: Result<&2, &2, FileError<DecodeError>, List<&2, Entry>>) -> IO(Result<&2, &2, LoadError<DecodeError>, SystemLinuxReport>):
  selectedWith(~DecodeError, ~Context, ~lookup, context, values, select(DecodeError, result))

# Environment captureLocal precedes file access, including the fallback path.
# An unavailable file still allows LOCALDOMAIN/RES_OPTIONS and lazy hostname.
def capturedWithSystemLinux(~DecodeError: Data, ~decode: List<&2, U32> -> Result<&2, &2, DecodeError, String>, ~Context: Data, ~lookup: Context -> IO(Result<&1, &1, U32 & String, String>), context: Context, path: String, chunkSize: U32, byteLimit: Nat, captureLocal: Result<&2, &2, EnvironmentError, Values>) -> IO(Result<&2, &2, LoadError<DecodeError>, SystemLinuxReport>):
  match captureLocal:
    case Fail{error}: IO.pure(Result<&2, &2, LoadError<DecodeError>, SystemLinuxReport>, Fail{Environment{error}})
    case Done{values}:
      do IO<Result<&2, &2, LoadError<DecodeError>, SystemLinuxReport>>:
        entries : Result<&2, &2, FileError<DecodeError>, List<&2, Entry>> <- readWith(~DecodeError, ~decode, path, chunkSize, byteLimit)
        parsedWith(~DecodeError, ~Context, ~lookup, context, values, entries)

def loadWithSystemLinux(~DecodeError: Data, ~decode: List<&2, U32> -> Result<&2, &2, DecodeError, String>, path: String, chunkSize: U32, byteLimit: Nat) -> IO(Result<&2, &2, LoadError<DecodeError>, SystemLinuxReport>):
  do IO<Result<&2, &2, LoadError<DecodeError>, SystemLinuxReport>>:
    captureLocal : Result<&2, &2, EnvironmentError, Values> <- capture()
    capturedWithSystemLinux(~DecodeError, ~decode, ~Unit, ~hostnameSystem, Unit{}, path, chunkSize, byteLimit, captureLocal)

# Valid original positions in glibc's one-to-three-server configuration.
# Rotation reorders entries, never changes this position metadata.
type Position is Data:
  First{}
  SecondOfTwo{}
  SecondOfThree{}
  ThirdOfThree{}

# Whole secondsLocal, necessarily positive even when retransmission is configured 0.
type Duration is Data:
  Duration{additionalSeconds: Nat}

type UdpTimeoutError is Data:
  UdpTimeoutInvalidTimeout{secondsLocal: U32}

def positive(secondsLocal: Nat) -> Duration:
  match secondsLocal:
    case Zero{}: Duration{Zero{}}
    case Succ{rest}: Duration{rest}

def seconds(duration: Duration) -> Nat:
  match duration:
    case Duration{additional}: Succ{additional}

def scaled(timeout: U32, position: Position) -> U32:
  match position:
    case First{}: timeout
    case SecondOfTwo{}: timeout
    case SecondOfThree{}: (timeout * 2 / 3 : U32)
    case ThirdOfThree{}: (timeout * 4 / 3 : U32)

def checked(valid: Bool, timeout: U32, position: Position) -> Result<&2, &2, UdpTimeoutError, Duration>:
  match valid:
    case False{}: Fail{UdpTimeoutInvalidTimeout{timeout}}
    case True{}: Done{positive(U32.to_nat(scaled(timeout, position)))}

# Resolver option parsing already caps timeout at 30. Reject direct invalid
# values instead of overflowing arithmetic or silently changing caller input.
# Checked values scale to at most 40 secondsLocal, so U32 arithmetic cannot overflow.
def budget(+timeout: U32, position: Position) -> Result<&2, &2, UdpTimeoutError, Duration>:
  checked(U32.is_le(timeout, 30), timeout, position)

# Prepared UDP budgets are 1..40 secondsLocal. Validate even manually constructed
# durations before conversion, consuming at most 40 successors of their Nat.
type MillisecondsError is Data:
  OutOfRange{}

def countMilliseconds(fuel: Nat, secondsLocal: Nat, accumulated: U32) -> Result<&2, &2, MillisecondsError, U32>:
  match fuel secondsLocal:
    case _ Zero{}: Done{accumulated}
    case Zero{} Succ{_}: Fail{OutOfRange{}}
    case Succ{rest} Succ{remaining}: countMilliseconds(rest, remaining, (accumulated + 1000 : U32))

def milliseconds(duration: Duration) -> Result<&2, &2, MillisecondsError, U32>:
  countMilliseconds(40n, seconds(duration), 0)

type Error is Data:
  NoServers{}
  TooManyServers{}
  InvalidTimeout{secondsLocal: U32}

type Located<-Server: Data> is Data:
  Located{server: Server, position: Position}

type Attempt<-Server: Data> is Data:
  Attempt{server: Server, position: Position, duration: Duration}

# Assign once in configuration order, before a rotation owner sees the entries.
# This checked UDP boundary accepts the supported one-to-three-server layouts.
# It never silently discards an excess entryUdpPlan or merges duplicate endpoints.
def locate(-Server: Data, servers: List<&2, Server>) -> Result<&2, &2, Error, List<&2, Located<Server>>>:
  match servers:
    case Nil{}: Fail{NoServers{}}
    case first <> Nil{}: Done{Located{first, First{}} <> Nil{}}
    case first <> second <> Nil{}: Done{Located{first, First{}} <> Located{second, SecondOfTwo{}} <> Nil{}}
    case first <> second <> third <> Nil{}: Done{Located{first, First{}} <> Located{second, SecondOfThree{}} <> Located{third, ThirdOfThree{}} <> Nil{}}
    case _ <> _ <> _ <> _ <> _: Fail{TooManyServers{}}

def timed(-Server: Data, server: Server, position: Position, result: Result<&2, &2, UdpTimeoutError, Duration>) -> Result<&2, &2, Error, Attempt<Server>>:
  match result:
    case Fail{UdpTimeoutInvalidTimeout{secondsLocal}}: Fail{InvalidTimeout{secondsLocal}}
    case Done{duration}: Done{Attempt{server, position, duration}}

def entryUdpPlan(-Server: Data, timeout: U32, value: Located<Server>) -> Result<&2, &2, Error, Attempt<Server>>:
  match value:
    case Located{server, +position}: timed(Server, server, position, budget(timeout, position))

def appendedUdpPlan(-Server: Data, accumulated: Result<&2, &2, Error, List<&2, Attempt<Server>>>, result: Result<&2, &2, Error, Attempt<Server>>) -> Result<&2, &2, Error, List<&2, Attempt<Server>>>:
  match accumulated result:
    case Fail{error} _: Fail{error}
    case Done{_} Fail{error}: Fail{error}
    case Done{reversed} Done{attempt}: Done{attempt <> reversed}

def budgets(-Server: Data, values: List<&2, Located<Server>>, +timeout: U32, accumulated: Result<&2, &2, Error, List<&2, Attempt<Server>>>) -> Result<&2, &2, Error, List<&2, Attempt<Server>>>:
  match values accumulated:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{reversed}: Done{List.reverse(&2, Attempt<Server>, reversed)}
    case first <> rest previous: budgets(Server, rest, timeout, appendedUdpPlan(Server, previous, entryUdpPlan(Server, timeout, first)))

def located(-Server: Data, timeout: U32, result: Result<&2, &2, Error, List<&2, Located<Server>>>) -> Result<&2, &2, Error, List<&2, Attempt<Server>>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{values}: budgets(Server, values, timeout, Done{Nil{}})

# Success returns only complete timed entries, suitable for rotation and the
# generic retry cursor. Failure exposes no partially accepted plan.
def prepare(-Server: Data, timeout: U32, servers: List<&2, Server>) -> Result<&2, &2, Error, List<&2, Attempt<Server>>>:
  located(Server, timeout, locate(Server, servers))

# Preserve all parsed options alongside entries timedTransport in configuration order.
# Rotation must operate on these entries, never recompute their positions.
type TransportPrepared<-Server: Data> is Data:
  TransportPrepared{options: OptionsOptions, servers: List<&2, Attempt<Server>>}

def timedTransport(-Server: Data, options: OptionsOptions, result: Result<&2, &2, Error, List<&2, Attempt<Server>>>) -> Result<&2, &2, Error, TransportPrepared<Server>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{servers}: Done{TransportPrepared{options, servers}}

def prepareTransport(-Server: Data, options: OptionsOptions, servers: List<&2, Server>) -> Result<&2, &2, Error, TransportPrepared<Server>>:
  match options:
    case OptionsOptions{ndots, +timeout, attempts, features}: timedTransport(Server, OptionsOptions{ndots, timeout, attempts, features}, prepare(Server, timeout, servers))

# A complete immutable configuration. Options have one canonical home in
# transport; request/searchLocal projections use those same retained settings.
type Config<-Server: Data> is Data:
  Config{transport: TransportPrepared<Server>, domains: Report, milliseconds: U32, maximum: U32}

def assembled(-Server: Data, domains: Report, milliseconds: U32, maximum: U32, result: Result<&2, &2, Error, TransportPrepared<Server>>) -> Result<&2, &2, Error, Config<Server>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{transport}: Done{Config{transport, domains, milliseconds, maximum}}

def prepareConfiguration(-Server: Data, servers: List<&2, Server>, milliseconds: U32, maximum: U32, searchLocal: Configuration) -> Result<&2, &2, Error, Config<Server>>:
  match searchLocal:
    case Configuration{options, domains}: assembled(Server, domains, milliseconds, maximum, prepareTransport(Server, options, servers))

def search(-Server: Data, config: Config<Server>) -> Configuration:
  match config:
    case Config{TransportPrepared{options, _}, domains, _, _}: Configuration{options, domains}

def rotating(-Server: Data, config: Config<Server>) -> Bool:
  match config:
    case Config{TransportPrepared{options, _}, _, _, _}: enabled(Rotate{}, options)

# One query's selected server order is retained across retry rounds. The caller
# supplies already-rotated entries (including their original server indices).
# This cursor stores two lists, not a materialized attempts-by-servers product.
type Cursor<-Server: Data> is Data:
  Cursor{laterRounds: Nat, servers: List<&2, Server>, remaining: List<&2, Server>}

type Step<-Server: Data> is Data:
  Exhausted{}
  Try{server: Server, next: Cursor<Server>}

def start(-Server: Data, attempts: Nat, +servers: List<&2, Server>) -> Cursor<Server>:
  match attempts:
    case Zero{}: Cursor{Zero{}, Nil{}, Nil{}}
    case Succ{later}: Cursor{later, servers, servers}

def restart(-Server: Data, rounds: Nat, +servers: List<&2, Server>) -> Step<Server>:
  match rounds servers:
    case Zero{} _: Exhausted{}
    case _ Nil{}: Exhausted{}
    case Succ{later} first <> rest: Try{first, Cursor{later, servers, rest}}

def next(-Server: Data, cursor: Cursor<Server>) -> Step<Server>:
  match cursor:
    case Cursor{later, servers, Nil{}}: restart(Server, later, servers)
    case Cursor{later, servers, first <> rest}: Try{first, Cursor{later, servers, rest}}

# Once UDP requests TCP, finish only the current pass. The selected entry is
# explicit so duplicate server values cannot accidentally select an earlier
# occurrence. Later UDP rounds do not enter the TCP fallback order.
def fallback(-Server: Data, selected: Server, next: Cursor<Server>) -> List<&2, Server>:
  match next:
    case Cursor{_, _, remaining}: selected <> remaining
