import Base
import ../../src/api/constrained-sampling.bend as C
import ../../src/api/openai-responses-shared.bend as O
import ../../src/types.bend as T
import ../../src/utils/json.bend as Json
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/utf16.bend as U
import ../../../runtime/test/schema.bend as Assert

def jsonTools(tools: List<&2, O.OpenAITool>) -> List<&2, T.JsonValue>:
  match tools:
    case Nil{}: Nil{}
    case head <> rest: O.toolToJson(head) <> jsonTools(rest)

def serialized(result: Maybe<&2, String>, expected: String) -> Bool:
  match result:
    case None{}: False{}
    case Some{actual}: U.equal(actual,expected)

def converted(actual: Result<&2, &2, C.Error, List<&2, O.OpenAITool>>, expected: Result<&2, &2, String, String>) -> Bool:
  match actual expected:
    case Done{tools} Done{wire}: serialized(Json.stringify(T.JsonArray{jsonTools(tools)}),wire)
    case Fail{error} Fail{message}: String.eq(C.errorMessage(error),message)
    case _ _: False{}

def entries(values: List<&2, R.Property<String>>) -> R.Record<V.Value>:
  match values:
    case Nil{}: R.new(V.Value)
    case R.Property{key,text} <> rest: R.set(V.Value,entries(rest),key,V.Text{text})

def properties(actual: Result<&2, &2, C.Error, R.Record<String>>, expected: Result<&2, &2, String, V.Value>) -> Bool:
  match actual expected:
    case Done{mapping} Done{value}: V.equal(V.ObjectValue{entries(R.entries(String,mapping))},value)
    case Fail{error} Fail{message}: String.eq(C.errorMessage(error),message)
    case _ _: False{}

def grammarJson(grammar: C.GrammarConstrainedSampling) -> T.JsonValue:
  match grammar:
    case C.GrammarConstrainedSampling{format,definition,property}: T.JsonObject{R.Record{R.Property{"format", T.JsonString{O.grammarSyntax(format)}} <> R.Property{"definition", T.JsonString{definition}} <> R.Property{"inputProperty", T.JsonString{property}} <> Nil{}}}

def grammar(actual: Result<&2, &2, C.Error, Maybe<&2, C.GrammarConstrainedSampling>>, expected: Result<&2, &2, String, Maybe<&2, String>>) -> Bool:
  match actual expected:
    case Done{None{}} Done{None{}}: True{}
    case Done{Some{value}} Done{Some{wire}}: serialized(Json.stringify(grammarJson(value)),wire)
    case Fail{error} Fail{message}: String.eq(C.errorMessage(error),message)
    case _ _: False{}

def grammarList(tools: List<&2, T.Tool<V.Value>>, expected: List<&2, Result<&2, &2, String, Maybe<&2, String>>>, +supported: Bool) -> Bool:
  match tools expected:
    case Nil{} Nil{}: True{}
    case head <> rest wanted <> tail: grammar(C.resolveGrammarConstrainedSampling(head,supported),wanted) && grammarList(rest,tail,supported)
    case _ _: False{}

def support(options: Maybe<&2, O.ConvertResponsesToolsOptions>) -> Bool:
  match options:
    case Some{O.ConvertResponsesToolsOptions{_,_,Some{value},_}}: value
    case _: False{}

def check(+tools: List<&2, T.Tool<V.Value>>, +options: Maybe<&2, O.ConvertResponsesToolsOptions>, expectedConversion: Result<&2, &2, String, String>, expectedProperties: Result<&2, &2, String, V.Value>, expectedGrammars: List<&2, Result<&2, &2, String, Maybe<&2, String>>>, label: String) -> IO(Unit):
  Assert.assertion(converted(O.convertResponsesTools(tools,options),expectedConversion) && properties(C.createGrammarToolInputProperties(Some{tools},support(options)),expectedProperties) && grammarList(tools,expectedGrammars,support(options)),label)

# Malformed raw schemas get native policy errors, never host-engine exceptions
# or array/property coercion. They cannot describe a valid grammar string input.
def malformedRoot(result: Result<&2, &2, C.Error, Maybe<&2, C.GrammarConstrainedSampling>>) -> Bool:
  match result:
    case Fail{C.InvalidGrammarSchema{"bad", C.ObjectParametersRequired{}}}: True{}
    case _: False{}

def malformedProperty(result: Result<&2, &2, C.Error, Maybe<&2, C.GrammarConstrainedSampling>>) -> Bool:
  match result:
    case Fail{C.InvalidGrammarSchema{"bad", C.PropertyMustBeString{"payload"}}}: True{}
    case _: False{}

def nativeErrors() -> IO(Unit):
  +config = {Some{T.SamplingConfigured{T.GrammarSampling{T.GrammarVariants{Some{"lark"},None{}}}}} : Maybe<&2, T.ToolConstrainedSampling>}
  do IO<Unit>:
    Assert.assertion(properties(C.createGrammarToolInputProperties(None{},True{}),Done{V.ObjectValue{R.new(V.Value)}}),"absent tools produce empty grammar map")
    Assert.assertion(malformedRoot(C.resolveGrammarConstrainedSampling(T.Tool{"bad","",V.Null{},config},True{})),"null grammar schema reports typed object-policy failure")
    Assert.assertion(malformedProperty(C.resolveGrammarConstrainedSampling(T.Tool{"bad","",V.ObjectValue{R.Record{R.Property{"type",V.Text{"object"}} <> R.Property{"required",V.ArrayValue{V.Text{"payload"} <> Nil{}}} <> R.Property{"properties",V.ObjectValue{R.Record{R.Property{"payload",V.Boolean{False{}}} <> Nil{}}}} <> Nil{}}},config},True{})),"present non-object property is an invalid string schema")
