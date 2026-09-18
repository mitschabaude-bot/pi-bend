import Base
import ../types.bend as T
import ./schema-json.bend as SchemaJson
import ./constrained-sampling-json.bend as Sampling
import ./json.bend as Json
import ../../../runtime/src/schema-value.bend as S
import ../../../runtime/src/record.bend as R

# Recoverable equivalents of upstream JSON round-trip failures. Unsupported
# live-object behavior stays explicit until the schema-object adapter exists.
type DeclarationError is Data:
  OmittedSchema{}
  BigIntSchema{}
  UnsupportedSchemaHook{}
  InvalidSchemaSnapshot{}
  NumberEncodingFailure{}

type DeclarationResult<-A: Data> is Data:
  Success{value: A}
  Failure{error: DeclarationError}

def rebuild(-M: Data, name: String, description: String, sampling: Maybe<&2, T.ToolConstrainedSampling>, snapshot: S.Snapshot<M>) -> DeclarationResult<T.Tool<S.Value<M>>>:
  match snapshot:
    case S.Projected{Some{parameters}}: Success{T.Tool{name, description, parameters, sampling}}
    case S.Projected{None{}}: Failure{OmittedSchema{}}
    case S.BigIntError{}: Failure{BigIntSchema{}}
    case S.UnsupportedToJSON{}: Failure{UnsupportedSchemaHook{}}

# Source: transcript.ts toToolDeclaration. Schema data is cloned/projected;
# constrainedSampling is retained rather than passed through schema projection.
def toToolDeclaration(-M: Data, tool: T.Tool<S.Value<M>>) -> DeclarationResult<T.Tool<S.Value<M>>>:
  match tool:
    case T.Tool{name, description, parameters, sampling}: rebuild(M, name, description, sampling, S.snapshot(M, parameters))

def addSampling(fields: R.Record<T.JsonValue>, sampling: Maybe<&2, T.ToolConstrainedSampling>) -> R.Record<T.JsonValue>:
  match sampling:
    case None{}: fields
    case Some{value}: R.set(T.JsonValue, fields, "constrainedSampling", Sampling.toJson(value))

def encoded(result: Maybe<&2, String>) -> DeclarationResult<String>:
  match result:
    case Some{value}: Success{value}
    case None{}: Failure{NumberEncodingFailure{}}

def serializeFields(name: String, description: String, sampling: Maybe<&2, T.ToolConstrainedSampling>, parameters: SchemaJson.Conversion) -> DeclarationResult<String>:
  match parameters:
    case SchemaJson.Converted{value}:
      fields = R.set(T.JsonValue, R.set(T.JsonValue, R.set(T.JsonValue, R.new(T.JsonValue), "name", T.JsonString{name}), "description", T.JsonString{description}), "parameters", value)
      encoded(Json.stringify(T.JsonObject{addSampling(fields, sampling)}))
    case SchemaJson.RootOmitted{}: Failure{OmittedSchema{}}
    case SchemaJson.BigIntError{}: Failure{BigIntSchema{}}
    case SchemaJson.UnsupportedToJSON{}: Failure{UnsupportedSchemaHook{}}
    case SchemaJson.InvalidSnapshot{}: Failure{InvalidSchemaSnapshot{}}

# Input is already the result of toToolDeclaration; do not project a second time.
def serializeDeclaration(-M: Data, result: DeclarationResult<T.Tool<S.Value<M>>>) -> DeclarationResult<String>:
  match result:
    case Failure{error}: Failure{error}
    case Success{T.Tool{name, description, parameters, sampling}}:
      serializeFields(name, description, sampling, SchemaJson.fromSnapshot(M, S.Projected{Some{parameters}}))

def compareRight(left: String, right: DeclarationResult<String>) -> DeclarationResult<Bool>:
  match right:
    case Failure{error}: Failure{error}
    case Success{value}: Success{String.eq(left, value)}

def compareLeft(-M: Data, left: DeclarationResult<String>, right: T.Tool<S.Value<M>>) -> DeclarationResult<Bool>:
  match left:
    case Failure{error}: Failure{error}
    case Success{value}: compareRight(value, serializeDeclaration(M, toToolDeclaration(M, right)))

def declarationsEqual(-M: Data, left: T.Tool<S.Value<M>>, right: T.Tool<S.Value<M>>) -> DeclarationResult<Bool>:
  compareLeft(M, serializeDeclaration(M, toToolDeclaration(M, left)), right)
