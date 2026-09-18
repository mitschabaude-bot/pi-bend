import Base
import ../types.bend as T
import ./strict-json-schema.bend as Strict
import ../../../runtime/src/schema-value.bend as V

type Error is Data:
  UnsupportedStrictJsonSchema{error: Strict.Error}
  RequiredStrictSchema{toolName: String, error: Strict.Error}
  StrictToolsUnsupported{toolName: String}

def errorMessage(error: Error) -> String:
  match error:
    case UnsupportedStrictJsonSchema{error}: Strict.errorMessage(error)
    case RequiredStrictSchema{name, error}: "Tool \"" ++ name ++ "\" requires JSON-schema constrained sampling, but " ++ Strict.errorMessage(error) ++ "."
    case StrictToolsUnsupported{name}: "Tool \"" ++ name ++ "\" requires JSON-schema constrained sampling, but strict tools are unsupported."

def strictSchemaResult(result: Result<&2, &2, Strict.Error, V.Value>) -> Result<&2, &2, Error, V.Value>:
  match result:
    case Done{schema}: Done{schema}
    case Fail{error}: Fail{UnsupportedStrictJsonSchema{error}}

def makeStrictJsonSchema(schema: V.Value) -> Result<&2, &2, Error, V.Value>:
  strictSchemaResult(Strict.makeStrictJsonSchema(schema))

def getJsonSchemaToolParameters(tool: T.Tool<V.Value>, strict: Maybe<&2, Bool>) -> Result<&2, &2, Error, V.Value>:
  match tool strict:
    case T.Tool{_, _, schema, _} Some{True{}}: makeStrictJsonSchema(schema)
    case T.Tool{_, _, schema, _} _: Done{schema}

def selectedStrict(name: String, policy: T.SamplingStrictness, result: Result<&2, &2, Strict.Error, V.Value>) -> Result<&2, &2, Error, Maybe<&2, Bool>>:
  match policy result:
    case _ Done{_}: Done{Some{True{}}}
    case T.Prefer{} Fail{_}: Done{None{}}
    case T.Require{} Fail{error}: Fail{RequiredStrictSchema{name, error}}

def supportedStrict(name: String, schema: V.Value, policy: T.SamplingStrictness, supported: Bool) -> Result<&2, &2, Error, Maybe<&2, Bool>>:
  match policy supported:
    case T.Prefer{} False{}: Done{None{}}
    case T.Require{} False{}: Fail{StrictToolsUnsupported{name}}
    case value True{}: selectedStrict(name, value, Strict.makeStrictJsonSchema(schema))

def resolveJsonSchemaStrictSampling(tool: T.Tool<V.Value>, supportsStrictMode: Bool) -> Result<&2, &2, Error, Maybe<&2, Bool>>:
  match tool:
    case T.Tool{name, _, schema, Some{T.SamplingConfigured{T.JsonSchemaSampling{policy}}}}: supportedStrict(name, schema, policy, supportsStrictMode)
    case _: Done{None{}}
