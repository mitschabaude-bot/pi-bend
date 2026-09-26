import Base
import ../config.bend as Config
import ./args.bend as Args
import ../../../ai/src/auth/types.bend as Auth
import ../../../ai/src/types.bend as Ai
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/text.bend as Text

# upstream cli/auth-command.ts: `pi auth print-api-key | print-bearer-token |
# check`. Upstream's AuthCommandError is the Fail message of these results.

type AuthCommandKind is Data:
  Check{}
  ApiKey{}
  BearerToken{}

type AuthCommand is Data:
  AuthCommand{kind: AuthCommandKind, args: List<&2, String>, json: Bool, credentials: Bool, noRefresh: Bool, minExpiryMs: Maybe<&2, Nat>}

def getAuthCommandName(kind: AuthCommandKind) -> String:
  match kind:
    case Check{}: "auth check"
    case ApiKey{}: "auth print-api-key"
    case BearerToken{}: "auth print-bearer-token"

def getAuthCommandUsage(kind: AuthCommandKind) -> String:
  match kind:
    case Check{}: Config.appName() ++ " auth check --provider <provider> [--json] [--credentials] [--no-refresh]"
    case ApiKey{}: Config.appName() ++ " auth print-api-key --provider <provider> [--model <model>]"
    case BearerToken{}: Config.appName() ++ " auth print-bearer-token --provider <provider> [--model <model>] [--min-expiry <duration>]"

def helpFlag(args: List<&2, String>) -> Bool:
  match args:
    case Nil{}: False{}
    case +arg <> rest: String.eq(arg, "--help") || String.eq(arg, "-h") || helpFlag(rest)

# upstream isAuthCommandHelp: `auth`, `auth help`, or any --help/-h after it.
def isAuthCommandHelp(+args: List<&2, String>) -> Bool:
  match args:
    case "auth" <> Nil{}: True{}
    case "auth" <> "help" <> _: True{}
    case "auth" <> _: helpFlag(args)
    case _: False{}

def AUTH_COMMAND_HELP() -> String:
  String.join(["Usage:", "  pi auth print-api-key [--provider <provider>] [--model <model>]", "  pi auth print-bearer-token [--provider <provider>] [--model <model>] [--min-expiry <duration>]", "  pi auth check [--provider <provider>] [--model <model>] [--json] [--credentials] [--no-refresh]", "", "Auth commands require at least one of --provider or --model. Checks refresh expired OAuth credentials by default; --no-refresh prevents this. --credentials emits the credential, or includes it in JSON output."], "\n")

def printAuthCommandHelp() -> IO(Unit): IO.print(AUTH_COMMAND_HELP())

def kindOf(name: Maybe<&2, String>) -> Maybe<&2, AuthCommandKind>:
  match name:
    case Some{"check"}: Some{Check{}}
    case Some{"print-api-key"}: Some{ApiKey{}}
    case Some{"print-bearer-token"}: Some{BearerToken{}}
    case _: None{}

def unknownCommand(name: Maybe<&2, String>) -> String:
  "Unknown auth command \"" ++ Maybe.default(&2, String, name, "") ++ "\". Use \"" ++ Config.appName() ++ " auth print-api-key\", \"" ++ Config.appName() ++ " auth print-bearer-token\", or \"" ++ Config.appName() ++ " auth check\"."

def digits(text: String, +value: Nat) -> Maybe<&2, Nat>:
  match text:
    case SNil{}: Some{value}
    case SCon{Chr{+code}, rest}: Bool.pick(Unit -> Maybe<&2, Nat>, U32.is_ge(code, 48) && U32.is_le(code, 57), _ => digits(rest, Nat.add(Nat.mul(value, 10n), U32.to_nat((code - 48 : U32)))), _ => None{})(Unit{})

def unitMs(unit: String) -> Maybe<&2, Nat>:
  match unit:
    case "ms": Some{1n}
    case "s": Some{1000n}
    case "m": Some{60000n}
    case "h": Some{3600000n}
    case _: None{}

def splitDigits(text: String, +reversed: String) -> String & String:
  match text:
    case SCon{Chr{+code}, +rest}: Bool.pick(Unit -> String & String, U32.is_ge(code, 48) && U32.is_le(code, 57), _ => splitDigits(rest, SCon{Chr{code}, reversed}), _ => (String.reverse(reversed), SCon{Chr{code}, rest}))(Unit{})
    case SNil{}: (String.reverse(reversed), "")

def scaled(amount: Maybe<&2, Nat>, unit: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match amount unit:
    case Some{a} Some{u}: Some{Nat.mul(a, u)}
    case _ _: None{}

def durationParts(pair: String & String) -> Maybe<&2, Nat>:
  match pair:
    case (SNil{}, _): None{}
    case (number, unit): scaled(digits(number, 0n), unitMs(Text.asciiLower(unit)))

# /^(\d+)(ms|s|m|h)$/iu
def parseDuration(text: String) -> Maybe<&2, Nat>: durationParts(splitDigits(text, ""))

type Parsing is Data:
  Parsing{args: List<&2, String>, json: Bool, credentials: Bool, noRefresh: Bool, minExpiryMs: Maybe<&2, Nat>}

def flagOnlyForCheck(+arg: String) -> String: arg ++ " is only supported by auth check"

def checkFlag(+arg: String, state: Parsing) -> Parsing:
  match state:
    case Parsing{args, json, credentials, noRefresh, minExpiryMs}: Parsing{args, json || String.eq(arg, "--json"), credentials || String.eq(arg, "--credentials"), noRefresh || String.eq(arg, "--no-refresh"), minExpiryMs}

def withExpiry(value: Nat, state: Parsing) -> Parsing:
  match state:
    case Parsing{args, json, credentials, noRefresh, _}: Parsing{args, json, credentials, noRefresh, Some{value}}

def withArg(+arg: String, state: Parsing) -> Parsing:
  match state:
    case Parsing{args, json, credentials, noRefresh, minExpiryMs}: Parsing{List.append(&2, String, args, [arg]), json, credentials, noRefresh, minExpiryMs}

def isBearer(kind: AuthCommandKind) -> Bool:
  match kind:
    case BearerToken{}: True{}
    case _: False{}

def isCheck(kind: AuthCommandKind) -> Bool:
  match kind:
    case Check{}: True{}
    case _: False{}

def durationResult(value: Maybe<&2, Nat>) -> Result<&2, &2, String, Nat>:
  match value:
    case Some{ms}: Done{ms}
    case None{}: Fail{"--min-expiry must use a duration such as 30m or 1h"}

def expiryValue(bearerKind: Bool, value: String) -> Result<&2, &2, String, Nat>:
  match bearerKind:
    case False{}: Fail{"--min-expiry is only supported by print-bearer-token"}
    case True{}: Result.bind(&2, &2, String, Unit, Nat, Done{Unit{}}, _ => durationResult(parseDuration(value)))

def expiryThen(parsed: Result<&2, &2, String, Nat>, state: Parsing, next: Parsing -> Result<&2, &2, String, Parsing>) -> Result<&2, &2, String, Parsing>:
  match parsed:
    case Fail{message}: Fail{message}
    case Done{value}: next(withExpiry(value, state))

def argStep(+kind: AuthCommandKind, +arg: String, +state: Parsing) -> Result<&2, &2, String, Parsing>:
  +flag = String.eq(arg, "--json") || String.eq(arg, "--credentials") || String.eq(arg, "--no-refresh")
  Bool.pick(Result<&2, &2, String, Parsing>, flag, Bool.pick(Result<&2, &2, String, Parsing>, isCheck(kind), Done{checkFlag(arg, state)}, Fail{flagOnlyForCheck(arg)}), Done{withArg(arg, state)})

def parseFlags(+kind: AuthCommandKind, args: List<&2, String>, state: Parsing) -> Result<&2, &2, String, Parsing>:
  match args:
    case Nil{}: Done{state}
    case "--min-expiry" <> Nil{}: expiryThen(expiryValue(isBearer(kind), ""), state, next => Done{next})
    case "--min-expiry" <> value <> more: expiryThen(expiryValue(isBearer(kind), value), state, next => parseFlags(kind, more, next))
    case arg <> rest: Result.bind(&2, &2, String, Parsing, Parsing, argStep(kind, arg, state), next => parseFlags(kind, rest, next))

def commandOf(kind: AuthCommandKind, parsed: Result<&2, &2, String, Parsing>) -> Result<&2, &2, String, Maybe<&2, AuthCommand>>:
  match parsed:
    case Fail{message}: Fail{message}
    case Done{Parsing{args, json, credentials, noRefresh, minExpiryMs}}: Done{Some{AuthCommand{kind, args, json, credentials, noRefresh, minExpiryMs}}}

def parseKind(kind: Maybe<&2, AuthCommandKind>, name: Maybe<&2, String>, rest: List<&2, String>) -> Result<&2, &2, String, Maybe<&2, AuthCommand>>:
  match kind:
    case None{}: Fail{unknownCommand(name)}
    case Some{+found}: commandOf(found, parseFlags(found, rest, Parsing{Nil{}, False{}, False{}, False{}, None{}}))

# upstream parseAuthCommand: None for other commands; Fail for an unknown
# auth command or a flag that command does not take.
def parseAuthCommand(args: List<&2, String>) -> Result<&2, &2, String, Maybe<&2, AuthCommand>>:
  match args:
    case "auth" <> Nil{}: Fail{unknownCommand(None{})}
    case "auth" <> +name <> rest: parseKind(kindOf(Some{name}), Some{name}, rest)
    case _: Done{None{}}

type RequestedAuth is Data:
  RequestedAuth{provider: Maybe<&2, String>, model: Maybe<&2, String>}

def nonEmpty(text: String) -> Maybe<&2, String>:
  match text:
    case SNil{}: None{}
    case other: Some{other}

def trimmed(value: Maybe<&2, String>) -> Maybe<&2, String>:
  match value:
    case Some{text}: nonEmpty(Text.trim(text))
    case None{}: None{}

def firstUnknown(entries: List<&2, R.Property<Args.FlagValue>>) -> Maybe<&2, String>:
  match entries:
    case Nil{}: None{}
    case R.Property{name, _} <> _: Some{name}

def requested(+kind: AuthCommandKind, provider: Maybe<&2, String>, model: Maybe<&2, String>) -> Result<&2, &2, String, RequestedAuth>:
  match provider model:
    case None{} None{}: Fail{Bool.pick(String, isCheck(kind), "Auth checks require --provider <provider> or --model <model>", "Credential printing requires --provider <provider> or --model <model>")}
    case _ _: Done{RequestedAuth{provider, model}}

def validated(+kind: AuthCommandKind, unknown: Maybe<&2, String>, extra: Bool, provider: Maybe<&2, String>, model: Maybe<&2, String>) -> Result<&2, &2, String, RequestedAuth>:
  match unknown extra:
    case Some{option} _: Fail{"Unknown option --" ++ option ++ " for \"" ++ getAuthCommandName(kind) ++ "\"."}
    case None{} True{}: Fail{"Auth commands only accept --provider and --model"}
    case None{} False{}: requested(kind, provider, model)

# upstream validateAuthCommandArgs: only --provider and --model, at least one.
def validateAuthCommandArgs(args: Args.Args, +kind: AuthCommandKind) -> Result<&2, &2, String, RequestedAuth>:
  match args:
    case Args.Args{provider, model, apiKey, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, messages, fileArgs, unknownFlags, _}:
      validated(kind, firstUnknown(R.entries(Args.FlagValue, unknownFlags)), Maybe.is_some(&2, String, apiKey) || Bool.not(List.is_empty(&2, String, messages)) || Bool.not(List.is_empty(&2, String, fileArgs)), trimmed(provider), trimmed(model))

# /^Bearer\s+(.+)$/iu: greedy whitespace, then a non-empty single-line
# token; all-whitespace tails backtrack to their last character.
def lastChar(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{c, SNil{}}: SCon{c, SNil{}}
    case SCon{_, rest}: lastChar(rest)

def lineTerminator(+code: U32) -> Bool: U32.is_eq(code, 10) || U32.is_eq(code, 13) || U32.is_eq(code, 8232) || U32.is_eq(code, 8233)

def singleLine(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+code}, rest}: Bool.not(lineTerminator(code)) && singleLine(rest)

def tokenAfter(+spaces: String, token: String) -> Maybe<&2, String>:
  match token:
    case SCon{+t, +ts}: Bool.pick(Maybe<&2, String>, singleLine(SCon{t, ts}), Some{SCon{t, ts}}, None{})
    case SNil{}: Bool.pick(Maybe<&2, String>, Nat.is_ge(String.length(spaces), 2n) && singleLine(lastChar(spaces)), Some{lastChar(spaces)}, None{})

def bearer(+value: String) -> Maybe<&2, String>:
  +rest = String.drop(value, 6n)
  +token = Text.trimStart(rest)
  +spaces = String.take(rest, Nat.sub(String.length(rest), String.length(token)))
  Bool.pick(Maybe<&2, String>, String.eq(Text.asciiLower(String.take(value, 6n)), "bearer") && Bool.not(String.is_empty(spaces)), tokenAfter(spaces, token), None{})

def headerText(value: Ai.Nullable<String>) -> Maybe<&2, String>:
  match value:
    case Ai.PresentValue{text}: bearer(text)
    case Ai.NullValue{}: None{}

def authorizationHeader(entries: List<&2, R.Property<Ai.Nullable<String>>>) -> Maybe<&2, String>:
  match entries:
    case Nil{}: None{}
    case R.Property{+name, value} <> rest: Bool.pick(Unit -> Maybe<&2, String>, String.eq(String.to_lower(name), "authorization"), _ => headerText(value), _ => authorizationHeader(rest))(Unit{})

def headersOf(headers: Maybe<&2, Ai.ProviderHeaders()>) -> Maybe<&2, String>:
  match headers:
    case Some{values}: authorizationHeader(R.entries(Ai.Nullable<String>, values))
    case None{}: None{}

# upstream getAuthCredential: the API key, else the token of a Bearer
# Authorization header.
def getAuthCredential(auth: Maybe<&2, Auth.AuthResult>) -> Maybe<&2, String>:
  match auth:
    case Some{Auth.AuthResult{Auth.ModelAuth{Some{SCon{k, ks}}, _, _}, _, _}}: Some{SCon{k, ks}}
    case Some{Auth.AuthResult{Auth.ModelAuth{_, headers, _}, _, _}}: headersOf(headers)
    case None{}: None{}
