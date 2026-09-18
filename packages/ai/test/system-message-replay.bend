import Base
import ./transcript-snapshot.bend as Snapshot
import ./tool-state.bend as ToolState
import ./executable-declaration.bend as Executable
import ./tool-declaration.bend as DeclarationTest
import ../src/utils/tool-declaration.bend as D
import ../../runtime/src/schema-value.bend as S
import ../../runtime/test/schema-value.bend as SchemaCheck
import ../src/types.bend as T
import ../src/utils/text.bend as Text
import ../src/utils/transcript.bend as Transcript
import ../../runtime/src/ref.bend as Ref
import ../../runtime/src/record.bend as Record
import ../../runtime/src/f64.bend as N
import ../../runtime/src/u64.bend as U

# Nine cases ported from system-message-replay.test.ts. Schema data matches
# pinned Type.Object({}); the schema builder/validator library remains pending.

def Message() -> Data: T.Message<S.Value<U32>, Unit, Unit, Unit>
def Context() -> Data: Snapshot.Context<S.Value<U32>, Unit, Unit, Unit>
def Normalized() -> Data: Snapshot.TranscriptContext<S.Value<U32>, Unit, Unit, Unit>

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def sameNumber(a: N.F64, b: N.F64) -> Bool:
  match a b:
    case N.F64{bitsA} N.F64{bitsB}: U.equal(bitsA, bitsB)

def sameSchema(parameters: S.Value<U32>) -> Bool:
  SchemaCheck.same(S.snapshot(U32, parameters), S.snapshot(U32, ToolState.emptyObjectSchema()))

def tool(name: String) -> IO(Ref.Ref<T.Tool<S.Value<U32>>>):
  +toolName = name
  Ref.new(T.Tool<S.Value<U32>>, T.Tool{toolName, String.join(toolName <> " tool" <> Nil{}, ""), ToolState.emptyObjectSchema(), None{}})

def checkTool(value: T.Tool<S.Value<U32>>) -> IO(Unit):
  match value:
    case T.Tool{name, description, parameters, None{}}: assertion(sameSchema(parameters) && String.eq(name, "a") && String.eq(description, "a tool"), "tool declaration changed")
    case _: assertion(False{}, "tool optional fields changed")

def checkHead(value: T.SystemMessage<S.Value<U32>>) -> IO(Unit):
  match value:
    case T.SystemMessage{T.SystemText{prompt}, None{}, Some{reference <> Nil{}}, None{}, timestamp}:
      do IO<Unit>:
        assertion(String.eq(prompt, "be brief") && sameNumber(timestamp, N.fromU32(0)), "normalized system prompt/timestamp")
        observed : T.Tool<S.Value<U32>> <- Ref.read(T.Tool<S.Value<U32>>, reference)
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
        value : T.UserMessage <- Ref.read(T.UserMessage, reference)
        checkUser(value, expected)
    case _: assertion(False{}, "normalized message list changed")

def checkUnchanged(value: Normalized(), expected: String) -> IO(Unit):
  match value:
    case Snapshot.TranscriptContext{messages}: checkTail(messages, expected)

def checkNormalized(value: Normalized()) -> IO(Ref.Ref<T.SystemMessage<S.Value<U32>>>):
  match value:
    case Snapshot.TranscriptContext{T.System{head} <> tail}:
      do IO<Ref.Ref<T.SystemMessage<S.Value<U32>>>>:
        +reference : Ref.Ref<T.SystemMessage<S.Value<U32>>> = head
        observed : T.SystemMessage<S.Value<U32>> <- Ref.read(T.SystemMessage<S.Value<U32>>, reference)
        checkHead(observed)
        checkTail(tail, "hi")
        return reference
    case _: IO.die(Ref.Ref<T.SystemMessage<S.Value<U32>>>, 1, "missing normalized system message")

def normalization() -> IO(Unit):
  do IO<Unit>:
    +user : Ref.Ref<T.UserMessage> <- Ref.new(T.UserMessage, T.UserMessage{T.UserText{"hi"}, N.fromU32(1)})
    +messages : List<&2, Message()> = T.User{user} <> Nil{}
    +plain : Normalized() <- Snapshot.normalizeContext(S.Value<U32>, Unit, Unit, Unit, Snapshot.Context{None{}, messages, None{}})
    checkUnchanged(plain, "hi")
    empty : Normalized() <- Snapshot.normalizeContext(S.Value<U32>, Unit, Unit, Unit, Snapshot.Context{Some{""}, messages, Some{Nil{}}})
    checkUnchanged(empty, "hi")
    +declaration : Ref.Ref<T.Tool<S.Value<U32>>> <- tool("a")
    combined : Normalized() <- Snapshot.normalizeContext(S.Value<U32>, Unit, Unit, Unit, Snapshot.Context{Some{"be brief"}, messages, Some{declaration <> Nil{}}})
    head : Ref.Ref<T.SystemMessage<S.Value<U32>>> <- checkNormalized(combined)
    previous : T.SystemMessage<S.Value<U32>> <- Ref.dispose(T.SystemMessage<S.Value<U32>>, head)
    # Supplemental identity assertion: normalization retains original messages.
    Ref.write(T.UserMessage, user, T.UserMessage{T.UserText{"changed"}, N.fromU32(1)})
    checkUnchanged(plain, "changed")
    previous : T.Tool<S.Value<U32>> <- Ref.dispose(T.Tool<S.Value<U32>>, declaration)
    previous : T.UserMessage <- Ref.dispose(T.UserMessage, user)
    IO.print("PASS normalizes the legacy prompt and tool fields into a leading system message")

def rendering() -> IO(Unit):
  do IO<Unit>:
    +first : Ref.Ref<T.Tool<S.Value<U32>>> <- tool("first")
    +second : Ref.Ref<T.Tool<S.Value<U32>>> <- tool("second")
    leadingSections : Record.Record<Maybe<&2, String>> = Record.set(Maybe<&2, String>, Record.set(Maybe<&2, String>, Record.new(Maybe<&2, String>), "a", Some{"<a>1</a>"}), "b", Some{"<b>1</b>"})
    updateSections : Record.Record<Maybe<&2, String>> = Record.set(Maybe<&2, String>, Record.set(Maybe<&2, String>, Record.set(Maybe<&2, String>, Record.new(Maybe<&2, String>), "a", Some{"<a>2</a>"}), "b", None{}), "c", Some{"<c>1</c>"})
    +leading : Ref.Ref<T.SystemMessage<S.Value<U32>>> <- Ref.new(T.SystemMessage<S.Value<U32>>, T.SystemMessage{T.SystemText{"base"}, Some{leadingSections}, Some{first <> Nil{}}, None{}, N.fromU32(10)})
    +update : Ref.Ref<T.SystemMessage<S.Value<U32>>> <- Ref.new(T.SystemMessage<S.Value<U32>>, T.SystemMessage{T.SystemText{""}, Some{updateSections}, Some{second <> Nil{}}, Some{T.ToolReference{"first"} <> Nil{}}, N.fromU32(14)})
    prompt : String <- Text.getSystemMessageText(S.Value<U32>, leading)
    assertion(String.eq(prompt, "base\n\n<a>1</a>\n\n<b>1</b>"), "complete system prompt")
    framed : String <- Text.renderSystemMessageUpdate(S.Value<U32>, update)
    assertion(String.eq(framed, "Updated system prompt section \"a\":\n\n<a>2</a>\n\nRemoved system prompt section \"b\".\n\nUpdated system prompt section \"c\":\n\n<c>1</c>"), "framed system update")
    previous : T.SystemMessage<S.Value<U32>> <- Ref.dispose(T.SystemMessage<S.Value<U32>>, leading)
    previous : T.SystemMessage<S.Value<U32>> <- Ref.dispose(T.SystemMessage<S.Value<U32>>, update)
    previous : T.Tool<S.Value<U32>> <- Ref.dispose(T.Tool<S.Value<U32>>, first)
    previous : T.Tool<S.Value<U32>> <- Ref.dispose(T.Tool<S.Value<U32>>, second)
    IO.print("PASS renders complete prompts and framed updates")


type Fixture is Data:
  Fixture{messages: List<&2, Message()>, tools: List<&2, Ref.Ref<T.Tool<S.Value<U32>>>>, text: Ref.Ref<T.TextContent>, cost: Ref.Ref<T.UsageCost>}

def fixtureMessages(f: Fixture) -> List<&2, Message()>:
  match f:
    case Fixture{messages, _, _, _}: messages

def createFixture() -> IO(Fixture):
  do IO<Fixture>:
    +first : Ref.Ref<T.Tool<S.Value<U32>>> <- tool("first")
    +second : Ref.Ref<T.Tool<S.Value<U32>>> <- tool("second")
    sections : Record.Record<Maybe<&2, String>> = Record.set(Maybe<&2, String>, Record.set(Maybe<&2, String>, Record.new(Maybe<&2, String>), "a", Some{"<a>1</a>"}), "b", Some{"<b>1</b>"})
    patch : Record.Record<Maybe<&2, String>> = Record.set(Maybe<&2, String>, Record.set(Maybe<&2, String>, Record.set(Maybe<&2, String>, Record.new(Maybe<&2, String>), "a", Some{"<a>2</a>"}), "b", None{}), "c", Some{"<c>1</c>"})
    head : Ref.Ref<T.SystemMessage<S.Value<U32>>> <- Ref.new(T.SystemMessage<S.Value<U32>>, T.SystemMessage{T.SystemText{"base"}, Some{sections}, Some{first <> Nil{}}, None{}, N.fromU32(10)})
    user : Ref.Ref<T.UserMessage> <- Ref.new(T.UserMessage, T.UserMessage{T.UserText{"hello"}, N.fromU32(11)})
    append : Ref.Ref<T.SystemMessage<S.Value<U32>>> <- Ref.new(T.SystemMessage<S.Value<U32>>, T.SystemMessage{T.SystemText{"also do this"}, None{}, None{}, None{}, N.fromU32(12)})
    +text : Ref.Ref<T.TextContent> <- Ref.new(T.TextContent, T.TextContent{"ok", None{}})
    +zero : N.F64 = N.fromU32(0)
    +cost : Ref.Ref<T.UsageCost> <- Ref.new(T.UsageCost, T.UsageCost{zero, zero, zero, zero, zero})
    assistant : Ref.Ref<T.AssistantMessage<Unit, Unit>> <- Ref.new(T.AssistantMessage<Unit, Unit>, T.AssistantMessage{T.AssistantText{text} <> Nil{}, "", "", "", None{}, None{}, None{}, None{}, T.Usage{zero, zero, zero, zero, None{}, None{}, zero, cost}, T.Stop{}, None{}, None{}, None{}, None{}, N.fromU32(13)})
    last : Ref.Ref<T.SystemMessage<S.Value<U32>>> <- Ref.new(T.SystemMessage<S.Value<U32>>, T.SystemMessage{T.SystemText{""}, Some{patch}, Some{second <> Nil{}}, Some{T.ToolReference{"first"} <> Nil{}}, N.fromU32(14)})
    return Fixture{T.System{head} <> T.User{user} <> T.System{append} <> T.Assistant{assistant} <> T.System{last} <> Nil{}, first <> second <> Nil{}, text, cost}

def disposeMessages(messages: List<&2, Message()>) -> IO(Unit):
  match messages:
    case Nil{}: IO.pure(Unit, Unit{})
    case T.System{reference} <> rest:
      do IO<Unit>:
        previous : T.SystemMessage<S.Value<U32>> <- Ref.dispose(T.SystemMessage<S.Value<U32>>, reference)
        disposeMessages(rest)
    case T.User{reference} <> rest:
      do IO<Unit>:
        previous : T.UserMessage <- Ref.dispose(T.UserMessage, reference)
        disposeMessages(rest)
    case T.Assistant{reference} <> rest:
      do IO<Unit>:
        previous : T.AssistantMessage<Unit, Unit> <- Ref.dispose(T.AssistantMessage<Unit, Unit>, reference)
        disposeMessages(rest)
    case T.ToolResult{reference} <> rest:
      do IO<Unit>:
        previous : T.ToolResultMessage<Unit> <- Ref.dispose(T.ToolResultMessage<Unit>, reference)
        disposeMessages(rest)

def disposeTools(tools: List<&2, Ref.Ref<T.Tool<S.Value<U32>>>>) -> IO(Unit):
  match tools:
    case Nil{}: IO.pure(Unit, Unit{})
    case reference <> rest:
      do IO<Unit>:
        previous : T.Tool<S.Value<U32>> <- Ref.dispose(T.Tool<S.Value<U32>>, reference)
        disposeTools(rest)

def disposeFixture(f: Fixture) -> IO(Unit):
  match f:
    case Fixture{messages, tools, text, cost}:
      do IO<Unit>:
        disposeMessages(messages)
        disposeTools(tools)
        previous : T.TextContent <- Ref.dispose(T.TextContent, text)
        previous : T.UsageCost <- Ref.dispose(T.UsageCost, cost)
        return Unit{}

def checkNamedTool(value: T.Tool<S.Value<U32>>, +expected: String) -> IO(Unit):
  match value:
    case T.Tool{name, description, parameters, None{}}: assertion(sameSchema(parameters) && String.eq(name, expected) && String.eq(description, String.join(expected <> " tool" <> Nil{}, "")), "replayed tool declaration")
    case _: assertion(False{}, "replayed tool fields changed")

def checkSections(fields: List<&2, Record.Property<Maybe<&2, String>>>) -> IO(Unit):
  match fields:
    case Record.Property{a, Some{first}} <> Record.Property{c, Some{second}} <> Nil{}:
      assertion(String.eq(a, "a") && String.eq(first, "<a>2</a>") && String.eq(c, "c") && String.eq(second, "<c>1</c>"), "replayed section values/order")
    case _: assertion(False{}, "deleted section retained or output fields missing")

def checkReplay(value: T.SystemMessage<S.Value<U32>>) -> IO(Unit):
  match value:
    case T.SystemMessage{T.SystemText{content}, Some{sections}, Some{reference <> Nil{}}, None{}, timestamp}:
      do IO<Unit>:
        assertion(String.eq(content, "base\n\nalso do this") && sameNumber(timestamp, N.fromU32(10)), "replayed content/first timestamp")
        checkSections(Record.entries(Maybe<&2, String>, sections))
        observed : T.Tool<S.Value<U32>> <- Ref.read(T.Tool<S.Value<U32>>, reference)
        checkNamedTool(observed, "second")
    case _: assertion(False{}, "replayed message shape")

def checkCurrent(value: Maybe<&2, Ref.Ref<T.SystemMessage<S.Value<U32>>>>) -> IO(Unit):
  match value:
    case None{}: assertion(False{}, "missing replayed message")
    case Some{reference}:
      do IO<Unit>:
        message : T.SystemMessage<S.Value<U32>> <- Ref.dispose(T.SystemMessage<S.Value<U32>>, reference)
        checkReplay(message)

def checkReplayUser(value: T.UserMessage) -> IO(Unit):
  match value:
    case T.UserMessage{T.UserText{text}, timestamp}: assertion(String.eq(text, "hello") && sameNumber(timestamp, N.fromU32(11)), "collapsed user fields changed")
    case _: assertion(False{}, "collapsed user content changed")

def checkReplayText(value: T.TextContent) -> IO(Unit):
  match value:
    case T.TextContent{text, None{}}: assertion(String.eq(text, "ok"), "collapsed assistant text changed")
    case _: assertion(False{}, "collapsed assistant text signature changed")

def checkReplayAssistant(value: T.AssistantMessage<Unit, Unit>) -> IO(Unit):
  match value:
    case T.AssistantMessage{T.AssistantText{text} <> Nil{}, _, _, _, _, _, _, _, _, _, _, _, _, _, timestamp}:
      do IO<Unit>:
        assertion(sameNumber(timestamp, N.fromU32(13)), "collapsed assistant timestamp changed")
        content : T.TextContent <- Ref.read(T.TextContent, text)
        checkReplayText(content)
    case _: assertion(False{}, "collapsed assistant content changed")

def checkCollapsed(value: Normalized()) -> IO(Unit):
  match value:
    case Snapshot.TranscriptContext{T.System{head} <> T.User{user} <> T.Assistant{assistant} <> Nil{}}:
      do IO<Unit>:
        message : T.SystemMessage<S.Value<U32>> <- Ref.read(T.SystemMessage<S.Value<U32>>, head)
        checkReplay(message)
        userValue : T.UserMessage <- Ref.read(T.UserMessage, user)
        checkReplayUser(userValue)
        assistantValue : T.AssistantMessage<Unit, Unit> <- Ref.read(T.AssistantMessage<Unit, Unit>, assistant)
        checkReplayAssistant(assistantValue)
    case _: assertion(False{}, "collapse must preserve user/assistant order")

def disposeCollapsedHead(value: Normalized()) -> IO(Unit):
  match value:
    case Snapshot.TranscriptContext{T.System{head} <> _}:
      do IO<Unit>:
        previous : T.SystemMessage<S.Value<U32>> <- Ref.dispose(T.SystemMessage<S.Value<U32>>, head)
        return Unit{}
    case _: IO.pure(Unit, Unit{})

def checkUncollapsed(value: Normalized()) -> IO(Unit):
  match value:
    case Snapshot.TranscriptContext{T.System{_} <> T.User{_} <> T.System{_} <> T.Assistant{_} <> T.System{_} <> Nil{}}: IO.pure(Unit, Unit{})
    case _: assertion(False{}, "supported mid-conversation system messages must stay in place")

def replayAndCollapse() -> IO(Unit):
  do IO<Unit>:
    +f : Fixture <- createFixture()
    +messages : List<&2, Message()> = fixtureMessages(f)
    current : Maybe<&2, Ref.Ref<T.SystemMessage<S.Value<U32>>>> <- Transcript.getCurrentSystemMessage(S.Value<U32>, Unit, Unit, Unit, messages)
    checkCurrent(current)
    prompt : String <- Transcript.getCurrentSystemPrompt(S.Value<U32>, Unit, Unit, Unit, messages)
    assertion(String.eq(prompt, "base\n\nalso do this\n\n<a>2</a>\n\n<c>1</c>"), "current system prompt")
    IO.print("PASS replays content, sections, and tools into one leading message")
    +collapsed : Normalized() <- Snapshot.collapseSystemMessages(S.Value<U32>, Unit, Unit, Unit, Snapshot.TranscriptContext{messages})
    checkCollapsed(collapsed)
    +again : Normalized() <- Snapshot.collapseSystemMessages(S.Value<U32>, Unit, Unit, Unit, collapsed)
    checkCollapsed(again)
    unchanged : Normalized() <- Snapshot.resolveTranscript(S.Value<U32>, Unit, Unit, Unit, Snapshot.TranscriptContext{messages}, Some{True{}})
    checkUncollapsed(unchanged)
    +fallback : Normalized() <- Snapshot.resolveTranscript(S.Value<U32>, Unit, Unit, Unit, Snapshot.TranscriptContext{messages}, None{})
    checkCollapsed(fallback)
    disposeCollapsedHead(fallback)
    disposeCollapsedHead(collapsed)
    disposeCollapsedHead(again)
    disposeFixture(f)
    IO.print("PASS collapse keeps only non-system messages after the replayed head")

def expectAbsent(value: Maybe<&2, Ref.Ref<T.SystemMessage<S.Value<U32>>>>) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit, Unit{})
    case Some{reference}:
      do IO<Unit>:
        previous : T.SystemMessage<S.Value<U32>> <- Ref.dispose(T.SystemMessage<S.Value<U32>>, reference)
        assertion(False{}, "unexpected system message")

def noSystem() -> IO(Unit):
  do IO<Unit>:
    +user : Ref.Ref<T.UserMessage> <- Ref.new(T.UserMessage, T.UserMessage{T.UserText{"hi"}, N.fromU32(1)})
    +context : Normalized() <- Snapshot.normalizeContext(S.Value<U32>, Unit, Unit, Unit, Snapshot.Context{None{}, T.User{user} <> Nil{}, None{}})
    current : Maybe<&2, Ref.Ref<T.SystemMessage<S.Value<U32>>>> <- Transcript.getCurrentSystemMessage(S.Value<U32>, Unit, Unit, Unit, T.User{user} <> Nil{})
    expectAbsent(current)
    prompt : String <- Transcript.getCurrentSystemPrompt(S.Value<U32>, Unit, Unit, Unit, T.User{user} <> Nil{})
    assertion(String.eq(prompt, ""), "no-system prompt must be empty")
    collapsed : Normalized() <- Snapshot.collapseSystemMessages(S.Value<U32>, Unit, Unit, Unit, context)
    checkUnchanged(collapsed, "hi")
    previous : T.UserMessage <- Ref.dispose(T.UserMessage, user)
    IO.print("PASS replay of a transcript without system messages is empty")

def checkLateTool(value: T.SystemMessage<S.Value<U32>>) -> IO(Unit):
  match value:
    case T.SystemMessage{_, _, Some{reference <> Nil{}}, _, _}:
      do IO<Unit>:
        observed : T.Tool<S.Value<U32>> <- Ref.read(T.Tool<S.Value<U32>>, reference)
        checkNamedTool(observed, "x")
    case _: assertion(False{}, "late patch tool missing")

def checkLateHead(value: Normalized()) -> IO(Unit):
  match value:
    case Snapshot.TranscriptContext{T.System{head} <> tail}:
      do IO<Unit>:
        observed : T.SystemMessage<S.Value<U32>> <- Ref.dispose(T.SystemMessage<S.Value<U32>>, head)
        checkLateTool(observed)
        checkTail(tail, "old session")
    case _: assertion(False{}, "late patch did not become the leading system message")

def latePatch() -> IO(Unit):
  do IO<Unit>:
    +user : Ref.Ref<T.UserMessage> <- Ref.new(T.UserMessage, T.UserMessage{T.UserText{"old session"}, N.fromU32(1)})
    +declaration : Ref.Ref<T.Tool<S.Value<U32>>> <- tool("x")
    +patch : Ref.Ref<T.SystemMessage<S.Value<U32>>> <- Ref.new(T.SystemMessage<S.Value<U32>>, T.SystemMessage{T.SystemText{""}, Some{Record.set(Maybe<&2, String>, Record.new(Maybe<&2, String>), "preamble", Some{"You are pi."})}, Some{declaration <> Nil{}}, None{}, N.fromU32(2)})
    +messages : List<&2, Message()> = T.User{user} <> T.System{patch} <> Nil{}
    context : Normalized() <- Snapshot.normalizeContext(S.Value<U32>, Unit, Unit, Unit, Snapshot.Context{None{}, messages, None{}})
    prompt : String <- Transcript.getCurrentSystemPrompt(S.Value<U32>, Unit, Unit, Unit, messages)
    assertion(String.eq(prompt, "You are pi."), "late prompt patch")
    collapsed : Normalized() <- Snapshot.collapseSystemMessages(S.Value<U32>, Unit, Unit, Unit, context)
    checkLateHead(collapsed)
    previous : T.UserMessage <- Ref.dispose(T.UserMessage, user)
    previous : T.SystemMessage<S.Value<U32>> <- Ref.dispose(T.SystemMessage<S.Value<U32>>, patch)
    previous : T.Tool<S.Value<U32>> <- Ref.dispose(T.Tool<S.Value<U32>>, declaration)
    IO.print("PASS a late full patch on a transcript without a leading message replays as the prompt")

def contextMessages(context: Normalized()) -> List<&2, Message()>:
  match context:
    case Snapshot.TranscriptContext{messages}: messages

def toolHistory() -> IO(Unit):
  do IO<Unit>:
    +f : Fixture <- createFixture()
    nonAdditive : Bool <- Transcript.hasNonAdditiveToolChanges(S.Value<U32>, Unit, Unit, Unit, fixtureMessages(f))
    assertion(nonAdditive, "original transcript must be non-additive")
    redefined : D.DeclarationResult<Bool> <- Transcript.hasToolRedefinitions(U32, Unit, Unit, Unit, fixtureMessages(f))
    assertion(DeclarationTest.sameBool(redefined, D.Success{False{}}), "original transcript must have no redefinitions")
    disposeFixture(f)
    +a : Ref.Ref<T.Tool<S.Value<U32>>> <- tool("a")
    +b : Ref.Ref<T.Tool<S.Value<U32>>> <- tool("b")
    +changed : Ref.Ref<T.Tool<S.Value<U32>>> <- Ref.new(T.Tool<S.Value<U32>>, ToolState.tool("a", "changed"))
    +first : Ref.Ref<T.SystemMessage<S.Value<U32>>> <- Ref.new(T.SystemMessage<S.Value<U32>>, T.SystemMessage{T.SystemText{""}, None{}, Some{a <> Nil{}}, None{}, N.fromU32(1)})
    +second : Ref.Ref<T.SystemMessage<S.Value<U32>>> <- Ref.new(T.SystemMessage<S.Value<U32>>, T.SystemMessage{T.SystemText{""}, None{}, Some{b <> Nil{}}, None{}, N.fromU32(2)})
    +replacement : Ref.Ref<T.SystemMessage<S.Value<U32>>> <- Ref.new(T.SystemMessage<S.Value<U32>>, T.SystemMessage{T.SystemText{""}, None{}, Some{changed <> Nil{}}, None{}, N.fromU32(2)})
    additive : Normalized() <- Snapshot.normalizeContext(S.Value<U32>, Unit, Unit, Unit, Snapshot.Context{None{}, T.System{first} <> T.System{second} <> Nil{}, None{}})
    nonAdditive : Bool <- Transcript.hasNonAdditiveToolChanges(S.Value<U32>, Unit, Unit, Unit, contextMessages(additive))
    assertion(Bool.not(nonAdditive), "distinct added names must be additive")
    +redeclared : Normalized() <- Snapshot.normalizeContext(S.Value<U32>, Unit, Unit, Unit, Snapshot.Context{None{}, T.System{first} <> T.System{replacement} <> Nil{}, None{}})
    nonAdditive : Bool <- Transcript.hasNonAdditiveToolChanges(S.Value<U32>, Unit, Unit, Unit, contextMessages(redeclared))
    assertion(nonAdditive, "same-name redeclaration must be non-additive")
    redefined : D.DeclarationResult<Bool> <- Transcript.hasToolRedefinitions(U32, Unit, Unit, Unit, contextMessages(redeclared))
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
