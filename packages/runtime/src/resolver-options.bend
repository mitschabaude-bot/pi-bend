import Base

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
  Unknown{token: String}

type Options is Data:
  Options{ndots: U32, timeoutSeconds: U32, attempts: U32, features: List<&2, Feature>}

type Report is Data:
  Report{values: Options, diagnostics: List<&2, Diagnostic>}

def defaults() -> Options: Options{1, 5, 2, Nil{}}

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

def enabled(feature: Feature, options: Options) -> Bool:
  match options:
    case Options{_, _, _, features}: contains(featureKey(feature), features, False{})

def inserted(present: Bool, feature: Feature, values: List<&2, Feature>) -> List<&2, Feature>:
  match present:
    case True{}: values
    case False{}: feature <> values

def enable(+feature: Feature, +values: List<&2, Feature>) -> List<&2, Feature>:
  inserted(contains(featureKey(feature), values, False{}), feature, values)

def apply(option: Option, values: Options) -> Options:
  match option values:
    case Number{Ndots{}, value} Options{_, timeout, attempts, features}: Options{value, timeout, attempts, features}
    case Number{Timeout{}, value} Options{ndots, _, attempts, features}: Options{ndots, value, attempts, features}
    case Number{Attempts{}, value} Options{ndots, timeout, _, features}: Options{ndots, timeout, value, features}
    case Enable{feature} Options{ndots, timeout, attempts, features}: Options{ndots, timeout, attempts, enable(feature, features)}

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
    case Nil{} None{}: Fail{Unknown{token}}
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

def applied(result: Result<&2, &2, Diagnostic, Option>, report: Report) -> Report:
  match result report:
    case Done{option} Report{values, diagnostics}: Report{apply(option, values), diagnostics}
    case Fail{diagnostic} Report{values, diagnostics}: Report{values, diagnostic <> diagnostics}

def scan(tokens: List<&2, String>, report: Report) -> Report:
  match tokens report:
    case Nil{} Report{values, diagnostics}: Report{values, List.reverse(&2, Diagnostic, diagnostics)}
    case token <> rest previous: scan(rest, applied(parseStrict(token), previous))

# Reports with diagnostics are unresolved configuration. No resolver consumes
# the partial values until its diagnostic policy has been selected explicitly.
def interpretStrict(tokens: List<&2, String>, initial: Options) -> Report:
  scan(tokens, Report{initial, Nil{}})
