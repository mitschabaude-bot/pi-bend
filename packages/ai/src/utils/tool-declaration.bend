import Base
import ../types.bend as T
import ./schema-json.bend as SchemaJson
import ./constrained-sampling-json.bend as Sampling
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

def addSampling(fields: R.Record<T.JsonValue>, sampling: Maybe<&2, T.ToolConstrainedSampling>) -> R.Record<T.JsonValue>:
  match sampling:
    case None{}: fields
    case Some{value}: R.set(T.JsonValue, fields, "constrainedSampling", Sampling.toJson(value))

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
