import Base
import ../types.bend as T
import ./constrained-sampling.bend as C
import ../utils/schema-json.bend as SchemaJson
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R

# Native wire declarations produced by convertResponsesTools. Message input
# items and streamed response events are separate remaining provider types.
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
