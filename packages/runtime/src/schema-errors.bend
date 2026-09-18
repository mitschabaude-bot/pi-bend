import Base
import ./schema-string.bend as Text
import ./schema.bend as S
import ./schema-value.bend as V
import ./record.bend as R
import ./f64.bend as F
import ./big-nat.bend as B

# Runtime diagnostics are values, independent of a locale or tool-message
# renderer. Paths retain individual field/index segments, including empty keys.
type Reason is Data:
  Rejected{}
  DuplicateItems{}
  ExpectedType{expected: S.JsonType}
  ExpectedTypes{expected: List<&2, S.JsonType>}
  ExpectedConstant{expected: V.Value}
  ExpectedEnumeration{allowed: List<&2, V.Value>}
  MissingFields{keys: List<&2, String>}
  AdditionalFields{keys: List<&2, String>}
  NumericMinimum{limit: F.F64, inclusive: Bool}
  NumericMaximum{limit: F.F64, inclusive: Bool}
  NumericMultipleOf{divisor: F.F64}
  StringLength{actual: B.BigNat, bounds: S.CountBounds}
  ItemCount{actual: B.BigNat, bounds: S.CountBounds}
  PropertyCount{actual: B.BigNat, bounds: S.CountBounds}
  ContainsCount{actual: B.BigNat, bounds: S.CountBounds}
  NoAlternative{}
  ExclusiveAlternatives{matched: B.BigNat}
  NegatedSchema{}
  ConditionalBranch{consequent: Bool}

type Issue is Data:
  Issue{path: List<&2, String>, reason: Reason}

type Task is Data:
  Visit{schema: S.Schema, value: V.Value, path: List<&2, String>}
  EmitIssue{issue: Issue}

def child(path: List<&2, String>, key: String) -> List<&2, String>:
  List.append(&2, String, path, key <> Nil{})

def emitUnless(valid: Bool, path: List<&2, String>, reason: Reason) -> List<&2, Task>:
  Bool.pick(List<&2, Task>, valid, Nil{}, EmitIssue{Issue{path, reason}} <> Nil{})

# The pinned validator reports only the conditional summary for a failed
# then branch, and branch errors followed by the summary for a failed else.
def conditionalFailure(valid: Bool, +consequent: Bool, branch: S.Schema, value: V.Value, +path: List<&2, String>) -> List<&2, Task>:
  match valid:
    case True{}: Nil{}
    case False{}:
      +summary = {EmitIssue{Issue{path, ConditionalBranch{consequent}}} <> Nil{} : List<&2, Task>}
      Bool.pick(List<&2, Task>, consequent, summary, Visit{branch, value, path} <> summary)

def conditionalTasks(+consequent: Bool, thenSchema: S.Schema, elseSchema: S.Schema, +value: V.Value, path: List<&2, String>) -> List<&2, Task>:
  +branch = Bool.pick(S.Schema, consequent, thenSchema, elseSchema)
  conditionalFailure(S.check(branch, value), consequent, branch, value, path)

def visits(schemas: List<&2, S.Schema>, +value: V.Value, +path: List<&2, String>) -> List<&2, Task>:
  match schemas:
    case Nil{}: Nil{}
    case schema <> rest: Visit{schema, value, path} <> visits(rest, value, path)

def matches(schemas: List<&2, S.Schema>, +value: V.Value) -> B.BigNat:
  match schemas:
    case Nil{}: B.zero()
    case schema <> rest: B.add(Bool.pick(B.BigNat, S.check(schema, value), B.one(), B.zero()), matches(rest, value))

def unionTasks(zero: Bool, exclusive: Bool, +matched: B.BigNat, schemas: List<&2, S.Schema>, value: V.Value, +path: List<&2, String>) -> List<&2, Task>:
  match zero:
    case True{}: List.append(&2, Task, visits(schemas, value, path), EmitIssue{Issue{path, Bool.pick(Reason, exclusive, ExclusiveAlternatives{matched}, NoAlternative{})}} <> Nil{})
    case False{}: emitUnless(Bool.not(exclusive) || B.equal(matched, B.one()), path, ExclusiveAlternatives{matched})

def missing(keys: List<&2, String>, +values: R.Record<V.Value>) -> List<&2, String>:
  match keys:
    case Nil{}: Nil{}
    case +key <> rest:
      +tail = missing(rest, values)
      Bool.pick(List<&2, String>, Maybe.is_some(&2, V.Value, R.get(V.Value, values, key)), tail, key <> tail)

def requiredTasks(keys: List<&2, String>, path: List<&2, String>) -> List<&2, Task>:
  match keys:
    case Nil{}: Nil{}
    case first <> rest: EmitIssue{Issue{path, MissingFields{first <> rest}}} <> Nil{}

def presentTask(schema: S.Schema, value: Maybe<&2, V.Value>, path: List<&2, String>) -> List<&2, Task>:
  match value:
    case None{}: Nil{}
    case Some{value}: Visit{schema, value, path} <> Nil{}

def propertyTasks(fields: List<&2, R.Property<S.Schema>>, +values: R.Record<V.Value>, +path: List<&2, String>) -> List<&2, Task>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{+key, schema} <> rest: List.append(&2, Task, presentTask(schema, R.get(V.Value, values, key), child(path, key)), propertyTasks(rest, values, path))

def extraFields(fields: List<&2, R.Property<V.Value>>, +declared: R.Record<S.Schema>) -> List<&2, R.Property<V.Value>>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{+key, value} <> rest:
      +tail = extraFields(rest, declared)
      Bool.pick(List<&2, R.Property<V.Value>>, Maybe.is_some(&2, S.Schema, R.get(S.Schema, declared, key)), tail, R.Property{key, value} <> tail)

def extraTasks(fields: List<&2, R.Property<V.Value>>, +schema: S.Schema, +path: List<&2, String>) -> List<&2, Task>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{key, value} <> rest: Visit{schema, value, child(path, key)} <> extraTasks(rest, schema, path)

def invalidExtras(fields: List<&2, R.Property<V.Value>>, +schema: S.Schema) -> List<&2, String>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{key, value} <> rest:
      +tail = invalidExtras(rest, schema)
      Bool.pick(List<&2, String>, S.check(schema, value), tail, key <> tail)

def extraSummary(keys: List<&2, String>, path: List<&2, String>) -> List<&2, Task>:
  match keys:
    case Nil{}: Nil{}
    case first <> rest: EmitIssue{Issue{path, AdditionalFields{first <> rest}}} <> Nil{}

def objectTasks(+declared: R.Record<S.Schema>, required: List<&2, String>, +additional: S.Schema, +values: R.Record<V.Value>, +path: List<&2, String>) -> List<&2, Task>:
  +extras = extraFields(R.entries(V.Value, values), declared)
  List.append(&2, Task, requiredTasks(missing(required, values), path), List.append(&2, Task, extraTasks(extras, additional, path), List.append(&2, Task, extraSummary(invalidExtras(extras, additional), path), propertyTasks(R.entries(S.Schema, declared), values, path))))

def arrayTasks(values: List<&2, V.Value>, prefix: List<&2, S.Schema>, +items: S.Schema, +path: List<&2, String>, +index: Nat) -> List<&2, Task>:
  match values prefix:
    case Nil{} _: Nil{}
    case head <> tail Nil{}: Visit{items, head, child(path, Nat.show(index))} <> arrayTasks(tail, Nil{}, items, path, index + 1n)
    case head <> tail schema <> rest: Visit{schema, head, child(path, Nat.show(index))} <> arrayTasks(tail, rest, items, path, index + 1n)

# Upstream reports all tuple-prefix failures but stops at the first invalid
# additional item. The native node names that validation boundary explicitly.
def additionalTasks(values: List<&2, V.Value>, +items: S.Schema, +path: List<&2, String>, +index: Nat) -> List<&2, Task>:
  match values:
    case Nil{}: Nil{}
    case +head <> tail:
      Bool.pick(Unit -> List<&2, Task>, S.check(items, head),
        _ => additionalTasks(tail, items, path, index + 1n),
        _ => Visit{items, head, child(path, Nat.show(index))} <> Nil{})(Unit{})

def contained(values: List<&2, V.Value>, +schema: S.Schema) -> B.BigNat:
  match values:
    case Nil{}: B.zero()
    case value <> rest: B.add(Bool.pick(B.BigNat, S.check(schema, value), B.one(), B.zero()), contained(rest, schema))

def expand(schema: S.Schema, value: V.Value, +path: List<&2, String>) -> List<&2, Task>:
  match schema value:
    case S.Accept{} _: Nil{}
    case S.Reject{} _: EmitIssue{Issue{path, Rejected{}}} <> Nil{}
    case S.JsonKind{+expected} value: emitUnless(S.matchesType(expected, value), path, ExpectedType{expected})
    case S.TypeUnion{+expected} value: emitUnless(S.matchesTypes(expected, value), path, ExpectedTypes{expected})
    case S.Constant{+expected} value: emitUnless(V.equal(expected, value), path, ExpectedConstant{expected})
    case S.Enumeration{+allowed} value: emitUnless(S.member(allowed, value), path, ExpectedEnumeration{allowed})
    case S.All{schemas} value: visits(schemas, value, path)
    case S.Any{+schemas} +value:
      +matched = matches(schemas, value)
      unionTasks(B.isZero(matched), False{}, matched, schemas, value, path)
    case S.One{+schemas} +value:
      +matched = matches(schemas, value)
      unionTasks(B.isZero(matched), True{}, matched, schemas, value, path)
    case S.Conditional{condition, consequent, alternative} +value: conditionalTasks(S.check(condition, value), consequent, alternative, value, path)
    case S.Not{inner} value: emitUnless(Bool.not(S.check(inner, value)), path, NegatedSchema{})
    case S.Minimum{+limit, +inclusive} V.Number{number}: emitUnless(S.lowerBound(F.compare(number, limit), inclusive), path, NumericMinimum{limit, inclusive})
    case S.Maximum{+limit, +inclusive} V.Number{number}: emitUnless(S.upperBound(F.compare(number, limit), inclusive), path, NumericMaximum{limit, inclusive})
    case S.MultipleOf{+divisor} V.Number{number}: emitUnless(S.multipleOf(number, divisor), path, NumericMultipleOf{divisor})
    case S.MultipleOf{_} _: Nil{}
    case S.UniqueItems{} V.ArrayValue{values}: emitUnless(S.unique(values), path, DuplicateItems{})
    case S.UniqueItems{} _: Nil{}
    case S.StringLength{+bounds} V.Text{text}:
      +actual = Text.length(text)
      emitUnless(S.inBounds(actual, bounds), path, StringLength{actual, bounds})
    case S.ItemCount{+bounds} V.ArrayValue{values}:
      +actual = S.cardinality(V.Value, values)
      emitUnless(S.inBounds(actual, bounds), path, ItemCount{actual, bounds})
    case S.PropertyCount{+bounds} V.ObjectValue{values}:
      +actual = S.cardinality(R.Property<V.Value>, R.entries(V.Value, values))
      emitUnless(S.inBounds(actual, bounds), path, PropertyCount{actual, bounds})
    case S.Contains{inner, +bounds} V.ArrayValue{values}:
      +actual = contained(values, inner)
      emitUnless(S.inBounds(actual, bounds), path, ContainsCount{actual, bounds})
    case S.Object{declared, required, additional} V.ObjectValue{values}: objectTasks(declared, required, additional, values, path)
    case S.Array{prefix, items} V.ArrayValue{values}: arrayTasks(values, prefix, items, path, 0n)
    case S.AdditionalItems{+offset, items} V.ArrayValue{values}: additionalTasks(S.dropItems(values, offset), items, path, offset)
    case S.AdditionalItems{_, _} _: Nil{}
    case S.Minimum{_, _} _: Nil{}
    case S.Maximum{_, _} _: Nil{}
    case S.StringLength{_} _: Nil{}
    case S.ItemCount{_} _: Nil{}
    case S.PropertyCount{_} _: Nil{}
    case S.Contains{_, _} _: Nil{}
    case S.Object{_, _, _} _: Nil{}
    case S.Array{_, _} _: Nil{}

def afterEmission(remaining: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match remaining:
    case None{}: None{}
    case Some{Zero{}}: Some{0n}
    case Some{Succ{rest}}: Some{rest}

# Every expansion consumes a finite schema child or instance element. Results
# accumulate in reverse so emitting another issue never copies prior issues.
@unsafe
def collect(tasks: List<&2, Task>, issues: List<&2, Issue>, remaining: Maybe<&2, Nat>) -> List<&2, Issue>:
  match tasks remaining:
    case _ Some{Zero{}}: List.reverse(&2, Issue, issues)
    case Nil{} _: List.reverse(&2, Issue, issues)
    case EmitIssue{issue} <> rest remaining: collect(rest, issue <> issues, afterEmission(remaining))
    case Visit{schema, value, path} <> rest remaining: collect(List.append(&2, Task, expand(schema, value, path), rest), issues, remaining)

def errors(schema: S.Schema, value: V.Value) -> List<&2, Issue>:
  collect(Visit{schema, value, Nil{}} <> Nil{}, Nil{}, None{})

def errorsLimited(schema: S.Schema, value: V.Value, limit: Nat) -> List<&2, Issue>:
  collect(Visit{schema, value, Nil{}} <> Nil{}, Nil{}, Some{limit})
