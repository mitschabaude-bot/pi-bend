import Base
import ./tool-state.bend as ToolState
import ./executable-declaration.bend as Executable
import ./tool-declaration.bend as DeclarationTest
import ../src/utils/tool-declaration.bend as D
import ../../runtime/src/schema-value.bend as S
import ../src/types.bend as T
import ../src/utils/text.bend as Text
import ../src/utils/transcript.bend as Transcript
import ../../runtime/src/record.bend as Record
import ../../runtime/src/f64.bend as N
import ../../runtime/src/u64.bend as U

# Nine cases ported from system-message-replay.test.ts. Schema data matches
# pinned Type.Object({}); the schema builder/validator library remains pending.

def Message() -> Data: T.Message<S.Value, Unit, Unit, Unit>
def Context() -> Data: T.Context<S.Value, Unit, Unit, Unit>
def Normalized() -> Data: T.TranscriptContext<S.Value, Unit, Unit, Unit>

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def sameNumber(a: N.F64, b: N.F64) -> Bool:
  match a b:
    case N.F64{bitsA} N.F64{bitsB}: U.equal(bitsA, bitsB)

def sameSchema(parameters: S.Value) -> Bool:
  S.equal(parameters, ToolState.emptyObjectSchema())

def tool(name: String) -> IO(T.Tool<S.Value>):
  +toolName = name
  IO.pure(T.Tool<S.Value>, T.Tool{toolName, String.join(toolName <> " tool" <> Nil{}, ""), ToolState.emptyObjectSchema(), None{}})

def checkTool(value: T.Tool<S.Value>) -> IO(Unit):
  match value:
    case T.Tool{name, description, parameters, None{}}: assertion(sameSchema(parameters) && String.eq(name, "a") && String.eq(description, "a tool"), "tool declaration changed")
    case _: assertion(False{}, "tool optional fields changed")

def checkHead(value: T.SystemMessage<S.Value>) -> IO(Unit):
  match value:
    case T.SystemMessage{T.SystemText{prompt}, None{}, Some{reference <> Nil{}}, None{}, timestamp}:
      do IO<Unit>:
        assertion(String.eq(prompt, "be brief") && sameNumber(timestamp, N.fromU32(0)), "normalized system prompt/timestamp")
        observed : T.Tool<S.Value> = reference
        checkTool(observed)
    case _: assertion(False{}, "normalized head shape")

def checkUser(value: T.UserMessage, expected: String) -> IO(Unit):
  match value:
    case T.UserMessage{T.UserText{text}, timestamp}: assertion(String.eq(text, expected) && sameNumber(timestamp, N.fromU32(1)), "user message changed")
    case _: assertion(False{}, "user content variant changed")

def checkTail(messages: List<&2, Message()>, expected: String) -> IO(Unit):
  match messages:
    case T.User{reference} <> Nil{}:
      do IO<Unit>:
        value : T.UserMessage = reference
        checkUser(value, expected)
    case _: assertion(False{}, "normalized message list changed")

def checkUnchanged(value: Normalized(), expected: String) -> IO(Unit):
  match value:
    case T.TranscriptContext{messages}: checkTail(messages, expected)

def checkNormalized(value: Normalized()) -> IO(T.SystemMessage<S.Value>):
  match value:
    case T.TranscriptContext{T.System{head} <> tail}:
      do IO<T.SystemMessage<S.Value>>:
        +reference : T.SystemMessage<S.Value> = head
        observed : T.SystemMessage<S.Value> = reference
        checkHead(observed)
        checkTail(tail, "hi")
        return reference
    case _: IO.die(T.SystemMessage<S.Value>, 1, "missing normalized system message")

def normalization() -> IO(Unit):
  do IO<Unit>:
    +user : T.UserMessage = T.UserMessage{T.UserText{"hi"}, N.fromU32(1)}
    +messages : List<&2, Message()> = T.User{user} <> Nil{}
    +plain : Normalized() = Transcript.normalizeContext(S.Value, Unit, Unit, Unit, T.Context{None{}, messages, None{}})
    checkUnchanged(plain, "hi")
    empty : Normalized() = Transcript.normalizeContext(S.Value, Unit, Unit, Unit, T.Context{Some{""}, messages, Some{Nil{}}})
    checkUnchanged(empty, "hi")
    +declaration : T.Tool<S.Value> <- tool("a")
    combined : Normalized() = Transcript.normalizeContext(S.Value, Unit, Unit, Unit, T.Context{Some{"be brief"}, messages, Some{declaration <> Nil{}}})
    head : T.SystemMessage<S.Value> <- checkNormalized(combined)
    previous : T.SystemMessage<S.Value> = head
    # Normalization preserves the immutable input value.
    checkUnchanged(plain, "hi")
    previous : T.Tool<S.Value> = declaration
    previous : T.UserMessage = user
    IO.print("PASS normalizes the legacy prompt and tool fields into a leading system message")

def rendering() -> IO(Unit):
  do IO<Unit>:
    +first : T.Tool<S.Value> <- tool("first")
    +second : T.Tool<S.Value> <- tool("second")
    leadingSections : Record.Record<Maybe<&2, String>> = Record.set(Maybe<&2, String>, Record.set(Maybe<&2, String>, Record.new(Maybe<&2, String>), "a", Some{"<a>1</a>"}), "b", Some{"<b>1</b>"})
    updateSections : Record.Record<Maybe<&2, String>> = Record.set(Maybe<&2, String>, Record.set(Maybe<&2, String>, Record.set(Maybe<&2, String>, Record.new(Maybe<&2, String>), "a", Some{"<a>2</a>"}), "b", None{}), "c", Some{"<c>1</c>"})
    +leading : T.SystemMessage<S.Value> = T.SystemMessage{T.SystemText{"base"}, Some{leadingSections}, Some{first <> Nil{}}, None{}, N.fromU32(10)}
    +update : T.SystemMessage<S.Value> = T.SystemMessage{T.SystemText{""}, Some{updateSections}, Some{second <> Nil{}}, Some{T.ToolReference{"first"} <> Nil{}}, N.fromU32(14)}
    prompt : String <- Text.getSystemMessageText(S.Value, leading)
    assertion(String.eq(prompt, "base\n\n<a>1</a>\n\n<b>1</b>"), "complete system prompt")
    framed : String <- Text.renderSystemMessageUpdate(S.Value, update)
    assertion(String.eq(framed, "Updated system prompt section \"a\":\n\n<a>2</a>\n\nRemoved system prompt section \"b\".\n\nUpdated system prompt section \"c\":\n\n<c>1</c>"), "framed system update")
    previous : T.SystemMessage<S.Value> = leading
    previous : T.SystemMessage<S.Value> = update
    previous : T.Tool<S.Value> = first
    previous : T.Tool<S.Value> = second
    IO.print("PASS renders complete prompts and framed updates")


type Fixture is Data:
  Fixture{messages: List<&2, Message()>, tools: List<&2, T.Tool<S.Value>>, text: T.TextContent, cost: T.UsageCost}

def fixtureMessages(f: Fixture) -> List<&2, Message()>:
  match f:
    case Fixture{messages, _, _, _}: messages

def createFixture() -> IO(Fixture):
  do IO<Fixture>:
    +first : T.Tool<S.Value> <- tool("first")
    +second : T.Tool<S.Value> <- tool("second")
    sections : Record.Record<Maybe<&2, String>> = Record.set(Maybe<&2, String>, Record.set(Maybe<&2, String>, Record.new(Maybe<&2, String>), "a", Some{"<a>1</a>"}), "b", Some{"<b>1</b>"})
    patch : Record.Record<Maybe<&2, String>> = Record.set(Maybe<&2, String>, Record.set(Maybe<&2, String>, Record.set(Maybe<&2, String>, Record.new(Maybe<&2, String>), "a", Some{"<a>2</a>"}), "b", None{}), "c", Some{"<c>1</c>"})
    head : T.SystemMessage<S.Value> = T.SystemMessage{T.SystemText{"base"}, Some{sections}, Some{first <> Nil{}}, None{}, N.fromU32(10)}
    user : T.UserMessage = T.UserMessage{T.UserText{"hello"}, N.fromU32(11)}
    append : T.SystemMessage<S.Value> = T.SystemMessage{T.SystemText{"also do this"}, None{}, None{}, None{}, N.fromU32(12)}
    +text : T.TextContent = T.TextContent{"ok", None{}}
    +zero : N.F64 = N.fromU32(0)
    +cost : T.UsageCost = T.UsageCost{zero, zero, zero, zero, zero}
    contents : List<&2, T.AssistantContent<Unit>> = T.AssistantText{text} <> Nil{}
    usage : T.Usage = T.Usage{zero, zero, zero, zero, None{}, None{}, zero, cost}
    assistant : T.AssistantMessage<Unit, Unit> = T.AssistantMessage{contents, "", "", "", None{}, None{}, None{}, None{}, usage, T.Stop{}, None{}, None{}, None{}, None{}, N.fromU32(13)}
    last : T.SystemMessage<S.Value> = T.SystemMessage{T.SystemText{""}, Some{patch}, Some{second <> Nil{}}, Some{T.ToolReference{"first"} <> Nil{}}, N.fromU32(14)}
    return Fixture{T.System{head} <> T.User{user} <> T.System{append} <> T.Assistant{assistant} <> T.System{last} <> Nil{}, first <> second <> Nil{}, text, cost}

def disposeAssistantContent(value: T.AssistantMessage<Unit, Unit>) -> IO(Unit):
  match value:
    case T.AssistantMessage{contents, _, _, _, _, _, _, _, usage, _, _, _, _, _, _}:
      do IO<Unit>:
        old : List<&2, T.AssistantContent<Unit>> = contents
        oldUsage : T.Usage = usage
        return Unit{}

def disposeMessages(messages: List<&2, Message()>) -> IO(Unit):
  match messages:
    case Nil{}: IO.pure(Unit, Unit{})
    case T.System{reference} <> rest:
      do IO<Unit>:
        previous : T.SystemMessage<S.Value> = reference
        disposeMessages(rest)
    case T.User{reference} <> rest:
      do IO<Unit>:
        previous : T.UserMessage = reference
        disposeMessages(rest)
    case T.Assistant{reference} <> rest:
      do IO<Unit>:
        previous : T.AssistantMessage<Unit, Unit> = reference
        disposeAssistantContent(previous)
        disposeMessages(rest)
    case T.ToolResult{reference} <> rest:
      do IO<Unit>:
        previous : T.ToolResultMessage<Unit> = reference
        disposeMessages(rest)

def disposeTools(tools: List<&2, T.Tool<S.Value>>) -> IO(Unit):
  match tools:
    case Nil{}: IO.pure(Unit, Unit{})
    case reference <> rest:
      do IO<Unit>:
        previous : T.Tool<S.Value> = reference
        disposeTools(rest)

def disposeFixture(f: Fixture) -> IO(Unit):
  match f:
    case Fixture{messages, tools, text, cost}:
      do IO<Unit>:
        disposeMessages(messages)
        disposeTools(tools)
        previous : T.TextContent = text
        previous : T.UsageCost = cost
        return Unit{}

def checkNamedTool(value: T.Tool<S.Value>, +expected: String) -> IO(Unit):
  match value:
    case T.Tool{name, description, parameters, None{}}: assertion(sameSchema(parameters) && String.eq(name, expected) && String.eq(description, String.join(expected <> " tool" <> Nil{}, "")), "replayed tool declaration")
    case _: assertion(False{}, "replayed tool fields changed")

def checkSections(fields: List<&2, Record.Property<Maybe<&2, String>>>) -> IO(Unit):
  match fields:
    case Record.Property{a, Some{first}} <> Record.Property{c, Some{second}} <> Nil{}:
      assertion(String.eq(a, "a") && String.eq(first, "<a>2</a>") && String.eq(c, "c") && String.eq(second, "<c>1</c>"), "replayed section values/order")
    case _: assertion(False{}, "deleted section retained or output fields missing")

def checkReplay(value: T.SystemMessage<S.Value>) -> IO(Unit):
  match value:
    case T.SystemMessage{T.SystemText{content}, Some{sections}, Some{reference <> Nil{}}, None{}, timestamp}:
      do IO<Unit>:
        assertion(String.eq(content, "base\n\nalso do this") && sameNumber(timestamp, N.fromU32(10)), "replayed content/first timestamp")
        checkSections(Record.entries(Maybe<&2, String>, sections))
        observed : T.Tool<S.Value> = reference
        checkNamedTool(observed, "second")
    case _: assertion(False{}, "replayed message shape")

def checkCurrent(value: Maybe<&2, T.SystemMessage<S.Value>>) -> IO(Unit):
  match value:
    case None{}: assertion(False{}, "missing replayed message")
    case Some{reference}:
      do IO<Unit>:
        message : T.SystemMessage<S.Value> = reference
        checkReplay(message)

def checkReplayUser(value: T.UserMessage) -> IO(Unit):
  match value:
    case T.UserMessage{T.UserText{text}, timestamp}: assertion(String.eq(text, "hello") && sameNumber(timestamp, N.fromU32(11)), "collapsed user fields changed")
    case _: assertion(False{}, "collapsed user content changed")

def checkReplayText(value: T.TextContent) -> IO(Unit):
  match value:
    case T.TextContent{text, None{}}: assertion(String.eq(text, "ok"), "collapsed assistant text changed")
    case _: assertion(False{}, "collapsed assistant text signature changed")

def checkReplayContents(value: List<&2, T.AssistantContent<Unit>>, timestamp: N.F64) -> IO(Unit):
  match value:
    case T.AssistantText{text} <> Nil{}:
      do IO<Unit>:
        assertion(sameNumber(timestamp, N.fromU32(13)), "collapsed assistant timestamp changed")
        content : T.TextContent = text
        checkReplayText(content)
    case _: assertion(False{}, "collapsed assistant content changed")

def checkReplayAssistant(value: T.AssistantMessage<Unit, Unit>) -> IO(Unit):
  match value:
    case T.AssistantMessage{contents, _, _, _, _, _, _, _, _, _, _, _, _, _, timestamp}:
      do IO<Unit>:
        value : List<&2, T.AssistantContent<Unit>> = contents
        checkReplayContents(value, timestamp)

def checkCollapsed(value: Normalized()) -> IO(Unit):
  match value:
    case T.TranscriptContext{T.System{head} <> T.User{user} <> T.Assistant{assistant} <> Nil{}}:
      do IO<Unit>:
        message : T.SystemMessage<S.Value> = head
        checkReplay(message)
        userValue : T.UserMessage = user
        checkReplayUser(userValue)
        assistantValue : T.AssistantMessage<Unit, Unit> = assistant
        checkReplayAssistant(assistantValue)
    case _: assertion(False{}, "collapse must preserve user/assistant order")

def disposeCollapsedHead(value: Normalized()) -> IO(Unit):
  match value:
    case T.TranscriptContext{T.System{head} <> _}:
      do IO<Unit>:
        previous : T.SystemMessage<S.Value> = head
        return Unit{}
    case _: IO.pure(Unit, Unit{})

def checkUncollapsed(value: Normalized()) -> IO(Unit):
  match value:
    case T.TranscriptContext{T.System{_} <> T.User{_} <> T.System{_} <> T.Assistant{_} <> T.System{_} <> Nil{}}: IO.pure(Unit, Unit{})
    case _: assertion(False{}, "supported mid-conversation system messages must stay in place")

def replayAndCollapse() -> IO(Unit):
  do IO<Unit>:
    +f : Fixture <- createFixture()
    +messages : List<&2, Message()> = fixtureMessages(f)
    current : Maybe<&2, T.SystemMessage<S.Value>> = Transcript.getCurrentSystemMessage(S.Value, Unit, Unit, Unit, messages)
    checkCurrent(current)
    prompt : String = Transcript.getCurrentSystemPrompt(S.Value, Unit, Unit, Unit, messages)
    assertion(String.eq(prompt, "base\n\nalso do this\n\n<a>2</a>\n\n<c>1</c>"), "current system prompt")
    IO.print("PASS replays content, sections, and tools into one leading message")
    +collapsed : Normalized() = Transcript.collapseSystemMessages(S.Value, Unit, Unit, Unit, T.TranscriptContext{messages})
    checkCollapsed(collapsed)
    +again : Normalized() = Transcript.collapseSystemMessages(S.Value, Unit, Unit, Unit, collapsed)
    checkCollapsed(again)
    unchanged : Normalized() = Transcript.resolveTranscript(S.Value, Unit, Unit, Unit, T.TranscriptContext{messages}, Some{True{}})
    checkUncollapsed(unchanged)
    +fallback : Normalized() = Transcript.resolveTranscript(S.Value, Unit, Unit, Unit, T.TranscriptContext{messages}, None{})
    checkCollapsed(fallback)
    disposeCollapsedHead(fallback)
    disposeCollapsedHead(collapsed)
    disposeCollapsedHead(again)
    disposeFixture(f)
    IO.print("PASS collapse keeps only non-system messages after the replayed head")

def expectAbsent(value: Maybe<&2, T.SystemMessage<S.Value>>) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit, Unit{})
    case Some{reference}:
      do IO<Unit>:
        previous : T.SystemMessage<S.Value> = reference
        assertion(False{}, "unexpected system message")

def noSystem() -> IO(Unit):
  do IO<Unit>:
    +user : T.UserMessage = T.UserMessage{T.UserText{"hi"}, N.fromU32(1)}
    +context : Normalized() = Transcript.normalizeContext(S.Value, Unit, Unit, Unit, T.Context{None{}, T.User{user} <> Nil{}, None{}})
    current : Maybe<&2, T.SystemMessage<S.Value>> = Transcript.getCurrentSystemMessage(S.Value, Unit, Unit, Unit, T.User{user} <> Nil{})
    expectAbsent(current)
    prompt : String = Transcript.getCurrentSystemPrompt(S.Value, Unit, Unit, Unit, T.User{user} <> Nil{})
    assertion(String.eq(prompt, ""), "no-system prompt must be empty")
    collapsed : Normalized() = Transcript.collapseSystemMessages(S.Value, Unit, Unit, Unit, context)
    checkUnchanged(collapsed, "hi")
    previous : T.UserMessage = user
    IO.print("PASS replay of a transcript without system messages is empty")

def checkLateTool(value: T.SystemMessage<S.Value>) -> IO(Unit):
  match value:
    case T.SystemMessage{_, _, Some{reference <> Nil{}}, _, _}:
      do IO<Unit>:
        observed : T.Tool<S.Value> = reference
        checkNamedTool(observed, "x")
    case _: assertion(False{}, "late patch tool missing")

def checkLateHead(value: Normalized()) -> IO(Unit):
  match value:
    case T.TranscriptContext{T.System{head} <> tail}:
      do IO<Unit>:
        observed : T.SystemMessage<S.Value> = head
        checkLateTool(observed)
        checkTail(tail, "old session")
    case _: assertion(False{}, "late patch did not become the leading system message")

def latePatch() -> IO(Unit):
  do IO<Unit>:
    +user : T.UserMessage = T.UserMessage{T.UserText{"old session"}, N.fromU32(1)}
    +declaration : T.Tool<S.Value> <- tool("x")
    +patch : T.SystemMessage<S.Value> = T.SystemMessage{T.SystemText{""}, Some{Record.set(Maybe<&2, String>, Record.new(Maybe<&2, String>), "preamble", Some{"You are pi."})}, Some{declaration <> Nil{}}, None{}, N.fromU32(2)}
    +messages : List<&2, Message()> = T.User{user} <> T.System{patch} <> Nil{}
    context : Normalized() = Transcript.normalizeContext(S.Value, Unit, Unit, Unit, T.Context{None{}, messages, None{}})
    prompt : String = Transcript.getCurrentSystemPrompt(S.Value, Unit, Unit, Unit, messages)
    assertion(String.eq(prompt, "You are pi."), "late prompt patch")
    collapsed : Normalized() = Transcript.collapseSystemMessages(S.Value, Unit, Unit, Unit, context)
    checkLateHead(collapsed)
    previous : T.UserMessage = user
    previous : T.SystemMessage<S.Value> = patch
    previous : T.Tool<S.Value> = declaration
    IO.print("PASS a late full patch on a transcript without a leading message replays as the prompt")

def contextMessages(context: Normalized()) -> List<&2, Message()>:
  match context:
    case T.TranscriptContext{messages}: messages

def toolHistory() -> IO(Unit):
  do IO<Unit>:
    +f : Fixture <- createFixture()
    nonAdditive : Bool = Transcript.hasNonAdditiveToolChanges(S.Value, Unit, Unit, Unit, fixtureMessages(f))
    assertion(nonAdditive, "original transcript must be non-additive")
    redefined : D.DeclarationResult<Bool> = Transcript.hasToolRedefinitions(Unit, Unit, Unit, fixtureMessages(f))
    assertion(DeclarationTest.sameBool(redefined, D.Success{False{}}), "original transcript must have no redefinitions")
    disposeFixture(f)
    +a : T.Tool<S.Value> <- tool("a")
    +b : T.Tool<S.Value> <- tool("b")
    +changed : T.Tool<S.Value> = ToolState.tool("a", "changed")
    +first : T.SystemMessage<S.Value> = T.SystemMessage{T.SystemText{""}, None{}, Some{a <> Nil{}}, None{}, N.fromU32(1)}
    +second : T.SystemMessage<S.Value> = T.SystemMessage{T.SystemText{""}, None{}, Some{b <> Nil{}}, None{}, N.fromU32(2)}
    +replacement : T.SystemMessage<S.Value> = T.SystemMessage{T.SystemText{""}, None{}, Some{changed <> Nil{}}, None{}, N.fromU32(2)}
    additive : Normalized() = Transcript.normalizeContext(S.Value, Unit, Unit, Unit, T.Context{None{}, T.System{first} <> T.System{second} <> Nil{}, None{}})
    nonAdditive : Bool = Transcript.hasNonAdditiveToolChanges(S.Value, Unit, Unit, Unit, contextMessages(additive))
    assertion(Bool.not(nonAdditive), "distinct added names must be additive")
    +redeclared : Normalized() = Transcript.normalizeContext(S.Value, Unit, Unit, Unit, T.Context{None{}, T.System{first} <> T.System{replacement} <> Nil{}, None{}})
    nonAdditive : Bool = Transcript.hasNonAdditiveToolChanges(S.Value, Unit, Unit, Unit, contextMessages(redeclared))
    assertion(nonAdditive, "same-name redeclaration must be non-additive")
    redefined : D.DeclarationResult<Bool> = Transcript.hasToolRedefinitions(Unit, Unit, Unit, contextMessages(redeclared))
    assertion(DeclarationTest.sameBool(redefined, D.Success{True{}}), "changed same-name declaration must be a redefinition")
    disposeMessages(T.System{first} <> T.System{second} <> T.System{replacement} <> Nil{})
    disposeTools(a <> b <> changed <> Nil{})
    IO.print("PASS detects non-additive tool history and redefinitions")

def main() -> IO(Unit):
  do IO<Unit>:
    normalization()
    rendering()
    replayAndCollapse()
    noSystem()
    latePatch()
    ToolState.upstreamCase()
    toolHistory()
    Executable.upstreamCase()
