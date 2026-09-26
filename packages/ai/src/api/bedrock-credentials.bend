import Base
import ../utils/provider-env.bend as Env
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

# The parts of the AWS SDK's default credential and region chains the
# Bedrock client relies on when pi passes no static credentials: shared
# config and credentials files (named profiles with static keys or a
# credential_process) and the region of the selected profile. SSO, role
# assumption, web identity and instance metadata are not provided here; a
# profile that needs them reports that.

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

def processFields(+profile: String, +fields: R.Record<V.Value>) -> Result<&2, &2, String, SigV4.Credentials>:
  Bool.pick(Result<&2, &2, String, SigV4.Credentials>, versionOne(R.get(V.Value, fields, "Version")), processKeys(profile, textMember(fields, "AccessKeyId"), textMember(fields, "SecretAccessKey"), textMember(fields, "SessionToken")), Fail{"Profile " ++ profile ++ " credential_process did not return Version 1."})

def processJson(+profile: String, result: Result<&2, &2, Decode.ParseError, V.Value>) -> Result<&2, &2, String, SigV4.Credentials>:
  match result:
    case Done{V.ObjectValue{fields}}: processFields(profile, fields)
    case _: Fail{"Profile " ++ profile ++ " credential_process returned invalid JSON."}

def processOutput(+profile: String, status: Result<&2, &2, Process.ExecutionError, U32>, bytes: List<&2, U32>) -> Result<&2, &2, String, SigV4.Credentials>:
  match status:
    case Done{0}: processJson(profile, Decode.parse(decodedText(Utf8.decode(Utf8.create(), bytes))))
    case _: Fail{"Profile " ++ profile ++ " credential_process failed."}

# fromProcess: the credential_process command through the shell, its stdout
# the JSON credentials document (Version 1).
def processCredentials(+profile: String, command: String) -> IO(Result<&2, &2, String, SigV4.Credentials>):
  do IO<Result<&2, &2, String, SigV4.Credentials>>:
    +sink : Ref.Ref<List<&2, U32>> <- Ref.new(List<&2, U32>, Nil{})
    +onData : C.Callback<List<&2, U32>, Result<&2, &2, String, Unit>> <- C.create(~Ref.Ref<List<&2, U32>>, ~List<&2, U32>, ~Result<&2, &2, String, Unit>, ~collect, sink)
    entries : List<String> <- IO.environment()
    status : Result<&2, &2, Process.ExecutionError, U32> <- Process.executeSelected(Process.Stdout{}, "/bin/sh", ["-c"], command, "/", entries, None{}, None{}, onData)
    C.dispose(List<&2, U32>, Result<&2, &2, String, Unit>, onData)
    bytes : List<&2, U32> <- Ref.dispose(List<&2, U32>, sink)
    return processOutput(profile, status, bytes)

def unsupported(+profile: String, +values: R.Record<String>) -> String:
  Bool.pick(String, Maybe.is_some(&2, String, R.get(String, values, "role_arn")) || Maybe.is_some(&2, String, R.get(String, values, "sso_session")) || Maybe.is_some(&2, String, R.get(String, values, "sso_start_url")) || Maybe.is_some(&2, String, R.get(String, values, "web_identity_token_file")), "Profile " ++ profile ++ " requires role assumption, SSO or web identity credentials, which this port does not provide", "Could not load credentials from any providers")

def fromProcessCommand(+profile: String, values: R.Record<String>, command: Maybe<&2, String>) -> IO(Result<&2, &2, String, SigV4.Credentials>):
  match command:
    case Some{text}: processCredentials(profile, text)
    case None{}: IO.pure(Result<&2, &2, String, SigV4.Credentials>, Fail{unsupported(profile, values)})

def fromProfile(+profile: String, +values: R.Record<String>, stored: Maybe<&2, SigV4.Credentials>) -> IO(Result<&2, &2, String, SigV4.Credentials>):
  match stored:
    case Some{credentials}: IO.pure(Result<&2, &2, String, SigV4.Credentials>, Done{credentials})
    case None{}: fromProcessCommand(profile, values, nonempty(R.get(String, values, "credential_process")))

def profileName(explicit: Maybe<&2, String>) -> IO(String):
  match explicit:
    case Some{SCon{c, cs}}: IO.pure(String, SCon{c, cs})
    case _:
      do IO<String>:
        ambient : Maybe<&2, String> <- Env.getProviderEnvValue("AWS_PROFILE", None{})
        return Maybe.default(&2, String, ambient, "default")

def resolvedProfile(+profile: String, files: Files) -> IO(Result<&2, &2, String, SigV4.Credentials>):
  +values = profileValues(files, profile)
  fromProfile(profile, values, staticCredentials(values))

# The default chain after the environment: the shared files' profile.
def resolveCredentials(profile: Maybe<&2, String>) -> IO(Result<&2, &2, String, SigV4.Credentials>):
  do IO<Result<&2, &2, String, SigV4.Credentials>>:
    +name : String <- profileName(profile)
    files : Files <- loadFiles()
    resolvedProfile(name, files)

# The SDK's region chain: AWS_REGION, then the profile's region.
def resolveRegion(profile: Maybe<&2, String>) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    region : Maybe<&2, String> <- Env.getProviderEnvValue("AWS_REGION", None{})
    +name : String <- profileName(profile)
    files : Files <- loadFiles()
    return Maybe.or(&2, String, region, nonempty(R.get(String, profileValues(files, name), "region")))
