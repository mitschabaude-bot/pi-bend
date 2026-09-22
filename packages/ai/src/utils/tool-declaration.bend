import Base
import ../types.bend as T
import ./schema-json.bend as SchemaJson
import ./json.bend as Json
import ../../../runtime/src/schema-value.bend as S
import ../../../runtime/src/record.bend as R

# Serialization can fail if a numeric value cannot be encoded.
type DeclarationError is Data:
  NumberEncodingFailure{}

type DeclarationResult<-A: Data> is Data:
  Success{value: A}
  Failure{error: DeclarationError}

# Immutable schema values can be shared directly; there is no cloning or
# object projection. AgentTool.toTool supplies the explicit declaration view.
def toToolDeclaration(tool: T.Tool<S.Value>) -> DeclarationResult<T.Tool<S.Value>>:
  Success{tool}

# Constrained-sampling declarations serialize like pi's JSON shape.
def optionalField(fields: R.Record<T.JsonValue>, key: String, value: Maybe<&2, String>) -> R.Record<T.JsonValue>:
  match value:
    case None{}: fields
    case Some{text}: R.set(T.JsonValue, fields, key, T.JsonString{text})

def grammarVariants(value: T.GrammarVariants) -> T.JsonValue:
  match value:
    case T.GrammarVariants{lark, regex}: T.JsonObject{optionalField(optionalField(R.new(T.JsonValue), "openai_lark", lark), "openai_regex", regex)}

def strictness(value: T.SamplingStrictness) -> String:
  match value:
    case T.Prefer{}: "prefer"
    case T.Require{}: "require"

def configFields(tag: String, key: String, value: T.JsonValue) -> R.Record<T.JsonValue>:
  R.set(T.JsonValue, R.set(T.JsonValue, R.new(T.JsonValue), "type", T.JsonString{tag}), key, value)

def samplingConfig(value: T.ConstrainedSamplingConfig) -> T.JsonValue:
  match value:
    case T.JsonSchemaSampling{strict}: T.JsonObject{configFields("json_schema", "strict", T.JsonString{strictness(strict)})}
    case T.GrammarSampling{variants}: T.JsonObject{configFields("grammar", "variants", grammarVariants(variants))}

def samplingToJson(value: T.ToolConstrainedSampling) -> T.JsonValue:
  match value:
    case T.SamplingDisabled{}: T.JsonBoolean{False{}}
    case T.SamplingConfigured{value}: samplingConfig(value)

def addSampling(fields: R.Record<T.JsonValue>, sampling: Maybe<&2, T.ToolConstrainedSampling>) -> R.Record<T.JsonValue>:
  match sampling:
    case None{}: fields
    case Some{value}: R.set(T.JsonValue, fields, "constrainedSampling", samplingToJson(value))

def encoded(result: Maybe<&2, String>) -> DeclarationResult<String>:
  match result:
    case Some{value}: Success{value}
    case None{}: Failure{NumberEncodingFailure{}}

def serializeFields(name: String, description: String, sampling: Maybe<&2, T.ToolConstrainedSampling>, parameters: T.JsonValue) -> DeclarationResult<String>:
  fields = R.set(T.JsonValue, R.set(T.JsonValue, R.set(T.JsonValue, R.new(T.JsonValue), "name", T.JsonString{name}), "description", T.JsonString{description}), "parameters", parameters)
  encoded(Json.stringify(T.JsonObject{addSampling(fields, sampling)}))

def serializeDeclaration(result: DeclarationResult<T.Tool<S.Value>>) -> DeclarationResult<String>:
  match result:
    case Failure{error}: Failure{error}
    case Success{T.Tool{name, description, parameters, sampling}}:
      serializeFields(name, description, sampling, SchemaJson.toJson(parameters))

def sameOptionalText(left: Maybe<&2, String>, right: Maybe<&2, String>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{b}: String.eq(a, b)
    case _ _: False{}

def sameConfig(left: T.ConstrainedSamplingConfig, right: T.ConstrainedSamplingConfig) -> Bool:
  match left right:
    case T.JsonSchemaSampling{T.Prefer{}} T.JsonSchemaSampling{T.Prefer{}}: True{}
    case T.JsonSchemaSampling{T.Require{}} T.JsonSchemaSampling{T.Require{}}: True{}
    case T.GrammarSampling{T.GrammarVariants{a, b}} T.GrammarSampling{T.GrammarVariants{c, d}}: sameOptionalText(a, c) && sameOptionalText(b, d)
    case _ _: False{}

def sameSampling(left: Maybe<&2, T.ToolConstrainedSampling>, right: Maybe<&2, T.ToolConstrainedSampling>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{T.SamplingDisabled{}} Some{T.SamplingDisabled{}}: True{}
    case Some{T.SamplingConfigured{a}} Some{T.SamplingConfigured{b}}: sameConfig(a, b)
    case _ _: False{}

def declarationsEqual(left: T.Tool<S.Value>, right: T.Tool<S.Value>) -> DeclarationResult<Bool>:
  match left right:
    case T.Tool{a, b, c, d} T.Tool{e, f, g, h}: Success{String.eq(a, e) && String.eq(b, f) && S.equal(c, g) && sameSampling(d, h)}
