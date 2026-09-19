import Base
import ./openai-responses-stream.bend as ResponseStream
import ./openai-responses-stream-pricing.bend as ResponsePricing
import ./openai-responses-assistant.bend as Assistant
import ./openai-responses-content.bend as Content
import ./openai-responses-ids.bend as Ids
import ./transform-messages.bend as Transform
import ../utils/transcript.bend as Transcript
import ../utils/text.bend as Text
import ../utils/hash.bend as Hash
import ../utils/sanitize-unicode.bend as Unicode
import ../../../runtime/src/callback.bend as Callback
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/date.bend as Date
import ../types.bend as T
import ./constrained-sampling.bend as C
import ../utils/schema-json.bend as SchemaJson
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R

# Native wire declarations and transcript input. Streamed response events
# remain a separate provider layer.
type GrammarToolFormat is Data:
  GrammarToolFormat{syntax: T.GrammarFormat, definition: String}

type OpenAITool is Data:
  FunctionTool{name: String, description: String, parameters: V.Value, strict: Maybe<&2, T.Nullable<Bool>>, deferLoading: Maybe<&2, Bool>}
  CustomTool{name: String, description: String, format: GrammarToolFormat, deferLoading: Maybe<&2, Bool>}

type ConvertResponsesToolsOptions is Data:
  ConvertResponsesToolsOptions{strict: Maybe<&2, T.Nullable<Bool>>, supportsStrictMode: Maybe<&2, Bool>, supportsOpenAIGrammarTools: Maybe<&2, Bool>, toolSearchResult: Maybe<&2, Bool>}

def option(value: Maybe<&2, Bool>, fallback: Bool) -> Bool:
  match value:
    case None{}: fallback
    case Some{boolean}: boolean

def strictDefault(value: Maybe<&2, T.Nullable<Bool>>) -> T.Nullable<Bool>:
  match value:
    case None{}: T.PresentValue{False{}}
    case Some{setting}: setting

def strictEnabled(value: T.Nullable<Bool>) -> Bool:
  match value:
    case T.NullValue{}: False{}
    case T.PresentValue{boolean}: boolean

def deferred(enabled: Bool) -> Maybe<&2, Bool>:
  match enabled:
    case True{}: Some{True{}}
    case False{}: None{}

def functionParameters(name: String, description: String, strict: Maybe<&2, T.Nullable<Bool>>, loading: Maybe<&2, Bool>, result: Result<&2, &2, C.Error, V.Value>) -> Result<&2, &2, C.Error, OpenAITool>:
  match result:
    case Fail{error}: Fail{error}
    case Done{parameters}: Done{FunctionTool{name, description, parameters, strict, loading}}

def functionDeclaration(tool: T.Tool<V.Value>, +strict: T.Nullable<Bool>, supported: Bool, loading: Maybe<&2, Bool>) -> Result<&2, &2, C.Error, OpenAITool>:
  match tool:
    case T.Tool{+name, +description, parameters, config}:
      functionParameters(name, description, Bool.pick(Maybe<&2, T.Nullable<Bool>>, supported, Some{strict}, None{}), loading, C.getJsonSchemaToolParameters(T.Tool{name, description, parameters, config}, Some{strictEnabled(strict)}))

def strictSelection(value: Maybe<&2, Bool>, fallback: T.Nullable<Bool>) -> T.Nullable<Bool>:
  match value:
    case None{}: fallback
    case Some{boolean}: T.PresentValue{boolean}

def strictTool(tool: T.Tool<V.Value>, fallback: T.Nullable<Bool>, supported: Bool, loading: Maybe<&2, Bool>, result: Result<&2, &2, C.Error, Maybe<&2, Bool>>) -> Result<&2, &2, C.Error, OpenAITool>:
  match result:
    case Fail{error}: Fail{error}
    case Done{strict}: functionDeclaration(tool, strictSelection(strict, fallback), supported, loading)

def customTool(tool: T.Tool<V.Value>, syntax: T.GrammarFormat, definition: String, loading: Maybe<&2, Bool>) -> Result<&2, &2, C.Error, OpenAITool>:
  match tool:
    case T.Tool{name, description, _, _}: Done{CustomTool{name, description, GrammarToolFormat{syntax, definition}, loading}}

def grammarTool(+tool: T.Tool<V.Value>, fallback: T.Nullable<Bool>, +supported: Bool, loading: Maybe<&2, Bool>, result: Result<&2, &2, C.Error, Maybe<&2, C.GrammarConstrainedSampling>>) -> Result<&2, &2, C.Error, OpenAITool>:
  match result:
    case Fail{error}: Fail{error}
    case Done{None{}}: strictTool(tool, fallback, supported, loading, C.resolveJsonSchemaStrictSampling(tool, supported))
    case Done{Some{C.GrammarConstrainedSampling{syntax, definition, _}}}: customTool(tool, syntax, definition, loading)

def collected(value: Result<&2, &2, C.Error, OpenAITool>, reversed: List<&2, OpenAITool>) -> Result<&2, &2, C.Error, List<&2, OpenAITool>>:
  match value:
    case Fail{error}: Fail{error}
    case Done{tool}: Done{tool <> reversed}

# Conversion visits tools in declaration order and returns the first error.
# The result accumulator makes error propagation explicit without mutation.
def convertFrom(tools: List<&2, T.Tool<V.Value>>, +fallback: T.Nullable<Bool>, +strictSupport: Bool, +grammarSupport: Bool, +loading: Maybe<&2, Bool>, result: Result<&2, &2, C.Error, List<&2, OpenAITool>>) -> Result<&2, &2, C.Error, List<&2, OpenAITool>>:
  match tools result:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{reversed}: Done{List.reverse(&2, OpenAITool, reversed)}
    case +head <> tail Done{reversed}: convertFrom(tail, fallback, strictSupport, grammarSupport, loading, collected(grammarTool(head, fallback, strictSupport, loading, C.resolveGrammarConstrainedSampling(head, grammarSupport)), reversed))

def convertConfigured(tools: List<&2, T.Tool<V.Value>>, options: ConvertResponsesToolsOptions) -> Result<&2, &2, C.Error, List<&2, OpenAITool>>:
  match options:
    case ConvertResponsesToolsOptions{strict, strictSupport, grammarSupport, search}:
      convertFrom(tools, strictDefault(strict), option(strictSupport, True{}), option(grammarSupport, False{}), deferred(option(search, False{})), Done{Nil{}})

def convertResponsesTools(tools: List<&2, T.Tool<V.Value>>, options: Maybe<&2, ConvertResponsesToolsOptions>) -> Result<&2, &2, C.Error, List<&2, OpenAITool>>:
  match options:
    case None{}: convertConfigured(tools, ConvertResponsesToolsOptions{None{}, None{}, None{}, None{}})
    case Some{value}: convertConfigured(tools, value)

def addLoading(fields: R.Record<T.JsonValue>, loading: Maybe<&2, Bool>) -> R.Record<T.JsonValue>:
  match loading:
    case None{}: fields
    case Some{value}: R.set(T.JsonValue, fields, "defer_loading", T.JsonBoolean{value})

def addStrict(fields: R.Record<T.JsonValue>, strict: Maybe<&2, T.Nullable<Bool>>) -> R.Record<T.JsonValue>:
  match strict:
    case None{}: fields
    case Some{T.NullValue{}}: R.set(T.JsonValue, fields, "strict", T.JsonNull{})
    case Some{T.PresentValue{value}}: R.set(T.JsonValue, fields, "strict", T.JsonBoolean{value})

def grammarSyntax(syntax: T.GrammarFormat) -> String:
  match syntax:
    case T.OpenAILark{}: "lark"
    case T.OpenAIRegex{}: "regex"

def toolToJson(tool: OpenAITool) -> T.JsonValue:
  match tool:
    case FunctionTool{name, description, parameters, strict, loading}:
      T.JsonObject{addStrict(addLoading(R.Record{R.Property{"type", T.JsonString{"function"}} <> R.Property{"name", T.JsonString{name}} <> R.Property{"description", T.JsonString{description}} <> R.Property{"parameters", SchemaJson.toJson(parameters)} <> Nil{}}, loading), strict)}
    case CustomTool{name, description, GrammarToolFormat{syntax, definition}, loading}:
      T.JsonObject{addLoading(R.Record{R.Property{"type", T.JsonString{"custom"}} <> R.Property{"name", T.JsonString{name}} <> R.Property{"description", T.JsonString{description}} <> R.Property{"format", T.JsonObject{R.Record{R.Property{"type", T.JsonString{"grammar"}} <> R.Property{"syntax", T.JsonString{grammarSyntax(syntax)}} <> R.Property{"definition", T.JsonString{definition}} <> Nil{}}}} <> Nil{}}, loading)}

type InstructionRole is Data:
  SystemRole{}
  DeveloperRole{}

type ResponseInputItem is Data:
  Instruction{role: InstructionRole, text: String}
  UserInput{value: Content.UserInput}
  AssistantInput{value: Assistant.AssistantItem}
  FunctionToolOutput{callId: String, output: Content.ToolResultOutput}
  CustomToolOutput{callId: String, output: Content.ToolResultOutput}
  AdditionalTools{tools: List<&2, OpenAITool>}
  ToolSearchCall{callId: String, names: List<&2, String>}
  ToolSearchOutput{callId: String, tools: List<&2, OpenAITool>}

type ConvertResponsesMessagesOptions is Data:
  ConvertResponsesMessagesOptions{includeSystemPrompt: Maybe<&2, Bool>, grammarToolInputProperties: Maybe<&2, R.Record<String>>, supportsMidConvoSystemMessages: Maybe<&2, Bool>, supportsAdditionalTools: Maybe<&2, Bool>, supportsToolSearch: Maybe<&2, Bool>, toolOptions: Maybe<&2, ConvertResponsesToolsOptions>}

type MessageError is Data:
  AssistantConversion{error: Assistant.Error}
  ToolConversion{error: C.Error}

type AssemblyConfig is Data:
  AssemblyConfig{includeInitial: Bool, grammar: R.Record<String>, additional: Bool, search: Bool, toolOptions: Maybe<&2, ConvertResponsesToolsOptions>, anchors: Bool, role: InstructionRole}

def messageOptions(options: Maybe<&2, ConvertResponsesMessagesOptions>) -> ConvertResponsesMessagesOptions:
  match options:
    case None{}: ConvertResponsesMessagesOptions{None{}, None{}, None{}, None{}, None{}, None{}}
    case Some{value}: value

def grammarProperties(value: Maybe<&2, R.Record<String>>) -> R.Record<String>:
  match value:
    case None{}: R.new(String)
    case Some{properties}: properties

def supportsDeveloper(api: T.ModelApi, compatibility: Maybe<&2, T.ModelCompatibility(api)>) -> Bool:
  match api compatibility:
    case T.OpenAIResponsesApi{} Some{T.OpenAIResponsesCompat{setting, _, _, _, _, _, _, _, _, _}}: option(setting, True{})
    case T.AzureOpenAIResponsesApi{} Some{T.OpenAIResponsesCompat{setting, _, _, _, _, _, _, _, _, _}}: option(setting, True{})
    case T.OpenAICodexResponsesApi{} Some{T.OpenAIResponsesCompat{setting, _, _, _, _, _, _, _, _, _}}: option(setting, True{})
    case T.OpenAICompletionsApi{} Some{T.OpenAICompletionsCompat{_, setting, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}: option(setting, True{})
    case _ _: True{}

def instructionRole(-J: Data, model: T.Model<J>) -> InstructionRole:
  match model:
    case T.Model{_, _, api, _, _, reasoning, _, _, _, _, _, _, _, compatibility}: Bool.pick(InstructionRole, reasoning && supportsDeveloper(api, compatibility), DeveloperRole{}, SystemRole{})

def anchors(-P: Data, tools: Transcript.TranscriptTools<P>) -> Bool:
  match tools:
    case Transcript.TranscriptTools{_, value}: value

def assemblyConfig(-P: Data, -A: Data, -G: Data, -D: Data, -J: Data, messages: List<&2, T.Message<P, A, G, D>>, model: T.Model<J>, options: ConvertResponsesMessagesOptions) -> AssemblyConfig:
  match options:
    case ConvertResponsesMessagesOptions{includeInitial, grammar, _, +additional, +search, tools}:
      AssemblyConfig{option(includeInitial, True{}), grammarProperties(grammar), option(additional, False{}), option(search, False{}), tools, anchors(P, Transcript.resolveTranscriptTools(P, A, G, D, messages, option(additional, False{}) || option(search, False{}))), instructionRole(J, model)}

def schemaTools(~P: Data, ~encode: P -> V.Value, tools: List<&2, T.Tool<P>>) -> List<&2, T.Tool<V.Value>>:
  match tools:
    case Nil{}: Nil{}
    case T.Tool{name, description, parameters, sampling} <> rest: T.Tool{name, description, encode(parameters), sampling} <> schemaTools(~P, ~encode, rest)

def toolNames(-P: Data, tools: List<&2, T.Tool<P>>) -> List<&2, String>:
  match tools:
    case Nil{}: Nil{}
    case T.Tool{name, _, _, _} <> rest: name <> toolNames(P, rest)

def searchToolOptions(options: Maybe<&2, ConvertResponsesToolsOptions>) -> Maybe<&2, ConvertResponsesToolsOptions>:
  match options:
    case None{}: Some{ConvertResponsesToolsOptions{None{}, None{}, None{}, Some{True{}}}}
    case Some{ConvertResponsesToolsOptions{strict, strictSupport, grammarSupport, _}}: Some{ConvertResponsesToolsOptions{strict, strictSupport, grammarSupport, Some{True{}}}}

def addedItems(result: Result<&2, &2, C.Error, List<&2, OpenAITool>>, additional: Bool, +names: List<&2, String>, index: Nat) -> Result<&2, &2, MessageError, List<&2, ResponseInputItem>>:
  match result additional:
    case Fail{error} _: Fail{ToolConversion{error}}
    case Done{tools} True{}: Done{AdditionalTools{tools} <> Nil{}}
    case Done{tools} False{}:
      +id = "pi_tool_load_" ++ Hash.shortHash("system:" ++ Nat.show(index) ++ ":" ++ String.join(names, ","))
      Done{ToolSearchCall{id, names} <> ToolSearchOutput{id, tools} <> Nil{}}

def selectedAdditions(~P: Data, ~encode: P -> V.Value, tools: List<&2, T.Tool<P>>, enabled: Bool, +additional: Bool, +options: Maybe<&2, ConvertResponsesToolsOptions>, index: Nat) -> Result<&2, &2, MessageError, List<&2, ResponseInputItem>>:
  match tools enabled:
    case Nil{} _: Done{Nil{}}
    case _ False{}: Done{Nil{}}
    case +head <> +rest True{}:
      addedItems(convertResponsesTools(schemaTools(~P, ~encode, head <> rest), Bool.pick(Maybe<&2, ConvertResponsesToolsOptions>, additional, options, searchToolOptions(options))), additional, toolNames(P, head <> rest), index)

def systemAdditions(~P: Data, ~encode: P -> V.Value, tools: List<&2, T.Tool<P>>, leading: Bool, config: AssemblyConfig, index: Nat) -> Result<&2, &2, MessageError, List<&2, ResponseInputItem>>:
  match config:
    case AssemblyConfig{_, _, +additional, search, options, anchored, _}: selectedAdditions(~P, ~encode, tools, Bool.not(leading) && anchored && (additional || search), additional, options, index)

def systemText(-P: Data, +message: T.SystemMessage<P>, +leading: Bool, config: AssemblyConfig) -> List<&2, ResponseInputItem>:
  match config:
    case AssemblyConfig{includeInitial, _, _, _, _, _, role}:
      +text = Bool.pick(String, leading, Text.renderComplete(P, message), Text.renderUpdate(P, message))
      Bool.pick(List<&2, ResponseInputItem>, (leading && Bool.not(includeInitial)) || String.is_empty(text), Nil{}, Instruction{role, Unicode.sanitizeSurrogates(text)} <> Nil{})

def combinedSystem(additions: Result<&2, &2, MessageError, List<&2, ResponseInputItem>>, text: List<&2, ResponseInputItem>) -> Result<&2, &2, MessageError, List<&2, ResponseInputItem>>:
  match additions:
    case Fail{error}: Fail{error}
    case Done{items}: Done{List.append(&2, ResponseInputItem, items, text)}

def convertSystem(~P: Data, ~encode: P -> V.Value, +message: T.SystemMessage<P>, +leading: Bool, +config: AssemblyConfig, index: Nat) -> Result<&2, &2, MessageError, List<&2, ResponseInputItem>>:
  combinedSystem(systemAdditions(~P, ~encode, Transcript.initialToolsValue(P, message), leading, config, index), systemText(P, message, leading, config))

def userItems(user: Maybe<&2, Content.UserInput>) -> List<&2, ResponseInputItem>:
  match user:
    case None{}: Nil{}
    case Some{value}: UserInput{value} <> Nil{}

def assistantItems(items: List<&2, Assistant.AssistantItem>) -> List<&2, ResponseInputItem>:
  match items:
    case Nil{}: Nil{}
    case head <> rest: AssistantInput{head} <> assistantItems(rest)

def assistantResult(result: Result<&2, &2, Assistant.Error, List<&2, Assistant.AssistantItem>>) -> Result<&2, &2, MessageError, List<&2, ResponseInputItem>>:
  match result:
    case Fail{error}: Fail{AssistantConversion{error}}
    case Done{items}: Done{assistantItems(items)}

def resultItem(custom: Maybe<&2, String>, callId: String, output: Content.ToolResultOutput) -> ResponseInputItem:
  match custom:
    case None{}: FunctionToolOutput{callId, output}
    case Some{_}: CustomToolOutput{callId, output}

def convertMessage(~P: Data, ~A: Data, ~G: Data, ~D: Data, ~J: Data, ~encodeParameters: P -> V.Value, ~encodeArguments: A -> V.Value, message: T.Message<P, A, G, D>, model: T.Model<J>, config: AssemblyConfig, first: Bool, index: Nat) -> Result<&2, &2, MessageError, List<&2, ResponseInputItem>>:
  match message config:
    case T.System{message} config: convertSystem(~P, ~encodeParameters, message, first, config, index)
    case T.User{T.UserMessage{content, _}} _: Done{userItems(Content.convertUserContent(content))}
    case T.Assistant{message} AssemblyConfig{_, grammar, _, _, _, _, _}: assistantResult(Assistant.convertAssistantMessage(~A, ~G, ~encodeArguments, Transform.target(J, model), message, index, grammar))
    case T.ToolResult{T.ToolResultMessage{id, name, content, _, _, _, _}} AssemblyConfig{_, grammar, _, _, _, _, _}: Done{resultItem(R.get(String, grammar, name), Ids.firstPart(id, ""), Content.convertToolResultOutput(J, model, content)) <> Nil{}}

# Source position always advances. The output message index skips leading
# systems and omitted user/assistant messages, but counts empty later systems.
def counted(-P: Data, -A: Data, -G: Data, -D: Data, message: T.Message<P, A, G, D>, first: Bool, items: List<&2, ResponseInputItem>) -> Bool:
  match message first items:
    case T.System{_} True{} _: False{}
    case T.System{_} False{} _: True{}
    case _ _ Nil{}: False{}
    case _ _ _: True{}

type AssemblyState is Data:
  AssemblyState{reversed: List<&2, ResponseInputItem>, index: Nat}

def appendMessage(-P: Data, -A: Data, -G: Data, -D: Data, message: T.Message<P, A, G, D>, first: Bool, state: AssemblyState, result: Result<&2, &2, MessageError, List<&2, ResponseInputItem>>) -> Result<&2, &2, MessageError, AssemblyState>:
  match state result:
    case _ Fail{error}: Fail{error}
    case AssemblyState{reversed, index} Done{+items}: Done{AssemblyState{List.append(&2, ResponseInputItem, List.reverse(&2, ResponseInputItem, items), reversed), index + Bool.pick(Nat, counted(P, A, G, D, message, first, items), 1n, 0n)}}

def assemblyIndex(state: AssemblyState) -> Nat:
  match state:
    case AssemblyState{_, index}: index

def assemble(~P: Data, ~A: Data, ~G: Data, ~D: Data, ~J: Data, ~encodeParameters: P -> V.Value, ~encodeArguments: A -> V.Value, messages: List<&2, T.Message<P, A, G, D>>, +model: T.Model<J>, +config: AssemblyConfig, +first: Bool, state: Result<&2, &2, MessageError, AssemblyState>) -> Result<&2, &2, MessageError, List<&2, ResponseInputItem>>:
  match messages state:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{AssemblyState{reversed, _}}: Done{List.reverse(&2, ResponseInputItem, reversed)}
    case +message <> rest Done{+current}:
      index = assemblyIndex(current)
      assemble(~P, ~A, ~G, ~D, ~J, ~encodeParameters, ~encodeArguments, rest, model, config, False{}, appendMessage(P, A, G, D, message, first, current, convertMessage(~P, ~A, ~G, ~D, ~J, ~encodeParameters, ~encodeArguments, message, model, config, first, index)))

def normalizeInput(-A: Data, -G: Data, -J: Data, providers: List<&2, String>, input: Transform.NormalizeToolCallIdInput<A, G, J>) -> IO(Result<&2, &2, MessageError, String>):
  match input:
    case Transform.NormalizeToolCallIdInput{id, model, source}: IO.pure(Result<&2, &2, MessageError, String>, Done{Ids.normalizeToolCallId(A, G, id, Transform.target(J, model), source, providers)})

def normalizeBody(-A: Data, -G: Data, -J: Data, providers: List<&2, String>) -> Transform.NormalizeToolCallIdInput<A, G, J> -> IO(Result<&2, &2, MessageError, String>):
  input => normalizeInput(A, G, J, providers, input)

def assembled(~P: Data, ~A: Data, ~G: Data, ~D: Data, ~J: Data, ~encodeParameters: P -> V.Value, ~encodeArguments: A -> V.Value, model: T.Model<J>, config: AssemblyConfig, result: Result<&2, &2, MessageError, List<&2, T.Message<P, A, G, D>>>) -> Result<&2, &2, MessageError, List<&2, ResponseInputItem>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{messages}: assemble(~P, ~A, ~G, ~D, ~J, ~encodeParameters, ~encodeArguments, messages, model, config, True{}, Done{AssemblyState{Nil{}, 0n}})

def convertResolved(~P: Data, ~A: Data, ~G: Data, ~D: Data, ~J: Data, ~encodeParameters: P -> V.Value, ~encodeArguments: A -> V.Value, ~now: Unit -> IO(F.F64), +model: T.Model<J>, context: T.TranscriptContext<P, A, G, D>, providers: List<&2, String>, options: ConvertResponsesMessagesOptions) -> IO(Result<&2, &2, MessageError, List<&2, ResponseInputItem>>):
  match context:
    case T.TranscriptContext{+messages}:
      do IO<Result<&2, &2, MessageError, List<&2, ResponseInputItem>>>:
        +normalizer : Transform.Normalizer(A, G, J, MessageError) <- Callback.create(~List<&2, String>, ~Transform.NormalizeToolCallIdInput<A, G, J>, ~Result<&2, &2, MessageError, String>, ~(normalizeBody(A, G, J)), providers)
        transformed : Result<&2, &2, MessageError, List<&2, T.Message<P, A, G, D>>> <- Transform.transformMessagesWith(~P, ~A, ~G, ~D, ~J, ~MessageError, ~now, messages, model, Some{normalizer})
        Callback.dispose(Transform.NormalizeToolCallIdInput<A, G, J>, Result<&2, &2, MessageError, String>, normalizer)
        return assembled(~P, ~A, ~G, ~D, ~J, ~encodeParameters, ~encodeArguments, model, assemblyConfig(P, A, G, D, J, messages, model, options), transformed)

def midConversation(options: ConvertResponsesMessagesOptions) -> Maybe<&2, Bool>:
  match options:
    case ConvertResponsesMessagesOptions{_, _, value, _, _, _}: value

# The callback belongs to this invocation and is retired after transformation,
# including typed failures. Application types remain intact until serialization.
def convertResponsesMessagesWith(~P: Data, ~A: Data, ~G: Data, ~D: Data, ~J: Data, ~encodeParameters: P -> V.Value, ~encodeArguments: A -> V.Value, ~now: Unit -> IO(F.F64), model: T.Model<J>, context: T.TranscriptContext<P, A, G, D>, allowedToolCallProviders: List<&2, String>, options: Maybe<&2, ConvertResponsesMessagesOptions>) -> IO(Result<&2, &2, MessageError, List<&2, ResponseInputItem>>):
  +configured = messageOptions(options)
  convertResolved(~P, ~A, ~G, ~D, ~J, ~encodeParameters, ~encodeArguments, ~now, model, Transcript.resolveTranscript(P, A, G, D, context, midConversation(configured)), allowedToolCallProviders, configured)

def parameterValue(value: V.Value) -> V.Value: value

def argumentRecord(value: R.Record<V.Value>) -> V.Value: V.ObjectValue{value}

def conversionClock(unused: Unit) -> IO(F.F64): Date.now()

def convertResponsesMessages(~G: Data, ~D: Data, ~J: Data, model: T.Model<J>, context: T.TranscriptContext<V.Value, R.Record<V.Value>, G, D>, allowedToolCallProviders: List<&2, String>, options: Maybe<&2, ConvertResponsesMessagesOptions>) -> IO(Result<&2, &2, MessageError, List<&2, ResponseInputItem>>):
  convertResponsesMessagesWith(~V.Value, ~R.Record<V.Value>, ~G, ~D, ~J, ~parameterValue, ~argumentRecord, ~conversionClock, model, context, allowedToolCallProviders, options)

def roleName(role: InstructionRole) -> String:
  match role:
    case SystemRole{}: "system"
    case DeveloperRole{}: "developer"

def toolJsonList(tools: List<&2, OpenAITool>) -> List<&2, T.JsonValue>:
  match tools:
    case Nil{}: Nil{}
    case head <> rest: toolToJson(head) <> toolJsonList(rest)

def toolsToJson(tools: List<&2, OpenAITool>) -> T.JsonValue:
  match tools:
    case Nil{}: T.JsonArray{Nil{}}
    case head <> rest: T.JsonArray{toolToJson(head) <> toolJsonList(rest)}

def resultToJson(kind: String, callId: String, output: Content.ToolResultOutput) -> T.JsonValue:
  T.JsonObject{R.Record{R.Property{"type", T.JsonString{kind}} <> R.Property{"call_id", T.JsonString{callId}} <> R.Property{"output", Content.outputToJson(output)} <> Nil{}}}

def nameCount(names: List<&2, String>) -> F.F64:
  match names:
    case Nil{}: F.fromU32(0)
    case _ <> rest: F.add(F.fromU32(1), nameCount(rest))

def searchArguments(+names: List<&2, String>) -> T.JsonValue:
  T.JsonObject{R.Record{R.Property{"query", T.JsonString{String.join(names, " ")}} <> R.Property{"limit", T.JsonNumber{nameCount(names)}} <> Nil{}}}

def searchItemToJson(kind: String, callId: String, field: String, value: T.JsonValue) -> T.JsonValue:
  T.JsonObject{R.Record{R.Property{"type", T.JsonString{kind}} <> R.Property{"call_id", T.JsonString{callId}} <> R.Property{"execution", T.JsonString{"client"}} <> R.Property{"status", T.JsonString{"completed"}} <> R.Property{field, value} <> Nil{}}}

def inputItemToJson(item: ResponseInputItem) -> T.JsonValue:
  match item:
    case Instruction{role, text}: T.JsonObject{R.Record{R.Property{"role", T.JsonString{roleName(role)}} <> R.Property{"content", T.JsonString{text}} <> Nil{}}}
    case UserInput{value}: Content.userToJson(value)
    case AssistantInput{value}: Assistant.itemToJson(value)
    case FunctionToolOutput{id, output}: resultToJson("function_call_output", id, output)
    case CustomToolOutput{id, output}: resultToJson("custom_tool_call_output", id, output)
    case AdditionalTools{tools}: T.JsonObject{R.Record{R.Property{"type", T.JsonString{"additional_tools"}} <> R.Property{"role", T.JsonString{"developer"}} <> R.Property{"tools", toolsToJson(tools)} <> Nil{}}}
    case ToolSearchCall{id, names}: searchItemToJson("tool_search_call", id, "arguments", searchArguments(names))
    case ToolSearchOutput{id, tools}: searchItemToJson("tool_search_output", id, "tools", toolsToJson(tools))

def inputJsonList(items: List<&2, ResponseInputItem>) -> List<&2, T.JsonValue>:
  match items:
    case Nil{}: Nil{}
    case head <> rest: inputItemToJson(head) <> inputJsonList(rest)

def inputToJson(items: List<&2, ResponseInputItem>) -> T.JsonValue:
  T.JsonArray{inputJsonList(items)}

# The public shared entry point owns processing, while callers own the reader,
# sink and pricing callback handles. Provider wrappers publish the final event.
def OpenAIResponsesStreamOptions(-E: Data) -> Data: ResponsePricing.OpenAIResponsesStreamOptions<E>

def responseStreamOptions(-E: Data, options: Maybe<&2, OpenAIResponsesStreamOptions(E)>) -> OpenAIResponsesStreamOptions(E):
  match options:
    case None{}: ResponsePricing.defaultOptions(E)
    case Some{value}: value

def processResponsesStream(-G: Data, -E: Data, -J: Data, source: ResponseStream.Reader<E>, output: T.AssistantMessage<V.Value, G>, sink: Callback.Callback<T.AssistantMessageEvent<V.Value, G>, Result<&2, &2, E, Unit>>, model: T.Model<J>, options: Maybe<&2, OpenAIResponsesStreamOptions(E)>) -> IO(ResponseStream.RunResult<G, E>):
  ResponseStream.processResponsesStream(G, E, J, source, output, sink, model, responseStreamOptions(E, options))
