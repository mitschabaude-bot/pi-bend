import Base
import ../src/api/google-shared.bend as Shared
import ../src/api/constrained-sampling.bend as Sampling
import ../src/types.bend as T
import ./anthropic-harness.bend as A
import ../../runtime/src/schema-value.bend as V

# pi-mono f07218c4d packages/ai/test/google-shared-convert-tools.test.ts.
def makeTool(parameters: String, sampling: Maybe<&2, T.ToolConstrainedSampling>) -> T.Tool<V.Value>:
  T.Tool{"test_tool", "A test tool", A.schema(parameters), sampling}

def declared(result: Result<&2, &2, Sampling.Error, Maybe<&2, T.JsonValue>>) -> Maybe<&2, T.JsonValue>:
  match result:
    case Done{value}: A.firstElement(A.fieldOf(A.firstElement(value), "functionDeclarations"))
    case Fail{_}: None{}

def declaration(parameters: String, useParameters: Bool) -> Maybe<&2, T.JsonValue>:
  declared(Shared.convertTools(makeTool(parameters, None{}) <> Nil{}, useParameters, True{}))

def stripped(+name: String, parameters: String, +want: String) -> IO(Unit):
  do IO<Unit>:
    +decl : Maybe<&2, T.JsonValue> <- IO.pure(Maybe<&2, T.JsonValue>, declaration(parameters, True{}))
    A.check(Maybe.is_some(&2, T.JsonValue, decl), name ++ ": declaration")
    A.equalJson(A.fieldOf(decl, "parameters"), want, name)
    A.pass(name)

def modeOf(result: Result<&2, &2, Sampling.Error, Maybe<&2, String>>) -> Maybe<&2, String>:
  match result:
    case Done{value}: value
    case Fail{_}: None{}

def errorOf(result: Result<&2, &2, Sampling.Error, Maybe<&2, String>>) -> Maybe<&2, String>:
  match result:
    case Fail{error}: Some{Sampling.errorMessage(error)}
    case Done{_}: None{}

def emptyDeclarations(result: Result<&2, &2, Sampling.Error, Maybe<&2, T.JsonValue>>) -> Bool:
  match result:
    case Done{None{}}: True{}
    case _: False{}

def validated() -> IO(Unit):
  +name = {"uses validated function calling for strict tools on Gemini 3" : String}
  +tool = makeTool("{\"type\":\"object\",\"properties\":{}}", Some{T.SamplingConfigured{T.JsonSchemaSampling{T.Require{}}}})
  do IO<Unit>:
    A.check(Shared.supportsGoogleStrictToolSampling("gemini-3.1-pro-preview"), name ++ ": gemini 3.1")
    A.check(Bool.not(Shared.supportsGoogleStrictToolSampling("gemini-2.5-pro")), name ++ ": gemini 2.5")
    A.equalText(modeOf(Shared.resolveGoogleFunctionCallingMode(tool <> Nil{}, None{}, True{})), Some{"VALIDATED"}, name ++ ": mode")
    A.check(A.contains(errorOf(Shared.resolveGoogleFunctionCallingMode(tool <> Nil{}, None{}, False{})), "Tool \"test_tool\" requires JSON-schema constrained sampling"), name ++ ": unsupported")
    A.pass(name)

def toolParameters(tool: T.Tool<V.Value>) -> V.Value:
  match tool:
    case T.Tool{_, _, parameters, _}: parameters

def run() -> IO(Unit):
  do IO<Unit>:
    stripped("strips JSON Schema meta keys from parameters when useParameters=true", "{\"$schema\":\"http://json-schema.org/draft-07/schema#\",\"$id\":\"urn:bash-tool\",\"$comment\":\"A bash tool for demonstration\",\"$defs\":{\"commandDef\":{\"type\":\"string\"}},\"definitions\":{\"legacyDef\":{\"type\":\"number\"}},\"type\":\"object\",\"properties\":{\"command\":{\"type\":\"string\"}},\"required\":[\"command\"]}", "{\"type\":\"object\",\"properties\":{\"command\":{\"type\":\"string\"}},\"required\":[\"command\"]}")
    stripped("recursively strips nested JSON Schema meta keys", "{\"$schema\":\"http://json-schema.org/draft-07/schema#\",\"type\":\"object\",\"properties\":{\"deep\":{\"$schema\":\"http://json-schema.org/draft-07/schema#\",\"$id\":\"urn:nested\",\"type\":\"string\"}}}", "{\"type\":\"object\",\"properties\":{\"deep\":{\"type\":\"string\"}}}")
    stripped("preserves $ref while stripping meta keys", "{\"$schema\":\"http://json-schema.org/draft-07/schema#\",\"type\":\"object\",\"properties\":{\"refProp\":{\"$ref\":\"#/$defs/someDef\",\"type\":\"string\"}}}", "{\"type\":\"object\",\"properties\":{\"refProp\":{\"$ref\":\"#/$defs/someDef\",\"type\":\"string\"}}}")
    +original : T.Tool<V.Value> <- IO.pure(T.Tool<V.Value>, makeTool("{\"$schema\":\"http://json-schema.org/draft-07/schema#\",\"type\":\"object\",\"properties\":{\"command\":{\"type\":\"string\"}},\"required\":[\"command\"]}", None{}))
    converted : Result<&2, &2, Sampling.Error, Maybe<&2, T.JsonValue>> <- IO.pure(Result<&2, &2, Sampling.Error, Maybe<&2, T.JsonValue>>, Shared.convertTools(original <> Nil{}, True{}, True{}))
    A.check(V.equal(toolParameters(original), A.schema("{\"$schema\":\"http://json-schema.org/draft-07/schema#\",\"type\":\"object\",\"properties\":{\"command\":{\"type\":\"string\"}},\"required\":[\"command\"]}")), "original parameters unchanged")
    A.pass("does not mutate the original Tool.parameters object")
    +kept : Maybe<&2, T.JsonValue> <- IO.pure(Maybe<&2, T.JsonValue>, declaration("{\"$schema\":\"http://json-schema.org/draft-07/schema#\",\"type\":\"object\",\"properties\":{\"command\":{\"type\":\"string\"}},\"required\":[\"command\"]}", False{}))
    A.equalJson(A.fieldOf(kept, "parametersJsonSchema"), "{\"$schema\":\"http://json-schema.org/draft-07/schema#\",\"type\":\"object\",\"properties\":{\"command\":{\"type\":\"string\"}},\"required\":[\"command\"]}", "parametersJsonSchema")
    A.pass("preserves $schema in parametersJsonSchema when useParameters=false")
    stripped("handles tools without $schema gracefully", "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"}},\"required\":[\"path\"]}", "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"}},\"required\":[\"path\"]}")
    validated()
    A.check(emptyDeclarations(Shared.convertTools(Nil{}, False{}, True{})) && emptyDeclarations(Shared.convertTools(Nil{}, True{}, True{})), "empty tool list")
    A.pass("returns undefined for empty tool list")
