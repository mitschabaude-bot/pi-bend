import Base
import ./cli/args.bend as Args
import ./cli/file-processor.bend as Files
import ./config.bend as Config
import ./core/agent-runtime.bend as Runtime
import ./core/tools/index.bend as Tools
import ./modes/print-mode.bend as Print
import ./utils/paths.bend as Paths
import ../../ai/src/types.bend as Ai
import ../../runtime/src/filesystem.bend as FS
import ../../runtime/src/utf8.bend as Utf8
import ../../runtime/src/posix-path.bend as Path

# The pi entry point: argument parsing, mode selection, initial message
# assembly, runtime creation and exit behavior. Interactive and RPC modes,
# sessions, extensions and package commands are not ported yet.

type AppMode is Data:
  Interactive{}
  PrintText{}
  PrintJson{}
  Rpc{}

def resolveAppMode(mode: Maybe<&2, Args.Mode>, print: Bool, stdinTty: Bool, stdoutTty: Bool) -> AppMode:
  match mode:
    case Some{Args.Rpc{}}: Rpc{}
    case Some{Args.Json{}}: PrintJson{}
    case _: Bool.pick(AppMode, print || Bool.not(stdinTty) || Bool.not(stdoutTty), PrintText{}, Interactive{})

def reportDiagnostics(diagnostics: List<&2, Args.Diagnostic>) -> IO(Unit):
  match diagnostics:
    case Nil{}: IO.pure(Unit, Unit{})
    case Args.Error{message} <> rest:
      do IO<Unit>:
        IO.print_err("Error: " ++ message)
        reportDiagnostics(rest)
    case Args.Warning{message} <> rest:
      do IO<Unit>:
        IO.print_err("Warning: " ++ message)
        reportDiagnostics(rest)

def hasError(diagnostics: List<&2, Args.Diagnostic>) -> Bool:
  match diagnostics:
    case Nil{}: False{}
    case Args.Error{_} <> _: True{}
    case _ <> rest: hasError(rest)

def nonempty(text: String) -> Maybe<&2, String>:
  match text:
    case SNil{}: None{}
    case value: Some{value}

def trimmed(bytes: Result<&2, &2, FS.Error, List<&2, U32>>) -> Maybe<&2, String>:
  match bytes:
    case Fail{_}: None{}
    case Done{octets}: nonempty(String.trim(Utf8.decodeBytes(octets)))

# Piped stdin becomes prompt text; a terminal stdin is left alone.
def readPipedStdin(stdinTty: Bool) -> IO(Maybe<&2, String>):
  match stdinTty:
    case True{}: IO.pure(Maybe<&2, String>, None{})
    case False{}:
      do IO<Maybe<&2, String>>:
        bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile("/dev/stdin")
        return trimmed(bytes)

type InitialMessage is Data:
  InitialMessage{text: Maybe<&2, String>, images: List<&2, Ai.ImageContent>, remaining: List<&2, String>}

def joined(parts: List<&2, String>) -> Maybe<&2, String>:
  match parts:
    case Nil{}: None{}
    case values: Some{String.join(values, "")}

def optionalPart(value: Maybe<&2, String>, rest: List<&2, String>) -> List<&2, String>:
  match value:
    case None{}: rest
    case Some{text}: text <> rest

# stdin content, @file text and the first CLI message form the initial prompt.
def buildInitialMessage(stdin: Maybe<&2, String>, fileText: Maybe<&2, String>, images: List<&2, Ai.ImageContent>, messages: List<&2, String>) -> InitialMessage:
  match messages:
    case Nil{}: InitialMessage{joined(optionalPart(stdin, optionalPart(fileText, Nil{}))), images, Nil{}}
    case first <> rest: InitialMessage{joined(optionalPart(stdin, optionalPart(fileText, [first]))), images, rest}

def processedText(files: Files.ProcessedFiles) -> Maybe<&2, String>:
  match files:
    case Files.ProcessedFiles{text, _}: nonempty(text)

def processedImages(files: Files.ProcessedFiles) -> List<&2, Ai.ImageContent>:
  match files:
    case Files.ProcessedFiles{_, images}: images

def fileError(error: Files.Error) -> String:
  match error:
    case Files.InvalidPath{input, _}: "Invalid file path: " ++ input
    case Files.NotFound{path, _}: "File not found: " ++ path
    case Files.Stat{path, _}: "Could not stat " ++ path
    case Files.Read{path, _}: "Could not read " ++ path
    case Files.InvalidEncoding{path, _}: "File is not valid UTF-8: " ++ path

# Tools
# -----

def prependName(name: Maybe<&2, Tools.ToolName>, rest: List<&2, Tools.ToolName>) -> List<&2, Tools.ToolName>:
  match name:
    case None{}: rest
    case Some{name}: name <> rest

def parseNames(names: List<&2, String>) -> List<&2, Tools.ToolName>:
  match names:
    case Nil{}: Nil{}
    case name <> rest: prependName(Tools.parseToolName(name), parseNames(rest))

def sameName(+left: Tools.ToolName, +right: Tools.ToolName) -> Bool:
  String.eq(Tools.toolName(left), Tools.toolName(right))

def containsName(names: List<&2, Tools.ToolName>, +name: Tools.ToolName) -> Bool:
  match names:
    case Nil{}: False{}
    case +first <> rest: sameName(first, name) || containsName(rest, name)

def without(names: List<&2, Tools.ToolName>, +excluded: List<&2, Tools.ToolName>) -> List<&2, Tools.ToolName>:
  match names:
    case Nil{}: Nil{}
    case +name <> rest:
      +tail = without(rest, excluded)
      Bool.pick(List<&2, Tools.ToolName>, containsName(excluded, name), tail, name <> tail)

# --no-tools disables everything; --tools allowlists; --exclude-tools denylists.
def selectedTools(noTools: Maybe<&2, Bool>, allow: Maybe<&2, List<&2, String>>, exclude: Maybe<&2, List<&2, String>>) -> List<&2, Tools.ToolName>:
  match noTools allow exclude:
    case Some{True{}} _ _: Nil{}
    case _ Some{names} excluded: without(parseNames(names), parseNames(Maybe.default(&2, List<&2, String>, excluded, Nil{})))
    case _ None{} excluded: without(Tools.allToolNames(), parseNames(Maybe.default(&2, List<&2, String>, excluded, Nil{})))

# Paths
# -----

def envOr(value: Result<&1, &1, U32 & String, String>, fallback: String) -> String:
  match value:
    case Done{SCon{first, rest}}: SCon{first, rest}
    case _: fallback

def located(value: Result<&2, &2, FS.Error, String>, fallback: String) -> String:
  match value:
    case Done{path}: path
    case Fail{_}: fallback

# Exit
# ----

def exitWith(code: U32) -> IO(Unit):
  match code:
    case 0: IO.pure(Unit, Unit{})
    case failure: IO.die(Unit, failure, "")

def fail(message: String) -> IO(Unit):
  do IO<Unit>:
    IO.print_err(message)
    IO.die(Unit, 1, "")

# Runs
# ----

def printWith(cwd: String, options: Print.PrintModeOptions, pair: Runtime.AgentRuntime & Runtime.Owner()) -> IO(Unit):
  match pair:
    case Tuple{runtime, agent}:
      do IO<Unit>:
        code : U32 <- Print.runPrintMode(agent, cwd, options)
        Runtime.dispose(runtime)
        exitWith(code)

def outputMode(mode: AppMode) -> Args.Mode:
  match mode:
    case PrintJson{}: Args.Json{}
    case _: Args.Text{}

def printMode(mode: Args.Mode, initial: InitialMessage, cwd: String, created: Runtime.Outcome(Runtime.AgentRuntime)) -> IO(Unit):
  match initial created:
    case _ Fail{error}: fail(error)
    case InitialMessage{text, images, remaining} Done{runtime}: printWith(cwd, Print.PrintModeOptions{mode, remaining, text, images}, Runtime.agentOf(runtime))

def createOptions(parsed: Args.Args, cwd: String, agentDir: String, authPath: String, bundlePath: String, packageDir: String) -> Runtime.CreateOptions:
  match parsed:
    case Args.Args{provider, model, apiKey, systemPrompt, appendSystemPrompt, thinking, _, _, _, _, _, _, _, _, _, _, _, _, tools, excludeTools, noTools, _, _, _, _, _, _, _, _, _, _, _, _, noContextFiles, _, _, _, _, _, _, _, _, _}:
      Runtime.CreateOptions{cwd, agentDir, authPath, bundlePath, packageDir, provider, model, apiKey, thinking, systemPrompt, Maybe.default(&2, List<&2, String>, appendSystemPrompt, Nil{}), selectedTools(noTools, tools, excludeTools), Bool.not(Maybe.default(&2, Bool, noContextFiles, False{}))}

def runWithFiles(parsed: Args.Args, mode: AppMode, stdin: Maybe<&2, String>, messages: List<&2, String>, +cwd: String, files: Files.ResultOf(Files.ProcessedFiles)) -> IO(Unit):
  match files:
    case Fail{error}: fail(fileError(error))
    case Done{+processed}:
      do IO<Unit>:
        agentDir : Result<&2, &2, FS.Error, String> <- Config.getAgentDir()
        authPath : Result<&2, &2, FS.Error, String> <- Config.getAuthPath()
        bundle : Result<&1, &1, U32 & String, String> <- IO.get_env("SSL_CERT_FILE")
        packageDir : Result<&1, &1, U32 & String, String> <- IO.get_env("PI_BEND_PACKAGE_DIR")
        created : Runtime.Outcome(Runtime.AgentRuntime) <- Runtime.create(createOptions(parsed, cwd, located(agentDir, Path.join(cwd, ".pi")), located(authPath, Path.join(cwd, "auth.json")), envOr(bundle, "/etc/ssl/certs/ca-certificates.crt"), envOr(packageDir, cwd)))
        printMode(outputMode(mode), buildInitialMessage(stdin, processedText(processed), processedImages(processed), messages), cwd, created)

def runPrint(+parsed: Args.Args, mode: AppMode, stdinTty: Bool, environment: Result<&2, &2, FS.Error, Paths.Environment>) -> IO(Unit):
  match parsed environment:
    case _ Fail{_}: fail("Could not resolve the working directory")
    case Args.Args{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, messages, fileArgs, _, _} Done{Paths.Environment{+cwd, home, url}}:
      do IO<Unit>:
        stdin : Maybe<&2, String> <- readPipedStdin(stdinTty)
        files : Files.ResultOf(Files.ProcessedFiles) <- Files.processFileArguments(Paths.Environment{cwd, home, url}, fileArgs, Files.defaults())
        runWithFiles(parsed, mode, stdin, messages, cwd, files)

def runMode(parsed: Args.Args, mode: AppMode, stdinTty: Bool) -> IO(Unit):
  match mode:
    case Interactive{}: fail("Interactive mode is not available in this port yet. Use --print/-p or --mode json.")
    case Rpc{}: fail("RPC mode is not available in this port yet.")
    case _:
      do IO<Unit>:
        environment : Result<&2, &2, FS.Error, Paths.Environment> <- Paths.loadEnvironment(Runtime.urlContext())
        runPrint(parsed, mode, stdinTty, environment)

def modeOf(parsed: Args.Args) -> Maybe<&2, Args.Mode>:
  match parsed:
    case Args.Args{_, _, _, _, _, _, _, _, _, _, mode, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: mode

def printFlag(parsed: Args.Args) -> Bool:
  match parsed:
    case Args.Args{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, Some{True{}}, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: True{}
    case _: False{}

def diagnosticsOf(parsed: Args.Args) -> List<&2, Args.Diagnostic>:
  match parsed:
    case Args.Args{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, diagnostics}: diagnostics

def helpFlag(parsed: Args.Args) -> Bool:
  match parsed:
    case Args.Args{_, _, _, _, _, _, _, _, Some{True{}}, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: True{}
    case _: False{}

def versionFlag(parsed: Args.Args) -> Bool:
  match parsed:
    case Args.Args{_, _, _, _, _, _, _, _, _, Some{True{}}, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: True{}
    case _: False{}

def dispatch(+parsed: Args.Args, help: Bool, version: Bool, invalid: Bool, +stdinTty: Bool, stdoutTty: Bool) -> IO(Unit):
  match help version invalid:
    case True{} _ _: IO.print(Args.helpText(Config.appName()))
    case _ True{} _: IO.print(Config.version())
    case _ _ True{}: IO.die(Unit, 1, "")
    case _ _ _: runMode(parsed, resolveAppMode(modeOf(parsed), printFlag(parsed), stdinTty, stdoutTty), stdinTty)

def run(+parsed: Args.Args) -> IO(Unit):
  do IO<Unit>:
    reportDiagnostics(diagnosticsOf(parsed))
    stdinTty : Bool <- IO.isTerminal(0)
    stdoutTty : Bool <- IO.isTerminal(1)
    dispatch(parsed, helpFlag(parsed), versionFlag(parsed), hasError(diagnosticsOf(parsed)), stdinTty, stdoutTty)

# The runtime hands over an affine argv list; the parser reads a shared one.
def shared(values: List<&1, String>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: value <> shared(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    run(Args.parseArgs(shared(values)))
