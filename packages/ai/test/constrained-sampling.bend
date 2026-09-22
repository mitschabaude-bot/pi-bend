import Base
import ../src/api/constrained-sampling.bend as C
import ../../runtime/src/schema.bend as D
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as R
import ../../runtime/test/schema.bend as Assert
import ./api/strict-json-schema.bend as Check
import ./api/grammar-input.bend as Grammar
import ../src/api/openai-responses-shared.bend as O
import ../src/types.bend as T
import ./api/responses-messages.bend as Responses
import ../../runtime/src/f64.bend as F
import ./api/responses-initial-input.bend as InitialInput

def parameters() -> V.Value:
  D.schemaBuilder(D.object(R.Record{
    R.Property{"path", D.requiredBuilder(D.string())} <>
    R.Property{"offset", D.optional(D.numberBuilder())} <>
    R.Property{"metadata", D.requiredBuilder(D.object(R.Record{R.Property{"enabled", D.optional(D.boolean())} <> Nil{}}))} <>
    R.Property{"nullable", D.optional(D.union(D.string() <> D.null() <> Nil{}))} <> Nil{}}))

def nullable(schema: V.Value) -> V.Value:
  V.ObjectValue{R.Record{R.Property{"anyOf", V.ArrayValue{schema <> D.schemaBuilder(D.null()) <> Nil{}}} <> Nil{}}}

def object(properties: List<&2, R.Property<V.Value>>, names: List<&2, V.Value>) -> V.Value:
  V.ObjectValue{R.Record{R.Property{"type", V.Text{"object"}} <> R.Property{"properties", V.ObjectValue{R.Record{properties}}} <> R.Property{"required", V.ArrayValue{names}} <> R.Property{"additionalProperties", V.Boolean{False{}}} <> Nil{}}}

def expected() -> V.Value:
  object(
    R.Property{"path", D.schemaBuilder(D.string())} <>
    R.Property{"offset", nullable(D.schemaBuilder(D.numberBuilder()))} <>
    R.Property{"metadata", object(R.Property{"enabled", nullable(D.schemaBuilder(D.boolean()))} <> Nil{}, V.Text{"enabled"} <> Nil{})} <>
    R.Property{"nullable", nullable(D.schemaBuilder(D.string()))} <> Nil{},
    V.Text{"path"} <> V.Text{"offset"} <> V.Text{"metadata"} <> V.Text{"nullable"} <> Nil{})

def originalRequired(value: Maybe<&2, V.Value>) -> Bool:
  match value:
    case Some{raw}: V.equal(raw, V.ArrayValue{V.Text{"path"} <> V.Text{"metadata"} <> Nil{}})
    case _: False{}

def unchanged(value: V.Value) -> Bool:
  match value:
    case V.ObjectValue{+fields}: Bool.not(Maybe.is_some(&2, V.Value, R.get(V.Value, fields, "additionalProperties"))) && originalRequired(R.get(V.Value, fields, "required"))
    case _: False{}

def derivesStrictSchemas() -> IO(Unit):
  +schema = parameters()
  do IO<Unit>:
    converted : Result<&2, &2, C.Error, V.Value> = C.makeStrictJsonSchema(schema)
    Assert.assertion(Check.sameSchema(converted, Done{expected()}), "strict provider schema preserves optional/nullable and nested fields")
    Assert.assertion(unchanged(schema), "original tool declaration retains its required fields and additionalProperties policy")
    IO.print("PASS derives strict provider schemas without changing tool definitions")

def completedGrammar(first: String, result: Result<&2, &2, C.Error, C.GrammarToolInputJsonUpdate>) -> IO(Unit):
  match result:
    case Done{C.GrammarToolInputJsonUpdate{+buffer, Some{second}}}:
      do IO<Unit>:
        Assert.assertion(String.eq(first ++ second, "{\"payload\":\"a\\\"\\nb\"}"), "grammar deltas form the expected JSON object")
        same : C.GrammarToolInputJsonBuffer <- Grammar.checked(C.appendGrammarToolInputJsonDelta(buffer, "payload", "a\"\nb", True{}), buffer, Done{None{}}, buffer, "repeated close emits no delta")
        unchanged : C.GrammarToolInputJsonBuffer <- Grammar.checked(C.appendGrammarToolInputJsonDelta(buffer, "payload", "changed", True{}), buffer, Fail{"grammar tool input for property \"payload\" changed after it was closed"}, buffer, "closed grammar input rejects changes")
        IO.print("PASS keeps grammar input JSON deltas append-only")
    case _: IO.die(Unit, 1, "closing grammar delta failed")

def startedGrammar(result: Result<&2, &2, C.Error, C.GrammarToolInputJsonUpdate>) -> IO(Unit):
  match result:
    case Done{C.GrammarToolInputJsonUpdate{buffer, Some{first}}}: completedGrammar(first, C.appendGrammarToolInputJsonDelta(buffer, "payload", "a\"\nb", True{}))
    case _: IO.die(Unit, 1, "initial grammar delta failed")

def grammarDeltas() -> IO(Unit):
  +original = {C.GrammarToolInputJsonBuffer{"", False{}, False{}} : C.GrammarToolInputJsonBuffer}
  do IO<Unit>:
    startedGrammar(C.appendGrammarToolInputJsonDelta(original, "payload", "a\"", False{}))
    Assert.assertion(Grammar.sameBuffer(original, C.GrammarToolInputJsonBuffer{"", False{}, False{}}), "retained grammar buffer remains unchanged")

def sampleParameters() -> V.Value:
  V.ObjectValue{R.Record{R.Property{"type", V.Text{"object"}} <> R.Property{"properties", V.ObjectValue{R.Record{R.Property{"payload", D.schemaBuilder(D.string())} <> Nil{}}}} <> R.Property{"required", V.ArrayValue{V.Text{"payload"} <> Nil{}}} <> R.Property{"additionalProperties", V.Boolean{False{}}} <> Nil{}}}

def sampleTool(schema: V.Value, config: Maybe<&2, T.ToolConstrainedSampling>) -> T.Tool<V.Value>:
  T.Tool{"sample_tool", "Sample tool", schema, config}

def strictConfig(required: Bool) -> Maybe<&2, T.ToolConstrainedSampling>:
  Some{T.SamplingConfigured{T.JsonSchemaSampling{Bool.pick(T.SamplingStrictness, required, T.Require{}, T.Prefer{})}}}

def larkConfig() -> Maybe<&2, T.ToolConstrainedSampling>:
  Some{T.SamplingConfigured{T.GrammarSampling{T.GrammarVariants{Some{"start: /[a-z]+/"}, None{}}}}}

def sameStrict(left: Maybe<&2, T.Nullable<Bool>>, right: Maybe<&2, T.Nullable<Bool>>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{T.NullValue{}} Some{T.NullValue{}}: True{}
    case Some{T.PresentValue{a}} Some{T.PresentValue{b}}: Grammar.sameBool(a,b)
    case _ _: False{}

def functionMatches(result: Result<&2, &2, C.Error, List<&2, O.OpenAITool>>, schema: V.Value, strict: Maybe<&2, T.Nullable<Bool>>) -> Bool:
  match result:
    case Done{O.FunctionTool{"sample_tool", "Sample tool", actual, setting, None{}} <> Nil{}}: V.equal(actual,schema) && sameStrict(setting,strict)
    case _: False{}

def customMatches(result: Result<&2, &2, C.Error, List<&2, O.OpenAITool>>) -> Bool:
  match result:
    case Done{O.CustomTool{"sample_tool", "Sample tool", O.GrammarToolFormat{T.OpenAILark{}, "start: /[a-z]+/"}, None{}} <> Nil{}}: True{}
    case _: False{}

def conversionFails(result: Result<&2, &2, C.Error, List<&2, O.OpenAITool>>, expected: String) -> Bool:
  match result:
    case Fail{error}: String.eq(C.errorMessage(error),expected)
    case _: False{}

def supportedConstraints() -> IO(Unit):
  +schema = sampleParameters()
  +grammar = sampleTool(schema,larkConfig())
  do IO<Unit>:
    Assert.assertion(functionMatches(O.convertResponsesTools(sampleTool(schema,strictConfig(False{})) <> Nil{},None{}),schema,Some{T.PresentValue{True{}}}), "preferred supported strict schema")
    Assert.assertion(conversionFails(O.convertResponsesTools(sampleTool(schema,strictConfig(True{})) <> Nil{},Some{O.ConvertResponsesToolsOptions{None{},Some{False{}},None{},None{}}}), "Tool \"sample_tool\" requires JSON-schema constrained sampling, but strict tools are unsupported."), "required strict capability rejection")
    Assert.assertion(customMatches(O.convertResponsesTools(grammar <> Nil{},Some{O.ConvertResponsesToolsOptions{None{},None{},Some{True{}},None{}}})), "supported Lark tool declaration")
    Assert.assertion(conversionFails(O.convertResponsesTools(sampleTool(schema,Some{T.SamplingConfigured{T.GrammarSampling{T.GrammarVariants{None{},None{}}}}}) <> Nil{},Some{O.ConvertResponsesToolsOptions{None{},None{},Some{True{}},None{}}}), "Tool \"sample_tool\" cannot use grammar constrained sampling: no supported grammar variant was provided."), "missing grammar variant rejection")
    Assert.assertion(functionMatches(O.convertResponsesTools(grammar <> Nil{},Some{O.ConvertResponsesToolsOptions{None{},Some{False{}},Some{False{}},None{}}}),schema,None{}), "unsupported grammar falls back without a strict field")
    Assert.assertion(functionMatches(O.convertResponsesTools(sampleTool(schema,Some{T.SamplingDisabled{}}) <> Nil{},None{}),schema,Some{T.PresentValue{False{}}}) && functionMatches(O.convertResponsesTools(sampleTool(schema,None{}) <> Nil{},None{}),schema,Some{T.PresentValue{False{}}}), "disabled sampling equals absent sampling")
    IO.print("PASS converts supported constraints and falls back when unsupported")

def schemaFails(result: Result<&2, &2, C.Error, V.Value>, expected: String) -> Bool:
  match result:
    case Fail{error}: String.eq(C.errorMessage(error),expected)
    case _: False{}

def rejectedSchema(+schema: V.Value, +reason: String) -> IO(Unit):
  do IO<Unit>:
    Assert.assertion(schemaFails(C.makeStrictJsonSchema(schema),reason), "unsupported strict schema error")
    Assert.assertion(Check.sameResolution(C.resolveJsonSchemaStrictSampling(sampleTool(schema,strictConfig(False{})),True{}),Done{None{}}), "unsupported preferred schema falls back")
    Assert.assertion(functionMatches(O.convertResponsesTools(sampleTool(schema,strictConfig(False{})) <> Nil{},Some{O.ConvertResponsesToolsOptions{None{},Some{True{}},None{},None{}}}),schema,Some{T.PresentValue{False{}}}), "fallback retains original schema with strict false")
    Assert.assertion(Check.sameResolution(C.resolveJsonSchemaStrictSampling(sampleTool(schema,strictConfig(True{})),True{}),Fail{"Tool \"sample_tool\" requires JSON-schema constrained sampling, but " ++ reason ++ "."}), "unsupported required schema fails")

def rejectsUnsafeSchemas() -> IO(Unit):
  do IO<Unit>:
    rejectedSchema(V.ObjectValue{R.Record{R.Property{"type", V.Text{"object"}} <> R.Property{"properties", V.ObjectValue{R.Record{R.Property{"metadata", V.ObjectValue{R.Record{R.Property{"type", V.Text{"object"}} <> R.Property{"properties", V.ObjectValue{R.new(V.Value)}} <> R.Property{"additionalProperties", D.schemaBuilder(D.string())} <> Nil{}}}} <> Nil{}}}} <> R.Property{"required", V.ArrayValue{V.Text{"metadata"} <> Nil{}}} <> Nil{}}}, "schema-valued or true additionalProperties is unsupported")
    rejectedSchema(V.ObjectValue{R.Record{R.Property{"allOf", V.ArrayValue{D.schemaBuilder(D.object(R.Record{R.Property{"a", D.requiredBuilder(D.string())} <> Nil{}})) <> D.schemaBuilder(D.object(R.Record{R.Property{"b", D.requiredBuilder(D.numberBuilder())} <> Nil{}})) <> Nil{}}} <> Nil{}}}, "allOf schemas are unsupported")
    rejectedSchema(D.schemaBuilder(D.object(R.Record{R.Property{"value", D.requiredBuilder(D.union(D.object(R.Record{R.Property{"nested", D.requiredBuilder(D.string())} <> Nil{}}) <> D.null() <> Nil{}))} <> Nil{}})), "object and array unions are unsupported")
    rejectedSchema(V.ObjectValue{R.Record{R.Property{"type", V.Text{"object"}} <> R.Property{"properties", V.ObjectValue{R.Record{R.Property{"child", V.ObjectValue{R.Record{R.Property{"$ref", V.Text{"https://example.com/child.json"}} <> Nil{}}}} <> Nil{}}}} <> R.Property{"required", V.ArrayValue{V.Text{"child"} <> Nil{}}} <> Nil{}}}, "$ref schemas are unsupported")
    IO.print("PASS falls back or rejects schemas that cannot be safely converted")

def replayContext(arguments: R.Record<V.Value>) -> T.TranscriptContext<V.Value,R.Record<V.Value>,Unit,Unit>:
  call = {T.AssistantToolCall{T.ToolCall{"call_1|ctc_1","sample_tool",arguments,None{},None{}}} : T.AssistantContent<R.Record<V.Value>>}
  assistant = Responses.assistant(call <> Nil{},"openai-responses","openai","target",T.ToolUse{})
  output = {T.ToolResult{T.ToolResultMessage{"call_1|ctc_1","sample_tool",T.TextImageText{T.TextContent{"done",None{}}} <> Nil{},None{},None{},False{},F.fromU32(1)}} : T.Message<V.Value,R.Record<V.Value>,Unit,Unit>}
  T.TranscriptContext{T.Assistant{assistant} <> output <> Nil{}}

def replayGrammar(arguments: R.Record<V.Value>) -> IO(Result<&2,&2,O.MessageError,List<&2,O.ResponseInputItem>>):
  options = {O.ConvertResponsesMessagesOptions{None{},Some{R.Record{R.Property{"sample_tool","payload"} <> Nil{}}},None{},None{},None{},None{}} : O.ConvertResponsesMessagesOptions}
  O.convertResponsesMessages(~Unit,~Unit,~Unit,Responses.model(True{},True{},None{}),replayContext(arguments),"openai" <> Nil{},Some{options})

def grammarReplay() -> IO(Unit):
  do IO<Unit>:
    missing : Result<&2,&2,O.MessageError,List<&2,O.ResponseInputItem>> <- replayGrammar(R.new(V.Value))
    Assert.assertion(Responses.matches(missing,Fail{"Grammar tool call \"sample_tool\" requires argument \"payload\" to be a string."}),"missing grammar replay input fails")
    numeric : Result<&2,&2,O.MessageError,List<&2,O.ResponseInputItem>> <- replayGrammar(R.Record{R.Property{"payload",V.Number{F.fromU32(42)}} <> Nil{}})
    Assert.assertion(Responses.matches(numeric,Fail{"Grammar tool call \"sample_tool\" requires argument \"payload\" to be a string."}),"numeric grammar replay input fails")
    replayed : Result<&2,&2,O.MessageError,List<&2,O.ResponseInputItem>> <- replayGrammar(R.Record{R.Property{"payload",V.Text{"abc"}} <> Nil{}})
    Assert.assertion(Responses.matches(replayed,Done{"[{\"type\":\"custom_tool_call\",\"id\":\"ctc_1\",\"call_id\":\"call_1\",\"name\":\"sample_tool\",\"input\":\"abc\"},{\"type\":\"custom_tool_call_output\",\"call_id\":\"call_1\",\"output\":\"done\"}]"}),"custom Responses call and output replay")
    IO.print("PASS replays grammar calls as custom Responses items")

def initialGrammarInput() -> IO(Unit):
  do IO<Unit>:
    InitialInput.run()
    IO.print("PASS starts custom Responses tool calls with their initial input")

def main() -> IO(Unit):
  do IO<Unit>:
    supportedConstraints()
    derivesStrictSchemas()
    rejectsUnsafeSchemas()
    grammarReplay()
    grammarDeltas()
    initialGrammarInput()
