import Base
import ./schema-value.bend as V
import ./record.bend as R
import ./f64.bend as F
import ./big-nat.bend as B
import ./number-string.bend as Number
import ./u64.bend as W
import ./uri-component.bend as Uri


# The pinned schema dependency measures a limited set of grapheme clusters.
# Keep this validation policy separate from general Unicode segmentation: skin
# tones, Hangul composition and other UAX #29 rules are not part of this policy.
def between(+point: U32, lower: U32, upper: U32) -> Bool:
  U32.is_ge(point, lower) && U32.is_le(point, upper)

def modifier(+point: U32) -> Bool:
  between(point, 768, 879) || between(point, 6832, 6911) || between(point, 7616, 7679) || between(point, 65056, 65071) || between(point, 65024, 65039)

def regional(point: U32) -> Bool: between(point, 127462, 127487)

def modifiers(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{Chr{+point}, +rest}:
      Bool.pick(Unit -> String, modifier(point), _ => modifiers(rest), _ => SCon{Chr{point}, rest})(Unit{})

@unsafe
def joined(text: String) -> String:
  match text:
    case SCon{Chr{8205}, SCon{_, rest}}: joined(modifiers(rest))
    case other: other

def regionalPair(enabled: Bool, text: String) -> String:
  match enabled text:
    case True{} SCon{Chr{+point}, +rest}: Bool.pick(String, regional(point), rest, SCon{Chr{point}, rest})
    case _ other: other

def next(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{Chr{point}, rest}: regionalPair(regional(point), joined(modifiers(rest)))

# Every iteration consumes at least its first scalar, plus any recognized
# modifiers/joined scalars. Large declared bounds never expand into unary Nats.
@unsafe
def countFrom(text: String, total: B.BigNat) -> B.BigNat:
  match text:
    case SNil{}: total
    case SCon{point, rest}: countFrom(next(SCon{point, rest}), B.add(total, B.fromU32(1)))

def length(text: String) -> B.BigNat: countFrom(text, B.zero())


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

type CountBounds is Data:
  CountBounds{minimum: B.BigNat, maximum: Maybe<&2, B.BigNat>}

type Schema is Data:
  Accept{}
  Reject{}
  JsonKind{kind: JsonType}
  TypeUnion{kinds: List<&2, JsonType>}
  Constant{value: V.Value}
  Enumeration{values: List<&2, V.Value>}
  All{schemas: List<&2, Schema>}
  Any{schemas: List<&2, Schema>}
  One{schemas: List<&2, Schema>}
  Not{schema: Schema}
  Conditional{condition: Schema, consequent: Schema, alternative: Schema}
  Minimum{limit: F.F64, inclusive: Bool}
  Maximum{limit: F.F64, inclusive: Bool}
  MultipleOf{divisor: F.F64}
  UniqueItems{}
  StringLength{bounds: CountBounds}
  ItemCount{bounds: CountBounds}
  PropertyCount{bounds: CountBounds}
  Contains{schema: Schema, bounds: CountBounds}
  Object{properties: R.Record<Schema>, required: List<&2, String>, additional: Schema}
  Array{prefix: List<&2, Schema>, items: Schema}
  AdditionalItems{offset: Nat, items: Schema}

# Tests pair child schemas with their own instance values. Keeping the work
# tree explicit avoids callbacks, mutable traversal state and object cloning.
type Test is Data:
  Check{schema: Schema, value: V.Value}
  Every{tests: List<&2, Test>}
  SomeTest{tests: List<&2, Test>}
  ExactlyOne{tests: List<&2, Test>, matched: Bool}
  Counted{previous: Bool, current: Bool, remaining: List<&2, Test>}
  Fixed{value: Bool}
  CountMatches{tests: List<&2, Test>, count: B.BigNat, bounds: CountBounds}
  CountNext{matched: Bool, remaining: List<&2, Test>, count: B.BigNat, bounds: CountBounds}

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

# A type array is one type constraint, not an anyOf of child schemas. Keeping
# that distinction allows diagnostics to describe the declaration accurately.
def matchesTypes(kinds: List<&2, JsonType>, +value: V.Value) -> Bool:
  match kinds:
    case Nil{}: False{}
    case head <> rest: matchesType(head, value) || matchesTypes(rest, value)

def member(values: List<&2, V.Value>, +value: V.Value) -> Bool:
  match values:
    case Nil{}: False{}
    case head <> tail: V.equal(head, value) || member(tail, value)

def unique(values: List<&2, V.Value>) -> Bool:
  match values:
    case Nil{}: True{}
    case head <> +rest:
      Bool.pick(Unit -> Bool, member(rest, head), _ => False{}, _ => unique(rest))(Unit{})

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

def dropItems(values: List<&2, V.Value>, offset: Nat) -> List<&2, V.Value>:
  match values offset:
    case values Zero{}: values
    case Nil{} _: Nil{}
    case _ <> rest Succ{offset}: dropItems(rest, offset)

def itemTests(values: List<&2, V.Value>, prefix: List<&2, Schema>, +items: Schema) -> List<&2, Test>:
  match values prefix:
    case Nil{} _: Nil{}
    case value <> tail Nil{}: Check{items, value} <> itemTests(tail, Nil{}, items)
    case value <> tail schema <> rest: Check{schema, value} <> itemTests(tail, rest, items)

# Count limits use compact exact integers: a large declared limit must not
# allocate one successor cell per unit or overflow a machine word.
def cardinality(-A: Data, values: List<&2, A>) -> B.BigNat:
  match values:
    case Nil{}: B.zero()
    case _ <> tail: B.add(B.one(), cardinality(A, tail))

def belowMaximum(count: B.BigNat, maximum: Maybe<&2, B.BigNat>) -> Bool:
  match maximum:
    case None{}: True{}
    case Some{limit}: Cmp.is_le(B.compare(count, limit))

def inBounds(+count: B.BigNat, bounds: CountBounds) -> Bool:
  match bounds:
    case CountBounds{minimum, maximum}: Cmp.is_ge(B.compare(count, minimum)) && belowMaximum(count, maximum)

def lowerBound(order: Maybe<&2, Cmp>, inclusive: Bool) -> Bool:
  match order:
    case Some{GT{}}: True{}
    case Some{EQ{}}: inclusive
    case _: False{}

def upperBound(order: Maybe<&2, Cmp>, inclusive: Bool) -> Bool:
  match order:
    case Some{LT{}}: True{}
    case Some{EQ{}}: inclusive
    case _: False{}

# Match the pinned validator's absolute remainder tolerance, including its
# integer/reciprocal shortcut. All arithmetic remains native binary64.
def nearMultiple(+value: F.F64) -> Bool:
  +tolerance = F.fromBits(1037794527, 3654794683)
  lowerBound(F.compare(value, F.negate(tolerance)), False{}) && upperBound(F.compare(value, tolerance), False{})

def multipleRemainder(+remainder: F.F64, +divisor: F.F64) -> Bool:
  nearMultiple(remainder) || nearMultiple(F.subtract(remainder, divisor)) || nearMultiple(F.add(remainder, divisor))

def multipleOf(+value: F.F64, +divisor: F.F64) -> Bool:
  (F.isInteger(value) && F.isInteger(F.divide(F.fromU32(1), divisor))) || multipleRemainder(F.remainder(value, divisor), divisor)

def containsTests(values: List<&2, V.Value>, +schema: Schema) -> List<&2, Test>:
  match values:
    case Nil{}: Nil{}
    case head <> tail: Check{schema, head} <> containsTests(tail, schema)

# Every expansion descends into a schema or instance child, or removes one
# pending test. No reference cycles exist in these immutable schema values.
@unsafe
def evaluate(test: Test) -> Bool:
  match test:
    case Fixed{value}: value
    case Check{Accept{}, _}: True{}
    case Check{Reject{}, _}: False{}
    case Check{JsonKind{kind}, value}: matchesType(kind, value)
    case Check{TypeUnion{kinds}, value}: matchesTypes(kinds, value)
    case Check{Constant{expected}, value}: V.equal(expected, value)
    case Check{Enumeration{values}, value}: member(values, value)
    case Check{All{schemas}, value}: evaluate(Every{tests(schemas, value)})
    case Check{Any{schemas}, value}: evaluate(SomeTest{tests(schemas, value)})
    case Check{One{schemas}, value}: evaluate(ExactlyOne{tests(schemas, value), False{}})
    case Check{Not{schema}, value}: Bool.not(evaluate(Check{schema, value}))
    case Check{Conditional{condition, consequent, alternative}, +value}:
      evaluate(Check{Bool.pick(Schema, evaluate(Check{condition, value}), consequent, alternative), value})
    case Check{Minimum{limit, inclusive}, V.Number{value}}: lowerBound(F.compare(value, limit), inclusive)
    case Check{Minimum{_, _}, _}: True{}
    case Check{Maximum{limit, inclusive}, V.Number{value}}: upperBound(F.compare(value, limit), inclusive)
    case Check{Maximum{_, _}, _}: True{}
    case Check{MultipleOf{divisor}, V.Number{value}}: multipleOf(value, divisor)
    case Check{MultipleOf{_}, _}: True{}
    case Check{UniqueItems{}, V.ArrayValue{values}}: unique(values)
    case Check{UniqueItems{}, _}: True{}
    case Check{StringLength{bounds}, V.Text{text}}: inBounds(length(text), bounds)
    case Check{StringLength{_}, _}: True{}
    case Check{ItemCount{bounds}, V.ArrayValue{values}}: inBounds(cardinality(V.Value, values), bounds)
    case Check{ItemCount{_}, _}: True{}
    case Check{PropertyCount{bounds}, V.ObjectValue{values}}: inBounds(cardinality(R.Property<V.Value>, R.entries(V.Value, values)), bounds)
    case Check{PropertyCount{_}, _}: True{}
    case Check{Contains{schema, bounds}, V.ArrayValue{values}}: evaluate(CountMatches{containsTests(values, schema), B.zero(), bounds})
    case Check{Contains{_, _}, _}: True{}
    case Check{Object{properties, required, additional}, V.ObjectValue{+value}}:
      evaluate(Every{requiredTests(required, value)}) && evaluate(Every{propertyTests(R.entries(V.Value, value), properties, additional)})
    case Check{Object{_, _, _}, _}: True{}
    case Check{Array{prefix, items}, V.ArrayValue{values}}: evaluate(Every{itemTests(values, prefix, items)})
    case Check{Array{_, _}, _}: True{}
    case Check{AdditionalItems{offset, items}, V.ArrayValue{values}}: evaluate(Every{itemTests(dropItems(values, offset), Nil{}, items)})
    case Check{AdditionalItems{_, _}, _}: True{}
    case Every{Nil{}}: True{}
    case Every{head <> tail}: evaluate(head) && evaluate(Every{tail})
    case SomeTest{Nil{}}: False{}
    case SomeTest{head <> tail}: evaluate(head) || evaluate(SomeTest{tail})
    case ExactlyOne{Nil{}, matched}: matched
    case ExactlyOne{head <> tail, matched}: evaluate(Counted{matched, evaluate(head), tail})
    case Counted{True{}, True{}, _}: False{}
    case Counted{previous, current, tail}: evaluate(ExactlyOne{tail, previous || current})
    case CountMatches{Nil{}, count, bounds}: inBounds(count, bounds)
    case CountMatches{head <> tail, count, bounds}: evaluate(CountNext{evaluate(head), tail, count, bounds})
    case CountNext{matched, tail, count, bounds}: evaluate(CountMatches{tail, B.add(count, Bool.pick(B.BigNat, matched, B.one(), B.zero())), bounds})

def check(schema: Schema, value: V.Value) -> Bool:
  evaluate(Check{schema, value})


# Runtime diagnostics are values, independent of a locale or tool-message
# renderer. Paths retain individual field/index segments, including empty keys.
type Reason is Data:
  Rejected{}
  DuplicateItems{}
  ExpectedType{expected: JsonType}
  ExpectedTypes{expected: List<&2, JsonType>}
  ExpectedConstant{expected: V.Value}
  ExpectedEnumeration{allowed: List<&2, V.Value>}
  MissingFields{keys: List<&2, String>}
  AdditionalFields{keys: List<&2, String>}
  NumericMinimum{limit: F.F64, inclusive: Bool}
  NumericMaximum{limit: F.F64, inclusive: Bool}
  NumericMultipleOf{divisor: F.F64}
  ErrorsStringLength{actual: B.BigNat, bounds: CountBounds}
  ErrorsItemCount{actual: B.BigNat, bounds: CountBounds}
  ErrorsPropertyCount{actual: B.BigNat, bounds: CountBounds}
  ContainsCount{actual: B.BigNat, bounds: CountBounds}
  NoAlternative{}
  ExclusiveAlternatives{matched: B.BigNat}
  NegatedSchema{}
  ConditionalBranch{consequent: Bool}

type Issue is Data:
  Issue{path: List<&2, String>, reason: Reason}

type ErrorsTask is Data:
  ErrorsVisit{schema: Schema, value: V.Value, path: List<&2, String>}
  EmitIssue{issue: Issue}

def child(path: List<&2, String>, key: String) -> List<&2, String>:
  List.append(&2, String, path, key <> Nil{})

def emitUnless(valid: Bool, path: List<&2, String>, reason: Reason) -> List<&2, ErrorsTask>:
  Bool.pick(List<&2, ErrorsTask>, valid, Nil{}, EmitIssue{Issue{path, reason}} <> Nil{})

# The pinned validator reports only the conditional summary for a failed
# then branch, and branch errors followed by the summary for a failed else.
def conditionalFailure(valid: Bool, +consequent: Bool, branch: Schema, value: V.Value, +path: List<&2, String>) -> List<&2, ErrorsTask>:
  match valid:
    case True{}: Nil{}
    case False{}:
      +summary = {EmitIssue{Issue{path, ConditionalBranch{consequent}}} <> Nil{} : List<&2, ErrorsTask>}
      Bool.pick(List<&2, ErrorsTask>, consequent, summary, ErrorsVisit{branch, value, path} <> summary)

def conditionalTasks(+consequent: Bool, thenSchema: Schema, elseSchema: Schema, +value: V.Value, path: List<&2, String>) -> List<&2, ErrorsTask>:
  +branch = Bool.pick(Schema, consequent, thenSchema, elseSchema)
  conditionalFailure(check(branch, value), consequent, branch, value, path)

def visits(schemas: List<&2, Schema>, +value: V.Value, +path: List<&2, String>) -> List<&2, ErrorsTask>:
  match schemas:
    case Nil{}: Nil{}
    case schema <> rest: ErrorsVisit{schema, value, path} <> visits(rest, value, path)

def matches(schemas: List<&2, Schema>, +value: V.Value) -> B.BigNat:
  match schemas:
    case Nil{}: B.zero()
    case schema <> rest: B.add(Bool.pick(B.BigNat, check(schema, value), B.one(), B.zero()), matches(rest, value))

def unionTasks(zero: Bool, exclusive: Bool, +matched: B.BigNat, schemas: List<&2, Schema>, value: V.Value, +path: List<&2, String>) -> List<&2, ErrorsTask>:
  match zero:
    case True{}: List.append(&2, ErrorsTask, visits(schemas, value, path), EmitIssue{Issue{path, Bool.pick(Reason, exclusive, ExclusiveAlternatives{matched}, NoAlternative{})}} <> Nil{})
    case False{}: emitUnless(Bool.not(exclusive) || B.equal(matched, B.one()), path, ExclusiveAlternatives{matched})

def missing(keys: List<&2, String>, +values: R.Record<V.Value>) -> List<&2, String>:
  match keys:
    case Nil{}: Nil{}
    case +key <> rest:
      +tail = missing(rest, values)
      Bool.pick(List<&2, String>, Maybe.is_some(&2, V.Value, R.get(V.Value, values, key)), tail, key <> tail)

def requiredTasks(keys: List<&2, String>, path: List<&2, String>) -> List<&2, ErrorsTask>:
  match keys:
    case Nil{}: Nil{}
    case first <> rest: EmitIssue{Issue{path, MissingFields{first <> rest}}} <> Nil{}

def presentTask(schema: Schema, value: Maybe<&2, V.Value>, path: List<&2, String>) -> List<&2, ErrorsTask>:
  match value:
    case None{}: Nil{}
    case Some{value}: ErrorsVisit{schema, value, path} <> Nil{}

def propertyTasks(fields: List<&2, R.Property<Schema>>, +values: R.Record<V.Value>, +path: List<&2, String>) -> List<&2, ErrorsTask>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{+key, schema} <> rest: List.append(&2, ErrorsTask, presentTask(schema, R.get(V.Value, values, key), child(path, key)), propertyTasks(rest, values, path))

def extraFields(fields: List<&2, R.Property<V.Value>>, +declared: R.Record<Schema>) -> List<&2, R.Property<V.Value>>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{+key, value} <> rest:
      +tail = extraFields(rest, declared)
      Bool.pick(List<&2, R.Property<V.Value>>, Maybe.is_some(&2, Schema, R.get(Schema, declared, key)), tail, R.Property{key, value} <> tail)

def extraTasks(fields: List<&2, R.Property<V.Value>>, +schema: Schema, +path: List<&2, String>) -> List<&2, ErrorsTask>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{key, value} <> rest: ErrorsVisit{schema, value, child(path, key)} <> extraTasks(rest, schema, path)

def invalidExtras(fields: List<&2, R.Property<V.Value>>, +schema: Schema) -> List<&2, String>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{key, value} <> rest:
      +tail = invalidExtras(rest, schema)
      Bool.pick(List<&2, String>, check(schema, value), tail, key <> tail)

def extraSummary(keys: List<&2, String>, path: List<&2, String>) -> List<&2, ErrorsTask>:
  match keys:
    case Nil{}: Nil{}
    case first <> rest: EmitIssue{Issue{path, AdditionalFields{first <> rest}}} <> Nil{}

def objectTasksErrors(+declared: R.Record<Schema>, required: List<&2, String>, +additional: Schema, +values: R.Record<V.Value>, +path: List<&2, String>) -> List<&2, ErrorsTask>:
  +extras = extraFields(R.entries(V.Value, values), declared)
  List.append(&2, ErrorsTask, requiredTasks(missing(required, values), path), List.append(&2, ErrorsTask, extraTasks(extras, additional, path), List.append(&2, ErrorsTask, extraSummary(invalidExtras(extras, additional), path), propertyTasks(R.entries(Schema, declared), values, path))))

def arrayTasksErrors(values: List<&2, V.Value>, prefix: List<&2, Schema>, +items: Schema, +path: List<&2, String>, +index: Nat) -> List<&2, ErrorsTask>:
  match values prefix:
    case Nil{} _: Nil{}
    case head <> tail Nil{}: ErrorsVisit{items, head, child(path, Nat.show(index))} <> arrayTasksErrors(tail, Nil{}, items, path, index + 1n)
    case head <> tail schema <> rest: ErrorsVisit{schema, head, child(path, Nat.show(index))} <> arrayTasksErrors(tail, rest, items, path, index + 1n)

# Upstream reports all tuple-prefix failures but stops at the first invalid
# additional item. The native node names that validation boundary explicitly.
def additionalTasks(values: List<&2, V.Value>, +items: Schema, +path: List<&2, String>, +index: Nat) -> List<&2, ErrorsTask>:
  match values:
    case Nil{}: Nil{}
    case +head <> tail:
      Bool.pick(Unit -> List<&2, ErrorsTask>, check(items, head),
        _ => additionalTasks(tail, items, path, index + 1n),
        _ => ErrorsVisit{items, head, child(path, Nat.show(index))} <> Nil{})(Unit{})

def contained(values: List<&2, V.Value>, +schema: Schema) -> B.BigNat:
  match values:
    case Nil{}: B.zero()
    case value <> rest: B.add(Bool.pick(B.BigNat, check(schema, value), B.one(), B.zero()), contained(rest, schema))

def expand(schema: Schema, value: V.Value, +path: List<&2, String>) -> List<&2, ErrorsTask>:
  match schema value:
    case Accept{} _: Nil{}
    case Reject{} _: EmitIssue{Issue{path, Rejected{}}} <> Nil{}
    case JsonKind{+expected} value: emitUnless(matchesType(expected, value), path, ExpectedType{expected})
    case TypeUnion{+expected} value: emitUnless(matchesTypes(expected, value), path, ExpectedTypes{expected})
    case Constant{+expected} value: emitUnless(V.equal(expected, value), path, ExpectedConstant{expected})
    case Enumeration{+allowed} value: emitUnless(member(allowed, value), path, ExpectedEnumeration{allowed})
    case All{schemas} value: visits(schemas, value, path)
    case Any{+schemas} +value:
      +matched = matches(schemas, value)
      unionTasks(B.isZero(matched), False{}, matched, schemas, value, path)
    case One{+schemas} +value:
      +matched = matches(schemas, value)
      unionTasks(B.isZero(matched), True{}, matched, schemas, value, path)
    case Conditional{condition, consequent, alternative} +value: conditionalTasks(check(condition, value), consequent, alternative, value, path)
    case Not{inner} value: emitUnless(Bool.not(check(inner, value)), path, NegatedSchema{})
    case Minimum{+limit, +inclusive} V.Number{number}: emitUnless(lowerBound(F.compare(number, limit), inclusive), path, NumericMinimum{limit, inclusive})
    case Maximum{+limit, +inclusive} V.Number{number}: emitUnless(upperBound(F.compare(number, limit), inclusive), path, NumericMaximum{limit, inclusive})
    case MultipleOf{+divisor} V.Number{number}: emitUnless(multipleOf(number, divisor), path, NumericMultipleOf{divisor})
    case MultipleOf{_} _: Nil{}
    case UniqueItems{} V.ArrayValue{values}: emitUnless(unique(values), path, DuplicateItems{})
    case UniqueItems{} _: Nil{}
    case StringLength{+bounds} V.Text{text}:
      +actual = length(text)
      emitUnless(inBounds(actual, bounds), path, ErrorsStringLength{actual, bounds})
    case ItemCount{+bounds} V.ArrayValue{values}:
      +actual = cardinality(V.Value, values)
      emitUnless(inBounds(actual, bounds), path, ErrorsItemCount{actual, bounds})
    case PropertyCount{+bounds} V.ObjectValue{values}:
      +actual = cardinality(R.Property<V.Value>, R.entries(V.Value, values))
      emitUnless(inBounds(actual, bounds), path, ErrorsPropertyCount{actual, bounds})
    case Contains{inner, +bounds} V.ArrayValue{values}:
      +actual = contained(values, inner)
      emitUnless(inBounds(actual, bounds), path, ContainsCount{actual, bounds})
    case Object{declared, required, additional} V.ObjectValue{values}: objectTasksErrors(declared, required, additional, values, path)
    case Array{prefix, items} V.ArrayValue{values}: arrayTasksErrors(values, prefix, items, path, 0n)
    case AdditionalItems{+offset, items} V.ArrayValue{values}: additionalTasks(dropItems(values, offset), items, path, offset)
    case AdditionalItems{_, _} _: Nil{}
    case Minimum{_, _} _: Nil{}
    case Maximum{_, _} _: Nil{}
    case StringLength{_} _: Nil{}
    case ItemCount{_} _: Nil{}
    case PropertyCount{_} _: Nil{}
    case Contains{_, _} _: Nil{}
    case Object{_, _, _} _: Nil{}
    case Array{_, _} _: Nil{}

def afterEmission(remaining: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match remaining:
    case None{}: None{}
    case Some{Zero{}}: Some{0n}
    case Some{Succ{rest}}: Some{rest}

# Every expansion consumes a finite schema child or instance element. Results
# accumulate in reverse so emitting another issue never copies prior issues.
@unsafe
def collect(tasks: List<&2, ErrorsTask>, issues: List<&2, Issue>, remaining: Maybe<&2, Nat>) -> List<&2, Issue>:
  match tasks remaining:
    case _ Some{Zero{}}: List.reverse(&2, Issue, issues)
    case Nil{} _: List.reverse(&2, Issue, issues)
    case EmitIssue{issue} <> rest remaining: collect(rest, issue <> issues, afterEmission(remaining))
    case ErrorsVisit{schema, value, path} <> rest remaining: collect(List.append(&2, ErrorsTask, expand(schema, value, path), rest), issues, remaining)

def errors(schema: Schema, value: V.Value) -> List<&2, Issue>:
  collect(ErrorsVisit{schema, value, Nil{}} <> Nil{}, Nil{}, None{})

def errorsLimited(schema: Schema, value: V.Value, limit: Nat) -> List<&2, Issue>:
  collect(ErrorsVisit{schema, value, Nil{}} <> Nil{}, Nil{}, Some{limit})


# Builder conversion is a separate policy from pi's plain-JSON coercion. A
# native declaration will choose its policy explicitly, without hidden symbols.
type Primitive is Data:
  ToBoolean{}
  ToNumber{}
  ToInteger{}
  ToString{}
  ToNull{}

type Error is Data:
  NumberFormattingFailed{}
  InvalidConversionState{}

def Converted() -> Data: Result<&2, &2, Error, V.Value>

def booleanText(+text: String) -> Maybe<&2, V.Value>:
  +lower = String.to_lower(text)
  Bool.pick(Maybe<&2, V.Value>, String.eq(lower, "true") || String.eq(text, "1"), Some{V.Boolean{True{}}},
    Bool.pick(Maybe<&2, V.Value>, String.eq(lower, "false") || String.eq(text, "0"), Some{V.Boolean{False{}}}, None{}))

def tryBoolean(value: V.Value) -> Maybe<&2, V.Value>:
  match value:
    case V.Null{}: Some{V.Boolean{False{}}}
    case V.Boolean{value}: Some{V.Boolean{value}}
    case V.Text{text}: booleanText(text)
    case V.Number{+number}:
      Bool.pick(Maybe<&2, V.Value>, V.equal(V.Number{number}, V.Number{F.fromU32(0)}), Some{V.Boolean{False{}}}, Bool.pick(Maybe<&2, V.Value>, V.equal(V.Number{number}, V.Number{F.fromU32(1)}), Some{V.Boolean{True{}}}, None{}))
    case _: None{}

# TypeBox also accepts decimal bigint-literal strings within the exact integer
# range. Parse that finite grammar directly; no JavaScript bigint is involved.
def literalDigits(text: String, +magnitude: B.BigNat) -> Maybe<&2, B.BigNat>:
  match text:
    case SNil{}: None{}
    case SCon{Chr{+code}, +rest}:
      Bool.pick(Unit -> Maybe<&2, B.BigNat>, U32.is_eq(code, 110),
        _ => Bool.pick(Maybe<&2, B.BigNat>, String.is_empty(rest), Some{magnitude}, None{}),
        _ => Bool.pick(Unit -> Maybe<&2, B.BigNat>, U32.is_ge(code, 48) && U32.is_le(code, 57),
          _ => literalDigits(rest, B.add(B.multiplyU32(magnitude, 10), B.fromU32((code - 48 : U32)))), _ => None{})(Unit{}))(Unit{})

def unsignedLiteral(text: String) -> Maybe<&2, B.BigNat>:
  match text:
    case SNil{}: None{}
    case SCon{Chr{+code}, +rest}:
      Bool.pick(Unit -> Maybe<&2, B.BigNat>, U32.is_eq(code, 48),
        _ => Bool.pick(Maybe<&2, B.BigNat>, String.eq(rest, "n"), Some{B.zero()}, None{}),
        _ => Bool.pick(Unit -> Maybe<&2, B.BigNat>, U32.is_ge(code, 49) && U32.is_le(code, 57),
          _ => literalDigits(rest, B.fromU32((code - 48 : U32))), _ => None{})(Unit{}))(Unit{})

def safeLiteral(negative: Bool, result: Maybe<&2, B.BigNat>) -> Maybe<&2, V.Value>:
  match result:
    case None{}: None{}
    case Some{+magnitude}:
      limit = {B.BigNat{65535 <> 65535 <> 65535 <> 31 <> Nil{}} : B.BigNat}
      prefix = Bool.pick(String, negative && Bool.not(B.isZero(magnitude)), "-", "")
      Bool.pick(Unit -> Maybe<&2, V.Value>, Cmp.is_le(B.compare(magnitude, limit)),
        _ => Some{V.Number{Number.toNumber(prefix ++ B.toDecimal(magnitude))}}, _ => None{})(Unit{})

def bigintLiteral(text: String) -> Maybe<&2, V.Value>:
  match text:
    case SCon{Chr{45}, rest}: safeLiteral(True{}, unsignedLiteral(rest))
    case other: safeLiteral(False{}, unsignedLiteral(other))

def booleanNumber(result: Maybe<&2, V.Value>, fallback: Maybe<&2, V.Value>) -> Maybe<&2, V.Value>:
  match result:
    case Some{V.Boolean{flag}}: Some{V.Number{F.fromU32(Bool.pick(U32, flag, 1, 0))}}
    case _: fallback

def parsedNumber(finite: Bool, parsed: F.F64, +text: String) -> Maybe<&2, V.Value>:
  match finite:
    case True{}: Some{V.Number{parsed}}
    case False{}: booleanNumber(booleanText(text), bigintLiteral(text))

def tryNumber(value: V.Value) -> Maybe<&2, V.Value>:
  match value:
    case V.Null{}: Some{V.Number{F.fromU32(0)}}
    case V.Boolean{flag}: Some{V.Number{F.fromU32(Bool.pick(U32, flag, 1, 0))}}
    case V.Number{+number}: Bool.pick(Maybe<&2, V.Value>, finite(F.decode(number)), Some{V.Number{number}}, None{})
    case V.Text{+text}:
      +parsed = Number.toNumber(text)
      parsedNumber(finite(F.decode(parsed)), parsed, text)
    case _: None{}

def tryNull(value: V.Value) -> Maybe<&2, V.Value>:
  match value:
    case V.Null{}: Some{V.Null{}}
    case V.Boolean{flag}: Bool.pick(Maybe<&2, V.Value>, flag, None{}, Some{V.Null{}})
    case V.Number{number}: Bool.pick(Maybe<&2, V.Value>, V.equal(V.Number{number}, V.Number{F.fromU32(0)}), Some{V.Null{}}, None{})
    case V.Text{+text}:
      +lower = String.to_lower(text)
      Bool.pick(Maybe<&2, V.Value>, String.eq(lower, "null") || String.eq(lower, "undefined") || String.eq(text, "") || String.eq(text, "0"), Some{V.Null{}}, None{})
    case _: None{}

def convertedOrOriginal(original: V.Value, converted: Maybe<&2, V.Value>) -> Converted():
  match converted:
    case None{}: Done{original}
    case Some{value}: Done{value}

def integerResult(value: Maybe<&2, V.Value>) -> Maybe<&2, V.Value>:
  match value:
    case Some{V.Number{number}}: Some{V.Number{F.truncate(number)}}
    case other: other

def formattedNumber(text: Maybe<&2, String>) -> Converted():
  match text:
    case Some{text}: Done{V.Text{text}}
    case None{}: Fail{NumberFormattingFailed{}}

def convertString(value: V.Value) -> Converted():
  match value:
    case V.Null{}: Done{V.Text{"null"}}
    case V.Boolean{flag}: Done{V.Text{Bool.pick(String, flag, "true", "false")}}
    case V.Number{number}: formattedNumber(F.toDecimal(number))
    case other: Done{other}

def convertPrimitive(primitive: Primitive, +value: V.Value) -> Converted():
  match primitive:
    case ToBoolean{}: convertedOrOriginal(value, tryBoolean(value))
    case ToNumber{}: convertedOrOriginal(value, tryNumber(value))
    case ToInteger{}: convertedOrOriginal(value, integerResult(tryNumber(value)))
    case ToString{}: convertString(value)
    case ToNull{}: convertedOrOriginal(value, tryNull(value))

# JSON-compatible literals have an explicit conversion kind. Bigint literals
# are outside JSON tool arguments; there is no host-language bigint value here.
type LiteralValue is Data:
  BooleanLiteral{value: Bool}
  NumberLiteral{value: F.F64}
  StringLiteral{value: String}

def literalValue(literal: LiteralValue) -> V.Value:
  match literal:
    case BooleanLiteral{value}: V.Boolean{value}
    case NumberLiteral{value}: V.Number{value}
    case StringLiteral{value}: V.Text{value}

def literalPrimitive(literal: LiteralValue) -> Primitive:
  match literal:
    case BooleanLiteral{_}: ToBoolean{}
    case NumberLiteral{_}: ToNumber{}
    case StringLiteral{_}: ToString{}

def selectLiteral(+expected: V.Value, +original: V.Value, result: Converted()) -> Converted():
  match result:
    case Fail{error}: Fail{error}
    case Done{+candidate}: Done{Bool.pick(V.Value, V.equal(expected, original), original, Bool.pick(V.Value, V.equal(expected, candidate), candidate, original))}

# Each union branch carries its executable constraint alongside its conversion
# policy. Candidates are checked against the complete union, in source order.
type Branch<-P: Data> is Data:
  Branch{schema: Schema, policy: P}

# Conversion policy is explicit data, separate from schema validation. Tuple
# conversion does not pad missing positions or drop additional positions.
type Policy is Data:
  Preserve{}
  Literal{value: LiteralValue}
  Union{branches: List<&2, Branch<Policy>>, candidateConstraint: Schema}
  Scalar{primitive: Primitive}
  ArrayItems{item: Policy}
  TupleItems{items: List<&2, Policy>}
  ObjectFields{fields: R.Record<Policy>, additional: Policy}

type Task is Data:
  Visit{policy: Policy, value: V.Value}
  FinishArray{count: Nat}
  FinishObject{keys: List<&2, String>}
  ConvertedValue{result: Converted()}
  TryAlternative{schema: Schema, branches: List<&2, Branch<Policy>>, original: V.Value}
  SelectAlternative{schema: Schema, remaining: List<&2, Branch<Policy>>, original: V.Value}

def branchSchemas(branches: List<&2, Branch<Policy>>) -> List<&2, Schema>:
  match branches:
    case Nil{}: Nil{}
    case Branch{schema, _} <> rest: schema <> branchSchemas(rest)

def unionConvert(+branches: List<&2, Branch<Policy>>) -> Policy:
  Union{branches, Any{branchSchemas(branches)}}

# An already-valid branch preserves the original input. Converted candidates
# must satisfy the whole configured union, including its outer constraints.
def scheduleUnion(+branches: List<&2, Branch<Policy>>, accepted: Schema, +original: V.Value, +rest: List<&2, Task>) -> List<&2, Task>:
  Bool.pick(Unit -> List<&2, Task>, check(Any{branchSchemas(branches)}, original),
    _ => Visit{Preserve{}, original} <> rest,
    _ => TryAlternative{accepted, branches, original} <> rest)(Unit{})

def arrayTasks(+policy: Policy, values: List<&2, V.Value>) -> List<&2, Task>:
  match values:
    case Nil{}: Nil{}
    case head <> tail: Visit{policy, head} <> arrayTasks(policy, tail)

def tupleTasks(policies: List<&2, Policy>, values: List<&2, V.Value>) -> List<&2, Task>:
  match policies values:
    case _ Nil{}: Nil{}
    case Nil{} head <> tail: Visit{Preserve{}, head} <> tupleTasks(Nil{}, tail)
    case policy <> policies head <> tail: Visit{policy, head} <> tupleTasks(policies, tail)

def fieldPolicy(selected: Maybe<&2, Policy>, additional: Policy) -> Policy:
  match selected:
    case None{}: additional
    case Some{policy}: policy

def objectTasks(+fields: R.Record<Policy>, +additional: Policy, values: List<&2, R.Property<V.Value>>) -> List<&2, Task>:
  match values:
    case Nil{}: Nil{}
    case R.Property{key, value} <> rest: Visit{fieldPolicy(R.get(Policy, fields, key), additional), value} <> objectTasks(fields, additional, rest)

def reverseKeys(values: List<&2, R.Property<V.Value>>, keys: List<&2, String>) -> List<&2, String>:
  match values:
    case Nil{}: keys
    case R.Property{key, _} <> rest: reverseKeys(rest, key <> keys)

def scheduleObject(fields: R.Record<Policy>, additional: Policy, value: V.Value, rest: List<&2, Task>) -> List<&2, Task>:
  match value:
    case V.ObjectValue{R.Record{+values}}: List.append(&2, Task, objectTasks(fields, additional, values), FinishObject{reverseKeys(values, Nil{})} <> rest)
    case other: Visit{Preserve{}, other} <> rest

def finishObject(keys: List<&2, String>, values: List<&2, V.Value>, fields: List<&2, R.Property<V.Value>>) -> List<&2, V.Value>:
  match keys values:
    case Nil{} rest: V.ObjectValue{R.Record{fields}} <> rest
    case key <> keys value <> rest: finishObject(keys, rest, R.Property{key, value} <> fields)
    case _ Nil{}: Nil{}

def arrayInput(value: V.Value) -> List<&2, V.Value>:
  match value:
    case V.ArrayValue{items}: items
    case other: other <> Nil{}

def scheduleArray(policy: Policy, +items: List<&2, V.Value>, rest: List<&2, Task>) -> List<&2, Task>:
  List.append(&2, Task, arrayTasks(policy, items), FinishArray{List.length(&2, V.Value, items)} <> rest)

def scheduleTuple(policies: List<&2, Policy>, value: V.Value, rest: List<&2, Task>) -> List<&2, Task>:
  match value:
    case V.ArrayValue{+items}: List.append(&2, Task, tupleTasks(policies, items), FinishArray{List.length(&2, V.Value, items)} <> rest)
    case other: Visit{Preserve{}, other} <> rest

# Child results arrive in reverse traversal order. Reassemble their original
# order without changing any input value or exposing intermediate mutations.
def finishArray(count: Nat, values: List<&2, V.Value>, items: List<&2, V.Value>) -> List<&2, V.Value>:
  match count values:
    case Zero{} rest: V.ArrayValue{items} <> rest
    case Succ{count} head <> tail: finishArray(count, tail, head <> items)
    case Succ{_} Nil{}: Nil{}

# Visits consume finite policy/value nodes; alternatives consume a finite
# branch list, always retrying the original value. FinishArray consumes its
# completed children. The explicit work list also handles deeply nested inputs.
@unsafe
def run(tasks: List<&2, Task>, values: List<&2, V.Value>) -> Converted():
  match tasks values:
    case Nil{} value <> Nil{}: Done{value}
    case Nil{} _: Fail{InvalidConversionState{}}
    case FinishObject{keys} <> rest values: run(rest, finishObject(keys, values, Nil{}))
    case Visit{ObjectFields{fields, additional}, value} <> rest values: run(scheduleObject(fields, additional, value, rest), values)
    case FinishArray{count} <> rest values: run(rest, finishArray(count, values, Nil{}))
    case Visit{Preserve{}, value} <> rest values: run(rest, value <> values)
    case Visit{Literal{+literal}, +original} <> rest values: run(ConvertedValue{selectLiteral(literalValue(literal), original, convertPrimitive(literalPrimitive(literal), original))} <> rest, values)
    case Visit{Union{branches, accepted}, original} <> rest values: run(scheduleUnion(branches, accepted, original, rest), values)
    case TryAlternative{_, Nil{}, original} <> rest values: run(rest, original <> values)
    case TryAlternative{+schema, Branch{_, policy} <> remaining, +original} <> rest values: run(Visit{policy, original} <> SelectAlternative{schema, remaining, original} <> rest, values)
    case SelectAlternative{+schema, remaining, original} <> +rest +candidate <> +values:
      Bool.pick(Unit -> Converted(), check(schema, candidate),
        _ => run(rest, candidate <> values),
        _ => run(TryAlternative{schema, remaining, original} <> rest, values))(Unit{})
    case SelectAlternative{_, _, _} <> _ Nil{}: Fail{InvalidConversionState{}}
    case Visit{Scalar{primitive}, value} <> rest values: run(ConvertedValue{convertPrimitive(primitive, value)} <> rest, values)
    case ConvertedValue{Done{converted}} <> rest values: run(rest, converted <> values)
    case ConvertedValue{Fail{error}} <> _ _: Fail{error}
    case Visit{ArrayItems{policy}, value} <> rest values: run(scheduleArray(policy, arrayInput(value), rest), values)
    case Visit{TupleItems{policies}, value} <> rest values: run(scheduleTuple(policies, value, rest), values)

def apply(policy: Policy, value: V.Value) -> Converted():
  run(Visit{policy, value} <> Nil{}, Nil{})


# A pointer is a value: its decoded segments retain empty names and literal
# slashes. Reading traverses only explicit dictionary fields and list elements.
type Pointer is Data:
  Pointer{segments: List<&2, String>}

def unescape(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{Chr{126}, SCon{Chr{49}, rest}}: SCon{Chr{47}, unescape(rest)}
    case SCon{Chr{126}, SCon{Chr{48}, rest}}: SCon{Chr{126}, unescape(rest)}
    case SCon{char, rest}: SCon{char, unescape(rest)}

def segments(text: String, current: String, reversed: List<&2, String>) -> List<&2, String>:
  match text:
    case SNil{}: List.reverse(&2, String, unescape(String.reverse(current)) <> reversed)
    case SCon{Chr{47}, rest}: segments(rest, "", unescape(String.reverse(current)) <> reversed)
    case SCon{char, rest}: segments(rest, SCon{char, current}, reversed)

def parse(text: String) -> Maybe<&2, Pointer>:
  match text:
    case SNil{}: Some{Pointer{Nil{}}}
    case SCon{Chr{47}, rest}: Some{Pointer{segments(rest, "", Nil{})}}
    case _: None{}

def decodedFragment(value: Maybe<&2, String>) -> Maybe<&2, Pointer>:
  match value:
    case None{}: None{}
    case Some{text}: parse(text)

# This accepts only local root/pointer fragments. Named anchors and external
# references require the schema resource resolver, not pointer traversal.
def parseFragment(text: String) -> Maybe<&2, Pointer>:
  match text:
    case SCon{Chr{35}, rest}: decodedFragment(Uri.decode(rest))
    case _: None{}

def arrayAt(values: List<&2, V.Value>, +key: String, +index: Nat) -> Maybe<&2, V.Value>:
  match values:
    case Nil{}: None{}
    case head <> rest:
      Bool.pick(Unit -> Maybe<&2, V.Value>, String.eq(key, Nat.show(index)),
        _ => Some{head}, _ => arrayAt(rest, key, index + 1n))(Unit{})

def fieldPointer(value: V.Value, key: String) -> Maybe<&2, V.Value>:
  match value:
    case V.ObjectValue{fields}: R.get(V.Value, fields, key)
    case V.ArrayValue{values}: arrayAt(values, key, 0n)
    case _: None{}

def traverse(path: List<&2, String>, value: Maybe<&2, V.Value>) -> Maybe<&2, V.Value>:
  match path value:
    case _ None{}: None{}
    case Nil{} value: value
    case key <> rest Some{value}: traverse(rest, fieldPointer(value, key))

def get(value: V.Value, pointer: Pointer) -> Maybe<&2, V.Value>:
  match pointer:
    case Pointer{path}: traverse(path, Some{value})

def escape(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{Chr{126}, rest}: "~0" ++ escape(rest)
    case SCon{Chr{47}, rest}: "~1" ++ escape(rest)
    case SCon{char, rest}: SCon{char, escape(rest)}

def renderedSegments(path: List<&2, String>) -> String:
  match path:
    case Nil{}: ""
    case head <> rest: "/" ++ escape(head) ++ renderedSegments(rest)

def render(pointer: Pointer) -> String:
  match pointer:
    case Pointer{path}: renderedSegments(path)


# Paths are ordered JSON field/index segments, independent of diagnostic text.
type LoadIssue is Data:
  UnsupportedKeyword{keyword: String}
  InvalidSchema{expected: String}
  InvalidConstruction{}
  UnsupportedReference{reference: String}
  UnsupportedReferenceCycle{reference: String}

type LoadError is Data:
  LoadError{path: List<&2, String>, issue: LoadIssue}

def Loaded() -> Data: Result<&2, &2, LoadError, Schema>

type Constructor is Data:
  Conjunction{}
  Disjunction{}
  TypeAlternatives{}
  Exclusive{}
  Negation{}
  LoadConditional{}
  Properties{keys: List<&2, String>}
  Additional{propertiesLoad: R.Record<Schema>}
  LoadTupleItems{}
  AllItems{}
  ExtraItems{prefix: List<&2, Schema>}
  Containing{bounds: CountBounds}

type Resolved is Data:
  Resolved{value: V.Value, path: List<&2, String>, key: String}
  Unresolved{}

def Resolution() -> Data: Result<&2, &2, LoadError, Resolved>

type LoadTask is Data:
  Read{value: V.Value, path: List<&2, String>}
  ResolveReference{reference: String, path: List<&2, String>}
  ReferenceResult{resolution: Resolution()}
  EndReference{}
  Keyword{key: String, value: V.Value, whole: R.Record<V.Value>, path: List<&2, String>}
  TypeName{value: V.Value, path: List<&2, String>}
  Push{schema: Schema}
  Build{constructor: Constructor, count: Nat}

def Scheduled() -> Data: Result<&2, &2, LoadError, List<&2, LoadTask>>

def childLoad(path: List<&2, String>, key: String) -> List<&2, String>:
  List.append(&2, String, path, key <> Nil{})

def invalid(-A: Data, path: List<&2, String>, expected: String) -> Result<&2, &2, LoadError, A>:
  Fail{LoadError{path, InvalidSchema{expected}}}

def parentReversed(path: List<&2, String>) -> List<&2, String>:
  match path:
    case Nil{}: Nil{}
    case _ <> rest: List.reverse(&2, String, rest)

def sibling(path: List<&2, String>, name: String) -> List<&2, String>:
  childLoad(parentReversed(List.reverse(&2, String, path)), name)

def conditional(value: V.Value, +whole: R.Record<V.Value>, +path: List<&2, String>) -> Scheduled():
  consequent = Maybe.default(&2, V.Value, R.get(V.Value, whole, "then"), V.Boolean{True{}})
  alternative = Maybe.default(&2, V.Value, R.get(V.Value, whole, "else"), V.Boolean{True{}})
  Done{Read{value, path} <> Read{consequent, sibling(path, "then")} <> Read{alternative, sibling(path, "else")} <> Build{LoadConditional{}, 3n} <> Nil{}}

def kindLoad(+name: String) -> Maybe<&2, JsonType>:
  Bool.pick(Maybe<&2, JsonType>, String.eq(name, "null"), Some{NullType{}}, Bool.pick(Maybe<&2, JsonType>, String.eq(name, "boolean"), Some{BooleanType{}}, Bool.pick(Maybe<&2, JsonType>, String.eq(name, "number"), Some{NumberType{}}, Bool.pick(Maybe<&2, JsonType>, String.eq(name, "integer"), Some{IntegerType{}}, Bool.pick(Maybe<&2, JsonType>, String.eq(name, "string"), Some{StringType{}}, Bool.pick(Maybe<&2, JsonType>, String.eq(name, "array"), Some{ArrayType{}}, Bool.pick(Maybe<&2, JsonType>, String.eq(name, "object"), Some{ObjectType{}}, None{})))))))

def typeNode(value: Maybe<&2, JsonType>, path: List<&2, String>) -> Loaded():
  match value:
    case Some{value}: Done{JsonKind{value}}
    case None{}: invalid(Schema, path, "a JSON type name")

def atomicType(value: V.Value, path: List<&2, String>) -> Loaded():
  match value:
    case V.Text{name}: typeNode(kindLoad(name), path)
    case _: invalid(Schema, path, "a JSON type name")

def typeMembers(values: List<&2, V.Value>, +path: List<&2, String>) -> List<&2, LoadTask>:
  match values:
    case Nil{}: Nil{}
    case value <> tail: TypeName{value, path} <> typeMembers(tail, path)

def pushed(value: Loaded()) -> Scheduled():
  match value:
    case Fail{error}: Fail{error}
    case Done{schema}: Done{Push{schema} <> Nil{}}

def typed(value: V.Value, +path: List<&2, String>) -> Scheduled():
  match value:
    case V.Text{name}: pushed(typeNode(kindLoad(name), path))
    case V.ArrayValue{+values}: Done{List.append(&2, LoadTask, typeMembers(values, path), Build{TypeAlternatives{}, List.length(&2, V.Value, values)} <> Nil{})}
    case _: invalid(List<&2, LoadTask>, path, "a type name or array of type names")

def childReads(values: List<&2, V.Value>, +path: List<&2, String>, +index: Nat) -> List<&2, LoadTask>:
  match values:
    case Nil{}: Nil{}
    case value <> tail: Read{value, childLoad(path, Nat.show(index))} <> childReads(tail, path, index + 1n)

def group(constructor: Constructor, value: V.Value, path: List<&2, String>) -> Scheduled():
  match value:
    case V.ArrayValue{+values}: Done{List.append(&2, LoadTask, childReads(values, path, 0n), Build{constructor, List.length(&2, V.Value, values)} <> Nil{})}
    case _: invalid(List<&2, LoadTask>, path, "an array of schemas")

def fieldKeys(fields: List<&2, R.Property<V.Value>>) -> List<&2, String>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{key, _} <> tail: key <> fieldKeys(tail)

def fieldReads(fields: List<&2, R.Property<V.Value>>, +path: List<&2, String>) -> List<&2, LoadTask>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{key, value} <> tail: Read{value, childLoad(path, key)} <> fieldReads(tail, path)

def propertiesLoad(value: V.Value, path: List<&2, String>) -> Scheduled():
  match value:
    case V.ObjectValue{R.Record{+fields}}: Done{List.append(&2, LoadTask, fieldReads(fields, path), Build{Properties{fieldKeys(fields)}, List.length(&2, R.Property<V.Value>, fields)} <> Nil{})}
    case _: invalid(List<&2, LoadTask>, path, "a dictionary of schemas")

def prependString(key: String, result: Result<&2, &2, LoadError, List<&2, String>>) -> Result<&2, &2, LoadError, List<&2, String>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{rest}: Done{key <> rest}

def strings(values: List<&2, V.Value>, +path: List<&2, String>) -> Result<&2, &2, LoadError, List<&2, String>>:
  match values:
    case Nil{}: Done{Nil{}}
    case V.Text{key} <> tail: prependString(key, strings(tail, path))
    case _: invalid(List<&2, String>, path, "an array of strings")

def requiredNode(result: Result<&2, &2, LoadError, List<&2, String>>) -> Scheduled():
  match result:
    case Fail{error}: Fail{error}
    case Done{keys}: Done{Push{Object{R.new(Schema), keys, Accept{}}} <> Nil{}}

def requiredLoad(value: V.Value, path: List<&2, String>) -> Scheduled():
  match value:
    case V.ArrayValue{values}: requiredNode(strings(values, path))
    case _: invalid(List<&2, LoadTask>, path, "an array of required field names")

def allowedFields(fields: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<Schema>>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{key, _} <> tail: R.Property{key, Accept{}} <> allowedFields(tail)

def declaredFields(value: Maybe<&2, V.Value>) -> R.Record<Schema>:
  match value:
    case Some{V.ObjectValue{R.Record{fields}}}: R.Record{allowedFields(fields)}
    case _: R.new(Schema)

def acceptedItems(values: List<&2, V.Value>) -> List<&2, Schema>:
  match values:
    case Nil{}: Nil{}
    case _ <> tail: Accept{} <> acceptedItems(tail)

def tuplePrefix(value: Maybe<&2, V.Value>) -> Maybe<&2, List<&2, Schema>>:
  match value:
    case Some{V.ArrayValue{values}}: Some{acceptedItems(values)}
    case _: None{}

def additionalItems(prefix: Maybe<&2, List<&2, Schema>>, value: V.Value, path: List<&2, String>) -> Scheduled():
  match prefix:
    case None{}: Done{Push{Accept{}} <> Nil{}}
    case Some{schemas}: Done{Read{value, path} <> Build{ExtraItems{schemas}, 1n} <> Nil{}}

def itemsLoad(value: V.Value, path: List<&2, String>) -> Scheduled():
  match value:
    case V.ArrayValue{+values}: group(LoadTupleItems{}, V.ArrayValue{values}, path)
    case other: Done{Read{other, path} <> Build{AllItems{}, 1n} <> Nil{}}

def numeric(lower: Bool, +inclusive: Bool, value: V.Value, path: List<&2, String>) -> Scheduled():
  match value:
    case V.Number{+limit}: Bool.pick(Scheduled(), finite(F.decode(limit)), Done{Push{Bool.pick(Schema, lower, Minimum{limit, inclusive}, Maximum{limit, inclusive})} <> Nil{}}, invalid(List<&2, LoadTask>, path, "a finite numeric bound"))
    case _: invalid(List<&2, LoadTask>, path, "a finite numeric bound")

def multiple(value: V.Value, path: List<&2, String>) -> Scheduled():
  match value:
    case V.Number{+divisor}: Bool.pick(Scheduled(), finite(F.decode(divisor)), Done{Push{MultipleOf{divisor}} <> Nil{}}, invalid(List<&2, LoadTask>, path, "a finite numeric divisor"))
    case _: invalid(List<&2, LoadTask>, path, "a finite numeric divisor")

def integerWord(value: W.U64) -> B.BigNat:
  match value:
    case W.U64{high, low}: B.add(B.shiftLeft(B.fromU32(high), 32n), B.fromU32(low))

def scaledInteger(large: Bool, exponent: U32, significand: W.U64) -> B.BigNat:
  match large:
    case True{}: B.shiftLeft(integerWord(significand), U32.to_nat((exponent - 1075 : U32)))
    case False{}: integerWord(W.shiftRight(significand, U32.to_nat((1075 - exponent : U32))))

def decodedCount(value: F.Decoded) -> B.BigNat:
  match value:
    case F.Finite{_, +exponent, significand}: scaledInteger(U32.is_ge(exponent, 1075), exponent, significand)
    case _: B.zero()

def acceptedCount(valid: Bool, value: F.F64, path: List<&2, String>) -> Result<&2, &2, LoadError, B.BigNat>:
  match valid:
    case True{}: Done{decodedCount(F.decode(value))}
    case False{}: invalid(B.BigNat, path, "a nonnegative finite integer")

def readCount(value: V.Value, path: List<&2, String>) -> Result<&2, &2, LoadError, B.BigNat>:
  match value:
    case V.Number{+number}: acceptedCount(finite(F.decode(number)) && F.isInteger(number) && lowerBound(F.compare(number, F.fromU32(0)), True{}), number, path)
    case _: invalid(B.BigNat, path, "a nonnegative finite integer")

def boundedCount(lower: Bool, +value: B.BigNat) -> CountBounds:
  Bool.pick(CountBounds, lower, CountBounds{value, None{}}, CountBounds{B.zero(), Some{value}})

def countNode(array: Bool, lower: Bool, result: Result<&2, &2, LoadError, B.BigNat>) -> Scheduled():
  match result:
    case Fail{error}: Fail{error}
    case Done{value}:
      +bounds = boundedCount(lower, value)
      Done{Push{Bool.pick(Schema, array, ItemCount{bounds}, PropertyCount{bounds})} <> Nil{}}

def lengthNode(lower: Bool, result: Result<&2, &2, LoadError, B.BigNat>) -> Scheduled():
  match result:
    case Fail{error}: Fail{error}
    case Done{value}: Done{Push{StringLength{boundedCount(lower, value)}} <> Nil{}}

def parentPath(path: List<&2, String>) -> List<&2, String>:
  match path:
    case Nil{}: Nil{}
    case _ <> Nil{}: Nil{}
    case first <> second <> rest: first <> parentPath(second <> rest)

def zeroMinimum(value: Maybe<&2, V.Value>) -> Bool:
  match value:
    case Some{value}: V.equal(value, V.Number{F.fromU32(0)})
    case None{}: False{}

# Keep the three contains constraints separate: their validity combines, but
# upstream emits a distinct issue for each failed keyword.
def contains(value: V.Value, whole: R.Record<V.Value>, path: List<&2, String>) -> Scheduled():
  minimum = Bool.pick(B.BigNat, zeroMinimum(R.get(V.Value, whole, "minContains")), B.zero(), B.one())
  Done{Read{value, path} <> Build{Containing{CountBounds{minimum, None{}}}, 1n} <> Nil{}}

def containsBound(lower: Bool, value: Result<&2, &2, LoadError, B.BigNat>, inner: Maybe<&2, V.Value>, path: List<&2, String>) -> Scheduled():
  match value inner:
    case Fail{error} _: Fail{error}
    case Done{_} None{}: Done{Push{Accept{}} <> Nil{}}
    case Done{limit} Some{schema}: Done{Read{schema, childLoad(parentPath(path), "contains")} <> Build{Containing{boundedCount(lower, limit)}, 1n} <> Nil{}}

def reference(value: V.Value, path: List<&2, String>) -> Scheduled():
  match value:
    case V.Text{text}: Done{ResolveReference{text, path} <> Nil{}}
    case _: invalid(List<&2, LoadTask>, path, "a schema reference string")

def definitions(value: V.Value, path: List<&2, String>) -> Scheduled():
  match value:
    case V.ObjectValue{_}: Done{Push{Accept{}} <> Nil{}}
    case _: invalid(List<&2, LoadTask>, path, "a schema definition dictionary")

type KeywordKind is Data:
  ReferenceKeyword{}
  DefinitionsKeyword{}
  TypeKeyword{}
  ConstKeyword{}
  EnumKeyword{}
  AllOfKeyword{}
  AnyOfKeyword{}
  OneOfKeyword{}
  IfKeyword{}
  ThenKeyword{}
  ElseKeyword{}
  NotKeyword{}
  PropertiesKeyword{}
  RequiredKeyword{}
  AdditionalPropertiesKeyword{}
  ItemsKeyword{}
  AdditionalItemsKeyword{}
  MultipleOfKeyword{}
  MinimumKeyword{}
  MaximumKeyword{}
  ExclusiveMinimumKeyword{}
  ExclusiveMaximumKeyword{}
  UniqueItemsKeyword{}
  MinLengthKeyword{}
  MaxLengthKeyword{}
  MinItemsKeyword{}
  MaxItemsKeyword{}
  MinPropertiesKeyword{}
  MaxPropertiesKeyword{}
  ContainsKeyword{}
  MinContainsKeyword{}
  MaxContainsKeyword{}
  AnnotationKeyword{}
  UnknownKeyword{}

def selectedKeyword(value: Maybe<&2, KeywordKind>) -> KeywordKind:
  match value:
    case Some{selected}: selected
    case None{}: UnknownKeyword{}

def keywordKind(key: String) -> KeywordKind:
  entries = {R.Record{R.Property{"$ref", ReferenceKeyword{}} <> R.Property{"$defs", DefinitionsKeyword{}} <> R.Property{"definitions", DefinitionsKeyword{}} <> R.Property{"type", TypeKeyword{}} <> R.Property{"const", ConstKeyword{}} <> R.Property{"enum", EnumKeyword{}} <> R.Property{"allOf", AllOfKeyword{}} <> R.Property{"anyOf", AnyOfKeyword{}} <> R.Property{"oneOf", OneOfKeyword{}} <> R.Property{"if", IfKeyword{}} <> R.Property{"then", ThenKeyword{}} <> R.Property{"else", ElseKeyword{}} <> R.Property{"not", NotKeyword{}} <> R.Property{"properties", PropertiesKeyword{}} <> R.Property{"required", RequiredKeyword{}} <> R.Property{"additionalProperties", AdditionalPropertiesKeyword{}} <> R.Property{"items", ItemsKeyword{}} <> R.Property{"additionalItems", AdditionalItemsKeyword{}} <> R.Property{"multipleOf", MultipleOfKeyword{}} <> R.Property{"minimum", MinimumKeyword{}} <> R.Property{"maximum", MaximumKeyword{}} <> R.Property{"exclusiveMinimum", ExclusiveMinimumKeyword{}} <> R.Property{"exclusiveMaximum", ExclusiveMaximumKeyword{}} <> R.Property{"uniqueItems", UniqueItemsKeyword{}} <> R.Property{"minLength", MinLengthKeyword{}} <> R.Property{"maxLength", MaxLengthKeyword{}} <> R.Property{"minItems", MinItemsKeyword{}} <> R.Property{"maxItems", MaxItemsKeyword{}} <> R.Property{"minProperties", MinPropertiesKeyword{}} <> R.Property{"maxProperties", MaxPropertiesKeyword{}} <> R.Property{"contains", ContainsKeyword{}} <> R.Property{"minContains", MinContainsKeyword{}} <> R.Property{"maxContains", MaxContainsKeyword{}} <> R.Property{"title", AnnotationKeyword{}} <> R.Property{"description", AnnotationKeyword{}} <> R.Property{"default", AnnotationKeyword{}} <> R.Property{"examples", AnnotationKeyword{}} <> R.Property{"deprecated", AnnotationKeyword{}} <> R.Property{"readOnly", AnnotationKeyword{}} <> R.Property{"writeOnly", AnnotationKeyword{}} <> Nil{}} : R.Record<KeywordKind>}
  selectedKeyword(R.get(KeywordKind, entries, key))

# Each keyword contributes one conjunct. Cross-keyword rules consult the whole
# schema explicitly, so dictionary enumeration order cannot change validation.
def dispatch(selected: KeywordKind, key: String, value: V.Value, whole: R.Record<V.Value>, +path: List<&2, String>) -> Scheduled():
  match selected:
    case ReferenceKeyword{}: reference(value, path)
    case DefinitionsKeyword{}: definitions(value, path)
    case TypeKeyword{}: typed(value, path)
    case ConstKeyword{}: Done{Push{Constant{value}} <> Nil{}}
    case EnumKeyword{}:
      match value:
        case V.ArrayValue{values}: Done{Push{Enumeration{values}} <> Nil{}}
        case _: invalid(List<&2, LoadTask>, path, "an array of enum values")
    case AllOfKeyword{}: group(Conjunction{}, value, path)
    case AnyOfKeyword{}: group(Disjunction{}, value, path)
    case OneOfKeyword{}: group(Exclusive{}, value, path)
    case IfKeyword{}: conditional(value, whole, path)
    case ThenKeyword{}: Done{Push{Accept{}} <> Nil{}}
    case ElseKeyword{}: Done{Push{Accept{}} <> Nil{}}
    case NotKeyword{}: Done{Read{value, path} <> Build{Negation{}, 1n} <> Nil{}}
    case PropertiesKeyword{}: propertiesLoad(value, path)
    case RequiredKeyword{}: requiredLoad(value, path)
    case AdditionalPropertiesKeyword{}: Done{Read{value, path} <> Build{Additional{declaredFields(R.get(V.Value, whole, "properties"))}, 1n} <> Nil{}}
    case ItemsKeyword{}: itemsLoad(value, path)
    case AdditionalItemsKeyword{}: additionalItems(tuplePrefix(R.get(V.Value, whole, "items")), value, path)
    case MultipleOfKeyword{}: multiple(value, path)
    case MinimumKeyword{}: numeric(True{}, True{}, value, path)
    case MaximumKeyword{}: numeric(False{}, True{}, value, path)
    case ExclusiveMinimumKeyword{}: numeric(True{}, False{}, value, path)
    case ExclusiveMaximumKeyword{}: numeric(False{}, False{}, value, path)
    case UniqueItemsKeyword{}:
      match value:
        case V.Boolean{enabled}: Done{Push{Bool.pick(Schema, enabled, UniqueItems{}, Accept{})} <> Nil{}}
        case _: invalid(List<&2, LoadTask>, path, "a boolean uniqueness flag")
    case MinLengthKeyword{}: lengthNode(True{}, readCount(value, path))
    case MaxLengthKeyword{}: lengthNode(False{}, readCount(value, path))
    case MinItemsKeyword{}: countNode(True{}, True{}, readCount(value, path))
    case MaxItemsKeyword{}: countNode(True{}, False{}, readCount(value, path))
    case MinPropertiesKeyword{}: countNode(False{}, True{}, readCount(value, path))
    case MaxPropertiesKeyword{}: countNode(False{}, False{}, readCount(value, path))
    case ContainsKeyword{}: contains(value, whole, path)
    case MinContainsKeyword{}: containsBound(True{}, readCount(value, path), R.get(V.Value, whole, "contains"), path)
    case MaxContainsKeyword{}: containsBound(False{}, readCount(value, path), R.get(V.Value, whole, "contains"), path)
    case AnnotationKeyword{}: Done{Push{Accept{}} <> Nil{}}
    case UnknownKeyword{}: Fail{LoadError{path, UnsupportedKeyword{key}}}

def keyword(+key: String, value: V.Value, whole: R.Record<V.Value>, path: List<&2, String>) -> Scheduled():
  dispatch(keywordKind(key), key, value, whole, path)

# Diagnostic keyword order is part of pi's displayed validation contract.
# Property dictionaries themselves retain their native insertion order.
def keywordOrder(selected: KeywordKind) -> U32:
  match selected:
    case TypeKeyword{}: 0
    case RequiredKeyword{}: 1
    case AdditionalPropertiesKeyword{}: 2
    case PropertiesKeyword{}: 3
    case MinPropertiesKeyword{}: 4
    case MaxPropertiesKeyword{}: 5
    case AdditionalItemsKeyword{}: 6
    case ContainsKeyword{}: 7
    case ItemsKeyword{}: 8
    case MaxContainsKeyword{}: 9
    case MaxItemsKeyword{}: 10
    case MinContainsKeyword{}: 11
    case MinItemsKeyword{}: 12
    case UniqueItemsKeyword{}: 13
    case MaxLengthKeyword{}: 14
    case MinLengthKeyword{}: 15
    case ExclusiveMaximumKeyword{}: 16
    case ExclusiveMinimumKeyword{}: 17
    case MaximumKeyword{}: 18
    case MinimumKeyword{}: 19
    case MultipleOfKeyword{}: 20
    case ReferenceKeyword{}: 21
    case DefinitionsKeyword{}: 29
    case ConstKeyword{}: 22
    case EnumKeyword{}: 23
    case IfKeyword{}: 24
    case ThenKeyword{}: 29
    case ElseKeyword{}: 29
    case NotKeyword{}: 25
    case AllOfKeyword{}: 26
    case AnyOfKeyword{}: 27
    case OneOfKeyword{}: 28
    case AnnotationKeyword{}: 29
    case UnknownKeyword{}: 29

def insertKeyword(+key: String, +value: V.Value, fields: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<V.Value>>:
  match fields:
    case Nil{}: R.Property{key, value} <> Nil{}
    case R.Property{+otherKey, +otherValue} <> +rest:
      Bool.pick(Unit -> List<&2, R.Property<V.Value>>, U32.is_le(keywordOrder(keywordKind(key)), keywordOrder(keywordKind(otherKey))),
        _ => R.Property{key, value} <> R.Property{otherKey, otherValue} <> rest,
        _ => R.Property{otherKey, otherValue} <> insertKeyword(key, value, rest))(Unit{})

def orderedKeywords(fields: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<V.Value>>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{key, value} <> rest: insertKeyword(key, value, orderedKeywords(rest))

def keywordTasks(fields: List<&2, R.Property<V.Value>>, +whole: R.Record<V.Value>, +path: List<&2, String>) -> List<&2, LoadTask>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{+key, value} <> tail: Keyword{key, value, whole, childLoad(path, key)} <> keywordTasks(tail, whole, path)

def read(value: V.Value, path: List<&2, String>) -> Scheduled():
  match value:
    case V.Boolean{flag}: Done{Push{Bool.pick(Schema, flag, Accept{}, Reject{})} <> Nil{}}
    case V.ObjectValue{+whole}:
      +fields = R.entries(V.Value, whole)
      Done{List.append(&2, LoadTask, keywordTasks(orderedKeywords(fields), whole, path), Build{Conjunction{}, List.length(&2, R.Property<V.Value>, fields)} <> Nil{})}
    case _: invalid(List<&2, LoadTask>, path, "an object or boolean schema")

def pairedProperties(keys: List<&2, String>, schemas: List<&2, Schema>) -> List<&2, R.Property<Schema>>:
  match keys schemas:
    case key <> keys schema <> schemas: R.Property{key, schema} <> pairedProperties(keys, schemas)
    case _ _: Nil{}

def prependType(typeName: JsonType, result: Result<&2, &2, LoadError, List<&2, JsonType>>) -> Result<&2, &2, LoadError, List<&2, JsonType>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{rest}: Done{typeName <> rest}

def compiledTypes(schemas: List<&2, Schema>) -> Result<&2, &2, LoadError, List<&2, JsonType>>:
  match schemas:
    case Nil{}: Done{Nil{}}
    case JsonKind{typeName} <> rest: prependType(typeName, compiledTypes(rest))
    case _: Fail{LoadError{Nil{}, InvalidConstruction{}}}

def typeAlternatives(result: Result<&2, &2, LoadError, List<&2, JsonType>>) -> Loaded():
  match result:
    case Fail{error}: Fail{error}
    case Done{kinds}: Done{TypeUnion{kinds}}

def construct(constructor: Constructor, schemas: List<&2, Schema>) -> Loaded():
  match constructor schemas:
    case Conjunction{} schemas: Done{All{schemas}}
    case Disjunction{} schemas: Done{Any{schemas}}
    case TypeAlternatives{} schemas: typeAlternatives(compiledTypes(schemas))
    case Exclusive{} schemas: Done{One{schemas}}
    case Negation{} schema <> Nil{}: Done{Not{schema}}
    case LoadConditional{} condition <> consequent <> alternative <> Nil{}: Done{Conditional{condition, consequent, alternative}}
    case Properties{keys} schemas: Done{Object{R.Record{pairedProperties(keys, schemas)}, Nil{}, Accept{}}}
    case Additional{fields} schema <> Nil{}: Done{Object{fields, Nil{}, schema}}
    case LoadTupleItems{} schemas: Done{Array{schemas, Accept{}}}
    case AllItems{} schema <> Nil{}: Done{Array{Nil{}, schema}}
    case ExtraItems{prefix} schema <> Nil{}: Done{AdditionalItems{List.length(&2, Schema, prefix), schema}}
    case Containing{bounds} schema <> Nil{}: Done{Contains{schema, bounds}}
    case _ _: Fail{LoadError{Nil{}, InvalidConstruction{}}}

type Stack is Data:
  Stack{values: List<&2, Schema>, rest: List<&2, Schema>}

def pop(count: Nat, stack: List<&2, Schema>, values: List<&2, Schema>) -> Result<&2, &2, LoadError, Stack>:
  match count stack:
    case Zero{} rest: Done{Stack{values, rest}}
    case Succ{count} head <> tail: pop(count, tail, head <> values)
    case _ _: Fail{LoadError{Nil{}, InvalidConstruction{}}}

def pushConstructed(value: Loaded(), rest: List<&2, Schema>) -> Result<&2, &2, LoadError, List<&2, Schema>>:
  match value:
    case Fail{error}: Fail{error}
    case Done{schema}: Done{schema <> rest}

def build(constructor: Constructor, popped: Result<&2, &2, LoadError, Stack>) -> Result<&2, &2, LoadError, List<&2, Schema>>:
  match popped:
    case Fail{error}: Fail{error}
    case Done{Stack{values, rest}}: pushConstructed(construct(constructor, values), rest)

def appendTasks(scheduled: Scheduled(), rest: List<&2, LoadTask>) -> Scheduled():
  match scheduled:
    case Fail{error}: Fail{error}
    case Done{tasks}: Done{List.append(&2, LoadTask, tasks, rest)}

def referenceActive(keys: List<&2, String>, +key: String) -> Bool:
  match keys:
    case Nil{}: False{}
    case head <> rest: String.eq(head, key) || referenceActive(rest, key)

def located(target: Maybe<&2, V.Value>, path: List<&2, String>, key: String) -> Resolution():
  match target:
    case None{}: Done{Unresolved{}}
    case Some{value}: Done{Resolved{value, path, key}}

def resolvedPointer(cyclic: Bool, root: V.Value, pointer: Pointer, key: String, ref: String, sourcePath: List<&2, String>) -> Resolution():
  match cyclic pointer:
    case True{} _: Fail{LoadError{sourcePath, UnsupportedReferenceCycle{ref}}}
    case False{} Pointer{+path}: located(get(root, Pointer{path}), path, key)

def parsedReference(root: V.Value, pointer: Maybe<&2, Pointer>, ref: String, sourcePath: List<&2, String>, active: List<&2, String>) -> Resolution():
  match pointer:
    case None{}: Fail{LoadError{sourcePath, UnsupportedReference{ref}}}
    case Some{+pointer}:
      +key = render(pointer)
      resolvedPointer(referenceActive(active, key), root, pointer, key, ref, sourcePath)

def resolve(root: V.Value, +ref: String, sourcePath: List<&2, String>, active: List<&2, String>) -> Resolution():
  parsedReference(root, parseFragment(ref), ref, sourcePath, active)

# Structural reads descend through a finite schema. References may revisit
# other branches, so active canonical pointer paths reject cycles explicitly
# until the graph evaluator supports recursive schemas.
@unsafe
def runLoad(scheduled: Scheduled(), compiled: Result<&2, &2, LoadError, List<&2, Schema>>, +root: V.Value, +active: List<&2, String>) -> Loaded():
  match scheduled compiled:
    case Fail{error} _: Fail{error}
    case _ Fail{error}: Fail{error}
    case Done{Nil{}} Done{schema <> Nil{}}: Done{schema}
    case Done{Nil{}} _: Fail{LoadError{Nil{}, InvalidConstruction{}}}
    case Done{ResolveReference{ref, path} <> rest} Done{stack}: runLoad(Done{ReferenceResult{resolve(root, ref, path, active)} <> rest}, Done{stack}, root, active)
    case Done{ReferenceResult{Fail{error}} <> _} _: Fail{error}
    case Done{ReferenceResult{Done{Unresolved{}}} <> rest} Done{stack}: runLoad(Done{Push{Reject{}} <> rest}, Done{stack}, root, active)
    case Done{ReferenceResult{Done{Resolved{value, path, key}}} <> rest} Done{stack}: runLoad(Done{Read{value, path} <> EndReference{} <> rest}, Done{stack}, root, key <> active)
    case Done{EndReference{} <> rest} Done{stack}:
      match active:
        case _ <> tail: runLoad(Done{rest}, Done{stack}, root, tail)
        case Nil{}: Fail{LoadError{Nil{}, InvalidConstruction{}}}
    case Done{TypeName{value, path} <> rest} Done{stack}: runLoad(appendTasks(pushed(atomicType(value, path)), rest), Done{stack}, root, active)
    case Done{Push{schema} <> rest} Done{stack}: runLoad(Done{rest}, Done{schema <> stack}, root, active)
    case Done{Read{value, path} <> rest} Done{stack}: runLoad(appendTasks(read(value, path), rest), Done{stack}, root, active)
    case Done{Keyword{key, value, whole, path} <> rest} Done{stack}: runLoad(appendTasks(keyword(key, value, whole, path), rest), Done{stack}, root, active)
    case Done{Build{constructor, count} <> rest} Done{stack}: runLoad(Done{rest}, build(constructor, pop(count, stack, Nil{})), root, active)

def compile(+schema: V.Value) -> Loaded():
  runLoad(Done{Read{schema, Nil{}} <> Nil{}}, Done{Nil{}}, schema, "" <> Nil{})


# A declaration carries its wire schema, executable constraint and conversion
# policy explicitly. Builders keep these projections together as immutable data.
type Declaration is Data:
  Declaration{schemaBuilder: V.Value, constraint: Schema, conversion: Policy}

def schemaBuilder(declaration: Declaration) -> V.Value:
  match declaration:
    case Declaration{raw, _, _}: raw

def constraint(declaration: Declaration) -> Schema:
  match declaration:
    case Declaration{_, checker, _}: checker

def conversion(declaration: Declaration) -> Policy:
  match declaration:
    case Declaration{_, _, policy}: policy

def primitiveBuilder(name: String, kind: JsonType, policy: Primitive) -> Declaration:
  Declaration{V.ObjectValue{R.Record{R.Property{"type", V.Text{name}} <> Nil{}}}, JsonKind{kind}, Scalar{policy}}

def boolean() -> Declaration: primitiveBuilder("boolean", BooleanType{}, ToBoolean{})
def numberBuilder() -> Declaration: primitiveBuilder("number", NumberType{}, ToNumber{})
def integer() -> Declaration: primitiveBuilder("integer", IntegerType{}, ToInteger{})
def string() -> Declaration: primitiveBuilder("string", StringType{}, ToString{})
def null() -> Declaration: primitiveBuilder("null", NullType{}, ToNull{})
def unknown() -> Declaration: Declaration{V.ObjectValue{R.new(V.Value)}, Accept{}, Preserve{}}
def never() -> Declaration: Declaration{V.ObjectValue{R.Record{R.Property{"not", V.ObjectValue{R.new(V.Value)}} <> Nil{}}}, Not{Accept{}}, Preserve{}}

def literalDeclaration(name: String, kind: JsonType, +value: V.Value, policy: LiteralValue) -> Declaration:
  Declaration{V.ObjectValue{R.Record{R.Property{"type", V.Text{name}} <> R.Property{"const", value} <> Nil{}}}, All{JsonKind{kind} <> Constant{value} <> Nil{}}, Literal{policy}}

def literalBuilder(value: LiteralValue) -> Declaration:
  match value:
    case BooleanLiteral{+value}: literalDeclaration("boolean", BooleanType{}, V.Boolean{value}, BooleanLiteral{value})
    case NumberLiteral{+value}: literalDeclaration("number", NumberType{}, V.Number{value}, NumberLiteral{value})
    case StringLiteral{+value}: literalDeclaration("string", StringType{}, V.Text{value}, StringLiteral{value})

def array(item: Declaration) -> Declaration:
  match item:
    case Declaration{raw, checker, policy}:
      Declaration{V.ObjectValue{R.Record{R.Property{"type", V.Text{"array"}} <> R.Property{"items", raw} <> Nil{}}}, All{JsonKind{ArrayType{}} <> Array{Nil{}, checker} <> Nil{}}, ArrayItems{policy}}

def schemasBuilder(items: List<&2, Declaration>) -> List<&2, V.Value>:
  match items:
    case Nil{}: Nil{}
    case head <> tail: schemaBuilder(head) <> schemasBuilder(tail)

def constraints(items: List<&2, Declaration>) -> List<&2, Schema>:
  match items:
    case Nil{}: Nil{}
    case head <> tail: constraint(head) <> constraints(tail)

def conversions(items: List<&2, Declaration>) -> List<&2, Policy>:
  match items:
    case Nil{}: Nil{}
    case head <> tail: conversion(head) <> conversions(tail)

def countBuilder(items: List<&2, Declaration>) -> B.BigNat:
  match items:
    case Nil{}: B.zero()
    case _ <> tail: B.add(countBuilder(tail), B.fromU32(1))

def tuple(+items: List<&2, Declaration>) -> Declaration:
  +size = countBuilder(items)
  Declaration{
    V.ObjectValue{R.Record{R.Property{"type", V.Text{"array"}} <> R.Property{"additionalItems", V.Boolean{False{}}} <> R.Property{"items", V.ArrayValue{schemasBuilder(items)}} <> R.Property{"minItems", V.Number{Number.toNumber(B.toDecimal(size))}} <> Nil{}}},
    All{JsonKind{ArrayType{}} <> AdditionalItems{List.length(&2, Declaration, items), Reject{}} <> Array{constraints(items), Accept{}} <> ItemCount{CountBounds{size, None{}}} <> Nil{}},
    TupleItems{conversions(items)}}

def branchesBuilder(items: List<&2, Declaration>) -> List<&2, Branch<Policy>>:
  match items:
    case Nil{}: Nil{}
    case Declaration{_, checker, policy} <> tail: Branch{checker, policy} <> branchesBuilder(tail)

def union(+items: List<&2, Declaration>) -> Declaration:
  Declaration{V.ObjectValue{R.Record{R.Property{"anyOf", V.ArrayValue{schemasBuilder(items)}} <> Nil{}}}, Any{constraints(items)}, unionConvert(branchesBuilder(items))}

def checkBuilder(declaration: Declaration, value: V.Value) -> Bool:
  check(constraint(declaration), value)

def convert(declaration: Declaration, value: V.Value) -> Converted():
  apply(conversion(declaration), value)

# Optionality belongs to a declared field, rather than hidden metadata on the
# schema value. Required and optional fields share the same value constraint.
type Field is Data:
  Required{declaration: Declaration}
  Optional{declaration: Declaration}

def requiredBuilder(declaration: Declaration) -> Field: Required{declaration}
def optional(declaration: Declaration) -> Field: Optional{declaration}

def fieldDeclaration(field: Field) -> Declaration:
  match field:
    case Required{declaration}: declaration
    case Optional{declaration}: declaration

def requiredKeys(fields: List<&2, R.Property<Field>>) -> List<&2, String>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{key, Required{_}} <> rest: key <> requiredKeys(rest)
    case R.Property{_, Optional{_}} <> rest: requiredKeys(rest)

def fieldSchemas(fields: List<&2, R.Property<Field>>) -> List<&2, R.Property<V.Value>>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{key, field} <> rest: R.Property{key, schemaBuilder(fieldDeclaration(field))} <> fieldSchemas(rest)

def fieldConstraints(fields: List<&2, R.Property<Field>>) -> List<&2, R.Property<Schema>>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{key, field} <> rest: R.Property{key, constraint(fieldDeclaration(field))} <> fieldConstraints(rest)

def fieldConversions(fields: List<&2, R.Property<Field>>) -> List<&2, R.Property<Policy>>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{key, field} <> rest: R.Property{key, conversion(fieldDeclaration(field))} <> fieldConversions(rest)

def textValues(keys: List<&2, String>) -> List<&2, V.Value>:
  match keys:
    case Nil{}: Nil{}
    case key <> rest: V.Text{key} <> textValues(rest)

def requiredSchema(keys: List<&2, String>) -> List<&2, R.Property<V.Value>>:
  match keys:
    case Nil{}: Nil{}
    case keys: R.Property{"required", V.ArrayValue{textValues(keys)}} <> Nil{}

# Literal-key conversion is the proposed native policy. Its known differences
# from TypeBox's regexp-key behavior await approval before public integration.
# This factory uses the default unconstrained, unconverted additional fields.
def object(fields: R.Record<Field>) -> Declaration:
  match fields:
    case R.Record{+fields}:
      +keys = requiredKeys(fields)
      Declaration{
        V.ObjectValue{R.Record{R.Property{"type", V.Text{"object"}} <> List.append(&2, R.Property<V.Value>, requiredSchema(keys), R.Property{"properties", V.ObjectValue{R.Record{fieldSchemas(fields)}}} <> Nil{})}},
        All{JsonKind{ObjectType{}} <> Object{R.Record{fieldConstraints(fields)}, keys, Accept{}} <> Nil{}},
        ObjectFields{R.Record{fieldConversions(fields)}, Preserve{}}}

# A schema-valued additional field has its own constraint and conversion
# policy. Declared fields take precedence; absent fields are never synthesized.
def objectWithAdditional(fields: R.Record<Field>, additional: Declaration) -> Declaration:
  match fields additional:
    case R.Record{+fields} Declaration{raw, checker, policy}:
      +keys = requiredKeys(fields)
      Declaration{
        V.ObjectValue{R.Record{R.Property{"type", V.Text{"object"}} <> List.append(&2, R.Property<V.Value>, requiredSchema(keys), R.Property{"properties", V.ObjectValue{R.Record{fieldSchemas(fields)}}} <> R.Property{"additionalProperties", raw} <> Nil{})}},
        All{JsonKind{ObjectType{}} <> Object{R.Record{fieldConstraints(fields)}, keys, checker} <> Nil{}},
        ObjectFields{R.Record{fieldConversions(fields)}, policy}}

# Constraint/annotation options preserve conversion, except that a boolean
# additionalProperties override removes that field conversion policy. Union
# candidate selection also uses the new whole schema constraint.
type OptionError is Data:
  UnsupportedOption{name: String}
  InvalidOptionSchema{error: LoadError}
  ExpectedObjectSchema{}

def Configured() -> Data: Result<&2, &2, OptionError, Declaration>

def booleanOption(value: V.Value) -> Bool:
  match value:
    case V.Boolean{_}: True{}
    case _: False{}

def supportedOption(kind: KeywordKind, value: V.Value) -> Bool:
  match kind:
    case AnnotationKeyword{}: True{}
    case MultipleOfKeyword{}: True{}
    case MinimumKeyword{}: True{}
    case MaximumKeyword{}: True{}
    case ExclusiveMinimumKeyword{}: True{}
    case ExclusiveMaximumKeyword{}: True{}
    case MinLengthKeyword{}: True{}
    case MaxLengthKeyword{}: True{}
    case MinItemsKeyword{}: True{}
    case MaxItemsKeyword{}: True{}
    case MinPropertiesKeyword{}: True{}
    case MaxPropertiesKeyword{}: True{}
    case UniqueItemsKeyword{}: True{}
    case AdditionalPropertiesKeyword{}: booleanOption(value)
    case _: False{}

def mergeOptions(options: List<&2, R.Property<V.Value>>, state: Result<&2, &2, OptionError, R.Record<V.Value>>) -> Result<&2, &2, OptionError, R.Record<V.Value>>:
  match options state:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{fields}: Done{fields}
    case R.Property{+key, +value} <> rest Done{fields}:
      mergeOptions(rest, Bool.pick(Unit -> Result<&2, &2, OptionError, R.Record<V.Value>>, supportedOption(keywordKind(key), value),
        _ => Done{R.set(V.Value, fields, key, value)}, _ => Fail{UnsupportedOption{key}})(Unit{}))

def additionalConversion(fields: R.Record<Policy>, additional: Policy, raw: Maybe<&2, V.Value>) -> Policy:
  match raw:
    case Some{V.Boolean{_}}: ObjectFields{fields, Preserve{}}
    case _: ObjectFields{fields, additional}

def configuredConversion(policy: Policy, checker: Schema, raw: V.Value) -> Policy:
  match policy:
    case Union{choices, _}: Union{choices, checker}
    case ObjectFields{fields, additional}:
      match raw:
        case V.ObjectValue{properties}:
          additionalConversion(fields, additional, R.get(V.Value, properties, "additionalProperties"))
        case _: ObjectFields{fields, additional}
    case other: other

def configuredSchema(+raw: V.Value, policy: Policy, loaded: Loaded()) -> Configured():
  match loaded:
    case Fail{error}: Fail{InvalidOptionSchema{error}}
    case Done{+checker}: Done{Declaration{raw, checker, configuredConversion(policy, checker, raw)}}

def configuredFields(fields: Result<&2, &2, OptionError, R.Record<V.Value>>, policy: Policy) -> Configured():
  match fields:
    case Fail{error}: Fail{error}
    case Done{+fields}: configuredSchema(V.ObjectValue{fields}, policy, compile(V.ObjectValue{fields}))

def withOptions(declaration: Declaration, options: R.Record<V.Value>) -> Configured():
  match declaration:
    case Declaration{V.ObjectValue{fields}, _, policy}: configuredFields(mergeOptions(R.entries(V.Value, options), Done{fields}), policy)
    case _: Fail{ExpectedObjectSchema{}}
