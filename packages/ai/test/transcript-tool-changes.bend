import Base
import ../src/types.bend as T
import ../src/utils/transcript.bend as Transcript
import ./anthropic-harness.bend as H
import ./responses-payload.bend as RP
import ../../runtime/src/f64.bend as F
import ../../runtime/src/record.bend as R
import ../../runtime/src/schema-value.bend as V

# pi-mono f07218c4d packages/ai/test/transcript-tool-changes.test.ts, the
# Anthropic Messages and OpenAI Responses cases: streamSimple's payload is
# captured by onPayload. The three Chat Completions cases are named request
# cases in tests/openai_completions_request_check.py.
def J() -> Data: T.JsonValue

# Contexts
# --------
def tool(+name: String) -> T.Tool<V.Value>: T.Tool{name, name ++ " tool", H.schema("{\"type\":\"object\",\"properties\":{}}"), None{}}

def redefined() -> T.Tool<V.Value>: T.Tool{"base_tool", "changed", H.schema("{\"type\":\"object\",\"properties\":{}}"), None{}}

def system(-G: Data, content: String, sections: Maybe<&2, R.Record<Maybe<&2, String>>>, added: Maybe<&2, List<&2, T.Tool<V.Value>>>, removed: Maybe<&2, List<&2, T.ToolReference>>, timestamp: U32) -> T.Message<V.Value, V.Value, G, Unit>:
  T.System{T.SystemMessage{T.SystemText{content}, sections, added, removed, F.fromU32(timestamp)}}

def user(-G: Data, content: String, timestamp: U32) -> T.Message<V.Value, V.Value, G, Unit>: T.User{T.UserMessage{T.UserText{content}, F.fromU32(timestamp)}}

def contextOf(-G: Data, messages: List<&2, T.Message<V.Value, V.Value, G, Unit>>) -> T.TranscriptContext<V.Value, V.Value, G, Unit>:
  Transcript.normalizeContext(V.Value, V.Value, G, Unit, T.Context{None{}, messages, None{}})

def initialSections() -> R.Record<Maybe<&2, String>>:
  R.Record{R.Property{"rules", Some{"<rules>\nold rules\n</rules>"}} <> R.Property{"docs", Some{"<docs>\nread docs\n</docs>"}} <> Nil{}}

def updatedSections() -> R.Record<Maybe<&2, String>>:
  R.Record{R.Property{"rules", Some{"<rules>\nnew rules\n</rules>"}} <> R.Property{"docs", None{}} <> Nil{}}

def opening(-G: Data) -> List<&2, T.Message<V.Value, V.Value, G, Unit>>:
  system(G, "base prompt", Some{initialSections()}, Some{[tool("base_tool")]}, None{}, 0) <> user(G, "before", 1) <> Nil{}

# The suite's `context`, or its first two messages.
def changes(-G: Data, whole: Bool) -> T.TranscriptContext<V.Value, V.Value, G, Unit>:
  match whole:
    case True{}: contextOf(G, List.append(&2, T.Message<V.Value, V.Value, G, Unit>, opening(G), system(G, "updated guidance", Some{updatedSections()}, Some{[tool("late_tool")]}, Some{[T.ToolReference{"base_tool"}]}, 2) <> Nil{}))
    case False{}: contextOf(G, opening(G))

def additions(-G: Data) -> T.TranscriptContext<V.Value, V.Value, G, Unit>:
  contextOf(G, system(G, "base prompt", None{}, Some{[tool("base_tool")]}, None{}, 0) <> user(G, "before", 1) <> system(G, "updated guidance", None{}, Some{[tool("late_tool")]}, None{}, 2) <> Nil{})

def sameNameRedefinition() -> H.Context():
  contextOf(H.Diagnostics(), system(H.Diagnostics(), "base prompt", None{}, Some{[tool("base_tool")]}, None{}, 0) <> system(H.Diagnostics(), "updated guidance", None{}, Some{[redefined()]}, Some{[T.ToolReference{"base_tool"}]}, 2) <> Nil{})

def noInitialTool() -> H.Context():
  contextOf(H.Diagnostics(), system(H.Diagnostics(), "base prompt", None{}, None{}, None{}, 0) <> system(H.Diagnostics(), "updated guidance", None{}, Some{[redefined()]}, None{}, 2) <> Nil{})

# JSON views
# ----------
def fieldValue(value: J(), name: String) -> J(): Maybe.default(&2, J(), H.fieldOf(Some{value}, name), T.JsonNull{})

# values.map((value) => value[name]), absent fields as null.
def plucked(values: List<&2, J()>, +name: String) -> List<&2, J()>:
  match values:
    case Nil{}: Nil{}
    case item <> rest: fieldValue(item, name) <> plucked(rest, name)

def pluck(values: List<&2, J()>, name: String) -> J(): T.JsonArray{plucked(values, name)}

def names(value: Maybe<&2, J()>) -> J(): pluck(H.elements(value), "name")

def equalJson(+actual: J(), +want: String, message: String) -> IO(Unit): H.equalJson(Some{actual}, want, message)

def lastOf(values: List<&2, J()>) -> Maybe<&2, J()>: List.head(&2, J(), List.reverse(&2, J(), values))

def at(values: List<&2, J()>, index: Nat) -> Maybe<&2, J()>:
  match values index:
    case Nil{} _: None{}
    case value <> _ 0n: Some{value}
    case _ <> rest 1n+previous: at(rest, previous)

def withoutBeta(+payload: Maybe<&2, J()>, message: String) -> IO(Unit):
  H.check(Bool.not(H.containsString(H.elements(H.fieldOf(payload, "betas")), "mid-conversation-tool-changes-2026-07-01")), message ++ ": unexpected tool-changes beta in " ++ H.showJson(H.fieldOf(payload, "betas")))

def textOf(value: Maybe<&2, J()>) -> Maybe<&2, String>: H.textOf2(value)

def kept(keep: Bool, item: J(), rest: List<&2, J()>) -> List<&2, J()>:
  match keep:
    case True{}: item <> rest
    case False{}: rest

def counted(hit: Bool, rest: Nat) -> Nat:
  match hit:
    case True{}: 1n + rest
    case False{}: rest

# Anthropic Messages
# ------------------
def anthropicModel(id: String, name: String, compat: Maybe<&2, T.AnthropicMessagesCompat>) -> T.Model<J()>:
  H.custom(id, name, "anthropic", "http://127.0.0.1:9", 1000, 100000, None{}, compat)

def anthropicCompat(midSystem: Maybe<&2, Bool>, toolChanges: Maybe<&2, Bool>) -> T.AnthropicMessagesCompat:
  T.AnthropicMessagesCompat{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, midSystem, toolChanges, None{}}

def native() -> T.Model<J()>: anthropicModel("claude-opus-5", "Claude Opus 5", Some{anthropicCompat(Some{True{}}, Some{True{}})})

def nativeTools(+tools: List<&2, J()>, +message: String) -> IO(Unit):
  do IO<Unit>:
    equalJson(pluck(tools, "name"), "[\"base_tool\",\"__pi_deferred_placeholder__\",\"late_tool\"]", message ++ " tool names")
    equalJson(pluck(tools, "cache_control"), "[{\"type\":\"ephemeral\"},null,null]", message ++ " cache_control")
    equalJson(pluck(tools, "defer_loading"), "[null,true,true]", message ++ " defer_loading")

def nativeUpdate(+update: Maybe<&2, J()>, +message: String) -> IO(Unit):
  +content = H.elements(H.fieldOf(update, "content"))
  +first = textOf(H.fieldOf(List.head(&2, J(), content), "text"))
  do IO<Unit>:
    H.equalText(textOf(H.fieldOf(update, "role")), Some{"system"}, message ++ " update role")
    equalJson(pluck(content, "type"), "[\"text\",\"tool_removal\",\"tool_addition\"]", message ++ " update blocks")
    equalJson(pluck(plucked(content, "tool"), "name"), "[null,\"base_tool\",\"late_tool\"]", message ++ " update tool names")
    H.check(H.contains(first, "updated guidance"), message ++ ": update text lacks the guidance")
    H.check(H.contains(first, "<rules>\nnew rules\n</rules>"), message ++ ": update text lacks the rules")
    H.check(H.contains(first, "Removed system prompt section \"docs\""), message ++ ": update text lacks the docs removal")

# OpenAI Responses
# ----------------
def responsesCompat(midSystem: Bool, additional: Bool, search: Bool) -> T.OpenAIResponsesCompat:
  T.OpenAIResponsesCompat{None{}, Bool.pick(Maybe<&2, Bool>, midSystem, Some{True{}}, None{}), None{}, None{}, None{}, None{}, Bool.pick(Maybe<&2, Bool>, additional, Some{True{}}, None{}), Bool.pick(Maybe<&2, Bool>, search, Some{True{}}, None{}), None{}, None{}}

def responsesModel(id: String, name: String, compat: T.OpenAIResponsesCompat) -> T.Model<J()>:
  T.Model{id, name, T.OpenAIResponsesApi{}, "openai", "http://127.0.0.1:9", True{}, None{}, T.InputText{} <> Nil{}, None{}, H.zeroCost(), None{}, F.fromU32(100000), F.fromU32(1000), None{}, None{}, Some{compat}}

def anthropicPayload(+model: T.Model<J()>, +context: H.Context()) -> IO(Maybe<&2, J()>):
  do IO<Maybe<&2, J()>>:
    outcome : H.Outcome <- H.runSimple(model, context, H.simple(Some{"test-key"}, None{}, None{}), H.Capture{})
    +payload : Maybe<&2, J()> <- IO.pure(Maybe<&2, J()>, H.payloadOf(outcome))
    H.check(Maybe.is_some(&2, J(), payload), "payload captured")
    return payload

def sendsNativeUpdates() -> IO(Unit):
  +name = {"sends Anthropic updates and tool changes in native system messages" : String}
  do IO<Unit>:
    +payload : Maybe<&2, J()> <- anthropicPayload(native(), changes(H.Diagnostics(), True{}))
    H.check(H.containsString(H.elements(H.fieldOf(payload, "betas")), "mid-conversation-tool-changes-2026-07-01"), name ++ ": tool-changes beta missing")
    equalJson(pluck(H.elements(H.fieldOf(payload, "system")), "text"), "[\"base prompt\\n\\n<rules>\\nold rules\\n</rules>\\n\\n<docs>\\nread docs\\n</docs>\"]", name ++ " system")
    nativeTools(H.elements(H.fieldOf(payload, "tools")), name)
    nativeUpdate(lastOf(H.elements(H.fieldOf(payload, "messages"))), name)
    initial : Maybe<&2, J()> <- anthropicPayload(native(), changes(H.Diagnostics(), False{}))
    equalJson(names(H.fieldOf(initial, "tools")), "[\"base_tool\",\"__pi_deferred_placeholder__\"]", name ++ " initial tools")
    H.pass(name)

def fallsBack(+context: H.Context(), +name: String) -> IO(Unit):
  do IO<Unit>:
    +payload : Maybe<&2, J()> <- anthropicPayload(native(), context)
    withoutBeta(payload, name)
    +tools : List<&2, J()> <- IO.pure(List<&2, J()>, H.elements(H.fieldOf(payload, "tools")))
    equalJson(pluck(tools, "name"), "[\"base_tool\"]", name ++ " tool names")
    equalJson(pluck(tools, "description"), "[\"changed\"]", name ++ " descriptions")
    equalJson(pluck(tools, "cache_control"), "[{\"type\":\"ephemeral\"}]", name ++ " cache_control")
    equalJson(pluck(tools, "defer_loading"), "[null]", name ++ " defer_loading")
    equalJson(pluck(H.elements(H.fieldOf(lastOf(H.elements(H.fieldOf(payload, "messages"))), "content")), "type"), "[\"text\"]", name ++ " last message blocks")

def sendsCurrentTools() -> IO(Unit):
  +name = {"sends the current Anthropic tool list when native tool changes cannot express the history" : String}
  do IO<Unit>:
    fallsBack(sameNameRedefinition(), name)
    fallsBack(noInitialTool(), name)
    H.pass(name)

def foldsWithoutSupport() -> IO(Unit):
  +name = {"folds Anthropic updates into the system prompt without native support" : String}
  do IO<Unit>:
    +payload : Maybe<&2, J()> <- anthropicPayload(anthropicModel("claude-sonnet-4-5", "Claude Sonnet 4.5", None{}), changes(H.Diagnostics(), True{}))
    withoutBeta(payload, name)
    equalJson(pluck(H.elements(H.fieldOf(payload, "system")), "text"), "[\"base prompt\\n\\nupdated guidance\\n\\n<rules>\\nnew rules\\n</rules>\"]", name ++ " system")
    equalJson(names(H.fieldOf(payload, "tools")), "[\"late_tool\"]", name ++ " tools")
    equalJson(pluck(H.elements(H.fieldOf(payload, "messages")), "role"), "[\"user\"]", name ++ " roles")
    H.pass(name)

def requiresBoth() -> IO(Unit):
  +name = {"requires both Anthropic capabilities for native tool changes" : String}
  do IO<Unit>:
    +payload : Maybe<&2, J()> <- anthropicPayload(anthropicModel("claude-opus-5", "Claude Opus 5", Some{anthropicCompat(None{}, Some{True{}})}), changes(H.Diagnostics(), True{}))
    withoutBeta(payload, name)
    equalJson(names(H.fieldOf(payload, "tools")), "[\"late_tool\"]", name ++ " tools")
    equalJson(pluck(H.elements(H.fieldOf(payload, "messages")), "role"), "[\"user\"]", name ++ " roles")
    H.pass(name)

def responsesPayload(+model: T.Model<J()>, +context: T.TranscriptContext<V.Value, V.Value, Unit, Unit>) -> IO(Maybe<&2, J()>):
  RP.simplePayload(model, context, T.SimpleStreamOptions{None{}, None{}, Some{"test-key"}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}})

def untyped(kind: Maybe<&2, J()>) -> Bool:
  match kind:
    case None{}: True{}
    case Some{_}: False{}

def isPlainDeveloper(+item: J()) -> Bool: untyped(H.fieldOf(Some{item}, "type")) && H.isRole(item, "developer")

def ofType(item: J(), name: String) -> Bool: H.hasString(item, "type", name)

def kindOr(kind: Maybe<&2, J()>, role: J()) -> J():
  match kind:
    case Some{found}: found
    case None{}: role

def typeOrRole(+item: J()) -> J(): kindOr(H.fieldOf(Some{item}, "type"), fieldValue(item, "role"))

def allOfType(values: List<&2, J()>, +name: String) -> List<&2, J()>:
  match values:
    case Nil{}: Nil{}
    case +item <> rest: kept(ofType(item, name), item, allOfType(rest, name))

def firstOfType(values: List<&2, J()>, name: String) -> Maybe<&2, J()>: List.head(&2, J(), allOfType(values, name))

def plainDevelopers(values: List<&2, J()>) -> List<&2, J()>:
  match values:
    case Nil{}: Nil{}
    case +item <> rest: kept(isPlainDeveloper(item), item, plainDevelopers(rest))

def developerCount(values: List<&2, J()>) -> Nat:
  match values:
    case Nil{}: 0n
    case item <> rest: counted(H.isRole(item, "developer"), developerCount(rest))

def kinds(values: List<&2, J()>) -> List<&2, J()>:
  match values:
    case Nil{}: Nil{}
    case item <> rest: typeOrRole(item) <> kinds(rest)

def anchorsAdditions() -> IO(Unit):
  +name = {"anchors OpenAI additions at their developer message" : String}
  do IO<Unit>:
    +payload : Maybe<&2, J()> <- responsesPayload(responsesModel("gpt-5.4", "GPT-5.4", responsesCompat(True{}, True{}, False{})), additions(Unit))
    +input : List<&2, J()> <- IO.pure(List<&2, J()>, H.elements(H.fieldOf(payload, "input")))
    equalJson(names(H.fieldOf(payload, "tools")), "[\"base_tool\"]", name ++ " tools")
    equalJson(names(H.fieldOf(firstOfType(input, "additional_tools"), "tools")), "[\"late_tool\"]", name ++ " additional tools")
    equalJson(pluck(plainDevelopers(input), "content"), "[\"base prompt\",\"updated guidance\"]", name ++ " developer messages")
    H.pass(name)

def mapsToolSearch() -> IO(Unit):
  +name = {"maps system-message additions into synthetic tool search" : String}
  do IO<Unit>:
    +payload : Maybe<&2, J()> <- responsesPayload(responsesModel("gpt-5.4", "GPT-5.4", responsesCompat(True{}, False{}, True{})), additions(Unit))
    +input : List<&2, J()> <- IO.pure(List<&2, J()>, H.elements(H.fieldOf(payload, "input")))
    equalJson(names(H.fieldOf(payload, "tools")), "[\"base_tool\"]", name ++ " tools")
    H.check(Maybe.is_some(&2, J(), firstOfType(input, "tool_search_call")), name ++ ": no tool_search_call item")
    equalJson(names(H.fieldOf(firstOfType(input, "tool_search_output"), "tools")), "[\"late_tool\"]", name ++ " tool search output")
    H.pass(name)

def foldsResponses() -> IO(Unit):
  +name = {"folds OpenAI updates into the leading developer message without native support" : String}
  do IO<Unit>:
    +payload : Maybe<&2, J()> <- responsesPayload(responsesModel("gpt-4.1", "GPT-4.1", responsesCompat(False{}, True{}, False{})), changes(Unit, True{}))
    +input : List<&2, J()> <- IO.pure(List<&2, J()>, H.elements(H.fieldOf(payload, "input")))
    equalJson(names(H.fieldOf(payload, "tools")), "[\"late_tool\"]", name ++ " tools")
    equalJson(T.JsonArray{kinds(input)}, "[\"developer\",\"user\"]", name ++ " input kinds")
    H.equalText(textOf(H.fieldOf(List.head(&2, J(), input), "content")), Some{"base prompt\n\nupdated guidance\n\n<rules>\nnew rules\n</rules>"}, name ++ " developer content")
    H.pass(name)

def fullStateFallback() -> IO(Unit):
  +name = {"falls back to the complete current tool state when removals are unsupported" : String}
  do IO<Unit>:
    +payload : Maybe<&2, J()> <- responsesPayload(responsesModel("gpt-5.4", "GPT-5.4", responsesCompat(True{}, True{}, False{})), changes(Unit, True{}))
    +input : List<&2, J()> <- IO.pure(List<&2, J()>, H.elements(H.fieldOf(payload, "input")))
    equalJson(names(H.fieldOf(payload, "tools")), "[\"late_tool\"]", name ++ " tools")
    H.check(Maybe.is_none(&2, J(), firstOfType(input, "additional_tools")), name ++ ": unexpected additional_tools")
    H.check(Nat.is_eq(developerCount(input), 2n), name ++ ": expected two developer messages")
    H.pass(name)

def run() -> IO(Unit):
  do IO<Unit>:
    sendsNativeUpdates()
    sendsCurrentTools()
    foldsWithoutSupport()
    requiresBoth()
    anchorsAdditions()
    mapsToolSearch()
    foldsResponses()
    fullStateFallback()

def main() -> IO(Unit): run()
