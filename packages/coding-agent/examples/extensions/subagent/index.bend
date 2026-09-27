import Base
import ./agents.bend as Agents
import ../../../src/config.bend as Config
import ../../../src/core/extensions/types.bend as Ext
import ../../../src/core/extensions/context.bend as Ctx
import ../../../src/core/extensions/loader.bend as Loader
import ../../../src/core/tools/index.bend as Tools
import ../../../src/core/tools/output-accumulator.bend as Temp
import ../../../src/modes/json-event.bend as JsonEvent
import ../../../../agent/src/types.bend as Agent
import ../../../../ai/src/types.bend as Ai
import ../../../../ai/src/utils/message-json.bend as Json
import ../../../../ai/src/utils/thinking-levels.bend as Levels
import ../../../../runtime/src/abort.bend as Abort
import ../../../../runtime/src/callback.bend as C
import ../../../../runtime/src/child-process.bend as Child
import ../../../../runtime/src/filesystem.bend as FS
import ../../../../runtime/src/json.bend as Decode
import ../../../../runtime/src/posix-path.bend as Path
import ../../../../runtime/src/record.bend as R
import ../../../../runtime/src/ref.bend as Ref
import ../../../../runtime/src/schema-value.bend as V
import ../../../../runtime/src/string.bend as Strings
import ../../../../runtime/src/text.bend as Text
import ../../../../runtime/src/utf8.bend as Utf8

# pi v0.87.1 examples/extensions/subagent/index.ts: the `subagent` tool
# delegates tasks to specialized agents, each in its own `pi --mode json -p
# --no-session` process with an isolated context window:
#
#   single:   { agent, task }
#   parallel: { tasks: [{ agent, task }, ...] }  (at most 8, 4 at a time)
#   chain:    { chain: [{ agent, task }, ...] }  ({previous} is the prior output)
#
# Native adaptations:
# - The TUI renderers (renderCall/renderResult and their formatting helpers)
#   are not ported: the native ToolDefinition has no renderers.
# - The subagent runs the running pi binary (/proc/self/exe; upstream
#   process.execPath). A generic JavaScript runtime (bun/node) falls back to
#   `pi` on PATH, as upstream does without a script path.
# - Details are the typed SubagentDetails rendered as JSON (RawDetails).
# - Upstream's returned `isError: true` is not part of AgentToolResult and the
#   agent loop ignores it; those results are ordinary results here as well.
# - Aborting kills the process with SIGKILL (Child.spawn's abort), where
#   upstream sends SIGTERM and SIGKILL after 5 s.
# - {previous} is replaced literally (JavaScript's `$&`-style replacement
#   patterns in the prior output are not interpreted).
# - The system prompt file is written into a fresh mkdtemp directory without
#   the process-wide file mutation queue, which extensions cannot reach.

def maxParallelTasks() -> Nat: 8n
def maxConcurrency() -> Nat: 4n
def perTaskOutputCap() -> Nat: 51200n

def zero() -> F64: U32.to_f64(0)

# Results
# -------

def Message() -> Data: JsonEvent.Message()

type UsageStats is Data:
  UsageStats{input: F64, output: F64, cacheRead: F64, cacheWrite: F64, cost: F64, contextTokens: F64, turns: Nat}

def emptyUsage() -> UsageStats: UsageStats{zero(), zero(), zero(), zero(), zero(), zero(), 0n}

type ResultSource is Data:
  KnownSource{source: Agents.AgentSource}
  UnknownSource{}

# exitCode None is a parallel task still waiting to run (upstream -1).
type SingleResult is Data:
  SingleResult{agent: String, agentSource: ResultSource, task: String, exitCode: Maybe<&2, U32>, messages: List<&2, Message()>, stderr: String, usage: UsageStats, model: Maybe<&2, String>, stopReason: Maybe<&2, String>, errorMessage: Maybe<&2, String>, step: Maybe<&2, Nat>}

type SubagentMode is Data:
  SingleMode{}
  ParallelMode{}
  ChainMode{}

def modeName(mode: SubagentMode) -> String:
  match mode:
    case SingleMode{}: "single"
    case ParallelMode{}: "parallel"
    case ChainMode{}: "chain"

type SubagentDetails is Data:
  SubagentDetails{mode: SubagentMode, agentScope: Agents.AgentScope, projectAgentsDir: Maybe<&2, String>, results: List<&2, SingleResult>}

# What every details value of one call shares (upstream makeDetails).
type DetailsScope is Data:
  DetailsScope{agentScope: Agents.AgentScope, projectAgentsDir: Maybe<&2, String>}

def makeDetails(scope: DetailsScope, mode: SubagentMode, results: List<&2, SingleResult>) -> SubagentDetails:
  match scope:
    case DetailsScope{agentScope, projectAgentsDir}: SubagentDetails{mode, agentScope, projectAgentsDir, results}

def messagesOf(result: SingleResult) -> List<&2, Message()>:
  match result:
    case SingleResult{_, _, _, _, messages, _, _, _, _, _, _}: messages

def resultAgent(result: SingleResult) -> String:
  match result:
    case SingleResult{agent, _, _, _, _, _, _, _, _, _, _}: agent

def resultStopReason(result: SingleResult) -> Maybe<&2, String>:
  match result:
    case SingleResult{_, _, _, _, _, _, _, _, stopReason, _, _}: stopReason

def withExitCode(result: SingleResult, code: U32) -> SingleResult:
  match result:
    case SingleResult{agent, source, task, _, messages, stderr, usage, model, stopReason, errorMessage, step}: SingleResult{agent, source, task, Some{code}, messages, stderr, usage, model, stopReason, errorMessage, step}

def isRunning(result: SingleResult) -> Bool:
  match result:
    case SingleResult{_, _, _, None{}, _, _, _, _, _, _, _}: True{}
    case _: False{}

# Output
# ------

def firstText(content: List<&2, Ai.AssistantContent<V.Value>>) -> Maybe<&2, String>:
  match content:
    case Nil{}: None{}
    case Ai.AssistantText{Ai.TextContent{text, _}} <> _: Some{text}
    case _ <> rest: firstText(rest)

def assistantText(message: Message()) -> Maybe<&2, String>:
  match message:
    case Agent.LlmMessage{Ai.Assistant{Ai.AssistantMessage{content, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}}: firstText(content)
    case _: None{}

def lastText(messages: List<&2, Message()>, found: Maybe<&2, String>) -> Maybe<&2, String>:
  match messages found:
    case _ Some{text}: Some{text}
    case Nil{} None{}: None{}
    case message <> rest None{}: lastText(rest, assistantText(message))

# The text of the last assistant message that has one.
def getFinalOutput(messages: List<&2, Message()>) -> String:
  Maybe.default(&2, String, lastText(List.reverse(&2, Message(), messages), None{}), "")

def failedStop(stopReason: Maybe<&2, String>) -> Bool:
  match stopReason:
    case Some{"error"}: True{}
    case Some{"aborted"}: True{}
    case _: False{}

def isFailedResult(result: SingleResult) -> Bool:
  match result:
    case SingleResult{_, _, _, Some{0}, _, _, _, _, stopReason, _, _}: failedStop(stopReason)
    case _: True{}

# JavaScript's `a || b` over optional strings: an empty string counts as
# missing.
def present(value: Maybe<&2, String>) -> Maybe<&2, String>:
  match value:
    case Some{""}: None{}
    case other: other

def orElse(value: Maybe<&2, String>, fallback: String) -> String:
  Maybe.default(&2, String, present(value), fallback)

def orMaybe(value: Maybe<&2, String>, fallback: Maybe<&2, String>) -> Maybe<&2, String>:
  match value:
    case Some{""}: fallback
    case Some{text}: Some{text}
    case None{}: fallback

def outputOf(failed: Bool, result: SingleResult) -> String:
  match failed result:
    case True{} SingleResult{_, _, _, _, messages, stderr, _, _, _, errorMessage, _}: orElse(orMaybe(errorMessage, orMaybe(Some{stderr}, Some{getFinalOutput(messages)})), "(no output)")
    case False{} SingleResult{_, _, _, _, messages, _, _, _, _, _, _}: orElse(Some{getFinalOutput(messages)}, "(no output)")

def getResultOutput(+result: SingleResult) -> String: outputOf(isFailedResult(result), result)

def utf8Width(char: Char) -> Nat:
  match char:
    case Chr{+code}: Bool.pick(Nat, U32.is_lt(code, 128), 1n, Bool.pick(Nat, U32.is_lt(code, 2048), 2n, Bool.pick(Nat, U32.is_lt(code, 65536), 3n, 4n)))

# The longest prefix whose UTF-8 encoding fits in `budget` bytes.
def prefixWithin(text: String, +budget: Nat, +reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{+char, rest}:
      +width = utf8Width(char)
      Bool.pick(Unit -> String, Nat.is_le(width, budget), _ => prefixWithin(rest, Nat.sub(budget, width), SCon{char, reversed}), _ => String.reverse(reversed))(Unit{})

def byteLength(text: String) -> Nat: List.length(&2, U32, Utf8.encode(text))

def truncatedOutput(+output: String, +total: Nat) -> String:
  +truncated = prefixWithin(output, perTaskOutputCap(), "")
  truncated ++ "\n\n[Output truncated: " ++ Nat.show(Nat.sub(total, byteLength(truncated))) ++ " bytes omitted. Full output preserved in tool details.]"

def truncateParallelOutput(+output: String) -> String:
  +total = byteLength(output)
  Bool.pick(Unit -> String, Nat.is_le(total, perTaskOutputCap()), _ => output, _ => truncatedOutput(output, total))(Unit{})

# Details as JSON
# ---------------

def sourceName(source: ResultSource) -> String:
  match source:
    case KnownSource{source}: Agents.agentSourceName(source)
    case UnknownSource{}: "unknown"

def exitCodeValue(code: Maybe<&2, U32>) -> V.Value:
  match code:
    case None{}: Json.number(F64.neg(U32.to_f64(1)))
    case Some{code}: Json.number(U32.to_f64(code))

def usageValue(usage: UsageStats) -> V.Value:
  match usage:
    case UsageStats{input, output, cacheRead, cacheWrite, cost, contextTokens, turns}:
      Json.object(Json.field("input", Json.number(input), Json.field("output", Json.number(output), Json.field("cacheRead", Json.number(cacheRead), Json.field("cacheWrite", Json.number(cacheWrite), Json.field("cost", Json.number(cost), Json.field("contextTokens", Json.number(contextTokens), Json.field("turns", Json.natural(turns), Nil{}))))))))

def messageValues(messages: List<&2, Message()>) -> List<&2, V.Value>:
  match messages:
    case Nil{}: Nil{}
    case message <> rest: JsonEvent.message(message) <> messageValues(rest)

def resultValue(result: SingleResult) -> V.Value:
  match result:
    case SingleResult{agent, source, task, exitCode, messages, stderr, usage, model, stopReason, errorMessage, step}:
      Json.object(Json.field("agent", Json.text(agent), Json.field("agentSource", Json.text(sourceName(source)), Json.field("task", Json.text(task), Json.field("exitCode", exitCodeValue(exitCode), Json.field("messages", V.ArrayValue{messageValues(messages)}, Json.field("stderr", Json.text(stderr), Json.field("usage", usageValue(usage), Json.optionalText("model", model, Json.optionalText("stopReason", stopReason, Json.optionalText("errorMessage", errorMessage, Json.optional("step", Maybe.map(&2, Nat, V.Value, Json.natural, step), Nil{}))))))))))))

def resultValues(results: List<&2, SingleResult>) -> List<&2, V.Value>:
  match results:
    case Nil{}: Nil{}
    case result <> rest: resultValue(result) <> resultValues(rest)

def nullableText(value: Maybe<&2, String>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{text}: Json.text(text)

def detailsValue(details: SubagentDetails) -> V.Value:
  match details:
    case SubagentDetails{mode, scope, projectAgentsDir, results}:
      Json.object(Json.field("mode", Json.text(modeName(mode)), Json.field("agentScope", Json.text(Agents.agentScopeName(scope)), Json.field("projectAgentsDir", nullableText(projectAgentsDir), Json.field("results", V.ArrayValue{resultValues(results)}, Nil{})))))

def toolResult(+text: String, details: SubagentDetails) -> Agent.AgentToolResult<Tools.ToolDetails>:
  Agent.AgentToolResult{Ai.TextImageText{Ai.TextContent{text, None{}}} <> Nil{}, Some{Tools.RawDetails{detailsValue(details)}}, None{}, None{}}

def textResult(+text: String, details: SubagentDetails) -> Tools.Output(): Done{toolResult(text, details)}

# Streaming updates
# -----------------
# Where a running agent's progress goes (upstream's per-mode onUpdate
# closures): the call's own update in single mode, the completed steps plus
# the current one in chain mode, and the shared per-task table in parallel
# mode (whose summary is emitted only when the call has an update callback).

def UpdateCallback() -> Data: Agent.AgentToolUpdateCallback(Tools.ToolDetails)

type UpdateTarget is Data:
  NoUpdates{}
  SingleUpdates{onUpdate: UpdateCallback(), scope: DetailsScope}
  ChainUpdates{onUpdate: UpdateCallback(), scope: DetailsScope, completed: List<&2, SingleResult>}
  ParallelUpdates{onUpdate: Maybe<&2, UpdateCallback()>, scope: DetailsScope, all: Ref.Ref<List<&2, SingleResult>>, index: Nat}

def runningText(result: SingleResult) -> String: orElse(Some{getFinalOutput(messagesOf(result))}, "(running...)")

def countRunning(results: List<&2, SingleResult>) -> Nat:
  match results:
    case Nil{}: 0n
    case result <> rest: Bool.pick(Nat, isRunning(result), 1n, 0n) + countRunning(rest)

def parallelProgress(+results: List<&2, SingleResult>) -> String:
  +total = List.length(&2, SingleResult, results)
  +running = countRunning(results)
  "Parallel: " ++ Nat.show(Nat.sub(total, running)) ++ "/" ++ Nat.show(total) ++ " done, " ++ Nat.show(running) ++ " running..."

def emitParallelUpdate(onUpdate: Maybe<&2, UpdateCallback()>, scope: DetailsScope, all: Ref.Ref<List<&2, SingleResult>>) -> IO(Unit):
  match onUpdate:
    case None{}: IO.pure(Unit, Unit{})
    case Some{callback}:
      do IO<Unit>:
        +results : List<&2, SingleResult> <- Ref.read(List<&2, SingleResult>, all)
        C.call(Agent.AgentToolResult<Tools.ToolDetails>, Unit, callback, toolResult(parallelProgress(results), makeDetails(scope, ParallelMode{}, results)))

def replaceAt(results: List<&2, SingleResult>, index: Nat, result: SingleResult) -> List<&2, SingleResult>:
  match results index:
    case Nil{} _: Nil{}
    case _ <> rest 0n: result <> rest
    case first <> rest 1n+previous: first <> replaceAt(rest, previous, result)

def storeResult(all: Ref.Ref<List<&2, SingleResult>>, index: Nat, result: SingleResult) -> IO(Unit):
  Ref.modify(List<&2, SingleResult>, Unit, all, current => (replaceAt(current, index, result), Unit{}))

def emitUpdate(target: UpdateTarget, +current: SingleResult) -> IO(Unit):
  match target:
    case NoUpdates{}: IO.pure(Unit, Unit{})
    case SingleUpdates{callback, scope}: C.call(Agent.AgentToolResult<Tools.ToolDetails>, Unit, callback, toolResult(runningText(current), makeDetails(scope, SingleMode{}, [current])))
    case ChainUpdates{callback, scope, completed}: C.call(Agent.AgentToolResult<Tools.ToolDetails>, Unit, callback, toolResult(runningText(current), makeDetails(scope, ChainMode{}, List.append(&2, SingleResult, completed, [current]))))
    case ParallelUpdates{onUpdate, +scope, +all, index}:
      do IO<Unit>:
        storeResult(all, index, current)
        emitParallelUpdate(onUpdate, scope, all)

# The JSON event stream
# ---------------------

def addUsage(stats: UsageStats, usage: Ai.Usage) -> UsageStats:
  match stats usage:
    case UsageStats{input, output, cacheRead, cacheWrite, cost, _, turns} Ai.Usage{addInput, addOutput, addRead, addWrite, _, _, totalTokens, Ai.UsageCost{_, _, _, _, total}}:
      UsageStats{F64.add(input, addInput), F64.add(output, addOutput), F64.add(cacheRead, addRead), F64.add(cacheWrite, addWrite), F64.add(cost, total), totalTokens, turns}

def countTurn(stats: UsageStats) -> UsageStats:
  match stats:
    case UsageStats{input, output, cacheRead, cacheWrite, cost, contextTokens, turns}: UsageStats{input, output, cacheRead, cacheWrite, cost, contextTokens, turns + 1n}

def nonEmpty(+text: String) -> Maybe<&2, String>: Bool.pick(Maybe<&2, String>, String.is_empty(text), None{}, Some{text})

def appended(result: SingleResult, message: Message()) -> SingleResult:
  match result:
    case SingleResult{agent, source, task, exitCode, messages, stderr, usage, model, stopReason, errorMessage, step}: SingleResult{agent, source, task, exitCode, List.append(&2, Message(), messages, [message]), stderr, usage, model, stopReason, errorMessage, step}

# An assistant message counts a turn and its usage, names the model unless
# one is known, and records its stop reason and error.
def assistantEnded(result: SingleResult, message: Ai.AssistantMessage<V.Value, Unit>) -> SingleResult:
  match result message:
    case SingleResult{agent, source, task, exitCode, messages, stderr, usage, model, _, errorMessage, step} Ai.AssistantMessage{_, _, _, messageModel, _, _, _, _, messageUsage, stopReason, _, messageError, _, _, _}:
      SingleResult{agent, source, task, exitCode, messages, stderr, addUsage(countTurn(usage), messageUsage), orMaybe(model, nonEmpty(messageModel)), Some{Json.stopReason(stopReason)}, orMaybe(messageError, errorMessage), step}

def messageEnded(+result: SingleResult, +message: Message()) -> SingleResult:
  match message:
    case Agent.LlmMessage{Ai.Assistant{assistant}}: assistantEnded(appended(result, message), assistant)
    case _: appended(result, message)

type StreamEvent is Data:
  MessageEnded{message: Message()}
  ToolResultEnded{message: Message()}
  OtherEvent{}

def decodedEvent(kind: String, decoded: Result<&2, &2, Decode.Error, Message()>) -> StreamEvent:
  match kind decoded:
    case _ Fail{_}: OtherEvent{}
    case "message_end" Done{message}: MessageEnded{message}
    case "tool_result_end" Done{message}: ToolResultEnded{message}
    case _ _: OtherEvent{}

def eventMessage(kind: String, message: Maybe<&2, V.Value>) -> StreamEvent:
  match message:
    case None{}: OtherEvent{}
    case Some{value}: decodedEvent(kind, JsonEvent.decodeMessage(value))

def typedEvent(kind: Maybe<&2, V.Value>, message: Maybe<&2, V.Value>) -> StreamEvent:
  match kind:
    case Some{V.Text{kind}}: eventMessage(kind, message)
    case _: OtherEvent{}

def streamEvent(parsed: Result<&2, &2, Decode.ParseError, V.Value>) -> StreamEvent:
  match parsed:
    case Done{V.ObjectValue{+fields}}: typedEvent(R.get(V.Value, fields, "type"), R.get(V.Value, fields, "message"))
    case _: OtherEvent{}

def lineEvent(+line: String) -> StreamEvent:
  Bool.pick(Unit -> StreamEvent, Text.blank(line), _ => OtherEvent{}, _ => streamEvent(Decode.parse(line)))(Unit{})

type RunState is Data:
  RunState{pending: List<&2, U32>, result: SingleResult}

def recorded(state: RunState, event: StreamEvent) -> RunState & Maybe<&2, SingleResult>:
  match state event:
    case RunState{pending, result} MessageEnded{message}:
      +next = messageEnded(result, message)
      (RunState{pending, next}, Some{next})
    case RunState{pending, result} ToolResultEnded{message}:
      +next = appended(result, message)
      (RunState{pending, next}, Some{next})
    case other OtherEvent{}: (other, None{})

def updated(target: UpdateTarget, changed: Maybe<&2, SingleResult>) -> IO(Unit):
  match changed:
    case None{}: IO.pure(Unit, Unit{})
    case Some{result}: emitUpdate(target, result)

def processLine(+state: Ref.Ref<RunState>, +target: UpdateTarget, +line: List<&2, U32>) -> IO(Unit):
  +event = lineEvent(Utf8.decodeBuffer(line))
  do IO<Unit>:
    changed : Maybe<&2, SingleResult> <- Ref.modify(RunState, Maybe<&2, SingleResult>, state, current => recorded(current, event))
    updated(target, changed)

def processLines(+state: Ref.Ref<RunState>, +target: UpdateTarget, lines: List<&2, List<&2, U32>>) -> IO(Unit):
  match lines:
    case Nil{}: IO.pure(Unit, Unit{})
    case line <> rest:
      do IO<Unit>:
        processLine(state, target, line)
        processLines(state, target, rest)

# Complete lines of `bytes` (after the pending partial line) and the new
# partial line. Lines are split on bytes, so a character split across chunks
# decodes whole.
type Split is Data:
  Split{lines: List<&2, List<&2, U32>>, pending: List<&2, U32>}

def splitLines(bytes: List<&2, U32>, +current: List<&2, U32>, +lines: List<&2, List<&2, U32>>) -> Split:
  match bytes:
    case Nil{}: Split{List.reverse(&2, List<&2, U32>, lines), List.reverse(&2, U32, current)}
    case +byte <> +rest: Bool.pick(Unit -> Split, U32.is_eq(byte, 10), _ => splitLines(rest, Nil{}, List.reverse(&2, U32, current) <> lines), _ => splitLines(rest, byte <> current, lines))(Unit{})

def splitState(result: SingleResult, split: Split) -> RunState & List<&2, List<&2, U32>>:
  match split:
    case Split{lines, rest}: (RunState{rest, result}, lines)

def takeLines(state: RunState, bytes: List<&2, U32>) -> RunState & List<&2, List<&2, U32>>:
  match state:
    case RunState{pending, result}: splitState(result, splitLines(List.append(&2, U32, pending, bytes), Nil{}, Nil{}))

type StreamEnv is Data:
  StreamEnv{state: Ref.Ref<RunState>, target: UpdateTarget}

def stdoutChunk(+env: StreamEnv, bytes: List<&2, U32>) -> IO(Result<&2, &2, String, Unit>):
  match env:
    case StreamEnv{+state, +target}:
      do IO<Result<&2, &2, String, Unit>>:
        lines : List<&2, List<&2, U32>> <- Ref.modify(RunState, List<&2, List<&2, U32>>, state, current => takeLines(current, bytes))
        processLines(state, target, lines)
        return Done{Unit{}}

def onStdout(env: StreamEnv, bytes: List<&2, U32>) -> IO(Result<&2, &2, String, Unit>): stdoutChunk(env, bytes)

def withStderr(state: RunState, +text: String) -> RunState & Unit:
  match state:
    case RunState{pending, SingleResult{agent, source, task, exitCode, messages, stderr, usage, model, stopReason, errorMessage, step}}:
      (RunState{pending, SingleResult{agent, source, task, exitCode, messages, stderr ++ text, usage, model, stopReason, errorMessage, step}}, Unit{})

def onStderr(state: Ref.Ref<RunState>, bytes: List<&2, U32>) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    Ref.modify(RunState, Unit, state, current => withStderr(current, Utf8.decodeBuffer(bytes)))
    return Done{Unit{}}

# After the process closed, a final unterminated line is processed too.
def takePending(state: RunState) -> RunState & List<&2, U32>:
  match state:
    case RunState{pending, result}: (RunState{Nil{}, result}, pending)

def flushPending(+state: Ref.Ref<RunState>, +target: UpdateTarget) -> IO(Unit):
  do IO<Unit>:
    +pending : List<&2, U32> <- Ref.modify(RunState, List<&2, U32>, state, takePending)
    Bool.pick(IO(Unit), Text.blank(Utf8.decodeBuffer(pending)), IO.pure(Unit, Unit{}), processLine(state, target, pending))

# Invocation
# ----------

type Invocation is Type:
  Invocation{command: String, args: List<String>}

def isGenericRuntime(+name: String) -> Bool:
  String.eq(name, "node") || String.eq(name, "bun") || String.eq(name, "node.exe") || String.eq(name, "bun.exe")

def commandFor(executable: Result<&2, &2, FS.Error, String>) -> String:
  match executable:
    case Fail{_}: "pi"
    case Done{+path}: Bool.pick(String, isGenericRuntime(Text.asciiLower(Path.basename(path))), "pi", path)

# upstream getPiInvocation: the running pi executable, or `pi` on PATH when
# the host is a generic JavaScript runtime.
def getPiInvocation(args: List<String>) -> IO(Invocation):
  do IO<Invocation>:
    executable : Result<&2, &2, FS.Error, String> <- FS.realpath("/proc/self/exe")
    return Invocation{commandFor(executable), args}

# Arguments
# ---------

type DispatchDefaults is Data:
  DispatchDefaults{model: Maybe<&2, String>, thinkingLevel: Maybe<&2, String>}

def modelArgs(model: Maybe<&2, String>) -> List<String>:
  match model:
    case None{}: []
    case Some{model}: ["--model", model]

def thinkingArgs(inherits: Bool, level: Maybe<&2, String>) -> List<String>:
  match inherits level:
    case True{} Some{level}: ["--thinking", level]
    case _ _: []

def toolArgs(tools: Maybe<&2, List<&2, String>>) -> List<String>:
  match tools:
    case Some{first <> rest}: ["--tools", String.join(first <> rest, ",")]
    case _: []

def isNone(value: Maybe<&2, String>) -> Bool:
  match value:
    case None{}: True{}
    case Some{_}: False{}

def dispatchModel(dispatch: DispatchDefaults) -> Maybe<&2, String>:
  match dispatch:
    case DispatchDefaults{model, _}: model

def agentArgs(agent: Agents.AgentConfig, dispatch: DispatchDefaults) -> List<String>:
  match agent dispatch:
    case Agents.AgentConfig{_, _, tools, +model, _, _, _} DispatchDefaults{defaultModel, thinking}:
      List.concat(&1, String, [["--mode", "json", "-p", "--no-session"], modelArgs(orMaybe(model, defaultModel)), thinkingArgs(isNone(model), thinking), toolArgs(tools)])

# upstream `agentName.replace(/[^\w.-]+/g, "_")`
def nameChar(char: Char) -> Bool:
  match char:
    case Chr{+code}: (U32.is_ge(code, 48) && U32.is_le(code, 57)) || (U32.is_ge(code, 65) && U32.is_le(code, 90)) || (U32.is_ge(code, 97) && U32.is_le(code, 122)) || U32.is_eq(code, 95) || U32.is_eq(code, 46) || U32.is_eq(code, 45)

def safeFrom(text: String, +replacing: Bool, +reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{+char, +rest}:
      Bool.pick(Unit -> String, nameChar(char), _ => safeFrom(rest, False{}, SCon{char, reversed}), _ => safeFrom(rest, True{}, Bool.pick(String, replacing, reversed, SCon{'_', reversed})))(Unit{})

def safeName(name: String) -> String: safeFrom(name, False{}, "")

# The system prompt file: a fresh private directory, the file in it with
# mode 0600.
type PromptFile is Data:
  PromptFile{dir: String, filePath: String}

def promptWritten(+dir: String, +filePath: String, written: Result<&2, &2, FS.Error, Unit>) -> Result<&2, &2, String, PromptFile>:
  match written:
    case Fail{error}: Fail{FS.errorMessage(error)}
    case Done{_}: Done{PromptFile{dir, filePath}}

def writeInto(+agentName: String, +prompt: String, created: Result<&1, &1, U32 & String, String>) -> IO(Result<&2, &2, String, PromptFile>):
  match created:
    case Fail{(_, message)}: IO.pure(Result<&2, &2, String, PromptFile>, Fail{message})
    case Done{+dir}:
      +filePath = Path.join(dir, "prompt-" ++ safeName(agentName) ++ ".md")
      do IO<Result<&2, &2, String, PromptFile>>:
        written : Result<&2, &2, FS.Error, Unit> <- FS.writeFileMode(filePath, prompt, 384)
        return promptWritten(dir, filePath, written)

def writePromptToTempFile(+agentName: String, +prompt: String) -> IO(Result<&2, &2, String, PromptFile>):
  do IO<Result<&2, &2, String, PromptFile>>:
    tmp : String <- Temp.tempDirectory(["TMPDIR", "TMP", "TEMP"], None{})
    created : Result<&1, &1, U32 & String, String> <- Directory.mkdtemp(Path.join(tmp, "pi-subagent-XXXXXX"))
    writeInto(agentName, prompt, created)

def removePromptFile(file: Maybe<&2, PromptFile>) -> IO(Unit):
  match file:
    case None{}: IO.pure(Unit, Unit{})
    case Some{PromptFile{dir, filePath}}:
      do IO<Unit>:
        unlinked : Result<&1, &1, U32 & String, Unit> <- File.unlink(filePath)
        removed : Result<&1, &1, U32 & String, Unit> <- Directory.remove(dir)
        return Unit{}

# Running one agent
# -----------------

type RunEnv is Data:
  RunEnv{defaultCwd: String, dispatch: DispatchDefaults, agents: List<&2, Agents.AgentConfig>}

def findAgent(agents: List<&2, Agents.AgentConfig>, +name: String) -> Maybe<&2, Agents.AgentConfig>:
  match agents:
    case Nil{}: None{}
    case +agent <> rest: Bool.pick(Maybe<&2, Agents.AgentConfig>, String.eq(Agents.agentName(agent), name), Some{agent}, findAgent(rest, name))

def quotedNames(agents: List<&2, Agents.AgentConfig>) -> List<&2, String>:
  match agents:
    case Nil{}: Nil{}
    case agent <> rest: ("\"" ++ Agents.agentName(agent) ++ "\"") <> quotedNames(rest)

def unknownAgent(agents: List<&2, Agents.AgentConfig>, +agentName: String, task: String, step: Maybe<&2, Nat>) -> SingleResult:
  SingleResult{agentName, UnknownSource{}, task, Some{1}, Nil{}, "Unknown agent: \"" ++ agentName ++ "\". Available agents: " ++ orElse(Some{String.join(quotedNames(agents), ", ")}, "none") ++ ".", emptyUsage(), None{}, None{}, None{}, step}

type Exit is Data:
  Exited{code: U32}
  AbortedExit{}

def exitOf(result: Result<&2, &2, Child.ExecutionError, U32>) -> Exit:
  match result:
    case Done{code}: Exited{code}
    case Fail{Child.ExecutionAborted{}}: AbortedExit{}
    case Fail{_}: Exited{1}

def finished(exit: Exit, result: SingleResult) -> Result<&2, &2, String, SingleResult>:
  match exit:
    case AbortedExit{}: Fail{"Subagent was aborted"}
    case Exited{code}: Done{withExitCode(result, code)}

def runResult(state: RunState) -> SingleResult:
  match state:
    case RunState{_, result}: result

def spawnAgent(+target: UpdateTarget, invocation: Invocation, cwd: String, signal: Maybe<&2, Abort.AbortSignal<Unit>>, initial: SingleResult) -> IO(Result<&2, &2, String, SingleResult>):
  match invocation:
    case Invocation{command, args}:
      do IO<Result<&2, &2, String, SingleResult>>:
        +state : Ref.Ref<RunState> <- Ref.new(RunState, RunState{Nil{}, initial})
        +stdout : C.Callback<List<&2, U32>, Result<&2, &2, String, Unit>> <- C.create(~StreamEnv, ~List<&2, U32>, ~Result<&2, &2, String, Unit>, ~onStdout, StreamEnv{state, target})
        +stderr : C.Callback<List<&2, U32>, Result<&2, &2, String, Unit>> <- C.create(~Ref.Ref<RunState>, ~List<&2, U32>, ~Result<&2, &2, String, Unit>, ~onStderr, state)
        env : List<String> <- IO.environment()
        spawned : Result<&2, &2, Child.ExecutionError, U32> <- Child.spawn(command, args, cwd, env, Child.signalList(signal), stdout, stderr)
        C.dispose(List<&2, U32>, Result<&2, &2, String, Unit>, stdout)
        C.dispose(List<&2, U32>, Result<&2, &2, String, Unit>, stderr)
        flushPending(state, target)
        final : RunState <- Ref.dispose(RunState, state)
        return finished(exitOf(spawned), runResult(final))

def promptArgs(file: Maybe<&2, PromptFile>) -> List<String>:
  match file:
    case None{}: []
    case Some{PromptFile{_, filePath}}: ["--append-system-prompt", filePath]

def spawnWithPrompt(+target: UpdateTarget, base: List<String>, +task: String, cwd: String, signal: Maybe<&2, Abort.AbortSignal<Unit>>, initial: SingleResult, +file: Maybe<&2, PromptFile>) -> IO(Result<&2, &2, String, SingleResult>):
  do IO<Result<&2, &2, String, SingleResult>>:
    invocation : Invocation <- getPiInvocation(List.concat(&1, String, [base, promptArgs(file), ["Task: " ++ task]]))
    result : Result<&2, &2, String, SingleResult> <- spawnAgent(target, invocation, cwd, signal, initial)
    removePromptFile(file)
    return result

def spawnPrompted(+target: UpdateTarget, base: List<String>, +task: String, cwd: String, signal: Maybe<&2, Abort.AbortSignal<Unit>>, initial: SingleResult, written: Result<&2, &2, String, Maybe<&2, PromptFile>>) -> IO(Result<&2, &2, String, SingleResult>):
  match written:
    case Fail{error}: IO.pure(Result<&2, &2, String, SingleResult>, Fail{error})
    case Done{file}: spawnWithPrompt(target, base, task, cwd, signal, initial, file)

def somePrompt(written: Result<&2, &2, String, PromptFile>) -> Result<&2, &2, String, Maybe<&2, PromptFile>>:
  Result.map(&2, &2, String, PromptFile, Maybe<&2, PromptFile>, file => Some{file}, written)

def writtenPrompt(+name: String, +systemPrompt: String) -> IO(Result<&2, &2, String, Maybe<&2, PromptFile>>):
  do IO<Result<&2, &2, String, Maybe<&2, PromptFile>>>:
    written : Result<&2, &2, String, PromptFile> <- writePromptToTempFile(name, systemPrompt)
    return somePrompt(written)

def promptFileFor(+name: String, +systemPrompt: String) -> IO(Result<&2, &2, String, Maybe<&2, PromptFile>>):
  Bool.pick(Unit -> IO(Result<&2, &2, String, Maybe<&2, PromptFile>>), Text.blank(systemPrompt),
    _ => IO.pure(Result<&2, &2, String, Maybe<&2, PromptFile>>, Done{None{}}),
    _ => writtenPrompt(name, systemPrompt))(Unit{})

def initialResult(agent: Agents.AgentConfig, task: String, defaultModel: Maybe<&2, String>, step: Maybe<&2, Nat>) -> SingleResult:
  match agent:
    case Agents.AgentConfig{name, _, _, model, _, source, _}: SingleResult{name, KnownSource{source}, task, Some{0}, Nil{}, "", emptyUsage(), orMaybe(model, defaultModel), None{}, None{}, step}

def agentPrompt(agent: Agents.AgentConfig) -> String:
  match agent:
    case Agents.AgentConfig{_, _, _, _, systemPrompt, _, _}: systemPrompt

def runAgent(env: RunEnv, +agent: Agents.AgentConfig, +task: String, cwd: Maybe<&2, String>, step: Maybe<&2, Nat>, signal: Maybe<&2, Abort.AbortSignal<Unit>>, +target: UpdateTarget) -> IO(Result<&2, &2, String, SingleResult>):
  match env:
    case RunEnv{defaultCwd, +dispatch, _}:
      do IO<Result<&2, &2, String, SingleResult>>:
        written : Result<&2, &2, String, Maybe<&2, PromptFile>> <- promptFileFor(Agents.agentName(agent), agentPrompt(agent))
        spawnPrompted(target, agentArgs(agent, dispatch), task, Maybe.default(&2, String, cwd, defaultCwd), signal, initialResult(agent, task, dispatchModel(dispatch), step), written)

def runFound(+env: RunEnv, found: Maybe<&2, Agents.AgentConfig>, +agents: List<&2, Agents.AgentConfig>, +agentName: String, +task: String, cwd: Maybe<&2, String>, step: Maybe<&2, Nat>, signal: Maybe<&2, Abort.AbortSignal<Unit>>, target: UpdateTarget) -> IO(Result<&2, &2, String, SingleResult>):
  match found:
    case None{}: IO.pure(Result<&2, &2, String, SingleResult>, Done{unknownAgent(agents, agentName, task, step)})
    case Some{agent}: runAgent(env, agent, task, cwd, step, signal, target)

def runSingleAgent(+env: RunEnv, +agentName: String, +task: String, cwd: Maybe<&2, String>, step: Maybe<&2, Nat>, signal: Maybe<&2, Abort.AbortSignal<Unit>>, target: UpdateTarget) -> IO(Result<&2, &2, String, SingleResult>):
  match env:
    case RunEnv{_, _, +agents}: runFound(env, findAgent(agents, agentName), agents, agentName, task, cwd, step, signal, target)

# Parameters
# ----------

type TaskItem is Data:
  TaskItem{agent: String, task: String, cwd: Maybe<&2, String>}

type SubagentParams is Data:
  SubagentParams{agent: Maybe<&2, String>, task: Maybe<&2, String>, tasks: Maybe<&2, List<&2, TaskItem>>, chain: Maybe<&2, List<&2, TaskItem>>, agentScope: Maybe<&2, Agents.AgentScope>, confirmProjectAgents: Maybe<&2, Bool>, cwd: Maybe<&2, String>}

def stringProperty(+description: String) -> V.Value:
  Json.object(Json.field("type", Json.text("string"), Json.field("description", Json.text(description), Nil{})))

def itemSchema(+taskDescription: String) -> V.Value:
  Json.object(Json.field("type", Json.text("object"), Json.field("required", V.ArrayValue{[Json.text("agent"), Json.text("task")]}, Json.field("properties", Json.object(Json.field("agent", stringProperty("Name of the agent to invoke"), Json.field("task", stringProperty(taskDescription), Json.field("cwd", stringProperty("Working directory for the agent process"), Nil{})))), Nil{}))))

def arrayProperty(items: V.Value, +description: String) -> V.Value:
  Json.object(Json.field("type", Json.text("array"), Json.field("items", items, Json.field("description", Json.text(description), Nil{}))))

def scopeProperty() -> V.Value:
  Json.object(Json.field("type", Json.text("string"), Json.field("enum", V.ArrayValue{[Json.text("user"), Json.text("project"), Json.text("both")]}, Json.field("description", Json.text("Which agent directories to use. Default: \"user\". Use \"both\" to include project-local agents."), Json.field("default", Json.text("user"), Nil{})))))

def confirmProperty() -> V.Value:
  Json.object(Json.field("type", Json.text("boolean"), Json.field("description", Json.text("Prompt before running project-local agents. Default: true."), Json.field("default", Json.boolean(True{}), Nil{}))))

# upstream SubagentParams as TypeBox renders it.
def subagentParams() -> V.Value:
  Json.object(Json.field("type", Json.text("object"), Json.field("properties", Json.object(
    Json.field("agent", stringProperty("Name of the agent to invoke (for single mode)"),
    Json.field("task", stringProperty("Task to delegate (for single mode)"),
    Json.field("tasks", arrayProperty(itemSchema("Task to delegate to the agent"), "Array of {agent, task} for parallel execution"),
    Json.field("chain", arrayProperty(itemSchema("Task with optional {previous} placeholder for prior output"), "Array of {agent, task} for sequential execution"),
    Json.field("agentScope", scopeProperty(),
    Json.field("confirmProjectAgents", confirmProperty(),
    Json.field("cwd", stringProperty("Working directory for the agent process (single mode)"), Nil{})))))))), Nil{})))

def decodeTaskItem(value: V.Value) -> Result<&2, &2, Decode.Error, TaskItem>:
  do Result<&2, &2, Decode.Error, TaskItem>:
    +fields : R.Record<V.Value> <- Decode.object(value)
    agent : String <- Decode.required(String, fields, "agent", Decode.string)
    task : String <- Decode.required(String, fields, "task", Decode.string)
    cwd : Maybe<&2, String> <- Decode.optional(String, fields, "cwd", Decode.string)
    return TaskItem{agent, task, cwd}

def scopeFound(found: Maybe<&2, Agents.AgentScope>) -> Result<&2, &2, Decode.Error, Agents.AgentScope>:
  match found:
    case Some{scope}: Done{scope}
    case None{}: Fail{Decode.InvalidValue{Nil{}, "user, project or both"}}

def decodeScope(value: V.Value) -> Result<&2, &2, Decode.Error, Agents.AgentScope>:
  match value:
    case V.Text{name}: scopeFound(Agents.agentScopeOf(name))
    case _: Fail{Decode.WrongType{Nil{}, "string"}}

def decodeItems(value: V.Value) -> Result<&2, &2, Decode.Error, List<&2, TaskItem>>: Decode.list(~TaskItem, ~decodeTaskItem, value)

def decodeParams(value: V.Value) -> Result<&2, &2, Decode.Error, SubagentParams>:
  do Result<&2, &2, Decode.Error, SubagentParams>:
    +fields : R.Record<V.Value> <- Decode.object(value)
    agent : Maybe<&2, String> <- Decode.optional(String, fields, "agent", Decode.string)
    task : Maybe<&2, String> <- Decode.optional(String, fields, "task", Decode.string)
    tasks : Maybe<&2, List<&2, TaskItem>> <- Decode.optional(List<&2, TaskItem>, fields, "tasks", decodeItems)
    chain : Maybe<&2, List<&2, TaskItem>> <- Decode.optional(List<&2, TaskItem>, fields, "chain", decodeItems)
    agentScope : Maybe<&2, Agents.AgentScope> <- Decode.optional(Agents.AgentScope, fields, "agentScope", decodeScope)
    confirm : Maybe<&2, Bool> <- Decode.optional(Bool, fields, "confirmProjectAgents", Json.decodeBoolean)
    cwd : Maybe<&2, String> <- Decode.optional(String, fields, "cwd", Decode.string)
    return SubagentParams{agent, task, tasks, chain, agentScope, confirm, cwd}

def itemsOf(items: Maybe<&2, List<&2, TaskItem>>) -> List<&2, TaskItem>:
  match items:
    case Some{items}: items
    case None{}: Nil{}

def hasItems(items: Maybe<&2, List<&2, TaskItem>>) -> Bool: Bool.not(List.is_empty(&2, TaskItem, itemsOf(items)))

def presentText(value: Maybe<&2, String>) -> Bool: Bool.not(isNone(present(value)))

def countTrue(flags: List<&2, Bool>) -> Nat:
  match flags:
    case Nil{}: 0n
    case flag <> rest: Bool.pick(Nat, flag, 1n, 0n) + countTrue(rest)

# Available and requested agents
# ------------------------------

def availableList(agents: List<&2, Agents.AgentConfig>) -> List<&2, String>:
  match agents:
    case Nil{}: Nil{}
    case Agents.AgentConfig{name, _, _, _, _, source, _} <> rest: (name ++ " (" ++ Agents.agentSourceName(source) ++ ")") <> availableList(rest)

def available(agents: List<&2, Agents.AgentConfig>) -> String: orElse(Some{String.join(availableList(agents), ", ")}, "none")

# The requested agent names in order of first mention: chain steps, tasks,
# then the single agent.
def itemAgents(items: List<&2, TaskItem>) -> List<&2, String>:
  match items:
    case Nil{}: Nil{}
    case TaskItem{agent, _, _} <> rest: agent <> itemAgents(rest)

def singleAgent(agent: Maybe<&2, String>) -> List<&2, String>:
  match agent:
    case Some{""}: Nil{}
    case Some{name}: [name]
    case None{}: Nil{}

def containsName(names: List<&2, String>, +name: String) -> Bool:
  match names:
    case Nil{}: False{}
    case other <> rest: String.eq(other, name) || containsName(rest, name)

def distinctFrom(names: List<&2, String>, +seen: List<&2, String>) -> List<&2, String>:
  match names:
    case Nil{}: Nil{}
    case +name <> +rest: Bool.pick(Unit -> List<&2, String>, containsName(seen, name), _ => distinctFrom(rest, seen), _ => name <> distinctFrom(rest, name <> seen))(Unit{})

def distinct(names: List<&2, String>) -> List<&2, String>: distinctFrom(names, Nil{})

def projectName(agent: Maybe<&2, Agents.AgentConfig>, others: List<&2, String>) -> List<&2, String>:
  match agent:
    case Some{Agents.AgentConfig{name, _, _, _, _, Agents.ProjectSource{}, _}}: name <> others
    case _: others

def projectAgentsRequested(+agents: List<&2, Agents.AgentConfig>, names: List<&2, String>) -> List<&2, String>:
  match names:
    case Nil{}: Nil{}
    case name <> rest: projectName(findAgent(agents, name), projectAgentsRequested(agents, rest))

def requestedNames(params: SubagentParams) -> List<&2, String>:
  match params:
    case SubagentParams{agent, _, tasks, chain, _, _, _}: distinct(List.concat(&2, String, [itemAgents(itemsOf(chain)), itemAgents(itemsOf(tasks)), singleAgent(agent)]))

def includesProject(scope: Agents.AgentScope) -> Bool:
  match scope:
    case Agents.UserScope{}: False{}
    case _: True{}

def canceledMode(+hasChain: Bool, +hasTasks: Bool) -> SubagentMode:
  Bool.pick(SubagentMode, hasChain, ChainMode{}, Bool.pick(SubagentMode, hasTasks, ParallelMode{}, SingleMode{}))

# Chain
# -----

type CallEnv is Data:
  CallEnv{run: RunEnv, scope: DetailsScope, signal: Maybe<&2, Abort.AbortSignal<Unit>>, onUpdate: Maybe<&2, UpdateCallback()>}

def chainTarget(onUpdate: Maybe<&2, UpdateCallback()>, scope: DetailsScope, completed: List<&2, SingleResult>) -> UpdateTarget:
  match onUpdate:
    case None{}: NoUpdates{}
    case Some{callback}: ChainUpdates{callback, scope, completed}

def outputOfLast(found: Maybe<&2, SingleResult>) -> String:
  match found:
    case None{}: "(no output)"
    case Some{result}: orElse(Some{getFinalOutput(messagesOf(result))}, "(no output)")

def lastOutput(results: List<&2, SingleResult>) -> String: outputOfLast(List.last(&2, SingleResult, results))

# After a step: stop with the call's output, or go on with the step's output
# as {previous}.
type ChainNext is Data:
  ChainStop{output: Tools.Output()}
  ChainOn{previous: String, results: List<&2, SingleResult>}

def stepped(outcome: Result<&2, &2, String, SingleResult>, +index: Nat, +agent: String, +scope: DetailsScope, +results: List<&2, SingleResult>) -> ChainNext:
  match outcome:
    case Fail{error}: ChainStop{Fail{Tools.failure(error)}}
    case Done{+result}:
      +all = List.append(&2, SingleResult, results, [result])
      Bool.pick(ChainNext, isFailedResult(result), ChainStop{textResult("Chain stopped at step " ++ Nat.show(index) ++ " (" ++ agent ++ "): " ++ getResultOutput(result), makeDetails(scope, ChainMode{}, all))}, ChainOn{getFinalOutput(messagesOf(result)), all})

def isStop(next: ChainNext) -> Bool:
  match next:
    case ChainStop{_}: True{}
    case ChainOn{_, _}: False{}

def stopOutput(next: ChainNext) -> Tools.Output():
  match next:
    case ChainStop{output}: output
    case ChainOn{_, _}: Fail{Tools.failure("chain continued")}

def nextPrevious(next: ChainNext) -> String:
  match next:
    case ChainOn{previous, _}: previous
    case ChainStop{_}: ""

def nextResults(next: ChainNext) -> List<&2, SingleResult>:
  match next:
    case ChainOn{_, results}: results
    case ChainStop{_}: Nil{}

def envScope(env: CallEnv) -> DetailsScope:
  match env:
    case CallEnv{_, scope, _, _}: scope

def runChain(steps: List<&2, TaskItem>, +env: CallEnv, +index: Nat, +previous: String, +results: List<&2, SingleResult>) -> IO(Tools.Output()):
  match steps:
    case Nil{}: IO.pure(Tools.Output(), textResult(lastOutput(results), makeDetails(envScope(env), ChainMode{}, results)))
    case TaskItem{+agent, task, cwd} <> rest:
      match env:
        case CallEnv{+run, +scope, +signal, +onUpdate}:
          do IO<Tools.Output()>:
            outcome : Result<&2, &2, String, SingleResult> <- runSingleAgent(run, agent, Strings.replaceAll(task, "{previous}", previous), cwd, Some{index}, signal, chainTarget(onUpdate, scope, results))
            +next : ChainNext = stepped(outcome, index, agent, scope, results)
            Bool.pick(Unit -> IO(Tools.Output()), isStop(next), _ => IO.pure(Tools.Output(), stopOutput(next)), _ => runChain(rest, env, index + 1n, nextPrevious(next), nextResults(next)))(Unit{})

# Parallel
# --------
# Up to maxConcurrency workers take the tasks in order (upstream
# mapWithConcurrencyLimit); each task's result lands at its index of the
# shared table, which starts with a waiting placeholder per task.

type Indexed is Data:
  Indexed{index: Nat, item: TaskItem}

type Pool is Data:
  Pool{queue: Ref.Ref<List<&2, Indexed>>, all: Ref.Ref<List<&2, SingleResult>>}

def placeholders(items: List<&2, TaskItem>) -> List<&2, SingleResult>:
  match items:
    case Nil{}: Nil{}
    case TaskItem{agent, task, _} <> rest: SingleResult{agent, UnknownSource{}, task, None{}, Nil{}, "", emptyUsage(), None{}, None{}, None{}, None{}} <> placeholders(rest)

def indexed(items: List<&2, TaskItem>, +index: Nat) -> List<&2, Indexed>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: Indexed{index, item} <> indexed(rest, index + 1n)

def popped(queue: List<&2, Indexed>) -> List<&2, Indexed> & Maybe<&2, Indexed>:
  match queue:
    case Nil{}: (Nil{}, None{})
    case next <> rest: (rest, Some{next})

type WorkStatus is Data:
  Idle{}
  Worked{}
  WorkFailed{error: String}

def stored(outcome: Result<&2, &2, String, SingleResult>, +index: Nat, +env: CallEnv, +all: Ref.Ref<List<&2, SingleResult>>) -> IO(WorkStatus):
  match outcome env:
    case Fail{error} _: IO.pure(WorkStatus, WorkFailed{error})
    case Done{result} CallEnv{_, scope, _, onUpdate}:
      do IO<WorkStatus>:
        storeResult(all, index, result)
        emitParallelUpdate(onUpdate, scope, all)
        return Worked{}

def runNext(next: Maybe<&2, Indexed>, +env: CallEnv, +all: Ref.Ref<List<&2, SingleResult>>) -> IO(WorkStatus):
  match next env:
    case None{} _: IO.pure(WorkStatus, Idle{})
    case Some{Indexed{+index, TaskItem{agent, task, cwd}}} CallEnv{+run, +scope, +signal, +onUpdate}:
      do IO<WorkStatus>:
        outcome : Result<&2, &2, String, SingleResult> <- runSingleAgent(run, agent, task, cwd, None{}, signal, ParallelUpdates{onUpdate, scope, all, index})
        stored(outcome, index, env, all)

def isWorked(status: WorkStatus) -> Bool:
  match status:
    case Worked{}: True{}
    case _: False{}

def statusResult(status: WorkStatus) -> Result<&2, &2, String, Unit>:
  match status:
    case WorkFailed{error}: Fail{error}
    case _: Done{Unit{}}

# The number of tasks bounds how many a worker takes.
def worker(fuel: Nat, +env: CallEnv, +pool: Pool) -> IO(Result<&2, &2, String, Unit>):
  match fuel pool:
    case 0n _: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case 1n+rest Pool{+queue, +all}:
      do IO<Result<&2, &2, String, Unit>>:
        next : Maybe<&2, Indexed> <- Ref.modify(List<&2, Indexed>, Maybe<&2, Indexed>, queue, popped)
        +status : WorkStatus <- runNext(next, env, all)
        Bool.pick(Unit -> IO(Result<&2, &2, String, Unit>), isWorked(status), _ => worker(rest, env, pool), _ => IO.pure(Result<&2, &2, String, Unit>, statusResult(status)))(Unit{})

def forkWorkers(count: Nat, +fuel: Nat, +env: CallEnv, +pool: Pool) -> IO(List<&2, Chan(Result<&2, &2, String, Unit>)>):
  match count:
    case 0n: IO.pure(List<&2, Chan(Result<&2, &2, String, Unit>)>, Nil{})
    case 1n+rest:
      do IO<List<&2, Chan(Result<&2, &2, String, Unit>)>>:
        task : Chan(Result<&2, &2, String, Unit>) <- IO.fork(Result<&2, &2, String, Unit>, worker(fuel, env, pool))
        others : List<&2, Chan(Result<&2, &2, String, Unit>)> <- forkWorkers(rest, fuel, env, pool)
        return task <> others

def firstFailure(first: Result<&2, &2, String, Unit>, rest: Result<&2, &2, String, Unit>) -> Result<&2, &2, String, Unit>:
  match first:
    case Fail{error}: Fail{error}
    case Done{_}: rest

def joinWorkers(tasks: List<&2, Chan(Result<&2, &2, String, Unit>)>) -> IO(Result<&2, &2, String, Unit>):
  match tasks:
    case Nil{}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case +task <> rest:
      do IO<Result<&2, &2, String, Unit>>:
        first : Result<&2, &2, String, Unit> <- IO.join(Result<&2, &2, String, Unit>, task)
        others : Result<&2, &2, String, Unit> <- joinWorkers(rest)
        return firstFailure(first, others)

def failedStatus(stopReason: Maybe<&2, String>) -> String:
  match stopReason:
    case Some{""}: "failed"
    case Some{"end"}: "failed"
    case Some{reason}: "failed (" ++ reason ++ ")"
    case None{}: "failed"

def summary(+result: SingleResult) -> String:
  "### [" ++ resultAgent(result) ++ "] " ++ Bool.pick(String, isFailedResult(result), failedStatus(resultStopReason(result)), "completed") ++ "\n\n" ++ truncateParallelOutput(getResultOutput(result))

def summaries(results: List<&2, SingleResult>) -> List<&2, String>:
  match results:
    case Nil{}: Nil{}
    case result <> rest: summary(result) <> summaries(rest)

def successCount(results: List<&2, SingleResult>) -> Nat:
  match results:
    case Nil{}: 0n
    case result <> rest: Bool.pick(Nat, isFailedResult(result), 0n, 1n) + successCount(rest)

def parallelDone(joined: Result<&2, &2, String, Unit>, +scope: DetailsScope, +results: List<&2, SingleResult>) -> Tools.Output():
  match joined:
    case Fail{error}: Fail{Tools.failure(error)}
    case Done{_}: textResult("Parallel: " ++ Nat.show(successCount(results)) ++ "/" ++ Nat.show(List.length(&2, SingleResult, results)) ++ " succeeded\n\n" ++ String.join(summaries(results), "\n\n---\n\n"), makeDetails(scope, ParallelMode{}, results))

def concurrencyFor(+count: Nat) -> Nat: Bool.pick(Nat, Nat.is_lt(count, maxConcurrency()), count, maxConcurrency())

def runPool(+env: CallEnv, +items: List<&2, TaskItem>) -> IO(Tools.Output()):
  +count = List.length(&2, TaskItem, items)
  do IO<Tools.Output()>:
    +all : Ref.Ref<List<&2, SingleResult>> <- Ref.new(List<&2, SingleResult>, placeholders(items))
    +queue : Ref.Ref<List<&2, Indexed>> <- Ref.new(List<&2, Indexed>, indexed(items, 0n))
    workers : List<&2, Chan(Result<&2, &2, String, Unit>)> <- forkWorkers(concurrencyFor(count), count, env, Pool{queue, all})
    joined : Result<&2, &2, String, Unit> <- joinWorkers(workers)
    results : List<&2, SingleResult> <- Ref.dispose(List<&2, SingleResult>, all)
    remaining : List<&2, Indexed> <- Ref.dispose(List<&2, Indexed>, queue)
    return parallelDone(joined, envScope(env), results)

def runParallel(+env: CallEnv, +items: List<&2, TaskItem>) -> IO(Tools.Output()):
  +count = List.length(&2, TaskItem, items)
  Bool.pick(Unit -> IO(Tools.Output()), Nat.is_lt(maxParallelTasks(), count),
    _ => IO.pure(Tools.Output(), textResult("Too many parallel tasks (" ++ Nat.show(count) ++ "). Max is " ++ Nat.show(maxParallelTasks()) ++ ".", makeDetails(envScope(env), ParallelMode{}, Nil{}))),
    _ => runPool(env, items))(Unit{})

# Single
# ------

def singleTarget(onUpdate: Maybe<&2, UpdateCallback()>, scope: DetailsScope) -> UpdateTarget:
  match onUpdate:
    case None{}: NoUpdates{}
    case Some{callback}: SingleUpdates{callback, scope}

def singleDone(outcome: Result<&2, &2, String, SingleResult>, +scope: DetailsScope) -> Tools.Output():
  match outcome:
    case Fail{error}: Fail{Tools.failure(error)}
    case Done{+result}:
      Bool.pick(Unit -> Tools.Output(), isFailedResult(result),
        _ => textResult("Agent " ++ orElse(resultStopReason(result), "failed") ++ ": " ++ getResultOutput(result), makeDetails(scope, SingleMode{}, [result])),
        _ => textResult(orElse(Some{getFinalOutput(messagesOf(result))}, "(no output)"), makeDetails(scope, SingleMode{}, [result])))(Unit{})

def runSingle(env: CallEnv, +agent: String, +task: String, cwd: Maybe<&2, String>) -> IO(Tools.Output()):
  match env:
    case CallEnv{run, +scope, signal, onUpdate}:
      do IO<Tools.Output()>:
        outcome : Result<&2, &2, String, SingleResult> <- runSingleAgent(run, agent, task, cwd, None{}, signal, singleTarget(onUpdate, scope))
        return singleDone(outcome, scope)

# Execute
# -------

type Selected is Data:
  RunChain{items: List<&2, TaskItem>}
  RunParallel{items: List<&2, TaskItem>}
  RunSingle{agent: String, task: String, cwd: Maybe<&2, String>}
  NoMode{}

def singleSelected(agent: Maybe<&2, String>, task: Maybe<&2, String>, cwd: Maybe<&2, String>) -> Selected:
  match agent task:
    case Some{""} _: NoMode{}
    case _ Some{""}: NoMode{}
    case Some{agent} Some{task}: RunSingle{agent, task, cwd}
    case _ _: NoMode{}

def selectMode(params: SubagentParams) -> Selected:
  match params:
    case SubagentParams{agent, task, +tasks, +chain, _, _, cwd}:
      Bool.pick(Selected, hasItems(chain), RunChain{itemsOf(chain)}, Bool.pick(Selected, hasItems(tasks), RunParallel{itemsOf(tasks)}, singleSelected(agent, task, cwd)))

def runSelected(selected: Selected, +env: CallEnv, agents: List<&2, Agents.AgentConfig>) -> IO(Tools.Output()):
  match selected:
    case RunChain{items}: runChain(items, env, 1n, "", Nil{})
    case RunParallel{items}: runParallel(env, items)
    case RunSingle{agent, task, cwd}: runSingle(env, agent, task, cwd)
    case NoMode{}: IO.pure(Tools.Output(), textResult("Invalid parameters. Available agents: " ++ available(agents), makeDetails(envScope(env), SingleMode{}, Nil{})))

def modeCount(params: SubagentParams) -> Nat:
  match params:
    case SubagentParams{agent, task, tasks, chain, _, _, _}: countTrue([hasItems(chain), hasItems(tasks), presentText(agent) && presentText(task)])

def paramsScope(params: SubagentParams) -> Agents.AgentScope:
  match params:
    case SubagentParams{_, _, _, _, scope, _, _}: Maybe.default(&2, Agents.AgentScope, scope, Agents.UserScope{})

def confirmsProjectAgents(params: SubagentParams) -> Bool:
  match params:
    case SubagentParams{_, _, _, _, _, confirm, _}: Maybe.default(&2, Bool, confirm, True{})

def paramsHaveChain(params: SubagentParams) -> Bool:
  match params:
    case SubagentParams{_, _, _, chain, _, _, _}: hasItems(chain)

def paramsHaveTasks(params: SubagentParams) -> Bool:
  match params:
    case SubagentParams{_, _, tasks, _, _, _, _}: hasItems(tasks)

# upstream's confirmation: when the scope includes project agents,
# confirmation is on, there is a UI and the project is not trusted, the user
# approves the requested project-local agents (if any).
def approval(+needed: Bool, +ctx: Ctx.ExtensionContext, +names: List<&2, String>, projectAgentsDir: Maybe<&2, String>) -> IO(Bool):
  Bool.pick(Unit -> IO(Bool), needed && Bool.not(List.is_empty(&2, String, names)),
    _ => Ctx.confirm(ctx, "Run project-local agents?", "Agents: " ++ String.join(names, ", ") ++ "\nSource: " ++ Maybe.default(&2, String, projectAgentsDir, "(unknown)") ++ "\n\nProject agents are repo-controlled. Only continue for trusted repositories.", Ctx.dialogOptions()),
    _ => IO.pure(Bool, True{}))(Unit{})

def approvedCall(+params: SubagentParams, +env: CallEnv, +agents: List<&2, Agents.AgentConfig>, +ctx: Ctx.ExtensionContext, projectAgentsDir: Maybe<&2, String>) -> IO(Tools.Output()):
  do IO<Tools.Output()>:
    hasUI : Bool <- Ctx.hasUI(ctx)
    trusted : Bool <- Ctx.isProjectTrusted(ctx)
    +ok : Bool <- approval(includesProject(paramsScope(params)) && confirmsProjectAgents(params) && hasUI && Bool.not(trusted), ctx, projectAgentsRequested(agents, requestedNames(params)), projectAgentsDir)
    Bool.pick(Unit -> IO(Tools.Output()), ok,
      _ => runSelected(selectMode(params), env, agents),
      _ => IO.pure(Tools.Output(), textResult("Canceled: project-local agents not approved.", makeDetails(envScope(env), canceledMode(paramsHaveChain(params), paramsHaveTasks(params)), Nil{}))))(Unit{})

def callEnv(run: RunEnv, scope: DetailsScope, signal: Maybe<&2, Abort.AbortSignal<Unit>>, onUpdate: Maybe<&2, UpdateCallback()>) -> CallEnv: CallEnv{run, scope, signal, onUpdate}

def discoveredCall(+params: SubagentParams, discovery: Result<&2, &2, String, Agents.AgentDiscoveryResult>, run: DispatchDefaults, +ctx: Ctx.ExtensionContext, signal: Maybe<&2, Abort.AbortSignal<Unit>>, onUpdate: Maybe<&2, UpdateCallback()>) -> IO(Tools.Output()):
  match discovery:
    case Fail{error}: IO.pure(Tools.Output(), Fail{Tools.failure(error)})
    case Done{Agents.AgentDiscoveryResult{+agents, +projectAgentsDir}}:
      +env = callEnv(RunEnv{Ctx.cwd(ctx), run, agents}, DetailsScope{paramsScope(params), projectAgentsDir}, signal, onUpdate)
      Bool.pick(Unit -> IO(Tools.Output()), Nat.is_eq(modeCount(params), 1n),
        _ => approvedCall(params, env, agents, ctx, projectAgentsDir),
        _ => IO.pure(Tools.Output(), textResult("Invalid parameters. Provide exactly one mode.\nAvailable agents: " ++ available(agents), makeDetails(envScope(env), SingleMode{}, Nil{}))))(Unit{})

def modelReference(model: Maybe<&2, Ai.Model<Ai.JsonValue>>) -> Maybe<&2, String>:
  match model:
    case None{}: None{}
    case Some{+model}: Some{Ai.modelProvider(model) ++ "/" ++ Ai.modelId(model)}

def decodedCall(+agentDir: String, decoded: Result<&2, &2, Decode.Error, SubagentParams>, +ctx: Ctx.ExtensionContext, signal: Maybe<&2, Abort.AbortSignal<Unit>>, onUpdate: Maybe<&2, UpdateCallback()>) -> IO(Tools.Output()):
  match decoded:
    case Fail{error}: IO.pure(Tools.Output(), Fail{Tools.failure("Invalid subagent parameters: " ++ Decode.describe(error))})
    case Done{+params}:
      do IO<Tools.Output()>:
        model : Maybe<&2, Ai.Model<Ai.JsonValue>> <- Ctx.model(ctx)
        thinking : Ai.ModelThinkingLevel <- Ctx.thinkingLevel(ctx)
        discovery : Result<&2, &2, String, Agents.AgentDiscoveryResult> <- Agents.discoverAgents(agentDir, Ctx.cwd(ctx), paramsScope(params))
        discoveredCall(params, discovery, DispatchDefaults{modelReference(model), Some{Levels.name(thinking)}}, ctx, signal, onUpdate)

type ExtensionEnv is Data:
  ExtensionEnv{agentDir: String}

def executeCall(+env: ExtensionEnv, call: Ext.ToolCallInput) -> IO(Tools.Output()):
  match env call:
    case ExtensionEnv{agentDir} Ext.ToolCallInput{Agent.ToolExecutionInput{_, params, signal, onUpdate}, ctx}: decodedCall(agentDir, decodeParams(params), ctx, signal, onUpdate)

def executeSubagent(env: ExtensionEnv, call: Ext.ToolCallInput) -> IO(Tools.Output()): executeCall(env, call)

# Registration
# ------------

def toolDescription(+agentDir: String) -> String:
  String.join(["Delegate tasks to specialized subagents with isolated context.", "Modes: single (agent + task), parallel (tasks array), chain (sequential with {previous} placeholder).", "Default agent scope is \"user\" (from " ++ Path.join(agentDir, "agents") ++ ").", "To enable project-local agents in " ++ Config.configDirName() ++ "/agents, set agentScope: \"both\" (or \"project\")."], " ")

# The extension over an explicit agent directory (upstream reads
# getAgentDir()).
def subagentExtensionWith(+agentDir: String, +api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    execute : Ext.ToolExecute() <- C.create(~ExtensionEnv, ~Ext.ToolCallInput, ~Tools.Output(), ~executeSubagent, ExtensionEnv{agentDir})
    Loader.registerTool(api, Ext.ToolDefinition{"subagent", "Subagent", toolDescription(agentDir), None{}, Nil{}, subagentParams(), None{}, execute})

def registered(located: Config.Located(), +api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  match located:
    case Fail{error}: IO.pure(Result<&2, &2, String, Unit>, Fail{FS.errorMessage(error)})
    case Done{agentDir}: subagentExtensionWith(agentDir, api)

# upstream's default export.
def subagentExtension(+api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    located : Config.Located() <- Config.getAgentDir()
    registered(located, api)
