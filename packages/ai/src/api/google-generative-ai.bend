import Base
import ../types.bend as T
import ../models.bend as Models
import ../utils/text.bend as Text
import ../utils/transcript.bend as Transcript
import ../utils/sanitize-unicode.bend as Unicode
import ../utils/headers.bend as HeaderUtils
import ./constrained-sampling.bend as Sampling
import ./google-shared.bend as Shared
import ./simple-options.bend as Simple
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V

# The Google Generative AI request side (pi `google-generative-ai.ts`):
# GoogleOptions, streamSimple's option mapping, buildParams (the SDK's
# GenerateContentParameters that onPayload sees), createClient's headers,
# and the @google/genai 2.21.0 conversion of those parameters into the
# Gemini Developer API request.
def J() -> Data: T.JsonValue

def Fields() -> Data: R.Record<J()>

def str(value: String) -> J(): T.JsonString{value}

def num(value: F64) -> J(): T.JsonNumber{value}

def obj(fields: List<&2, R.Property<J()>>) -> J(): T.JsonObject{R.Record{fields}}

def field(name: String, value: J()) -> R.Property<J()>: R.Property{name, value}

def optionalField(name: String, value: Maybe<&2, J()>, rest: List<&2, R.Property<J()>>) -> List<&2, R.Property<J()>>:
  match value:
    case None{}: rest
    case Some{item}: field(name, item) <> rest

def choiceName(value: T.ToolChoice) -> String:
  match value:
    case T.AutoTool{}: "auto"
    case T.NoTool{}: "none"

def budgetFor(id: String, level: T.ThinkingLevel) -> Maybe<&2, F64>:
  match level:
    case T.Minimal{}: Some{F.fromU32(Bool.pick(U32, String.contains(id, "2.5-flash-lite"), 512, 128))}
    case T.Low{}: Some{F.fromU32(2048)}
    case T.Medium{}: Some{F.fromU32(8192)}
    case _: Some{F.fromU32(Bool.pick(U32, String.contains(id, "2.5-pro"), 32768, 24576))}

def modelBudget(+id: String, level: T.ThinkingLevel) -> F64:
  Maybe.default(&2, F64, Bool.pick(Maybe<&2, F64>, String.contains(id, "2.5-pro") || String.contains(id, "2.5-flash"), budgetFor(id, level), None{}), F.negate(F.fromU32(1)))

def customBudget(level: T.ThinkingLevel, budgets: T.ThinkingBudgets) -> Maybe<&2, F64>:
  match level budgets:
    case T.Minimal{} T.ThinkingBudgets{value, _, _, _}: value
    case T.Low{} T.ThinkingBudgets{_, value, _, _}: value
    case T.Medium{} T.ThinkingBudgets{_, _, value, _}: value
    case _ T.ThinkingBudgets{_, _, _, value}: value

# upstream getGoogleBudget: a custom budget for the level, else the Gemini
# 2.5 Pro/Flash/Flash-Lite defaults, else dynamic (-1).
def getGoogleBudget(+model: T.Model<J()>, +level: T.ThinkingLevel, custom: Maybe<&2, T.ThinkingBudgets>) -> F64:
  match custom:
    case Some{budgets}: Maybe.default(&2, F64, customBudget(level, budgets), modelBudget(T.modelId(model), level))
    case None{}: modelBudget(T.modelId(model), level)

def simpleKey(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: Maybe<&2, T.SimpleStreamOptions<J(), Signal, Telemetry, Fetch, Error>>) -> Maybe<&2, String>:
  match options:
    case None{}: None{}
    case Some{T.SimpleStreamOptions{_, _, key, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}: key

def maybeConfig(result: Result<&2, &2, String, J()>) -> Result<&2, &2, String, Maybe<&2, J()>>:
  match result:
    case Fail{message}: Fail{message}
    case Done{value}: Done{Some{value}}

def nonemptyText(text: String) -> Maybe<&2, J()>:
  match text:
    case SNil{}: None{}
    case value: Some{str(Unicode.sanitizeSurrogates(value))}

def instructionOf(value: Maybe<&2, T.SystemMessage<V.Value>>) -> Maybe<&2, J()>:
  match value:
    case None{}: None{}
    case Some{message}: nonemptyText(Text.renderComplete(V.Value, message))

def systemInstruction(-G: Data, -D: Data, messages: List<&2, T.Message<V.Value, V.Value, G, D>>) -> Maybe<&2, J()>:
  instructionOf(Transcript.getInitialSystemMessage(V.Value, V.Value, G, D, messages))

def modeConfig(value: Maybe<&2, String>) -> Maybe<&2, J()>:
  match value:
    case None{}: None{}
    case Some{mode}: Some{obj(field("functionCallingConfig", obj(field("mode", str(mode)) <> Nil{})) <> Nil{})}

type ToolFields is Data:
  ToolFields{tools: Maybe<&2, J()>, toolConfig: Maybe<&2, J()>}

def toolFields(tools: Result<&2, &2, Sampling.Error, Maybe<&2, J()>>, mode: Result<&2, &2, Sampling.Error, Maybe<&2, String>>) -> Result<&2, &2, String, ToolFields>:
  match tools mode:
    case Fail{error} _: Fail{Sampling.errorMessage(error)}
    case _ Fail{error}: Fail{Sampling.errorMessage(error)}
    case Done{declared} Done{selected}: Done{ToolFields{declared, modeConfig(selected)}}

def currentToolFields(+tools: List<&2, T.Tool<V.Value>>, choice: Maybe<&2, String>, +strict: Bool) -> Result<&2, &2, String, ToolFields>:
  match tools:
    case Nil{}: Done{ToolFields{None{}, None{}}}
    case _: toolFields(Shared.convertTools(tools, False{}, strict), Shared.resolveGoogleFunctionCallingMode(tools, choice, strict))

def contextMessages(-G: Data, -D: Data, context: T.TranscriptContext<V.Value, V.Value, G, D>) -> List<&2, T.Message<V.Value, V.Value, G, D>>:
  match context:
    case T.TranscriptContext{messages}: messages

# createClient
# ------------
def modelHeaders(model: T.Model<J()>) -> Maybe<&2, R.Record<String>>:
  match model:
    case T.Model{_, _, _, _, _, _, _, _, _, _, _, _, _, _, headers, _}: headers

# upstream createClient's httpOptions.headers: pi's User-Agent, the model's
# headers, then the options' headers (null removes).
def clientHeaders(agent: String, +model: T.Model<J()>, custom: Maybe<&2, T.ProviderHeaders()>) -> R.Record<String>:
  Maybe.default(&2, R.Record<String>, HeaderUtils.providerHeadersToRecord(Some{HeaderUtils.overlay(HeaderUtils.overlayStrings(HeaderUtils.fromRecord(R.Record{R.Property{"User-Agent", agent} <> Nil{}}), modelHeaders(model)), custom)}), R.new(String))

# SDK request conversion
# ----------------------
def J2() -> Data: Maybe<&2, J()>

def get(fields: Fields(), name: String) -> Maybe<&2, J()>: R.get(J(), fields, name)

def fieldsOf(value: J()) -> Fields():
  match value:
    case T.JsonObject{fields}: fields
    case _: R.new(J())

def picked(+fields: Fields(), names: List<&2, String>) -> List<&2, R.Property<J()>>:
  match names:
    case Nil{}: Nil{}
    case +name <> rest: optionalField(name, get(fields, name), picked(fields, rest))

def functionCall(value: J()) -> J(): obj(picked(fieldsOf(value), ["args", "id", "name"]))

def blob(value: J()) -> J(): obj(picked(fieldsOf(value), ["data", "mimeType"]))

def mldevPart(value: J()) -> J():
  match value:
    case T.JsonObject{+fields}: obj(List.concat(&2, R.Property<J()>, picked(fields, ["mediaResolution", "toolCall", "toolResponse", "audioTranscription", "codeExecutionResult", "executableCode", "fileData"]) <> optionalField("functionCall", Maybe.map(&2, J(), J(), functionCall, get(fields, "functionCall")), Nil{}) <> picked(fields, ["functionResponse"]) <> optionalField("inlineData", Maybe.map(&2, J(), J(), blob, get(fields, "inlineData")), Nil{}) <> picked(fields, ["text", "thought", "thoughtSignature", "videoMetadata", "partMetadata", "mediaProcessing"]) <> Nil{}))
    case other: other

def mldevParts(values: List<&2, J()>) -> List<&2, J()>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: mldevPart(value) <> mldevParts(rest)

def partsOf(value: Maybe<&2, J()>) -> Maybe<&2, J()>:
  match value:
    case Some{T.JsonArray{values}}: Some{T.JsonArray{mldevParts(values)}}
    case other: other

def mldevContent(value: J()) -> J():
  match value:
    case T.JsonObject{+fields}: obj(optionalField("parts", partsOf(get(fields, "parts")), optionalField("role", get(fields, "role"), Nil{})))
    case other: other

def mldevContents(values: List<&2, J()>) -> List<&2, J()>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: mldevContent(value) <> mldevContents(rest)

# tContent: a string system instruction is one user text part.
def instructionContent(value: J()) -> J():
  match value:
    case T.JsonString{text}: obj(field("parts", T.JsonArray{obj(field("text", str(text)) <> Nil{}) <> Nil{}}) <> field("role", str("user")) <> Nil{})
    case other: mldevContent(other)

def mldevTool(value: J()) -> J():
  match value:
    case T.JsonObject{+fields}: obj(picked(fields, ["googleMaps", "mcpServers", "codeExecution", "computerUse", "functionDeclarations", "googleSearch", "googleSearchRetrieval", "urlContext", "fileSearch"]))
    case other: other

def mldevTools(values: List<&2, J()>) -> List<&2, J()>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: mldevTool(value) <> mldevTools(rest)

def toolsOf(value: Maybe<&2, J()>) -> Maybe<&2, J()>:
  match value:
    case Some{T.JsonArray{values}}: Some{T.JsonArray{mldevTools(values)}}
    case other: other

def callingConfig(value: J()) -> J(): obj(picked(fieldsOf(value), ["allowedFunctionNames", "mode"]))

def toolConfigOf(value: J()) -> J():
  match value:
    case T.JsonObject{+fields}: obj(optionalField("functionCallingConfig", Maybe.map(&2, J(), J(), callingConfig, get(fields, "functionCallingConfig")), picked(fields, ["retrievalConfig", "includeServerSideToolInvocations"])))
    case other: other

def requestFields(+config: Fields()) -> List<&2, R.Property<J()>>:
  List.concat(&2, R.Property<J()>, picked(config, ["serviceTier"]) <> optionalField("systemInstruction", Maybe.map(&2, J(), J(), instructionContent, get(config, "systemInstruction")), Nil{}) <> picked(config, ["safetySettings"]) <> optionalField("tools", toolsOf(get(config, "tools")), Nil{}) <> optionalField("toolConfig", Maybe.map(&2, J(), J(), toolConfigOf, get(config, "toolConfig")), Nil{}) <> picked(config, ["cachedContent"]) <> Nil{})

def contentsOf(value: Maybe<&2, J()>) -> Maybe<&2, J()>:
  match value:
    case Some{T.JsonArray{values}}: Some{T.JsonArray{mldevContents(values)}}
    case other: other

def modelText(value: Maybe<&2, J()>) -> Maybe<&2, String>:
  match value:
    case Some{T.JsonString{id}}: Some{id}
    case _: None{}

def payloadModel(params: J()) -> Maybe<&2, String>:
  match params:
    case T.JsonObject{fields}: modelText(R.get(J(), fields, "model"))
    case _: None{}

# Options
# -------
# upstream GoogleOptions.thinking: budgetTokens -1 is dynamic, 0 disables.
type GoogleThinking is Data:
  GoogleThinking{enabled: Bool, budgetTokens: Maybe<&2, F64>, level: Maybe<&2, Shared.GoogleApiThinkingLevel>}

# upstream GoogleOptions extends StreamOptions; toolChoice is "auto", "none"
# or "any".
type GoogleOptions<-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data> is Data:
  GoogleOptions{base: T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>, toolChoice: Maybe<&2, String>, thinking: Maybe<&2, GoogleThinking>}

def disabled(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, base: T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>, choice: Maybe<&2, String>) -> GoogleOptions<Signal, Telemetry, Fetch, Error>:
  GoogleOptions{base, choice, Some{GoogleThinking{False{}, None{}, None{}}}}

def enabledFor(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, levels: Bool, +model: T.Model<J()>, base: T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>, choice: Maybe<&2, String>, +level: T.ThinkingLevel, budgets: Maybe<&2, T.ThinkingBudgets>) -> GoogleOptions<Signal, Telemetry, Fetch, Error>:
  match levels:
    case True{}: GoogleOptions{base, choice, Some{GoogleThinking{True{}, None{}, Some{Shared.toGoogleThinkingLevel(level)}}}}
    case False{}: GoogleOptions{base, choice, Some{GoogleThinking{True{}, Some{getGoogleBudget(model, level, budgets)}, None{}}}}

def enabledOptions(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, +model: T.Model<J()>, base: T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>, choice: Maybe<&2, String>, +level: T.ThinkingLevel, budgets: Maybe<&2, T.ThinkingBudgets>) -> GoogleOptions<Signal, Telemetry, Fetch, Error>:
  enabledFor(Signal, Telemetry, Fetch, Error, Shared.usesGoogleThinkingLevel(model), model, base, choice, level, budgets)

def resolvedLevel(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, +model: T.Model<J()>, base: T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>, choice: Maybe<&2, String>, budgets: Maybe<&2, T.ThinkingBudgets>, resolved: Result<&2, &2, String, T.ThinkingLevel>) -> Result<&2, &2, String, GoogleOptions<Signal, Telemetry, Fetch, Error>>:
  match resolved:
    case Fail{message}: Fail{message}
    case Done{level}: Done{enabledOptions(Signal, Telemetry, Fetch, Error, model, base, choice, level, budgets)}

def clamped(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, +model: T.Model<J()>, base: T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>, choice: Maybe<&2, String>, budgets: Maybe<&2, T.ThinkingBudgets>, level: T.ModelThinkingLevel) -> Result<&2, &2, String, GoogleOptions<Signal, Telemetry, Fetch, Error>>:
  match level:
    case T.Off{}: Done{disabled(Signal, Telemetry, Fetch, Error, base, choice)}
    case T.Thinking{selected}: resolvedLevel(Signal, Telemetry, Fetch, Error, model, base, choice, budgets, Shared.resolveGoogleThinkingLevel(model, selected))

def simpleThinking(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, +model: T.Model<J()>, base: T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>, choice: Maybe<&2, String>, reasoning: Maybe<&2, T.ThinkingLevel>, budgets: Maybe<&2, T.ThinkingBudgets>) -> Result<&2, &2, String, GoogleOptions<Signal, Telemetry, Fetch, Error>>:
  match reasoning:
    case None{}: Done{disabled(Signal, Telemetry, Fetch, Error, base, choice)}
    case Some{level}: clamped(Signal, Telemetry, Fetch, Error, model, base, choice, budgets, Models.clampThinkingLevel(J(), model, T.Thinking{level}))

def simpleWith(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, +model: T.Model<J()>, base: T.StreamOptions<J(), Signal, Telemetry, Fetch, Error>, options: Maybe<&2, T.SimpleStreamOptions<J(), Signal, Telemetry, Fetch, Error>>) -> Result<&2, &2, String, GoogleOptions<Signal, Telemetry, Fetch, Error>>:
  match options:
    case None{}: simpleThinking(Signal, Telemetry, Fetch, Error, model, base, None{}, None{}, None{})
    case Some{T.SimpleStreamOptions{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, choice, reasoning, _, budgets}}:
      simpleThinking(Signal, Telemetry, Fetch, Error, model, base, Maybe.map(&2, T.ToolChoice, String, choiceName, choice), reasoning, budgets)

def keyedOptions(~G: Data, ~D: Data, ~Signal: Data, ~Telemetry: Data, ~Fetch: Data, ~Error: Data, +model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, +options: Maybe<&2, T.SimpleStreamOptions<J(), Signal, Telemetry, Fetch, Error>>, key: Maybe<&2, String>) -> Result<&2, &2, String, GoogleOptions<Signal, Telemetry, Fetch, Error>>:
  match key:
    case Some{SCon{c, cs}}: simpleWith(Signal, Telemetry, Fetch, Error, model, Simple.buildBaseOptions(~G, ~D, ~J(), ~Signal, ~Telemetry, ~Fetch, ~Error, model, context, options, Some{SCon{c, cs}}), options)
    case _: Fail{"No API key for provider: " ++ T.modelProvider(model)}

# upstream streamSimple's GoogleOptions. A missing API key and an unsupported
# level mapping are the errors upstream throws before a stream exists.
# Without a reasoning level (or when it clamps to off) thinking is disabled;
# level models get a thinkingLevel, the others a token budget.
def streamSimpleOptions(~G: Data, ~D: Data, ~Signal: Data, ~Telemetry: Data, ~Fetch: Data, ~Error: Data, +model: T.Model<J()>, context: T.TranscriptContext<V.Value, V.Value, G, D>, +options: Maybe<&2, T.SimpleStreamOptions<J(), Signal, Telemetry, Fetch, Error>>) -> Result<&2, &2, String, GoogleOptions<Signal, Telemetry, Fetch, Error>>:
  keyedOptions(~G, ~D, ~Signal, ~Telemetry, ~Fetch, ~Error, model, context, options, simpleKey(Signal, Telemetry, Fetch, Error, options))

def thinkingFor(+model: T.Model<J()>, thinking: Maybe<&2, GoogleThinking>, reasoning: Bool) -> Result<&2, &2, String, Maybe<&2, J()>>:
  match thinking reasoning:
    case Some{GoogleThinking{True{}, _, Some{level}}} True{}: Done{Some{obj(field("includeThoughts", T.JsonBoolean{True{}}) <> field("thinkingLevel", str(Shared.googleLevelName(level))) <> Nil{})}}
    case Some{GoogleThinking{True{}, Some{tokens}, None{}}} True{}: Done{Some{obj(field("includeThoughts", T.JsonBoolean{True{}}) <> field("thinkingBudget", num(tokens)) <> Nil{})}}
    case Some{GoogleThinking{True{}, None{}, None{}}} True{}: Done{Some{obj(field("includeThoughts", T.JsonBoolean{True{}}) <> Nil{})}}
    case Some{GoogleThinking{False{}, _, _}} True{}: maybeConfig(Shared.getDisabledGoogleThinkingConfig(model))
    case _ _: Done{None{}}

# buildParams
# -----------
def thinkingConfig(+model: T.Model<J()>, thinking: Maybe<&2, GoogleThinking>) -> Result<&2, &2, String, Maybe<&2, J()>>:
  thinkingFor(model, thinking, T.modelReasoning(model))

def configFields(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: GoogleOptions<Signal, Telemetry, Fetch, Error>, system: Maybe<&2, J()>, tools: ToolFields, thinking: Maybe<&2, J()>) -> J():
  match options tools:
    case GoogleOptions{T.StreamOptions{_, _, _, _, _, _, _, _, _, _, _, temperature, _, maxTokens, _, _, _, _, _}, _, _} ToolFields{declared, config}:
      obj(optionalField("temperature", Maybe.map(&2, F64, J(), num, temperature), optionalField("maxOutputTokens", Maybe.map(&2, F64, J(), num, maxTokens), optionalField("systemInstruction", system, optionalField("tools", declared, optionalField("toolConfig", config, optionalField("thinkingConfig", thinking, Nil{})))))))

def optionsThinking(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: GoogleOptions<Signal, Telemetry, Fetch, Error>) -> Maybe<&2, GoogleThinking>:
  match options:
    case GoogleOptions{_, _, thinking}: thinking

def optionsChoice(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: GoogleOptions<Signal, Telemetry, Fetch, Error>) -> Maybe<&2, String>:
  match options:
    case GoogleOptions{_, choice, _}: choice

def assembled(-Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, +model: T.Model<J()>, contents: List<&2, J()>, options: GoogleOptions<Signal, Telemetry, Fetch, Error>, system: Maybe<&2, J()>, tools: Result<&2, &2, String, ToolFields>, thinking: Result<&2, &2, String, Maybe<&2, J()>>) -> Result<&2, &2, String, J()>:
  match tools thinking:
    case Fail{message} _: Fail{message}
    case _ Fail{message}: Fail{message}
    case Done{selected} Done{config}: Done{obj(field("model", str(T.modelId(model))) <> field("contents", T.JsonArray{contents}) <> field("config", configFields(Signal, Telemetry, Fetch, Error, options, system, selected, config)) <> Nil{})}

# upstream buildParams over the collapsed transcript: SDK parameters
# {model, contents, config}; the config's abort signal is the request's.
def buildParams(~G: Data, ~D: Data, ~Signal: Data, ~Telemetry: Data, ~Fetch: Data, ~Error: Data, +model: T.Model<J()>, +context: T.TranscriptContext<V.Value, V.Value, G, D>, +options: GoogleOptions<Signal, Telemetry, Fetch, Error>) -> IO(Result<&2, &2, String, J()>):
  +messages = contextMessages(G, D, context)
  +tools = Transcript.getCurrentTools(V.Value, V.Value, G, D, messages)
  do IO<Result<&2, &2, String, J()>>:
    contents : List<&2, J()> <- Shared.convertMessages(~G, ~D, model, context)
    return assembled(Signal, Telemetry, Fetch, Error, model, contents, options, systemInstruction(G, D, messages), currentToolFields(tools, optionsChoice(Signal, Telemetry, Fetch, Error, options), Shared.supportsGoogleStrictToolSampling(T.modelId(model))), thinkingConfig(model, optionsThinking(Signal, Telemetry, Fetch, Error, options)))

def generationFields() -> List<&2, String>:
  ["temperature", "topP", "topK", "candidateCount", "maxOutputTokens", "stopSequences", "responseLogprobs", "logprobs", "presencePenalty", "frequencyPenalty", "seed", "responseMimeType", "responseSchema", "responseJsonSchema", "responseModalities", "mediaResolution", "speechConfig", "thinkingConfig", "audioTranscriptionConfig", "imageConfig", "enableEnhancedCivicAnswers"]

def withConfig(contents: List<&2, R.Property<J()>>, config: Maybe<&2, J()>) -> J():
  match config:
    case None{}: obj(contents)
    case Some{+selected}: obj(List.concat(&2, R.Property<J()>, contents <> requestFields(fieldsOf(selected)) <> (field("generationConfig", obj(picked(fieldsOf(selected), generationFields()))) <> Nil{}) <> Nil{}))

# generateContentParametersToMldev: contents, the config's request-level
# fields, then generationConfig. Fields outside this list are not sent, as the
# SDK drops them.
def requestBody(params: J()) -> J():
  match params:
    case T.JsonObject{+fields}: withConfig(optionalField("contents", contentsOf(get(fields, "contents")), Nil{}), get(fields, "config"))
    case other: other
