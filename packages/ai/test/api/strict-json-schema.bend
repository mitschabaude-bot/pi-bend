import Base
import ../../src/types.bend as T
import ../../src/api/constrained-sampling.bend as C
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/test/schema.bend as Assert

def sameSchema(actual: Result<&2, &2, C.Error, V.Value>, expected: Result<&2, &2, String, V.Value>) -> Bool:
  match actual expected:
    case Done{a} Done{b}: V.equal(a, b)
    case Fail{a} Fail{b}: String.eq(C.errorMessage(a), b)
    case _ _: False{}

def sameResolution(actual: Result<&2, &2, C.Error, Maybe<&2, Bool>>, expected: Result<&2, &2, String, Maybe<&2, Bool>>) -> Bool:
  match actual expected:
    case Done{None{}} Done{None{}}: True{}
    case Done{Some{True{}}} Done{Some{True{}}}: True{}
    case Fail{a} Fail{b}: String.eq(C.errorMessage(a), b)
    case _ _: False{}

def config(index: U32) -> Maybe<&2, T.ToolConstrainedSampling>:
  match index:
    case 0: None{}
    case 1: Some{T.SamplingDisabled{}}
    case 2: Some{T.SamplingConfigured{T.JsonSchemaSampling{T.Prefer{}}}}
    case 3: Some{T.SamplingConfigured{T.JsonSchemaSampling{T.Require{}}}}
    case _: Some{T.SamplingConfigured{T.GrammarSampling{T.GrammarVariants{None{}, None{}}}}}

def tool(schema: V.Value, policy: U32) -> T.Tool<V.Value>:
  T.Tool{"sample_tool", "Sample tool", schema, config(policy)}

def checkResolutions(expected: List<&2, Result<&2, &2, String, Maybe<&2, Bool>>>, +schema: V.Value, +index: U32) -> Bool:
  match expected:
    case Nil{}: U32.is_eq(index, 10)
    case head <> rest: sameResolution(C.resolveJsonSchemaStrictSampling(tool(schema, (index / 2 : U32)), U32.is_eq((index % 2 : U32), 1)), head) && checkResolutions(rest, schema, (index + 1 : U32))

def check(+schema: V.Value, +expected: Result<&2, &2, String, V.Value>, resolutions: List<&2, Result<&2, &2, String, Maybe<&2, Bool>>>, label: String) -> IO(Unit):
  Assert.assertion(sameSchema(C.makeStrictJsonSchema(schema), expected) && sameSchema(C.getJsonSchemaToolParameters(tool(schema, 0), Some{True{}}), expected) && sameSchema(C.getJsonSchemaToolParameters(tool(schema, 3), Some{False{}}), Done{schema}) && sameSchema(C.getJsonSchemaToolParameters(tool(schema, 3), None{}), Done{schema}) && checkResolutions(resolutions, schema, 0), label)
