import Base
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R

# An explicit work stack transforms finite schema trees without mutation or
# cloning. Failure carries a schema-policy error rather than a JS exception.
type Error is Data:
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

def errorMessage(error: Error) -> String:
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

def present(value: Maybe<&2, V.Value>) -> Bool:
  match value:
    case None{}: False{}
    case Some{_}: True{}

def unsupported(keys: List<&2, String>, +fields: R.Record<V.Value>) -> Maybe<&2, String>:
  match keys:
    case Nil{}: None{}
    case +key <> rest: Bool.pick(Maybe<&2, String>, present(R.get(V.Value, fields, key)), Some{key}, unsupported(rest, fields))

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
    case V.ObjectValue{+fields}: typeIncludes(R.get(V.Value, fields, "type"), "object") || typeIncludes(R.get(V.Value, fields, "type"), "array") || present(R.get(V.Value, fields, "properties")) || present(R.get(V.Value, fields, "items"))
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
  Reject{error: Error}

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
    case V.Text{key} <> rest: present(R.get(V.Value, properties, key)) && knownRequired(rest, properties)
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
    case False{}: Bool.pick(Step, present(R.get(V.Value, fields, "properties")), Reject{PropertiesRequireObject{}}, Continue{rest, V.ObjectValue{fields}})

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
def run(step: Step) -> Result<&2, &2, Error, V.Value>:
  match step:
    case Reject{error}: Fail{error}
    case Continue{Nil{}, value}: Done{value}
    case Continue{task <> rest, value}: run(next(task, rest, value))

def makeStrictJsonSchema(schema: V.Value) -> Result<&2, &2, Error, V.Value>:
  match schema:
    case V.ObjectValue{fields}: run(Continue{CheckNode{V.ObjectValue{fields}} <> CheckRoot{} <> Nil{}, V.Null{}})
    case _: Fail{RootMustBeObject{}}
