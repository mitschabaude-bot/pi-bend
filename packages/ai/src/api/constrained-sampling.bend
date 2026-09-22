import Base
import ../types.bend as T
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/json.bend as JsonString
import ../../../runtime/src/utf16.bend as Utf16
import ../../../runtime/src/text.bend as Space

# Strict JSON schemas
# -------------------

# An explicit work stack transforms finite schema trees without mutation or
# cloning. Failure carries a schema-policy error rather than a JS exception.
type StrictSchemaError is Data:
  RootMustBeObject{}
  NodeMustBeObject{}
  UnsupportedKeyword{key: String}
  EmptyOrInvalidUnion{}
  StructuredUnion{}
  TupleItems{}
  PropertiesRequireObject{}
  AdditionalPropertiesUnsupported{}
  PropertiesMustBeMap{}
  RequiredMustBeStrings{}
  UnknownRequiredProperty{}

def strictSchemaMessage(error: StrictSchemaError) -> String:
  match error:
    case RootMustBeObject{}: "root schema must have type object"
    case NodeMustBeObject{}: "boolean schemas are unsupported"
    case UnsupportedKeyword{key}: key ++ " schemas are unsupported"
    case EmptyOrInvalidUnion{}: "anyOf must contain at least one schema"
    case StructuredUnion{}: "object and array unions are unsupported"
    case TupleItems{}: "tuple schemas are unsupported"
    case PropertiesRequireObject{}: "properties require type object"
    case AdditionalPropertiesUnsupported{}: "schema-valued or true additionalProperties is unsupported"
    case PropertiesMustBeMap{}: "object properties must be a schema map"
    case RequiredMustBeStrings{}: "object required must be a string array"
    case UnknownRequiredProperty{}: "required contains an unknown property"

def unsupportedKeys() -> List<&2, String>:
  "$ref" <> "$defs" <> "definitions" <> "allOf" <> "oneOf" <> "patternProperties" <> "dependentSchemas" <> "dependencies" <> "unevaluatedProperties" <> "propertyNames" <> "contains" <> "prefixItems" <> "not" <> "if" <> "then" <> "else" <> Nil{}

def unsupported(keys: List<&2, String>, +fields: R.Record<V.Value>) -> Maybe<&2, String>:
  match keys:
    case Nil{}: None{}
    case +key <> rest: Bool.pick(Maybe<&2, String>, Maybe.is_some(&2, V.Value, R.get(V.Value, fields, key)), Some{key}, unsupported(rest, fields))

def textEquals(value: Maybe<&2, V.Value>, expected: String) -> Bool:
  match value:
    case Some{V.Text{text}}: String.eq(text, expected)
    case _: False{}

def includesText(values: List<&2, V.Value>, +expected: String) -> Bool:
  match values:
    case Nil{}: False{}
    case V.Text{text} <> rest: String.eq(text, expected) || includesText(rest, expected)
    case _ <> rest: includesText(rest, expected)

def includesNull(values: List<&2, V.Value>) -> Bool:
  match values:
    case Nil{}: False{}
    case V.Null{} <> _: True{}
    case _ <> rest: includesNull(rest)

def typeIncludes(value: Maybe<&2, V.Value>, +expected: String) -> Bool:
  match value:
    case Some{V.ArrayValue{values}}: includesText(values, expected)
    case other: textEquals(other, expected)

def structured(value: V.Value) -> Bool:
  match value:
    case V.ObjectValue{+fields}: typeIncludes(R.get(V.Value, fields, "type"), "object") || typeIncludes(R.get(V.Value, fields, "type"), "array") || Maybe.is_some(&2, V.Value, R.get(V.Value, fields, "properties")) || Maybe.is_some(&2, V.Value, R.get(V.Value, fields, "items"))
    case _: False{}

def nullConstant(value: Maybe<&2, V.Value>) -> Bool:
  match value:
    case Some{V.Null{}}: True{}
    case _: False{}

def nullEnum(value: Maybe<&2, V.Value>) -> Bool:
  match value:
    case Some{V.ArrayValue{values}}: includesNull(values)
    case _: False{}

def unionValues(value: Maybe<&2, V.Value>) -> List<&2, V.Value>:
  match value:
    case Some{V.ArrayValue{values}}: values
    case _: Nil{}

# Work only expands finite anyOf children of the input schema.
@unsafe
def nullAllowed(work: List<&2, V.Value>) -> Bool:
  match work:
    case Nil{}: False{}
    case V.ObjectValue{+fields} <> rest:
      typeIncludes(R.get(V.Value, fields, "type"), "null") || nullConstant(R.get(V.Value, fields, "const")) || nullEnum(R.get(V.Value, fields, "enum")) || nullAllowed(List.append(&2, V.Value, unionValues(R.get(V.Value, fields, "anyOf")), rest))
    case _ <> rest: nullAllowed(rest)

def makeNullable(required: Bool, +value: V.Value) -> V.Value:
  Bool.pick(V.Value, required || nullAllowed(value <> Nil{}), value, V.ObjectValue{R.Record{R.Property{"anyOf", V.ArrayValue{value <> V.ObjectValue{R.Record{R.Property{"type", V.Text{"null"}} <> Nil{}}} <> Nil{}}} <> Nil{}}})

type Task is Data:
  CheckNode{schema: V.Value}
  CheckUnion{fields: R.Record<V.Value>}
  UnionNext{remaining: List<&2, V.Value>, reversed: List<&2, V.Value>}
  UnionCollect{remaining: List<&2, V.Value>, reversed: List<&2, V.Value>}
  UnionDone{fields: R.Record<V.Value>}
  CheckItems{fields: R.Record<V.Value>}
  ItemsDone{fields: R.Record<V.Value>}
  CheckObject{fields: R.Record<V.Value>}
  PropertyNext{fields: R.Record<V.Value>, remaining: List<&2, R.Property<V.Value>>, required: List<&2, V.Value>, converted: R.Record<V.Value>, names: List<&2, V.Value>, hadProperties: Bool}
  PropertyCollect{fields: R.Record<V.Value>, remaining: List<&2, R.Property<V.Value>>, required: List<&2, V.Value>, converted: R.Record<V.Value>, names: List<&2, V.Value>, key: String, isRequired: Bool, hadProperties: Bool}
  CheckRoot{}

type Step is Data:
  Continue{tasks: List<&2, Task>, value: V.Value}
  Reject{error: StrictSchemaError}

def nodeFields(unsupported: Maybe<&2, String>, fields: R.Record<V.Value>, rest: List<&2, Task>) -> Step:
  match unsupported:
    case Some{key}: Reject{UnsupportedKeyword{key}}
    case None{}: Continue{CheckUnion{fields} <> rest, V.Null{}}

def nodePlan(value: V.Value, rest: List<&2, Task>) -> Step:
  match value:
    case V.ObjectValue{+fields}: nodeFields(unsupported(unsupportedKeys(), fields), fields, rest)
    case _: Reject{NodeMustBeObject{}}

def unionPlan(value: Maybe<&2, V.Value>, fields: R.Record<V.Value>, rest: List<&2, Task>) -> Step:
  match value:
    case None{}: Continue{CheckItems{fields} <> rest, V.Null{}}
    case Some{V.ArrayValue{head <> tail}}: Continue{UnionNext{head <> tail, Nil{}} <> UnionDone{fields} <> rest, V.Null{}}
    case _: Reject{EmptyOrInvalidUnion{}}

def unionChild(isStructured: Bool, value: V.Value, tail: List<&2, V.Value>, reversed: List<&2, V.Value>, rest: List<&2, Task>) -> Step:
  match isStructured:
    case True{}: Reject{StructuredUnion{}}
    case False{}: Continue{CheckNode{value} <> UnionCollect{tail, reversed} <> rest, V.Null{}}

def itemsPlan(value: Maybe<&2, V.Value>, fields: R.Record<V.Value>, rest: List<&2, Task>) -> Step:
  match value:
    case None{}: Continue{CheckObject{fields} <> rest, V.Null{}}
    case Some{V.ArrayValue{_}}: Reject{TupleItems{}}
    case Some{schema}: Continue{CheckNode{schema} <> ItemsDone{fields} <> rest, V.Null{}}

def stringValues(values: List<&2, V.Value>) -> Bool:
  match values:
    case Nil{}: True{}
    case V.Text{_} <> rest: stringValues(rest)
    case _: False{}

def knownRequired(required: List<&2, V.Value>, +properties: R.Record<V.Value>) -> Bool:
  match required:
    case Nil{}: True{}
    case V.Text{key} <> rest: Maybe.is_some(&2, V.Value, R.get(V.Value, properties, key)) && knownRequired(rest, properties)
    case _: False{}

def propertyNames(properties: List<&2, R.Property<V.Value>>) -> List<&2, V.Value>:
  match properties:
    case Nil{}: Nil{}
    case R.Property{key, _} <> rest: V.Text{key} <> propertyNames(rest)

def requiredPlan(validStrings: Bool, fields: R.Record<V.Value>, +properties: R.Record<V.Value>, +required: List<&2, V.Value>, hadProperties: Bool, rest: List<&2, Task>) -> Step:
  match validStrings:
    case False{}: Reject{RequiredMustBeStrings{}}
    case True{}:
      Bool.pick(Step, knownRequired(required, properties), Continue{PropertyNext{fields, R.entries(V.Value, properties), required, R.new(V.Value), propertyNames(R.entries(V.Value, properties)), hadProperties} <> rest, V.Null{}}, Reject{UnknownRequiredProperty{}})

def requiredInput(value: Maybe<&2, V.Value>, fields: R.Record<V.Value>, properties: R.Record<V.Value>, hadProperties: Bool, rest: List<&2, Task>) -> Step:
  match value:
    case None{}: requiredPlan(True{}, fields, properties, Nil{}, hadProperties, rest)
    case Some{V.ArrayValue{+values}}: requiredPlan(stringValues(values), fields, properties, values, hadProperties, rest)
    case _: Reject{RequiredMustBeStrings{}}

def propertiesPlan(value: Maybe<&2, V.Value>, +fields: R.Record<V.Value>, rest: List<&2, Task>) -> Step:
  match value:
    case None{}: requiredInput(R.get(V.Value, fields, "required"), fields, R.new(V.Value), False{}, rest)
    case Some{V.ObjectValue{properties}}: requiredInput(R.get(V.Value, fields, "required"), fields, properties, True{}, rest)
    case _: Reject{PropertiesMustBeMap{}}

def additionalPlan(value: Maybe<&2, V.Value>, +fields: R.Record<V.Value>, rest: List<&2, Task>) -> Step:
  match value:
    case None{}: propertiesPlan(R.get(V.Value, fields, "properties"), fields, rest)
    case Some{V.Boolean{False{}}}: propertiesPlan(R.get(V.Value, fields, "properties"), fields, rest)
    case _: Reject{AdditionalPropertiesUnsupported{}}

def objectPlan(isObject: Bool, +fields: R.Record<V.Value>, rest: List<&2, Task>) -> Step:
  match isObject:
    case True{}: additionalPlan(R.get(V.Value, fields, "additionalProperties"), fields, rest)
    case False{}: Bool.pick(Step, Maybe.is_some(&2, V.Value, R.get(V.Value, fields, "properties")), Reject{PropertiesRequireObject{}}, Continue{rest, V.ObjectValue{fields}})

def completedObject(fields: R.Record<V.Value>, properties: R.Record<V.Value>, names: List<&2, V.Value>, hadProperties: Bool) -> V.Value:
  +result = R.set(V.Value, R.set(V.Value, fields, "required", V.ArrayValue{names}), "additionalProperties", V.Boolean{False{}})
  V.ObjectValue{Bool.pick(R.Record<V.Value>, hadProperties, R.set(V.Value, result, "properties", V.ObjectValue{properties}), result)}

def rootPlan(+value: V.Value, rest: List<&2, Task>) -> Step:
  match value:
    case V.ObjectValue{+fields}: Bool.pick(Step, textEquals(R.get(V.Value, fields, "type"), "object"), Continue{rest, V.ObjectValue{fields}}, Reject{RootMustBeObject{}})
    case _: Reject{RootMustBeObject{}}

def next(task: Task, rest: List<&2, Task>, value: V.Value) -> Step:
  match task:
    case CheckNode{schema}: nodePlan(schema, rest)
    case CheckUnion{+fields}: unionPlan(R.get(V.Value, fields, "anyOf"), fields, rest)
    case UnionNext{Nil{}, reversed}: Continue{rest, V.ArrayValue{List.reverse(&2, V.Value, reversed)}}
    case UnionNext{+head <> tail, reversed}: unionChild(structured(head), head, tail, reversed, rest)
    case UnionCollect{remaining, reversed}: Continue{UnionNext{remaining, value <> reversed} <> rest, V.Null{}}
    case UnionDone{fields}: Continue{CheckItems{R.set(V.Value, fields, "anyOf", value)} <> rest, V.Null{}}
    case CheckItems{+fields}: itemsPlan(R.get(V.Value, fields, "items"), fields, rest)
    case ItemsDone{fields}: Continue{CheckObject{R.set(V.Value, fields, "items", value)} <> rest, V.Null{}}
    case CheckObject{+fields}: objectPlan(textEquals(R.get(V.Value, fields, "type"), "object"), fields, rest)
    case PropertyNext{fields, Nil{}, _, converted, names, had}: Continue{rest, completedObject(fields, converted, names, had)}
    case PropertyNext{fields, R.Property{+key, schema} <> tail, +required, converted, names, had}:
      Continue{CheckNode{schema} <> PropertyCollect{fields, tail, required, converted, names, key, includesText(required, key), had} <> rest, V.Null{}}
    case PropertyCollect{fields, remaining, required, converted, names, key, isRequired, had}:
      Continue{PropertyNext{fields, remaining, required, R.set(V.Value, converted, key, makeNullable(isRequired, value)), names, had} <> rest, V.Null{}}
    case CheckRoot{}: rootPlan(value, rest)

# Each visit consumes a finite schema node; continuation frames rebuild it once.
@unsafe
def run(step: Step) -> Result<&2, &2, StrictSchemaError, V.Value>:
  match step:
    case Reject{error}: Fail{error}
    case Continue{Nil{}, value}: Done{value}
    case Continue{task <> rest, value}: run(next(task, rest, value))

def strictJsonSchema(schema: V.Value) -> Result<&2, &2, StrictSchemaError, V.Value>:
  match schema:
    case V.ObjectValue{fields}: run(Continue{CheckNode{V.ObjectValue{fields}} <> CheckRoot{} <> Nil{}, V.Null{}})
    case _: Fail{RootMustBeObject{}}

# Constrained sampling
# --------------------

type GrammarSchemaError is Data:
  ObjectParametersRequired{}
  OneRequiredStringProperty{}
  MissingPropertySchema{inputProperty: String}
  PropertyMustBeString{inputProperty: String}

type Error is Data:
  UnsupportedStrictJsonSchema{error: StrictSchemaError}
  RequiredStrictSchema{toolName: String, error: StrictSchemaError}
  StrictToolsUnsupported{toolName: String}
  GrammarArgumentNotString{toolName: String, inputProperty: String}
  GrammarInputClosed{inputProperty: String}
  GrammarInputChanged{inputProperty: String}
  GrammarVariantMissing{toolName: String}
  InvalidGrammarSchema{toolName: String, reason: GrammarSchemaError}

def grammarSchemaMessage(reason: GrammarSchemaError) -> String:
  match reason:
    case ObjectParametersRequired{}: "grammar constrained sampling requires an object parameter schema"
    case OneRequiredStringProperty{}: "grammar constrained sampling requires exactly one required string property"
    case MissingPropertySchema{property}: "grammar constrained sampling requires a properties entry for " ++ property
    case PropertyMustBeString{property}: "grammar constrained sampling property " ++ property ++ " must have type string"

def errorMessage(error: Error) -> String:
  match error:
    case UnsupportedStrictJsonSchema{error}: strictSchemaMessage(error)
    case RequiredStrictSchema{name, error}: "Tool \"" ++ name ++ "\" requires JSON-schema constrained sampling, but " ++ strictSchemaMessage(error) ++ "."
    case StrictToolsUnsupported{name}: "Tool \"" ++ name ++ "\" requires JSON-schema constrained sampling, but strict tools are unsupported."
    case GrammarArgumentNotString{name, property}: "Grammar tool call \"" ++ name ++ "\" requires argument \"" ++ property ++ "\" to be a string."
    case GrammarInputClosed{property}: "grammar tool input for property \"" ++ property ++ "\" changed after it was closed"
    case GrammarInputChanged{property}: "grammar tool input for property \"" ++ property ++ "\" changed non-monotonically"

    case GrammarVariantMissing{name}: "Tool \"" ++ name ++ "\" cannot use grammar constrained sampling: no supported grammar variant was provided."
    case InvalidGrammarSchema{name, reason}: "Tool \"" ++ name ++ "\" cannot use grammar constrained sampling: " ++ grammarSchemaMessage(reason) ++ "."

def strictSchemaResult(result: Result<&2, &2, StrictSchemaError, V.Value>) -> Result<&2, &2, Error, V.Value>:
  match result:
    case Done{schema}: Done{schema}
    case Fail{error}: Fail{UnsupportedStrictJsonSchema{error}}

def makeStrictJsonSchema(schema: V.Value) -> Result<&2, &2, Error, V.Value>:
  strictSchemaResult(strictJsonSchema(schema))

def getJsonSchemaToolParameters(tool: T.Tool<V.Value>, strict: Maybe<&2, Bool>) -> Result<&2, &2, Error, V.Value>:
  match tool strict:
    case T.Tool{_, _, schema, _} Some{True{}}: makeStrictJsonSchema(schema)
    case T.Tool{_, _, schema, _} _: Done{schema}

def selectedStrict(name: String, policy: T.SamplingStrictness, result: Result<&2, &2, StrictSchemaError, V.Value>) -> Result<&2, &2, Error, Maybe<&2, Bool>>:
  match policy result:
    case _ Done{_}: Done{Some{True{}}}
    case T.Prefer{} Fail{_}: Done{None{}}
    case T.Require{} Fail{error}: Fail{RequiredStrictSchema{name, error}}

def supportedStrict(name: String, schema: V.Value, policy: T.SamplingStrictness, supported: Bool) -> Result<&2, &2, Error, Maybe<&2, Bool>>:
  match policy supported:
    case T.Prefer{} False{}: Done{None{}}
    case T.Require{} False{}: Fail{StrictToolsUnsupported{name}}
    case value True{}: selectedStrict(name, value, strictJsonSchema(schema))

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

type GrammarConstrainedSampling is Data:
  GrammarConstrainedSampling{format: T.GrammarFormat, definition: String, inputProperty: String}

def grammarProperty(value: Maybe<&2, V.Value>, +property: String) -> Result<&2, &2, GrammarSchemaError, String>:
  match value:
    case None{}: Fail{MissingPropertySchema{property}}
    case Some{V.ObjectValue{fields}}: Bool.pick(Result<&2, &2, GrammarSchemaError, String>, textEquals(R.get(V.Value, fields, "type"), "string"), Done{property}, Fail{PropertyMustBeString{property}})
    case _: Fail{PropertyMustBeString{property}}

def grammarProperties(value: Maybe<&2, V.Value>, +property: String) -> Result<&2, &2, GrammarSchemaError, String>:
  match value:
    case Some{V.ObjectValue{fields}}: grammarProperty(R.get(V.Value, fields, property), property)
    case _: Fail{MissingPropertySchema{property}}

def grammarRequired(value: Maybe<&2, V.Value>, fields: R.Record<V.Value>) -> Result<&2, &2, GrammarSchemaError, String>:
  match value:
    case Some{V.ArrayValue{V.Text{property} <> Nil{}}}: grammarProperties(R.get(V.Value, fields, "properties"), property)
    case _: Fail{OneRequiredStringProperty{}}

def grammarObject(isObject: Bool, +fields: R.Record<V.Value>) -> Result<&2, &2, GrammarSchemaError, String>:
  match isObject:
    case True{}: grammarRequired(R.get(V.Value, fields, "required"), fields)
    case False{}: Fail{ObjectParametersRequired{}}

def inferGrammarInputProperty(schema: V.Value) -> Result<&2, &2, GrammarSchemaError, String>:
  match schema:
    case V.ObjectValue{+fields}: grammarObject(textEquals(R.get(V.Value, fields, "type"), "object"), fields)
    case _: Fail{ObjectParametersRequired{}}

def nonblank(value: Maybe<&2, String>) -> Maybe<&2, String>:
  match value:
    case None{}: None{}
    case Some{+text}: Bool.pick(Maybe<&2, String>, Space.blank(text), None{}, Some{text})

def resolvedGrammar(name: String, format: T.GrammarFormat, definition: String, property: Result<&2, &2, GrammarSchemaError, String>) -> Result<&2, &2, Error, Maybe<&2, GrammarConstrainedSampling>>:
  match property:
    case Fail{reason}: Fail{InvalidGrammarSchema{name, reason}}
    case Done{inputProperty}: Done{Some{GrammarConstrainedSampling{format, definition, inputProperty}}}

def chooseGrammar(name: String, schema: V.Value, lark: Maybe<&2, String>, regex: Maybe<&2, String>) -> Result<&2, &2, Error, Maybe<&2, GrammarConstrainedSampling>>:
  match lark regex:
    case Some{definition} _: resolvedGrammar(name, T.OpenAILark{}, definition, inferGrammarInputProperty(schema))
    case None{} Some{definition}: resolvedGrammar(name, T.OpenAIRegex{}, definition, inferGrammarInputProperty(schema))
    case None{} None{}: Fail{GrammarVariantMissing{name}}

def resolveGrammarConstrainedSampling(tool: T.Tool<V.Value>, supportsOpenAIGrammarTools: Bool) -> Result<&2, &2, Error, Maybe<&2, GrammarConstrainedSampling>>:
  match tool supportsOpenAIGrammarTools:
    case T.Tool{name, _, schema, Some{T.SamplingConfigured{T.GrammarSampling{T.GrammarVariants{lark, regex}}}}} True{}: chooseGrammar(name, schema, nonblank(lark), nonblank(regex))
    case _ _: Done{None{}}

def addGrammarProperty(result: Result<&2, &2, Error, Maybe<&2, GrammarConstrainedSampling>>, name: String, properties: R.Record<String>) -> Result<&2, &2, Error, R.Record<String>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{None{}}: Done{properties}
    case Done{Some{GrammarConstrainedSampling{_, _, property}}}: Done{R.set(String, properties, name, property)}

def grammarToolName(tool: T.Tool<V.Value>) -> String:
  match tool:
    case T.Tool{name, _, _, _}: name

def grammarPropertiesFrom(tools: List<&2, T.Tool<V.Value>>, +supported: Bool, result: Result<&2, &2, Error, R.Record<String>>) -> Result<&2, &2, Error, R.Record<String>>:
  match tools result:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{properties}: Done{properties}
    case +head <> tail Done{properties}: grammarPropertiesFrom(tail, supported, addGrammarProperty(resolveGrammarConstrainedSampling(head, supported), grammarToolName(head), properties))

def createGrammarToolInputProperties(tools: Maybe<&2, List<&2, T.Tool<V.Value>>>, supportsOpenAIGrammarTools: Bool) -> Result<&2, &2, Error, R.Record<String>>:
  match tools:
    case None{}: Done{R.new(String)}
    case Some{values}: grammarPropertiesFrom(values, supportsOpenAIGrammarTools, Done{R.new(String)})
