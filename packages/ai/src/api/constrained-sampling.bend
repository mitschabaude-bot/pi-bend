import Base
import ../types.bend as T
import ./strict-json-schema.bend as Strict
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/json-string.bend as JsonString
import ../../../runtime/src/utf16.bend as Utf16

type Error is Data:
  UnsupportedStrictJsonSchema{error: Strict.Error}
  RequiredStrictSchema{toolName: String, error: Strict.Error}
  StrictToolsUnsupported{toolName: String}
  GrammarArgumentNotString{toolName: String, inputProperty: String}
  GrammarInputClosed{inputProperty: String}
  GrammarInputChanged{inputProperty: String}

def errorMessage(error: Error) -> String:
  match error:
    case UnsupportedStrictJsonSchema{error}: Strict.errorMessage(error)
    case RequiredStrictSchema{name, error}: "Tool \"" ++ name ++ "\" requires JSON-schema constrained sampling, but " ++ Strict.errorMessage(error) ++ "."
    case StrictToolsUnsupported{name}: "Tool \"" ++ name ++ "\" requires JSON-schema constrained sampling, but strict tools are unsupported."
    case GrammarArgumentNotString{name, property}: "Grammar tool call \"" ++ name ++ "\" requires argument \"" ++ property ++ "\" to be a string."
    case GrammarInputClosed{property}: "grammar tool input for property \"" ++ property ++ "\" changed after it was closed"
    case GrammarInputChanged{property}: "grammar tool input for property \"" ++ property ++ "\" changed non-monotonically"

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

def grammarInput(value: Maybe<&2, V.Value>, toolName: String, inputProperty: String) -> Result<&2, &2, Error, String>:
  match value:
    case Some{V.Text{text}}: Done{text}
    case _: Fail{GrammarArgumentNotString{toolName, inputProperty}}

def getGrammarToolInput(toolName: String, arguments: R.Record<V.Value>, +inputProperty: String) -> Result<&2, &2, Error, String>:
  grammarInput(R.get(V.Value, arguments, inputProperty), toolName, inputProperty)

type GrammarToolInputJsonBuffer is Data:
  GrammarToolInputJsonBuffer{input: String, started: Bool, closed: Bool}

# State is returned explicitly. Retaining an earlier buffer is a stable snapshot.
type GrammarToolInputJsonUpdate is Data:
  GrammarToolInputJsonUpdate{buffer: GrammarToolInputJsonBuffer, delta: Maybe<&2, String>}

# Provider chunks may divide a UTF-16 surrogate pair. Compare prefixes in code
# units, then let the JSON encoder escape the newly appended fragment alone.
def unitsForChar(supplementary: Bool, +code: U32, rest: String) -> String:
  match supplementary:
    case True{}: SCon{Chr{(55296 + (code - 65536) / 1024 : U32)}, SCon{Chr{(56320 + (code - 65536) % 1024 : U32)}, rest}}
    case False{}: SCon{Chr{code}, rest}

def codeUnits(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{Chr{+code}, rest}: unitsForChar(U32.is_gt(code, 65535), code, codeUnits(rest))

def prefixSuffix(prefix: String, next: String) -> Maybe<&2, String>:
  match prefix next:
    case SNil{} rest: Some{rest}
    case SCon{Chr{a}, old} SCon{Chr{b}, rest}: Bool.pick(Maybe<&2, String>, U32.is_eq(a, b), prefixSuffix(old, rest), None{})
    case _ _: None{}

def emitGrammarDelta(empty: Bool, old: GrammarToolInputJsonBuffer, started: Bool, property: String, nextInput: String, delta: String, close: Bool) -> GrammarToolInputJsonUpdate:
  match empty close:
    case True{} False{}: GrammarToolInputJsonUpdate{old, None{}}
    case _ +finish:
      prefix = Bool.pick(String, started, "", "{" ++ JsonString.quote(property) ++ ":\"")
      suffix = Bool.pick(String, finish, "\"}", "")
      GrammarToolInputJsonUpdate{GrammarToolInputJsonBuffer{nextInput, True{}, finish}, Some{prefix ++ JsonString.escaped(Utf16.normalize(delta)) ++ suffix}}

def appendOpenGrammar(result: Maybe<&2, String>, old: GrammarToolInputJsonBuffer, started: Bool, property: String, nextInput: String, close: Bool) -> Result<&2, &2, Error, GrammarToolInputJsonUpdate>:
  match result:
    case None{}: Fail{GrammarInputChanged{property}}
    case Some{+delta}: Done{emitGrammarDelta(String.is_empty(delta), old, started, property, nextInput, delta, close)}

def appendGrammarToolInputJsonDelta(buffer: GrammarToolInputJsonBuffer, inputProperty: String, +nextInput: String, +close: Bool) -> Result<&2, &2, Error, GrammarToolInputJsonUpdate>:
  match buffer:
    case GrammarToolInputJsonBuffer{+input, started, True{}}:
      Bool.pick(Result<&2, &2, Error, GrammarToolInputJsonUpdate>, close && Utf16.equal(input, nextInput), Done{GrammarToolInputJsonUpdate{GrammarToolInputJsonBuffer{input, started, True{}}, None{}}}, Fail{GrammarInputClosed{inputProperty}})
    case GrammarToolInputJsonBuffer{+input, +started, False{}}:
      appendOpenGrammar(prefixSuffix(codeUnits(input), codeUnits(nextInput)), GrammarToolInputJsonBuffer{input, started, False{}}, started, inputProperty, nextInput, close)
