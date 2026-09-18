import Base
import ./schema-value.bend as V
import ./record.bend as R
import ./f64.bend as F

# Native executable schema vocabulary. JSON-schema loading and diagnostics are
# separate concerns; no unknown keyword can silently become an accepting node.
type JsonType is Data:
  NullType{}
  BooleanType{}
  NumberType{}
  IntegerType{}
  StringType{}
  ArrayType{}
  ObjectType{}

type Schema is Data:
  Accept{}
  Reject{}
  JsonKind{kind: JsonType}
  Constant{value: V.Value}
  Enumeration{values: List<&2, V.Value>}
  All{schemas: List<&2, Schema>}
  Any{schemas: List<&2, Schema>}
  One{schemas: List<&2, Schema>}
  Not{schema: Schema}
  Object{properties: R.Record<Schema>, required: List<&2, String>, additional: Schema}
  Array{prefix: List<&2, Schema>, items: Schema}

# Tests pair child schemas with their own instance values. Keeping the work
# tree explicit avoids callbacks, mutable traversal state and object cloning.
type Test is Data:
  Check{schema: Schema, value: V.Value}
  Every{tests: List<&2, Test>}
  SomeTest{tests: List<&2, Test>}
  ExactlyOne{tests: List<&2, Test>, matched: Bool}
  Counted{previous: Bool, current: Bool, remaining: List<&2, Test>}
  Fixed{value: Bool}

def finite(number: F.Decoded) -> Bool:
  match number:
    case F.Finite{_, _, _}: True{}
    case _: False{}

def matchesType(kind: JsonType, value: V.Value) -> Bool:
  match kind value:
    case NullType{} V.Null{}: True{}
    case BooleanType{} V.Boolean{_}: True{}
    case NumberType{} V.Number{number}: finite(F.decode(number))
    case IntegerType{} V.Number{+number}: finite(F.decode(number)) && F.isInteger(number)
    case StringType{} V.Text{_}: True{}
    case ArrayType{} V.ArrayValue{_}: True{}
    case ObjectType{} V.ObjectValue{_}: True{}
    case _ _: False{}

def member(values: List<&2, V.Value>, +value: V.Value) -> Bool:
  match values:
    case Nil{}: False{}
    case head <> tail: V.equal(head, value) || member(tail, value)

def tests(schemas: List<&2, Schema>, +value: V.Value) -> List<&2, Test>:
  match schemas:
    case Nil{}: Nil{}
    case head <> tail: Check{head, value} <> tests(tail, value)

def requiredTests(required: List<&2, String>, +value: R.Record<V.Value>) -> List<&2, Test>:
  match required:
    case Nil{}: Nil{}
    case key <> tail: Fixed{Maybe.is_some(&2, V.Value, R.get(V.Value, value, key))} <> requiredTests(tail, value)

def propertySchema(schema: Maybe<&2, Schema>, additional: Schema) -> Schema:
  match schema:
    case Some{value}: value
    case None{}: additional

def propertyTests(values: List<&2, R.Property<V.Value>>, +properties: R.Record<Schema>, +additional: Schema) -> List<&2, Test>:
  match values:
    case Nil{}: Nil{}
    case R.Property{key, value} <> tail: Check{propertySchema(R.get(Schema, properties, key), additional), value} <> propertyTests(tail, properties, additional)

def itemTests(values: List<&2, V.Value>, prefix: List<&2, Schema>, +items: Schema) -> List<&2, Test>:
  match values prefix:
    case Nil{} _: Nil{}
    case value <> tail Nil{}: Check{items, value} <> itemTests(tail, Nil{}, items)
    case value <> tail schema <> rest: Check{schema, value} <> itemTests(tail, rest, items)

# Every expansion descends into a schema or instance child, or removes one
# pending test. No reference cycles exist in these immutable schema values.
@unsafe
def evaluate(test: Test) -> Bool:
  match test:
    case Fixed{value}: value
    case Check{Accept{}, _}: True{}
    case Check{Reject{}, _}: False{}
    case Check{JsonKind{kind}, value}: matchesType(kind, value)
    case Check{Constant{expected}, value}: V.equal(expected, value)
    case Check{Enumeration{values}, value}: member(values, value)
    case Check{All{schemas}, value}: evaluate(Every{tests(schemas, value)})
    case Check{Any{schemas}, value}: evaluate(SomeTest{tests(schemas, value)})
    case Check{One{schemas}, value}: evaluate(ExactlyOne{tests(schemas, value), False{}})
    case Check{Not{schema}, value}: Bool.not(evaluate(Check{schema, value}))
    case Check{Object{properties, required, additional}, V.ObjectValue{+value}}:
      evaluate(Every{requiredTests(required, value)}) && evaluate(Every{propertyTests(R.entries(V.Value, value), properties, additional)})
    case Check{Object{_, _, _}, _}: True{}
    case Check{Array{prefix, items}, V.ArrayValue{values}}: evaluate(Every{itemTests(values, prefix, items)})
    case Check{Array{_, _}, _}: True{}
    case Every{Nil{}}: True{}
    case Every{head <> tail}: evaluate(head) && evaluate(Every{tail})
    case SomeTest{Nil{}}: False{}
    case SomeTest{head <> tail}: evaluate(head) || evaluate(SomeTest{tail})
    case ExactlyOne{Nil{}, matched}: matched
    case ExactlyOne{head <> tail, matched}: evaluate(Counted{matched, evaluate(head), tail})
    case Counted{True{}, True{}, _}: False{}
    case Counted{previous, current, tail}: evaluate(ExactlyOne{tail, previous || current})

def check(schema: Schema, value: V.Value) -> Bool:
  evaluate(Check{schema, value})
