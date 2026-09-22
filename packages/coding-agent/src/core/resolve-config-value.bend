import Base
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/ref.bend as Ref
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/utf8.bend as Utf8
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/f64.bend as F
import ../../../ai/src/types.bend as Ai
import ../utils/child-process.bend as Child

# Configuration values that may be shell commands, environment variables or
# literals. Used by auth storage and the model registry.

type TemplatePart is Data:
  Literal{value: String}
  EnvReference{name: String}

type ConfigValueReference is Data:
  Command{config: String}
  Template{parts: List<&2, TemplatePart>}

# Template syntax
# ---------------

def nameStart(+c: Char) -> Bool: Char.is_alpha(c) || Char.is_eq(c, '_')
def nameChar(+c: Char) -> Bool: nameStart(c) || Char.is_digit(c)

def allNameChars(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{c, rest}: nameChar(c) && allNameChars(rest)

def validName(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{first, rest}: nameStart(first) && allNameChars(rest)

# Name scanning carries its decision as data so the loop stays structurally
# recursive on fuel; definitions cannot refer forward in Bend.
type Split is Data:
  Split{name: String, rest: String}

type Scan is Data:
  Scanning{text: String, reversed: String}
  Scanned{value: Split}

def nameStep(+c: Char, +rest: String, +reversed: String) -> Scan:
  Bool.pick(Scan, nameChar(c), Scanning{rest, SCon{c, reversed}}, Scanned{Split{String.reverse(reversed), SCon{c, rest}}})

def scanLoop(fuel: Nat, state: Scan) -> Split:
  match fuel state:
    case _ Scanned{value}: value
    case _ Scanning{SNil{}, reversed}: Split{String.reverse(reversed), ""}
    case 0n Scanning{text, reversed}: Split{String.reverse(reversed), text}
    case 1n+n Scanning{SCon{c, rest}, reversed}: scanLoop(n, nameStep(c, rest, reversed))

# Longest `[A-Za-z_][A-Za-z0-9_]*` prefix and the remaining text.
def scanName(+text: String) -> Split:
  scanLoop(1n + String.length(text), Scanning{text, ""})

# Text up to the first `}` and the text after it; None without a closing brace.
def scanBraced(text: String, reversed: String) -> Maybe<&2, Split>:
  match text:
    case SNil{}: None{}
    case SCon{'}', rest}: Some{Split{String.reverse(reversed), rest}}
    case SCon{c, rest}: scanBraced(rest, SCon{c, reversed})

# Literal text accumulates reversed and is flushed as one part, so adjacent
# literal characters never produce separate parts.
def flush(literal: String, parts: List<&2, TemplatePart>) -> List<&2, TemplatePart>:
  match literal:
    case SNil{}: parts
    case value: Literal{String.reverse(value)} <> parts

def prependReversed(text: String, literal: String) -> String:
  match text:
    case SNil{}: literal
    case SCon{c, rest}: prependReversed(rest, SCon{c, literal})

type Step is Data:
  Step{text: String, literal: String, parts: List<&2, TemplatePart>}

def bracedName(valid: Bool, name: String, after: String, literal: String, parts: List<&2, TemplatePart>) -> Step:
  match valid:
    case True{}: Step{after, "", EnvReference{name} <> flush(literal, parts)}
    case False{}: Step{after, prependReversed("${" ++ name ++ "}", literal), parts}

# Without a closing brace the `$` is literal and scanning resumes at `{`.
def bracedStep(found: Maybe<&2, Split>, afterBrace: String, literal: String, parts: List<&2, TemplatePart>) -> Step:
  match found:
    case None{}: Step{SCon{'{', afterBrace}, SCon{'$', literal}, parts}
    case Some{Split{+name, after}}: bracedName(validName(name), name, after, literal, parts)

def bareStep(scanned: Split, literal: String, parts: List<&2, TemplatePart>) -> Step:
  match scanned:
    case Split{"", rest}: Step{rest, SCon{'$', literal}, parts}
    case Split{name, rest}: Step{rest, "", EnvReference{name} <> flush(literal, parts)}

# `$$` and `$!` escape a literal `$` and `!`; `${NAME}` and `$NAME` reference
# environment variables; anything else is literal text.
def dollarStep(text: String, literal: String, parts: List<&2, TemplatePart>) -> Step:
  match text:
    case SCon{'$', rest}: Step{rest, SCon{'$', literal}, parts}
    case SCon{'!', rest}: Step{rest, SCon{'!', literal}, parts}
    case SCon{'{', +rest}: bracedStep(scanBraced(rest, ""), rest, literal, parts)
    case other: bareStep(scanName(other), literal, parts)

def parseTemplate(fuel: Nat, step: Step) -> List<&2, TemplatePart>:
  match fuel step:
    case _ Step{SNil{}, literal, parts}: List.reverse(&2, TemplatePart, flush(literal, parts))
    case 0n Step{text, literal, parts}: List.reverse(&2, TemplatePart, flush(prependReversed(text, literal), parts))
    case 1n+n Step{SCon{'$', rest}, literal, parts}: parseTemplate(n, dollarStep(rest, literal, parts))
    case 1n+n Step{SCon{c, rest}, literal, parts}: parseTemplate(n, Step{rest, SCon{c, literal}, parts})

def template(+text: String) -> ConfigValueReference:
  Template{parseTemplate(1n + String.length(text), Step{text, "", Nil{}})}

def parseConfigValueReference(config: String) -> ConfigValueReference:
  match config:
    case SCon{'!', rest}: Command{SCon{'!', rest}}
    case value: template(value)

def isCommand(reference: ConfigValueReference) -> Bool:
  match reference:
    case Command{_}: True{}
    case Template{_}: False{}

def isCommandConfigValue(config: String) -> Bool: isCommand(parseConfigValueReference(config))

def containsName(names: List<&2, String>, +name: String) -> Bool:
  match names:
    case Nil{}: False{}
    case +first <> rest: String.eq(first, name) || containsName(rest, name)

def referencedNames(parts: List<&2, TemplatePart>, +seen: List<&2, String>) -> List<&2, String>:
  match parts:
    case Nil{}: List.reverse(&2, String, seen)
    case Literal{_} <> rest: referencedNames(rest, seen)
    case EnvReference{+name} <> rest: referencedNames(rest, Bool.pick(List<&2, String>, containsName(seen, name), seen, name <> seen))

def templateNames(reference: ConfigValueReference) -> List<&2, String>:
  match reference:
    case Command{_}: Nil{}
    case Template{parts}: referencedNames(parts, Nil{})

def getConfigValueEnvVarNames(config: String) -> List<&2, String>:
  templateNames(parseConfigValueReference(config))

# The single variable a value consists of, if it is exactly one reference.
def singleName(reference: ConfigValueReference) -> Maybe<&2, String>:
  match reference:
    case Template{EnvReference{name} <> Nil{}}: Some{name}
    case _: None{}

def getConfigValueEnvVarName(config: String) -> Maybe<&2, String>: singleName(parseConfigValueReference(config))

# Environment
# -----------

def Scope() -> Data: Maybe<&2, Ai.ProviderEnv()>

def nonempty(value: Maybe<&2, String>) -> Maybe<&2, String>:
  match value:
    case Some{SNil{}}: None{}
    case other: other

def scoped(name: String, env: Scope()) -> Maybe<&2, String>:
  match env:
    case None{}: None{}
    case Some{fields}: nonempty(R.get(String, fields, name))

def processValue(value: Result<&1, &1, U32 & String, String>) -> Maybe<&2, String>:
  match value:
    case Done{text}: nonempty(Some{text})
    case Fail{_}: None{}

# Credential-scoped values win; empty values fall through to the process.
def unscoped(name: String, value: Maybe<&2, String>) -> IO(Maybe<&2, String>):
  match value:
    case Some{value}: IO.pure(Maybe<&2, String>, Some{value})
    case None{}:
      do IO<Maybe<&2, String>>:
        value : Result<&1, &1, U32 & String, String> <- IO.get_env(name)
        return processValue(value)

def resolveEnvConfigValue(+name: String, env: Scope()) -> IO(Maybe<&2, String>):
  unscoped(name, scoped(name, env))

def missingNames(names: List<&2, String>, +env: Scope(), +missing: List<&2, String>) -> IO(List<&2, String>):
  match names:
    case Nil{}: IO.pure(List<&2, String>, List.reverse(&2, String, missing))
    case +name <> rest:
      do IO<List<&2, String>>:
        value : Maybe<&2, String> <- resolveEnvConfigValue(name, env)
        missingNames(rest, env, Bool.pick(List<&2, String>, Maybe.is_none(&2, String, value), name <> missing, missing))

def getMissingConfigValueEnvVarNames(config: String, env: Scope()) -> IO(List<&2, String>):
  missingNames(getConfigValueEnvVarNames(config), env, Nil{})

def isConfigValueConfigured(config: String, env: Scope()) -> IO(Bool):
  do IO<Bool>:
    missing : List<&2, String> <- getMissingConfigValueEnvVarNames(config, env)
    return List.is_empty(&2, String, missing)

# One unresolvable reference makes the whole value unresolved.
def appended(value: Maybe<&2, String>, fragments: List<&2, String>) -> Maybe<&2, List<&2, String>>:
  match value:
    case None{}: None{}
    case Some{text}: Some{text <> fragments}

def resolveParts(parts: List<&2, TemplatePart>, +env: Scope(), fragments: Maybe<&2, List<&2, String>>) -> IO(Maybe<&2, String>):
  match parts fragments:
    case _ None{}: IO.pure(Maybe<&2, String>, None{})
    case Nil{} Some{reversed}: IO.pure(Maybe<&2, String>, Some{String.join(List.reverse(&2, String, reversed), "")})
    case Literal{value} <> rest Some{reversed}: resolveParts(rest, env, Some{value <> reversed})
    case EnvReference{name} <> rest Some{reversed}:
      do IO<Maybe<&2, String>>:
        value : Maybe<&2, String> <- resolveEnvConfigValue(name, env)
        resolveParts(rest, env, appended(value, reversed))

# Commands
# --------

# Command output is captured through the shared child-process runner with
# upstream's ten-second limit; stderr is discarded and stdin is closed.
def collect(sink: Ref.Ref<List<&2, U32>>, bytes: List<&2, U32>) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    Ref.modify(List<&2, U32>, Unit, sink, previous => (List.append(&2, U32, previous, bytes), Unit{}))
    return Done{Unit{}}

def trimmedOutput(status: Result<&2, &2, Child.ExecutionError, U32>, bytes: List<&2, U32>) -> Maybe<&2, String>:
  match status:
    case Done{0}: nonempty(Some{String.trim(Utf8.decodeBytes(bytes))})
    case _: None{}

def runCommand(command: String, cwd: String) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    +sink : Ref.Ref<List<&2, U32>> <- Ref.new(List<&2, U32>, Nil{})
    +onData : C.Callback<List<&2, U32>, Result<&2, &2, String, Unit>> <- C.create(~Ref.Ref<List<&2, U32>>, ~List<&2, U32>, ~Result<&2, &2, String, Unit>, ~collect, sink)
    entries : List<String> <- IO.environment()
    status : Result<&2, &2, Child.ExecutionError, U32> <- Child.execute("/bin/sh", ["-c"], command, cwd, entries, None{}, Some{F.fromU32(10)}, onData)
    C.dispose(List<&2, U32>, Result<&2, &2, String, Unit>, onData)
    bytes : List<&2, U32> <- Ref.dispose(List<&2, U32>, sink)
    return trimmedOutput(status, bytes)

def located(cwd: Result<&2, &2, FS.Error, String>) -> String:
  match cwd:
    case Done{value}: value
    case Fail{_}: "/"

# Runs the text after `!` through the default shell, as execSync does.
def executeCommandUncached(commandConfig: String) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    cwd : Result<&2, &2, FS.Error, String> <- FS.cwd()
    runCommand(String.drop(commandConfig, 1n), located(cwd))

# Successful and failed command results are cached for the resolver's
# lifetime; environment references are never cached.
type Resolver is Data:
  Resolver{cache: Ref.Ref<R.Record<Maybe<&2, String>>>}

def newResolver() -> IO(Resolver):
  do IO<Resolver>:
    cache : Ref.Ref<R.Record<Maybe<&2, String>>> <- Ref.new(R.Record<Maybe<&2, String>>, R.new(Maybe<&2, String>))
    return Resolver{cache}

def clearConfigValueCache(resolver: Resolver) -> IO(Unit):
  match resolver:
    case Resolver{cache}: Ref.write(R.Record<Maybe<&2, String>>, cache, R.new(Maybe<&2, String>))

def disposeResolver(resolver: Resolver) -> IO(Unit):
  match resolver:
    case Resolver{cache}:
      do IO<Unit>:
        entries : R.Record<Maybe<&2, String>> <- Ref.dispose(R.Record<Maybe<&2, String>>, cache)
        return Unit{}

def remembered(cache: Ref.Ref<R.Record<Maybe<&2, String>>>, +commandConfig: String, cached: Maybe<&2, Maybe<&2, String>>) -> IO(Maybe<&2, String>):
  match cached:
    case Some{value}: IO.pure(Maybe<&2, String>, value)
    case None{}:
      do IO<Maybe<&2, String>>:
        +value : Maybe<&2, String> <- executeCommandUncached(commandConfig)
        Ref.modify(R.Record<Maybe<&2, String>>, Unit, cache, entries => (R.set(Maybe<&2, String>, entries, commandConfig, value), Unit{}))
        return value

def executeCommand(resolver: Resolver, +commandConfig: String) -> IO(Maybe<&2, String>):
  match resolver:
    case Resolver{+cache}:
      do IO<Maybe<&2, String>>:
        entries : R.Record<Maybe<&2, String>> <- Ref.read(R.Record<Maybe<&2, String>>, cache)
        remembered(cache, commandConfig, R.get(Maybe<&2, String>, entries, commandConfig))

# Resolution
# ----------

def resolveReference(resolver: Resolver, reference: ConfigValueReference, env: Scope()) -> IO(Maybe<&2, String>):
  match reference:
    case Command{config}: executeCommand(resolver, config)
    case Template{parts}: resolveParts(parts, env, Some{Nil{}})

# `!command` executes the rest through the shell and uses trimmed stdout;
# `$NAME`/`${NAME}` interpolate environment variables; `$$` and `$!` escape.
def resolveConfigValue(resolver: Resolver, config: String, env: Scope()) -> IO(Maybe<&2, String>):
  resolveReference(resolver, parseConfigValueReference(config), env)

def resolveUncached(reference: ConfigValueReference, env: Scope()) -> IO(Maybe<&2, String>):
  match reference:
    case Command{value}: executeCommandUncached(value)
    case Template{parts}: resolveParts(parts, env, Some{Nil{}})

def resolveConfigValueUncached(config: String, env: Scope()) -> IO(Maybe<&2, String>):
  resolveUncached(parseConfigValueReference(config), env)
