import Base
import ../utils/provider-env.bend as Env
import ./bedrock-credential-services.bend as Services
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/sha1.bend as Sha1
import ../../../runtime/src/url.bend as URL
import ../../../runtime/src/timer.bend as Timer
import ../../../runtime/src/abort.bend as Abort
import ../utils/schema-json.bend as SchemaJson
import ../utils/json.bend as JsonWire
import ../../../runtime/src/aws-sigv4.bend as SigV4
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/child-process.bend as Process
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/json.bend as Decode
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/ref.bend as Ref
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/text.bend as Space
import ../../../runtime/src/utf8.bend as Utf8
import ../../../runtime/src/f64.bend as F

# The AWS SDK's default credential and region chains as the Bedrock client
# relies on them when pi passes no static credentials: the shared config and
# credentials files and the provider chain over them
# (bedrock-credential-services.bend makes the service calls). Not provided:
# console login sessions (login_session) and the SDK clients' retries.

# Shared ini files
# ----------------

type Section is Data:
  Section{name: String, values: R.Record<String>}

def sectionName(+line: String) -> Maybe<&2, String>:
  +trimmed = Space.trim(line)
  Bool.pick(Maybe<&2, String>, String.starts_with(trimmed, "[") && String.ends_with(trimmed, "]"), Some{Space.trim(String.take(String.drop(trimmed, 1n), String.length(trimmed) - 2n))}, None{})

def beforeEquals(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{'=', _}: SNil{}
    case SCon{c, rest}: SCon{c, beforeEquals(rest)}

def afterEquals(text: String) -> Maybe<&2, String>:
  match text:
    case SNil{}: None{}
    case SCon{'=', rest}: Some{rest}
    case SCon{_, rest}: afterEquals(rest)

def comment(+line: String) -> Bool:
  +trimmed = Space.trimStart(line)
  String.starts_with(trimmed, "#") || String.starts_with(trimmed, ";") || String.is_empty(trimmed)

def withValue(sections: List<&2, Section>, +key: String, value: String) -> List<&2, Section>:
  match sections:
    case Section{name, values} <> rest: Section{name, R.set(String, values, key, value)} <> rest
    case Nil{}: Nil{}

def assigned(sections: List<&2, Section>, +line: String, value: Maybe<&2, String>) -> List<&2, Section>:
  match value:
    case None{}: sections
    case Some{text}: withValue(sections, Space.trim(beforeEquals(line)), Space.trim(text))

def sectionLine(sections: List<&2, Section>, +line: String, name: Maybe<&2, String>) -> List<&2, Section>:
  match name:
    case Some{section}: Section{section, R.new(String)} <> sections
    case None{}: assigned(sections, line, afterEquals(line))

# Sections in reverse order of appearance; later keys win within a section.
def parseLines(lines: List<&2, String>, +sections: List<&2, Section>) -> List<&2, Section>:
  match lines:
    case Nil{}: sections
    case +line <> rest: parseLines(rest, Bool.pick(List<&2, Section>, comment(line), sections, sectionLine(sections, line, sectionName(line))))

def withoutCarriage(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{'\r', rest}: withoutCarriage(rest)
    case SCon{c, rest}: SCon{c, withoutCarriage(rest)}

def parseIni(text: String) -> List<&2, Section>: parseLines(String.split(withoutCarriage(text), '\n'), Nil{})

def mergedEntries(entries: List<&2, R.Property<String>>, base: R.Record<String>) -> R.Record<String>:
  match entries:
    case Nil{}: base
    case R.Property{key, value} <> rest: mergedEntries(rest, R.set(String, base, key, value))

def merged(base: R.Record<String>, over: R.Record<String>) -> R.Record<String>:
  match over:
    case R.Record{entries}: mergedEntries(entries, base)

# The values of a named section (a config file names profiles "profile X"
# except "default"); sections of the same name merge, later values winning.
def sectionValues(sections: List<&2, Section>, +name: String) -> R.Record<String>:
  match sections:
    case Nil{}: R.new(String)
    case Section{+section, values} <> rest:
      +earlier = sectionValues(rest, name)
      Bool.pick(R.Record<String>, String.eq(section, name), merged(earlier, values), earlier)

def configSection(+profile: String) -> String: Bool.pick(String, String.eq(profile, "default"), "default", "profile " ++ profile)

type Files is Data:
  Files{config: List<&2, Section>, credentials: List<&2, Section>}

# The selected profile: the config file's values overlaid by the credentials
# file's (the SDK's parseKnownFiles).
def profileValues(files: Files, +profile: String) -> R.Record<String>:
  match files:
    case Files{config, credentials}: merged(sectionValues(config, configSection(profile)), sectionValues(credentials, profile))

def decodedText(value: Utf8.Decoded) -> String:
  match value:
    case Utf8.Decoded{_, text}: text

def fileText(result: Result<&2, &2, FS.Error, List<&2, U32>>) -> String:
  match result:
    case Done{bytes}: decodedText(Utf8.decode(Utf8.create(), bytes))
    case Fail{_}: ""

def homePath(home: Maybe<&2, String>, +name: String) -> String: Maybe.default(&2, String, home, "") ++ "/.aws/" ++ name

def pathOf(explicit: Maybe<&2, String>, home: Maybe<&2, String>, +name: String) -> String:
  match explicit:
    case Some{SCon{c, cs}}: SCon{c, cs}
    case _: homePath(home, name)

def readText(path: String) -> IO(String):
  do IO<String>:
    result : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(path)
    return fileText(result)

def loadFiles() -> IO(Files):
  do IO<Files>:
    +home : Maybe<&2, String> <- Env.getProviderEnvValue("HOME", None{})
    configPath : Maybe<&2, String> <- Env.getProviderEnvValue("AWS_CONFIG_FILE", None{})
    credentialsPath : Maybe<&2, String> <- Env.getProviderEnvValue("AWS_SHARED_CREDENTIALS_FILE", None{})
    config : String <- readText(pathOf(configPath, home, "config"))
    credentials : String <- readText(pathOf(credentialsPath, home, "credentials"))
    return Files{parseIni(config), parseIni(credentials)}

# Credentials
# -----------

def nonempty(value: Maybe<&2, String>) -> Maybe<&2, String>:
  match value:
    case Some{SCon{c, cs}}: Some{SCon{c, cs}}
    case _: None{}

def staticFrom(access: Maybe<&2, String>, secret: Maybe<&2, String>, token: Maybe<&2, String>) -> Maybe<&2, SigV4.Credentials>:
  match access secret:
    case Some{key} Some{value}: Some{SigV4.Credentials{key, value, token}}
    case _ _: None{}

def staticCredentials(+values: R.Record<String>) -> Maybe<&2, SigV4.Credentials>:
  staticFrom(nonempty(R.get(String, values, "aws_access_key_id")), nonempty(R.get(String, values, "aws_secret_access_key")), nonempty(R.get(String, values, "aws_session_token")))

def collect(sink: Ref.Ref<List<&2, U32>>, bytes: List<&2, U32>) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    Ref.modify(List<&2, U32>, Unit, sink, previous => (List.append(&2, U32, previous, bytes), Unit{}))
    return Done{Unit{}}

def textOf(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{text}}: nonempty(Some{text})
    case _: None{}

def versionOne(value: Maybe<&2, V.Value>) -> Bool:
  match value:
    case Some{V.Number{number}}: F.isEqual(F.compare(number, F.fromU32(1)))
    case _: False{}

def textMember(fields: R.Record<V.Value>, name: String) -> Maybe<&2, String>: textOf(R.get(V.Value, fields, name))

def processKeys(profile: String, access: Maybe<&2, String>, secret: Maybe<&2, String>, token: Maybe<&2, String>) -> Result<&2, &2, String, SigV4.Credentials>:
  match access secret:
    case Some{key} Some{value}: Done{SigV4.Credentials{key, value, token}}
    case _ _: Fail{"Profile " ++ profile ++ " credential_process returned invalid credentials."}

def expiredParsed(value: Result<&2, &2, Date.ParseError, F64>, now: F64) -> Bool:
  match value:
    case Done{ms}: F.isGreater(F.compare(now, ms))
    case Fail{_}: False{}

def expiredAt(value: Maybe<&2, String>, now: F64) -> Bool:
  match value:
    case Some{SCon{c, cs}}: expiredParsed(Date.parseIso(SCon{c, cs}), now)
    case _: False{}

def processFields(+profile: String, +fields: R.Record<V.Value>, now: F64) -> Result<&2, &2, String, SigV4.Credentials>:
  Bool.pick(Result<&2, &2, String, SigV4.Credentials>, versionOne(R.get(V.Value, fields, "Version")), Bool.pick(Result<&2, &2, String, SigV4.Credentials>, expiredAt(textMember(fields, "Expiration"), now), Fail{"Profile " ++ profile ++ " credential_process returned expired credentials."}, processKeys(profile, textMember(fields, "AccessKeyId"), textMember(fields, "SecretAccessKey"), nonempty(textMember(fields, "SessionToken")))), Fail{"Profile " ++ profile ++ " credential_process did not return Version 1."})

def processJson(+profile: String, result: Result<&2, &2, Decode.ParseError, V.Value>, now: F64) -> Result<&2, &2, String, SigV4.Credentials>:
  match result:
    case Done{V.ObjectValue{fields}}: processFields(profile, fields, now)
    case _: Fail{"Profile " ++ profile ++ " credential_process returned invalid JSON."}

def processOutput(+profile: String, command: String, status: Result<&2, &2, Process.ExecutionError, U32>, bytes: List<&2, U32>, now: F64) -> Result<&2, &2, String, SigV4.Credentials>:
  match status:
    case Done{0}: processJson(profile, Decode.parse(String.trim(decodedText(Utf8.decode(Utf8.create(), bytes)))), now)
    case _: Fail{"Command failed: " ++ command}

# fromProcess: the credential_process command through the shell, its stdout
# the JSON credentials document (Version 1).
def processCredentials(+profile: String, +command: String) -> IO(Result<&2, &2, String, SigV4.Credentials>):
  do IO<Result<&2, &2, String, SigV4.Credentials>>:
    +sink : Ref.Ref<List<&2, U32>> <- Ref.new(List<&2, U32>, Nil{})
    +onData : C.Callback<List<&2, U32>, Result<&2, &2, String, Unit>> <- C.create(~Ref.Ref<List<&2, U32>>, ~List<&2, U32>, ~Result<&2, &2, String, Unit>, ~collect, sink)
    entries : List<String> <- IO.environment()
    status : Result<&2, &2, Process.ExecutionError, U32> <- Process.executeSelected(Process.Stdout{}, "/bin/sh", ["-c"], command, "/", entries, None{}, None{}, onData)
    C.dispose(List<&2, U32>, Result<&2, &2, String, Unit>, onData)
    bytes : List<&2, U32> <- Ref.dispose(List<&2, U32>, sink)
    now : F64 <- Date.now()
    return processOutput(profile, command, status, bytes, now)

# The default chain
# -----------------

# A chain link's outcome: credentials, a failure the chain passes over
# (CredentialsProviderError with tryNextLink), or one that stops it.
type Step is Data:
  Resolved{credentials: SigV4.Credentials}
  Next{message: String}
  Stop{message: String}

def stepOf(result: Result<&2, &2, String, SigV4.Credentials>) -> Step:
  match result:
    case Done{credentials}: Resolved{credentials}
    case Fail{message}: Next{message}

def stopOf(result: Result<&2, &2, String, SigV4.Credentials>) -> Step:
  match result:
    case Done{credentials}: Resolved{credentials}
    case Fail{message}: Stop{message}

def serviceStop(result: Result<&2, &2, Services.ServiceError, SigV4.Credentials>) -> Step:
  match result:
    case Done{credentials}: Resolved{credentials}
    case Fail{Services.ServiceError{_, message}}: Stop{message}

# What the chain reads besides the files: the HTTP client, the Bedrock
# client's region (the STS "parent" region) and the explicit profile.
type Chain<-Reason: Data> is Data:
  Chain{transport: Services.Transport<Reason>, region: Maybe<&2, String>, profile: Maybe<&2, String>}

def transportOf(~Reason: Data, chain: Chain<Reason>) -> Services.Transport<Reason>:
  match chain:
    case Chain{transport, _, _}: transport

def env(+name: String) -> IO(Maybe<&2, String>): Env.getProviderEnvValue(name, None{})

def truthy(value: Maybe<&2, String>) -> Bool:
  match value:
    case Some{SCon{_, _}}: True{}
    case _: False{}

def get(values: R.Record<String>, name: String) -> Maybe<&2, String>: R.get(String, values, name)

def has(values: R.Record<String>, name: String) -> Bool: Maybe.is_some(&2, String, R.get(String, values, name))

def keyNames(entries: List<&2, R.Property<String>>) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{name, _} <> rest: name <> keyNames(rest)

def keys(values: R.Record<String>) -> List<&2, String>:
  match values:
    case R.Record{entries}: keyNames(entries)

# fromEnv
def envCredentials(access: Maybe<&2, String>, secret: Maybe<&2, String>, token: Maybe<&2, String>) -> Step:
  match access secret:
    case Some{SCon{a, as}} Some{SCon{s, ss}}: Resolved{SigV4.Credentials{SCon{a, as}, SCon{s, ss}, nonempty(token)}}
    case _ _: Next{"Unable to find environment variable credentials."}

def fromEnv() -> IO(Step):
  do IO<Step>:
    access : Maybe<&2, String> <- env("AWS_ACCESS_KEY_ID")
    secret : Maybe<&2, String> <- env("AWS_SECRET_ACCESS_KEY")
    token : Maybe<&2, String> <- env("AWS_SESSION_TOKEN")
    return envCredentials(access, secret, token)

# Profile kinds (credential-provider-ini)
# ---------------------------------------

def isStatic(+values: R.Record<String>) -> Bool: has(values, "aws_access_key_id") && has(values, "aws_secret_access_key")

def isSourceProfile(+values: R.Record<String>) -> Bool: has(values, "source_profile") && Bool.not(has(values, "credential_source"))

def isCredentialSource(+values: R.Record<String>) -> Bool: has(values, "credential_source") && Bool.not(has(values, "source_profile"))

def isAssumeRole(+values: R.Record<String>) -> Bool: has(values, "role_arn") && (isSourceProfile(values) || isCredentialSource(values))

def isCredentialSourceWithoutRoleArn(+values: R.Record<String>) -> Bool: Bool.not(truthy(get(values, "role_arn"))) && truthy(get(values, "credential_source"))

def isWebIdentity(+values: R.Record<String>) -> Bool: has(values, "web_identity_token_file") && has(values, "role_arn")

def isProcess(values: R.Record<String>) -> Bool: has(values, "credential_process")

def isSso(+values: R.Record<String>) -> Bool: has(values, "sso_start_url") || has(values, "sso_account_id") || has(values, "sso_session") || has(values, "sso_region") || has(values, "sso_role_name")

def isLogin(values: R.Record<String>) -> Bool: truthy(get(values, "login_session"))

# The source of a (chain of) role assumptions.
type Base is Data:
  StaticBase{credentials: SigV4.Credentials}
  SourceBase{profile: String, source: String}
  WebIdentityBase{file: String, roleArn: String, sessionName: Maybe<&2, String>}
  ProcessBase{profile: String, command: String}
  SsoBase{profile: String, values: R.Record<String>}
  FailedBase{step: Step}

type RoleStep is Data:
  RoleStep{profile: String, roleArn: String, sessionName: Maybe<&2, String>, externalId: Maybe<&2, String>, duration: Maybe<&2, String>, mfa: Maybe<&2, String>}

# The base credentials, the roles assumed from them (innermost first) and the
# STS region of the outermost role profile, whose role assumer the SDK
# creates and reuses for the inner ones.
type Plan is Data:
  Plan{base: Base, roles: List<&2, RoleStep>, region: Maybe<&2, String>}

def roleOf(+profile: String, +values: R.Record<String>) -> RoleStep:
  RoleStep{profile, Maybe.default(&2, String, get(values, "role_arn"), ""), nonempty(get(values, "role_session_name")), get(values, "external_id"), nonempty(get(values, "duration_seconds")), nonempty(get(values, "mfa_serial"))}

def contains(names: List<&2, String>, +name: String) -> Bool:
  match names:
    case Nil{}: False{}
    case first <> rest: String.eq(first, name) || contains(rest, name)

# How resolveProfileData treats a profile.
type ProfileKind is Data:
  StaticKind{}
  RoleKind{}
  WebIdentityKind{}
  ProcessKind{}
  SsoKind{}
  LoginKind{}
  UnknownKind{}

def kindOf(+values: R.Record<String>, visited: Bool, recursive: Bool) -> ProfileKind:
  Bool.pick(ProfileKind, visited && isStatic(values), StaticKind{}, Bool.pick(ProfileKind, recursive || isAssumeRole(values), RoleKind{}, Bool.pick(ProfileKind, isStatic(values), StaticKind{}, Bool.pick(ProfileKind, isWebIdentity(values), WebIdentityKind{}, Bool.pick(ProfileKind, isProcess(values), ProcessKind{}, Bool.pick(ProfileKind, isSso(values), SsoKind{}, Bool.pick(ProfileKind, isLogin(values), LoginKind{}, UnknownKind{})))))))

def staticOf(+values: R.Record<String>) -> SigV4.Credentials:
  SigV4.Credentials{Maybe.default(&2, String, get(values, "aws_access_key_id"), ""), Maybe.default(&2, String, get(values, "aws_secret_access_key"), ""), get(values, "aws_session_token")}

def couldNotResolve(+profile: String) -> Step: Next{"Could not resolve credentials using profile: [" ++ profile ++ "] in configuration/credentials file(s)."}

def rolesWith(+values: R.Record<String>, +profile: String, +roles: List<&2, RoleStep>) -> List<&2, RoleStep>:
  Bool.pick(List<&2, RoleStep>, isCredentialSourceWithoutRoleArn(values), roles, roleOf(profile, values) <> roles)

# The outermost role profile's region, once one is met.
type RoleRegion is Data:
  Unset{}
  RegionSet{region: Maybe<&2, String>}

def firstRegion(region: RoleRegion, values: R.Record<String>) -> RoleRegion:
  match region:
    case Unset{}: RegionSet{get(values, "region")}
    case known: known

def planRegion(region: RoleRegion) -> Maybe<&2, String>:
  match region:
    case RegionSet{value}: value
    case Unset{}: None{}

def plan(base: Base, roles: List<&2, RoleStep>, region: RoleRegion) -> Plan: Plan{base, roles, planRegion(region)}

# upstream resolveProfileData as a plan: walking source_profile links from
# the selected profile, collecting the roles to assume (each prepended, so the
# innermost comes first) until a profile supplies base credentials. `kind` and
# `source` describe `profile`; `region` is set once a role profile is met.
def walk(depth: Nat, +files: Files, +selected: String, +profile: String, +values: R.Record<String>, kind: ProfileKind, source: Maybe<&2, String>, +visited: List<&2, String>, +roles: List<&2, RoleStep>, +region: RoleRegion) -> Plan:
  match depth:
    case 0n: plan(FailedBase{couldNotResolve(profile)}, roles, region)
    case 1n+left:
      match kind:
        case StaticKind{}: plan(StaticBase{staticOf(values)}, roles, region)
        case WebIdentityKind{}: plan(WebIdentityBase{Maybe.default(&2, String, get(values, "web_identity_token_file"), ""), Maybe.default(&2, String, get(values, "role_arn"), ""), get(values, "role_session_name")}, roles, region)
        case ProcessKind{}: plan(ProcessBase{profile, Maybe.default(&2, String, get(values, "credential_process"), "")}, roles, region)
        case SsoKind{}: plan(SsoBase{profile, values}, roles, region)
        case LoginKind{}: plan(FailedBase{Next{"Profile " ++ profile ++ " uses a console login session (login_session), which this port does not provide."}}, roles, region)
        case UnknownKind{}: plan(FailedBase{couldNotResolve(profile)}, roles, region)
        case RoleKind{}:
          match source:
            case None{}: plan(SourceBase{profile, Maybe.default(&2, String, get(values, "credential_source"), "")}, rolesWith(values, profile, roles), firstRegion(region, values))
            case Some{+next}:
              +nextValues = profileValues(files, next)
              Bool.pick(Unit -> Plan, contains(visited, next), _ => plan(FailedBase{Next{"Detected a cycle attempting to resolve credentials for profile " ++ selected ++ ". Profiles visited: " ++ String.join(visited, ", ")}}, roles, region), _ =>
                walk(left, files, selected, next, nextValues, kindOf(nextValues, True{}, isCredentialSourceWithoutRoleArn(nextValues)), get(nextValues, "source_profile"), List.append(&2, String, visited, [next]), rolesWith(values, profile, roles), firstRegion(region, values)))(Unit{})

def planFor(+files: Files, +profile: String) -> Plan:
  +values = profileValues(files, profile)
  walk(64n, files, profile, profile, values, kindOf(values, False{}, False{}), get(values, "source_profile"), Nil{}, Nil{}, Unset{})

# Remote credentials (credential-provider-http, credential-provider-imds)
# ----------------------------------------------------------------------

def ECS_HOST() -> String: "http://169.254.170.2"

def hostOfUrl(parsed: Result<&2, &2, URL.Error, URL.URL>) -> Maybe<&2, String>:
  match parsed:
    case Done{URL.URL{_, _, _, Some{host}, _, _, _, _}}: Some{URL.serializeHost(host)}
    case _: None{}

def schemeOf(parsed: Result<&2, &2, URL.Error, URL.URL>) -> String:
  match parsed:
    case Done{URL.URL{scheme, _, _, _, _, _, _, _}}: URL.serializeScheme(scheme)
    case Fail{_}: ""

def loopbackIpv4(parts: List<&2, String>) -> Bool:
  match parts:
    case "127" <> _ <> _ <> _ <> Nil{}: True{}
    case _: False{}

# checkUrl: https, the ECS/EKS container hosts, or loopback.
def acceptedUrl(+scheme: String, +host: String) -> Bool:
  String.eq(scheme, "https") || String.eq(host, "169.254.170.2") || String.eq(host, "169.254.170.23") || String.eq(host, "[fd00:ec2::23]") || String.eq(host, "[::1]") || String.eq(host, "localhost") || loopbackIpv4(String.split(host, '.'))

def URL_NOT_ACCEPTED() -> String: "URL not accepted. It must either be HTTPS or match one of the following:\n  - loopback CIDR 127.0.0.0/8 or [::1/128]\n  - ECS container host 169.254.170.2\n  - EKS container host 169.254.170.23 or [fd00:ec2::23]"

# One fromHttp attempt: the authorization token (the token file, read on
# every attempt, before the token variable), then the request.
type Authorization is Data:
  Authorized{token: Maybe<&2, String>}
  Unauthorized{step: Step}

def validated(+token: String) -> Authorization:
  Bool.pick(Authorization, String.contains(token, "\r\n"), Unauthorized{Next{"Authorization token contains invalid \\r\\n sequence."}}, Authorized{Some{token}})

def authorizationRead(+file: String, value: Result<&2, &2, FS.Error, List<&2, U32>>) -> Authorization:
  match value:
    case Done{bytes}: validated(fileText(Done{bytes}))
    case Fail{_}: Unauthorized{Stop{"ENOENT: no such file or directory, open '" ++ file ++ "'"}}

def tokenFrom(file: Maybe<&2, String>, token: Maybe<&2, String>) -> IO(Authorization):
  match file token:
    case Some{SCon{+c, +cs}} _:
      do IO<Authorization>:
        bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(SCon{c, cs})
        return authorizationRead(SCon{c, cs}, bytes)
    case _ Some{SCon{+c, +cs}}: IO.pure(Authorization, validated(SCon{c, cs}))
    case _ _: IO.pure(Authorization, Authorized{None{}})

def attemptWith(~Reason: Data, +transport: Services.Transport<Reason>, +url: String, authorization: Authorization) -> IO(Step):
  match authorization:
    case Unauthorized{step}: IO.pure(Step, step)
    case Authorized{token}:
      do IO<Step>:
        result : Result<&2, &2, String, SigV4.Credentials> <- Services.containerRequest(~Reason, transport, url, token)
        return stepOf(result)

def containerAttempt(~Reason: Data, +transport: Services.Transport<Reason>, +url: String) -> IO(Step):
  do IO<Step>:
    file : Maybe<&2, String> <- env("AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE")
    token : Maybe<&2, String> <- env("AWS_CONTAINER_AUTHORIZATION_TOKEN")
    authorization : Authorization <- tokenFrom(file, token)
    attemptWith(~Reason, transport, url, authorization)

def resolvedStep(step: Step) -> Bool:
  match step:
    case Resolved{_}: True{}
    case _: False{}

# fromHttp's retryWrapper: up to three retries one second apart, whatever
# the failure.
@unsafe def containerAttempts(~Reason: Data, +transport: Services.Transport<Reason>, +url: String, +left: Nat) -> IO(Step):
  do IO<Step>:
    +step : Step <- containerAttempt(~Reason, transport, url)
    Bool.pick(Unit -> IO(Step), Nat.is_eq(left, 0n) || resolvedStep(step), _ => IO.pure(Step, step), _ =>
      do IO<Step>:
        slept : Result<&2, &2, Abort.AbortReason<Reason>, Unit> <- Timer.sleep(Reason, 1000, Services.signalOf(~Reason, transport))
        containerAttempts(~Reason, transport, url, Nat.sub(left, 1n)))(Unit{})

# fromHttp checks its URL when it is created, so a rejected URL fails the
# remote link itself (fromContainerMetadata never runs); an unparsable one is
# a plain error that stops the chain.
type HttpLink is Data:
  Created{step: Step}
  NotCreated{step: Step}

def urlChecked(+parsed: Result<&2, &2, URL.Error, URL.URL>) -> Maybe<&2, Step>:
  match parsed:
    case Fail{_}: Some{Stop{"Invalid URL"}}
    case Done{address}: Bool.pick(Maybe<&2, Step>, acceptedUrl(schemeOf(Done{address}), Maybe.default(&2, String, hostOfUrl(Done{address}), "")), None{}, Some{Next{URL_NOT_ACCEPTED()}})

def httpWith(~Reason: Data, +transport: Services.Transport<Reason>, +host: String, rejected: Maybe<&2, Step>) -> IO(HttpLink):
  match rejected:
    case Some{step}: IO.pure(HttpLink, NotCreated{step})
    case None{}:
      do IO<HttpLink>:
        step : Step <- containerAttempts(~Reason, transport, host, 3n)
        return Created{step}

def fromHttp(~Reason: Data, +transport: Services.Transport<Reason>, relative: Maybe<&2, String>, full: Maybe<&2, String>) -> IO(HttpLink):
  +host = Maybe.default(&2, String, Maybe.or(&2, String, Maybe.map(&2, String, String, path => ECS_HOST() ++ path, nonempty(relative)), nonempty(full)), "")
  httpWith(~Reason, transport, host, urlChecked(URL.parse(Services.contextOf(~Reason, transport), host)))

def containerMetadata(~Reason: Data, +transport: Services.Transport<Reason>, relative: Maybe<&2, String>, full: Maybe<&2, String>) -> IO(Step):
  match relative full:
    case Some{path} _:
      do IO<Step>:
        token : Maybe<&2, String> <- env("AWS_CONTAINER_AUTHORIZATION_TOKEN")
        result : Result<&2, &2, String, SigV4.Credentials> <- Services.containerRequest(~Reason, transport, ECS_HOST() ++ path, token)
        return stepOf(result)
    case None{} Some{+uri}:
      +parsed = URL.parse(Services.contextOf(~Reason, transport), uri)
      +host = Maybe.default(&2, String, hostOfUrl(parsed), "")
      Bool.pick(Unit -> IO(Step), String.eq(host, "localhost") || String.eq(host, "127.0.0.1"), _ =>
        do IO<Step>:
          token : Maybe<&2, String> <- env("AWS_CONTAINER_AUTHORIZATION_TOKEN")
          result : Result<&2, &2, String, SigV4.Credentials> <- Services.containerRequest(~Reason, transport, uri, token)
          return stepOf(result), _ => IO.pure(Step, Stop{host ++ " is not a valid container metadata service hostname"}))(Unit{})
    case None{} None{}: IO.pure(Step, Next{"No HTTP credential provider host provided.\nSet AWS_CONTAINER_CREDENTIALS_FULL_URI or AWS_CONTAINER_CREDENTIALS_RELATIVE_URI."})

# fromContainerMetadata: the relative URI on the ECS host, or a full URI on a
# Greengrass host.
def fromContainerMetadata(~Reason: Data, +transport: Services.Transport<Reason>, relative: Maybe<&2, String>, full: Maybe<&2, String>) -> IO(Step): containerMetadata(~Reason, transport, nonempty(relative), nonempty(full))

def afterHttp(~Reason: Data, +transport: Services.Transport<Reason>, relative: Maybe<&2, String>, full: Maybe<&2, String>, first: HttpLink) -> IO(Step):
  match first:
    case Created{Next{_}}: fromContainerMetadata(~Reason, transport, relative, full)
    case Created{other}: IO.pure(Step, other)
    case NotCreated{step}: IO.pure(Step, step)

def containerChain(~Reason: Data, +transport: Services.Transport<Reason>) -> IO(Step):
  do IO<Step>:
    +relative : Maybe<&2, String> <- env("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")
    +full : Maybe<&2, String> <- env("AWS_CONTAINER_CREDENTIALS_FULL_URI")
    first : HttpLink <- fromHttp(~Reason, transport, relative, full)
    afterHttp(~Reason, transport, relative, full, first)

def endpointOrMode(endpoint: Maybe<&2, String>, mode: Maybe<&2, String>) -> Result<&2, &2, String, String>:
  match endpoint mode:
    case Some{endpoint} _: Done{endpoint}
    case None{} None{}: Done{"http://169.254.169.254"}
    case None{} Some{"IPv4"}: Done{"http://169.254.169.254"}
    case None{} Some{"IPv6"}: Done{"http://[fd00:ec2::254]"}
    case None{} Some{other}: Fail{"Unsupported endpoint mode: " ++ other ++ ". Select from IPv4,IPv6"}

# IMDS
def imdsEndpoint(explicit: Maybe<&2, String>, configured: Maybe<&2, String>, mode: Maybe<&2, String>) -> Result<&2, &2, String, String>: endpointOrMode(Maybe.or(&2, String, nonempty(explicit), nonempty(configured)), mode)

def disabledValue(value: Maybe<&2, String>) -> Bool:
  match value:
    case Some{+text}: Bool.not(String.is_empty(text)) && Bool.not(String.eq(text, "false"))
    case None{}: False{}

def imdsFailure(error: Services.HttpError) -> String:
  match error:
    case Services.TimedOut{}: "TimeoutError from instance metadata service"
    case _: "Unable to connect to instance metadata service"

def imdsBody(response: Services.Imds) -> Result<&2, &2, String, String>:
  match response:
    case Services.ImdsFailed{error}: Fail{imdsFailure(error)}
    case Services.ImdsText{+status, body}: Bool.pick(Result<&2, &2, String, String>, U32.is_ge(status, 200) && U32.is_lt(status, 300), Done{body}, Fail{"Error response received from instance metadata service"})

def tokenFields(token: Maybe<&2, String>) -> List<&2, SigV4.Field>:
  match token:
    case Some{value}: [SigV4.Field{"x-aws-ec2-metadata-token", value}]
    case None{}: Nil{}

def imdsParsed(value: Maybe<&2, SigV4.Credentials>) -> Step:
  match value:
    case Some{credentials}: Resolved{credentials}
    case None{}: Next{"Invalid response received from instance metadata service."}

def imdsCredentialsOf(body: Result<&2, &2, String, String>) -> Step:
  match body:
    case Fail{message}: Next{message}
    case Done{+text}: imdsParsed(Services.imdsCredentials(text))

def imdsProfileRead(~Reason: Data, +transport: Services.Transport<Reason>, +endpoint: String, token: Maybe<&2, String>, profile: Result<&2, &2, String, String>) -> IO(Step):
  match profile:
    case Fail{message}: IO.pure(Step, Next{message})
    case Done{+name}:
      do IO<Step>:
        response : Services.Imds <- Services.imdsRequest(~Reason, transport, "GET", endpoint ++ "/latest/meta-data/iam/security-credentials/" ++ String.trim(name), tokenFields(token))
        return imdsCredentialsOf(imdsBody(response))

def imdsCredentialsWith(~Reason: Data, +transport: Services.Transport<Reason>, +endpoint: String, +token: Maybe<&2, String>) -> IO(Step):
  do IO<Step>:
    profile : Services.Imds <- Services.imdsRequest(~Reason, transport, "GET", endpoint ++ "/latest/meta-data/iam/security-credentials/", tokenFields(token))
    imdsProfileRead(~Reason, transport, endpoint, token, imdsBody(profile))

def v1Causes(profileBlocked: Bool, envBlocked: Bool) -> String:
  String.join(List.concat(&2, String, [Bool.pick(List<&2, String>, profileBlocked, ["config file profile (ec2_metadata_v1_disabled)"], Nil{}), Bool.pick(List<&2, String>, envBlocked, ["process environment variable (AWS_EC2_METADATA_V1_DISABLED)"], Nil{})]), ", ")

# The v1 fallback (no token), unless blocked by configuration.
def imdsV1(~Reason: Data, +transport: Services.Transport<Reason>, +endpoint: String, +envValue: Maybe<&2, String>, profileValue: Maybe<&2, String>) -> IO(Step):
  +envBlocked = disabledValue(envValue)
  +profileBlocked = Bool.pick(Bool, Maybe.is_some(&2, String, envValue), False{}, disabledValue(profileValue))
  Bool.pick(Unit -> IO(Step), envBlocked || profileBlocked, _ => IO.pure(Step, Next{"AWS EC2 Metadata v1 fallback has been blocked by AWS SDK configuration in the following: [" ++ v1Causes(profileBlocked, envBlocked) ++ "]."}), _ => imdsCredentialsWith(~Reason, transport, endpoint, None{}))(Unit{})

def afterToken(~Reason: Data, +transport: Services.Transport<Reason>, +endpoint: String, envValue: Maybe<&2, String>, profileValue: Maybe<&2, String>, response: Services.Imds) -> IO(Step):
  match response:
    case Services.ImdsText{+status, body}:
      Bool.pick(Unit -> IO(Step), U32.is_ge(status, 200) && U32.is_lt(status, 300), _ => imdsCredentialsWith(~Reason, transport, endpoint, Some{body}), _ => Bool.pick(Unit -> IO(Step), U32.is_eq(status, 400), _ => IO.pure(Step, Next{"EC2 Metadata token request returned error"}), _ => imdsV1(~Reason, transport, endpoint, envValue, profileValue))(Unit{}))(Unit{})
    case Services.ImdsFailed{_}: imdsV1(~Reason, transport, endpoint, envValue, profileValue)

def imdsAt(~Reason: Data, +transport: Services.Transport<Reason>, endpoint: Result<&2, &2, String, String>, values: R.Record<String>) -> IO(Step):
  match endpoint:
    case Fail{message}: IO.pure(Step, Stop{message})
    case Done{+base}:
      do IO<Step>:
        envValue : Maybe<&2, String> <- env("AWS_EC2_METADATA_V1_DISABLED")
        token : Services.Imds <- Services.imdsRequest(~Reason, transport, "PUT", base ++ "/latest/api/token", [SigV4.Field{"x-aws-ec2-metadata-token-ttl-seconds", "21600"}])
        afterToken(~Reason, transport, base, envValue, get(values, "ec2_metadata_v1_disabled"), token)

def fromInstanceMetadata(~Reason: Data, +transport: Services.Transport<Reason>, +values: R.Record<String>) -> IO(Step):
  do IO<Step>:
    explicit : Maybe<&2, String> <- env("AWS_EC2_METADATA_SERVICE_ENDPOINT")
    mode : Maybe<&2, String> <- env("AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE")
    imdsAt(~Reason, transport, imdsEndpoint(explicit, get(values, "ec2_metadata_service_endpoint"), Maybe.or(&2, String, nonempty(mode), get(values, "ec2_metadata_service_endpoint_mode"))), values)

# remoteProvider: container credentials, else IMDS unless disabled.
def remoteProvider(~Reason: Data, +transport: Services.Transport<Reason>, values: R.Record<String>) -> IO(Step):
  do IO<Step>:
    relative : Maybe<&2, String> <- env("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")
    full : Maybe<&2, String> <- env("AWS_CONTAINER_CREDENTIALS_FULL_URI")
    disabled : Maybe<&2, String> <- env("AWS_EC2_METADATA_DISABLED")
    Bool.pick(Unit -> IO(Step), truthy(relative) || truthy(full), _ => containerChain(~Reason, transport), _ => Bool.pick(Unit -> IO(Step), disabledValue(disabled), _ => IO.pure(Step, Next{"EC2 Instance Metadata Service access disabled"}), _ => fromInstanceMetadata(~Reason, transport, values))(Unit{}))(Unit{})

# STS
# ---

def stsDefaultRegion(ambient: Maybe<&2, String>, profileRegion: Maybe<&2, String>) -> String:
  Maybe.default(&2, String, Maybe.or(&2, String, nonempty(ambient), nonempty(profileRegion)), "us-east-1")

def stsEndpointFor(+region: String) -> IO(String):
  do IO<String>:
    service : Maybe<&2, String> <- env("AWS_ENDPOINT_URL_STS")
    global : Maybe<&2, String> <- env("AWS_ENDPOINT_URL")
    return Services.stsEndpoint(Maybe.or(&2, String, nonempty(service), nonempty(global)), region)

def profileName(explicit: Maybe<&2, String>) -> IO(String):
  match explicit:
    case Some{SCon{c, cs}}: IO.pure(String, SCon{c, cs})
    case _:
      do IO<String>:
        ambient : Maybe<&2, String> <- Env.getProviderEnvValue("AWS_PROFILE", None{})
        return Maybe.default(&2, String, ambient, "default")

# The STS client's region: the role profile's region, the Bedrock client's,
# then AWS_REGION, the selected profile's region, or us-east-1.
def stsRegion(~Reason: Data, chain: Chain<Reason>, files: Files, own: Maybe<&2, String>) -> IO(String):
  match chain:
    case Chain{_, parent, profile}:
      do IO<String>:
        ambient : Maybe<&2, String> <- env("AWS_REGION")
        +name : String <- profileName(profile)
        return Maybe.default(&2, String, Maybe.or(&2, String, nonempty(own), nonempty(parent)), stsDefaultRegion(ambient, get(profileValues(files, name), "region")))

def millis(+now: F64) -> String: Maybe.default(&2, String, F.toJsonNumber(now), "0")

def assumed(~Reason: Data, +chain: Chain<Reason>, files: Files, own: Maybe<&2, String>, role: RoleStep, source: SigV4.Credentials) -> IO(Step):
  match role:
    case RoleStep{_, roleArn, session, external, duration, _}:
      do IO<Step>:
        +region : String <- stsRegion(~Reason, chain, files, own)
        endpoint : String <- stsEndpointFor(region)
        now : F64 <- Date.now()
        result : Result<&2, &2, Services.ServiceError, SigV4.Credentials> <- Services.assumeRole(~Reason, transportOf(~Reason, chain), endpoint, region, source, roleArn, Maybe.default(&2, String, session, "aws-sdk-js-" ++ millis(now)), external, Maybe.default(&2, String, duration, "3600"))
        return serviceStop(result)

# The roles of a plan, innermost first, each assumed with the credentials of
# the previous step.
def applyRoles(~Reason: Data, +chain: Chain<Reason>, +files: Files, +region: Maybe<&2, String>, roles: List<&2, RoleStep>, step: Step) -> IO(Step):
  match roles step:
    case Nil{} done: IO.pure(Step, done)
    case role <> rest Resolved{source}:
      do IO<Step>:
        next : Step <- assumed(~Reason, chain, files, region, role, source)
        applyRoles(~Reason, chain, files, region, rest, next)
    case _ other: IO.pure(Step, other)

def webToken(~Reason: Data, +chain: Chain<Reason>, files: Files, file: String, roleArn: String, session: Maybe<&2, String>, bytes: Result<&2, &2, FS.Error, List<&2, U32>>) -> IO(Step):
  match bytes:
    case Fail{_}: IO.pure(Step, Stop{"ENOENT: no such file or directory, open '" ++ file ++ "'"})
    case Done{content}:
      do IO<Step>:
        region : String <- stsRegion(~Reason, chain, files, None{})
        endpoint : String <- stsEndpointFor(region)
        now : F64 <- Date.now()
        result : Result<&2, &2, Services.ServiceError, SigV4.Credentials> <- Services.assumeRoleWithWebIdentity(~Reason, transportOf(~Reason, chain), endpoint, roleArn, Maybe.default(&2, String, session, "aws-sdk-js-session-" ++ millis(now)), fileText(Done{content}))
        return serviceStop(result)

# fromWebToken: the token file's contents, then AssumeRoleWithWebIdentity.
def webIdentity(~Reason: Data, chain: Chain<Reason>, files: Files, +file: String, roleArn: String, session: Maybe<&2, String>) -> IO(Step):
  do IO<Step>:
    bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(file)
    webToken(~Reason, chain, files, file, roleArn, session, bytes)

def tokenFileWith(~Reason: Data, chain: Chain<Reason>, files: Files, file: Maybe<&2, String>, role: Maybe<&2, String>, session: Maybe<&2, String>) -> IO(Step):
  match file role:
    case Some{path} Some{arn}: webIdentity(~Reason, chain, files, path, arn, session)
    case _ _: IO.pure(Step, Next{"Web identity configuration not specified"})

# fromTokenFile from the environment.
def fromTokenFile(~Reason: Data, chain: Chain<Reason>, files: Files) -> IO(Step):
  do IO<Step>:
    file : Maybe<&2, String> <- env("AWS_WEB_IDENTITY_TOKEN_FILE")
    role : Maybe<&2, String> <- env("AWS_ROLE_ARN")
    session : Maybe<&2, String> <- env("AWS_ROLE_SESSION_NAME")
    tokenFileWith(~Reason, chain, files, nonempty(file), nonempty(role), session)

# SSO (credential-provider-sso, token-providers fromSso)
# -----------------------------------------------------

def REFRESH() -> String: "To refresh this SSO session run aws sso login with the corresponding profile."

def TOKEN_REFRESH() -> String: "To refresh this SSO session run 'aws sso login' with the corresponding profile."

def cachePath(home: Maybe<&2, String>, +id: String) -> String: Maybe.default(&2, String, home, "") ++ "/.aws/sso/cache/" ++ Sha1.hex(Utf8.encode(id)) ++ ".json"

type SsoToken is Data:
  SsoToken{json: V.Value, accessToken: Maybe<&2, String>, expiresAt: Maybe<&2, String>}

def tokenJson(parsed: Result<&2, &2, Decode.ParseError, V.Value>) -> Maybe<&2, SsoToken>:
  match parsed:
    case Done{V.ObjectValue{+fields}}: Some{SsoToken{V.ObjectValue{fields}, textOf(R.get(V.Value, fields, "accessToken")), textOf(R.get(V.Value, fields, "expiresAt"))}}
    case _: None{}

def tokenFile(+text: String) -> Maybe<&2, SsoToken>: tokenJson(Decode.parse(text))

def tokenRead(bytes: Result<&2, &2, FS.Error, List<&2, U32>>) -> Maybe<&2, SsoToken>:
  match bytes:
    case Done{content}: tokenFile(fileText(Done{content}))
    case Fail{_}: None{}

def readToken(path: String) -> IO(Maybe<&2, SsoToken>):
  do IO<Maybe<&2, SsoToken>>:
    bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(path)
    return tokenRead(bytes)

def expiryParsed(value: Result<&2, &2, Date.ParseError, F64>) -> F64:
  match value:
    case Done{ms}: ms
    case Fail{_}: F.nan()

def expiryOf(value: Maybe<&2, String>) -> F64:
  match value:
    case Some{text}: expiryParsed(Date.parseIso(text))
    case None{}: F.nan()

def field(value: V.Value, name: String) -> Maybe<&2, V.Value>:
  match value:
    case V.ObjectValue{fields}: R.get(V.Value, fields, name)
    case _: None{}

def tokenMember(token: SsoToken, name: String) -> Maybe<&2, String>:
  match token:
    case SsoToken{json, _, _}: textOf(field(json, name))

def requiredToken(+name: String, value: Maybe<&2, String>, refresh: Bool) -> Maybe<&2, String>:
  match value:
    case Some{_}: None{}
    case None{}: Some{"Value not present for '" ++ name ++ "' in SSO Token" ++ Bool.pick(String, refresh, ". Cannot refresh", "") ++ ". " ++ TOKEN_REFRESH()}

def firstMissing(values: List<&2, Maybe<&2, String>>) -> Maybe<&2, String>:
  match values:
    case Nil{}: None{}
    case Some{message} <> _: Some{message}
    case None{} <> rest: firstMissing(rest)

def expiredToken(+expires: F64, now: F64) -> Bool: F.isGreater(F.compare(now, expires))

# The token when the refresh fails: valid unless already expired.
def existingToken(+token: String, +expires: F64, now: F64) -> Result<&2, &2, String, String>:
  Bool.pick(Result<&2, &2, String, String>, expiredToken(expires, now), Fail{"Token is expired. " ++ TOKEN_REFRESH()}, Done{token})

def isoAt(+ms: F64) -> String: Maybe.default(&2, String, Date.formatIso(ms), "")

def refreshedJson(json: V.Value, +access: String, +expiresAt: String, +refresh: Maybe<&2, String>) -> V.Value:
  match json:
    case V.ObjectValue{fields}:
      +a = R.set(V.Value, fields, "accessToken", V.Text{access})
      +b = R.set(V.Value, a, "expiresAt", V.Text{expiresAt})
      V.ObjectValue{Bool.pick(R.Record<V.Value>, Maybe.is_some(&2, String, refresh), R.set(V.Value, b, "refreshToken", V.Text{Maybe.default(&2, String, refresh, "")}), R.remove(V.Value, b, "refreshToken"))}
    case other: other

def written(path: String, json: V.Value) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, FS.Error, Unit> <- FS.writeFile(path, Maybe.default(&2, String, JsonWire.stringifyPretty(SchemaJson.toJson(json)), "{}"))
    return Unit{}

def refreshedToken(path: String, token: SsoToken, created: Result<&2, &2, Services.ServiceError, Services.OidcToken>, now: F64) -> IO(Result<&2, &2, String, String>):
  match created token:
    case Done{Services.OidcToken{Some{+access}, Some{seconds}, refresh}} SsoToken{json, _, _}:
      +expires = F.add(now, F.multiply(seconds, F.fromU32(1000)))
      do IO<Result<&2, &2, String, String>>:
        written(path, refreshedJson(json, access, isoAt(expires), refresh))
        return Done{access}
    case Done{Services.OidcToken{None{}, _, _}} _: IO.pure(Result<&2, &2, String, String>, Fail{"Value not present for 'accessToken' in SSO Token. " ++ TOKEN_REFRESH()})
    case Done{Services.OidcToken{_, None{}, _}} _: IO.pure(Result<&2, &2, String, String>, Fail{"Value not present for 'expiresIn' in SSO Token. " ++ TOKEN_REFRESH()})
    case Fail{_} SsoToken{_, +access, expiresAt}: IO.pure(Result<&2, &2, String, String>, existingToken(Maybe.default(&2, String, access, ""), expiryOf(expiresAt), now))

def refreshWith(~Reason: Data, chain: Chain<Reason>, path: String, region: String, token: SsoToken, now: F64, client: Maybe<&2, String>, secret: Maybe<&2, String>, refresh: Maybe<&2, String>, missing: Maybe<&2, String>) -> IO(Result<&2, &2, String, String>):
  match missing:
    case Some{message}: IO.pure(Result<&2, &2, String, String>, Fail{message})
    case None{}:
      do IO<Result<&2, &2, String, String>>:
        service : Maybe<&2, String> <- env("AWS_ENDPOINT_URL_SSO_OIDC")
        created : Result<&2, &2, Services.ServiceError, Services.OidcToken> <- Services.createToken(~Reason, transportOf(~Reason, chain), Services.oidcEndpoint(nonempty(service), region), Maybe.default(&2, String, client, ""), Maybe.default(&2, String, secret, ""), Maybe.default(&2, String, refresh, ""))
        refreshedToken(path, token, created, now)

def refreshSession(~Reason: Data, chain: Chain<Reason>, path: String, region: String, +token: SsoToken, now: F64) -> IO(Result<&2, &2, String, String>):
  +client = tokenMember(token, "clientId")
  +secret = tokenMember(token, "clientSecret")
  +refresh = tokenMember(token, "refreshToken")
  refreshWith(~Reason, chain, path, region, token, now, client, secret, refresh, firstMissing([requiredToken("clientId", client, True{}), requiredToken("clientSecret", secret, True{}), requiredToken("refreshToken", refresh, True{})]))

# fromSso: the cached token, refreshed through SSO-OIDC within five minutes
# of its expiry.
def sessionToken(~Reason: Data, chain: Chain<Reason>, path: String, region: String, token: SsoToken) -> IO(Result<&2, &2, String, String>):
  match token:
    case SsoToken{json, +access, +expiresAt}:
      +missing = firstMissing([requiredToken("accessToken", access, False{}), requiredToken("expiresAt", expiresAt, False{})])
      do IO<Result<&2, &2, String, String>>:
        +now : F64 <- Date.now()
        +expires : F64 <- IO.pure(F64, expiryOf(expiresAt))
        Bool.pick(Unit -> IO(Result<&2, &2, String, String>), Maybe.is_some(&2, String, missing), _ => IO.pure(Result<&2, &2, String, String>, Fail{Maybe.default(&2, String, missing, "")}), _ =>
          Bool.pick(Unit -> IO(Result<&2, &2, String, String>), F.isGreater(F.compare(F.subtract(expires, now), F.fromU32(300000))), _ => IO.pure(Result<&2, &2, String, String>, Done{Maybe.default(&2, String, access, "")}), _ =>
            refreshSession(~Reason, chain, path, region, SsoToken{json, access, expiresAt}, now))(Unit{}))(Unit{})

def ssoStep(result: Result<&2, &2, Services.ServiceError, SigV4.Credentials>) -> Step:
  match result:
    case Done{credentials}: Resolved{credentials}
    case Fail{Services.ServiceError{"CredentialsProviderError", message}}: Stop{message}
    case Fail{Services.ServiceError{name, message}}: Stop{name ++ ": " ++ message}

def ssoCredentials(~Reason: Data, chain: Chain<Reason>, region: String, account: String, role: String, token: Result<&2, &2, String, String>) -> IO(Step):
  match token:
    case Fail{message}: IO.pure(Step, Stop{message})
    case Done{access}:
      do IO<Step>:
        service : Maybe<&2, String> <- env("AWS_ENDPOINT_URL_SSO")
        result : Result<&2, &2, Services.ServiceError, SigV4.Credentials> <- Services.getRoleCredentials(~Reason, transportOf(~Reason, chain), Services.ssoEndpoint(nonempty(service), region), account, role, access)
        return ssoStep(result)

def legacyToken(token: Maybe<&2, SsoToken>) -> IO(Result<&2, &2, String, String>):
  match token:
    case None{}: IO.pure(Result<&2, &2, String, String>, Fail{"The SSO session associated with this profile is invalid. " ++ REFRESH()})
    case Some{SsoToken{_, access, expiresAt}}:
      do IO<Result<&2, &2, String, String>>:
        now : F64 <- Date.now()
        return Bool.pick(Result<&2, &2, String, String>, Bool.not(F.isGreater(F.compare(F.subtract(expiryOf(expiresAt), now), F.fromU32(0)))), Fail{"The SSO session associated with this profile has expired. " ++ REFRESH()}, Done{Maybe.default(&2, String, access, "")})

# resolveSSOCredentials' own expiry check after fromSso.
def expiredAfterRefresh(result: Result<&2, &2, String, String>) -> Result<&2, &2, String, String>: result

def sessionTokenFor(~Reason: Data, chain: Chain<Reason>, path: String, region: String, profile: String, token: Maybe<&2, SsoToken>) -> IO(Result<&2, &2, String, String>):
  match token:
    case None{}: IO.pure(Result<&2, &2, String, String>, Fail{"The SSO session token associated with profile=" ++ profile ++ " was not found or is invalid. " ++ TOKEN_REFRESH()})
    case Some{value}:
      do IO<Result<&2, &2, String, String>>:
        result : Result<&2, &2, String, String> <- sessionToken(~Reason, chain, path, region, value)
        return expiredAfterRefresh(result)

def sessionValues(files: Files, +name: String) -> R.Record<String>:
  match files:
    case Files{config, _}: sectionValues(config, "sso-session " ++ name)

def sectionExists(sections: List<&2, Section>, +name: String) -> Bool:
  match sections:
    case Nil{}: False{}
    case Section{section, _} <> rest: String.eq(section, name) || sectionExists(rest, name)

def sessionExists(files: Files, +name: String) -> Bool:
  match files:
    case Files{config, _}: sectionExists(config, "sso-session " ++ name)

def withSession(+values: R.Record<String>, +session: R.Record<String>) -> R.Record<String>:
  +a = Maybe.default(&2, R.Record<String>, Maybe.map(&2, String, R.Record<String>, region => R.set(String, values, "sso_region", region), get(session, "sso_region")), values)
  Maybe.default(&2, R.Record<String>, Maybe.map(&2, String, R.Record<String>, url => R.set(String, a, "sso_start_url", url), get(session, "sso_start_url")), a)

def invalidSso(values: R.Record<String>) -> String:
  "Profile is configured with invalid SSO credentials. Required parameters \"sso_account_id\", \"sso_region\", \"sso_role_name\", \"sso_start_url\". Got " ++ String.join(keys(values), ", ") ++ "\nReference: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html"

def expiryPassed(cached: Maybe<&2, SsoToken>, now: F64) -> Bool:
  match cached:
    case Some{SsoToken{_, _, expiresAt}}: Bool.not(F.isGreater(F.compare(F.subtract(expiryOf(expiresAt), now), F.fromU32(0))))
    case None{}: False{}

# After fromSso, resolveSSOCredentials checks the token's expiry again.
def checkExpiry(access: Result<&2, &2, String, String>, session: Maybe<&2, String>, path: String) -> IO(Result<&2, &2, String, String>):
  match access session:
    case Done{token} Some{_}:
      do IO<Result<&2, &2, String, String>>:
        cached : Maybe<&2, SsoToken> <- readToken(path)
        now : F64 <- Date.now()
        return Bool.pick(Result<&2, &2, String, String>, expiryPassed(cached, now), Fail{"The SSO session associated with this profile has expired. " ++ REFRESH()}, Done{token})
    case other _: IO.pure(Result<&2, &2, String, String>, other)

def ssoWith(~Reason: Data, +chain: Chain<Reason>, files: Files, profile: String, values: R.Record<String>, url: Maybe<&2, String>, account: Maybe<&2, String>, +region: Maybe<&2, String>, role: Maybe<&2, String>) -> IO(Step):
  match url account region role:
    case Some{url} Some{account} Some{region} Some{role}:
      do IO<Step>:
        home : Maybe<&2, String> <- env("HOME")
        +session : Maybe<&2, String> <- IO.pure(Maybe<&2, String>, get(values, "sso_session"))
        +path : String <- IO.pure(String, cachePath(home, Maybe.default(&2, String, session, url)))
        +cached : Maybe<&2, SsoToken> <- readToken(path)
        access : Result<&2, &2, String, String> <- Bool.pick(Unit -> IO(Result<&2, &2, String, String>), Maybe.is_some(&2, String, session), _ => sessionTokenFor(~Reason, chain, path, region, profile, cached), _ => legacyToken(cached))(Unit{})
        checked : Result<&2, &2, String, String> <- checkExpiry(access, session, path)
        ssoCredentials(~Reason, chain, region, account, role, checked)
    case _ _ _ _: IO.pure(Step, Stop{invalidSso(values)})

def ssoValidated(~Reason: Data, chain: Chain<Reason>, files: Files, profile: String, +values: R.Record<String>) -> IO(Step): ssoWith(~Reason, chain, files, profile, values, nonempty(get(values, "sso_start_url")), nonempty(get(values, "sso_account_id")), nonempty(get(values, "sso_region")), nonempty(get(values, "sso_role_name")))

def ssoSession(~Reason: Data, chain: Chain<Reason>, +files: Files, profile: String, values: R.Record<String>, session: Maybe<&2, String>) -> IO(Step):
  match session:
    case Some{+name}:
      Bool.pick(Unit -> IO(Step), sessionExists(files, name), _ => ssoValidated(~Reason, chain, files, profile, withSession(values, sessionValues(files, name))), _ => IO.pure(Step, Stop{"Sso session '" ++ name ++ "' could not be found in shared credentials file."}))(Unit{})
    case None{}: ssoValidated(~Reason, chain, files, profile, values)

# fromSSO for an SSO profile: an sso-session supplies the region and start
# URL.
def fromSso(~Reason: Data, chain: Chain<Reason>, files: Files, profile: String, +values: R.Record<String>) -> IO(Step): ssoSession(~Reason, chain, files, profile, values, get(values, "sso_session"))

# Plans
# -----

def credentialSource(~Reason: Data, chain: Chain<Reason>, files: Files, profile: String, +source: String) -> IO(Step):
  match source:
    case "Environment": fromEnv()
    case "EcsContainer": containerChain(~Reason, transportOf(~Reason, chain))
    case "Ec2InstanceMetadata": fromInstanceMetadata(~Reason, transportOf(~Reason, chain), profileValues(files, profile))
    case other: IO.pure(Step, Next{"Unsupported credential source in profile " ++ profile ++ ". Got " ++ other ++ ", expected EcsContainer or Ec2InstanceMetadata or Environment."})

def processLink(+profile: String, command: Maybe<&2, String>) -> IO(Step):
  match command:
    case Some{command}:
      do IO<Step>:
        result : Result<&2, &2, String, SigV4.Credentials> <- processCredentials(profile, command)
        return stepOf(result)
    case None{}: IO.pure(Step, Next{"Profile " ++ profile ++ " did not contain credential_process."})

# fromProcess: the profile's credential_process, if it has one.
def fromProcess(files: Files, +profile: String) -> IO(Step): processLink(profile, get(profileValues(files, profile), "credential_process"))

def processStep(result: Result<&2, &2, String, SigV4.Credentials>) -> Step: stepOf(result)

def baseStep(~Reason: Data, chain: Chain<Reason>, files: Files, base: Base) -> IO(Step):
  match base:
    case StaticBase{credentials}: IO.pure(Step, Resolved{credentials})
    case SourceBase{profile, source}: credentialSource(~Reason, chain, files, profile, source)
    case WebIdentityBase{file, roleArn, session}: webIdentity(~Reason, chain, files, file, roleArn, session)
    case ProcessBase{profile, command}:
      do IO<Step>:
        result : Result<&2, &2, String, SigV4.Credentials> <- processCredentials(profile, command)
        return processStep(result)
    case SsoBase{profile, values}: fromSso(~Reason, chain, files, profile, values)
    case FailedBase{step}: IO.pure(Step, step)

# A role that needs an MFA code fails first, the outermost such role before
# anything else is resolved.
def mfaRequired(roles: List<&2, RoleStep>, found: Maybe<&2, String>) -> Maybe<&2, String>:
  match roles:
    case Nil{}: found
    case RoleStep{profile, _, _, _, _, Some{_}} <> rest: mfaRequired(rest, Some{profile})
    case _ <> rest: mfaRequired(rest, found)

def planned(~Reason: Data, +chain: Chain<Reason>, +files: Files, base: Base, roles: List<&2, RoleStep>, region: Maybe<&2, String>, mfa: Maybe<&2, String>) -> IO(Step):
  match mfa:
    case Some{name}: IO.pure(Step, Stop{"Profile " ++ name ++ " requires multi-factor authentication, but no MFA code callback was provided."})
    case None{}:
      do IO<Step>:
        first : Step <- baseStep(~Reason, chain, files, base)
        applyRoles(~Reason, chain, files, region, roles, first)

def runPlan(~Reason: Data, chain: Chain<Reason>, files: Files, plan: Plan) -> IO(Step):
  match plan:
    case Plan{base, +roles, region}: planned(~Reason, chain, files, base, roles, region, mfaRequired(roles, None{}))

def fromIni(~Reason: Data, chain: Chain<Reason>, +files: Files, +profile: String) -> IO(Step): runPlan(~Reason, chain, files, planFor(files, profile))

# The chain
# ---------

type Link is Data:
  EnvLink{}
  IniLink{}
  ProcessLink{}
  TokenFileLink{}
  RemoteLink{}

def link(~Reason: Data, chain: Chain<Reason>, files: Files, +profile: String, explicit: Bool, current: Link) -> IO(Step):
  match current:
    case EnvLink{}: Bool.pick(Unit -> IO(Step), explicit, _ => IO.pure(Step, Next{"AWS_PROFILE is set, skipping fromEnv provider."}), _ => fromEnv())(Unit{})
    case IniLink{}: fromIni(~Reason, chain, files, profile)
    case ProcessLink{}: fromProcess(files, profile)
    case TokenFileLink{}: fromTokenFile(~Reason, chain, files)
    case RemoteLink{}: remoteProvider(~Reason, transportOf(~Reason, chain), profileValues(files, profile))

def links() -> List<&2, Link>: [EnvLink{}, IniLink{}, ProcessLink{}, TokenFileLink{}, RemoteLink{}]

# The links in order until one resolves or stops the chain.
def run(~Reason: Data, +chain: Chain<Reason>, +files: Files, +profile: String, +explicit: Bool, remaining: List<&2, Link>, previous: Step) -> IO(Result<&2, &2, String, SigV4.Credentials>):
  match remaining previous:
    case _ Resolved{credentials}: IO.pure(Result<&2, &2, String, SigV4.Credentials>, Done{credentials})
    case _ Stop{message}: IO.pure(Result<&2, &2, String, SigV4.Credentials>, Fail{message})
    case Nil{} Next{_}: IO.pure(Result<&2, &2, String, SigV4.Credentials>, Fail{"Could not load credentials from any providers"})
    case current <> rest Next{_}:
      do IO<Result<&2, &2, String, SigV4.Credentials>>:
        step : Step <- link(~Reason, chain, files, profile, explicit, current)
        run(~Reason, chain, files, profile, explicit, rest, step)

def explicitProfile(explicit: Maybe<&2, String>) -> IO(Bool):
  match explicit:
    case Some{SCon{_, _}}: IO.pure(Bool, True{})
    case _:
      do IO<Bool>:
        ambient : Maybe<&2, String> <- env("AWS_PROFILE")
        return truthy(ambient)

# The SDK's default credential chain (credential-provider-node
# defaultProvider) as the Bedrock client uses it: environment keys unless a
# profile is selected, the shared-file profile (static keys, role
# assumption through source_profile or credential_source, web identity,
# credential_process, SSO), the profile's credential_process again
# (fromProcess), web identity from the environment, then container or
# instance metadata. fromSSO, which the Bedrock client configures without SSO
# options, always passes on.
def resolveCredentials(~Reason: Data, chain: Chain<Reason>) -> IO(Result<&2, &2, String, SigV4.Credentials>):
  match chain:
    case Chain{transport, region, +profile}:
      do IO<Result<&2, &2, String, SigV4.Credentials>>:
        +name : String <- profileName(profile)
        explicit : Bool <- explicitProfile(profile)
        files : Files <- loadFiles()
        run(~Reason, Chain{transport, region, profile}, files, name, explicit, links(), Next{""})

# The SDK's region chain: AWS_REGION, then the profile's region.
def resolveRegion(profile: Maybe<&2, String>) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    region : Maybe<&2, String> <- Env.getProviderEnvValue("AWS_REGION", None{})
    +name : String <- profileName(profile)
    files : Files <- loadFiles()
    return Maybe.or(&2, String, region, nonempty(R.get(String, profileValues(files, name), "region")))
