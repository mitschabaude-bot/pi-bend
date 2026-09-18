import Base
import ./validation-normalize.bend as Normalize
import ../../../runtime/src/schema.bend as Schema
import ../../../runtime/src/schema-load.bend as Loader
import ../../../runtime/src/number-string.bend as NumberString
import ../../../runtime/src/f64-decimal.bend as Decimal
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/f64.bend as F

# Validation consumes immutable schema and argument data directly.
def stringTypes(values: List<&2, V.Value>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case V.Text{text} <> tail: text <> stringTypes(tail)
    case _ <> tail: stringTypes(tail)

def typesFromProperty(value: Maybe<&2, V.Value>) -> List<&2, String>:
  match value:
    case Some{V.Text{text}}: text <> Nil{}
    case Some{V.ArrayValue{values}}: stringTypes(values)
    case _: Nil{}

def getSchemaTypes(schema: R.Record<V.Value>) -> List<&2, String>:
  typesFromProperty(R.get(V.Value, schema, "type"))

def matchesJsonType(value: V.Value, +kind: String) -> Bool:
  match value:
    case V.Number{number}: String.eq(kind, "number") || (String.eq(kind, "integer") && F.isInteger(number))
    case V.Boolean{_}: String.eq(kind, "boolean")
    case V.Text{_}: String.eq(kind, "string")
    case V.Null{}: String.eq(kind, "null")
    case V.ArrayValue{_}: String.eq(kind, "array")
    case V.ObjectValue{_}: String.eq(kind, "object")
    case _: False{}

# The formatter exposes an explicit impossible-state failure. Do not silently
# retain a number or fabricate a string if that dependency cannot format it.
type CoercionError is Data:
  NumberFormattingFailure{}
  UnionSchemaFailure{error: Loader.Error}
  PendingBooleanUnion{}

def Coercion() -> Data: Result<&2, &2, CoercionError, V.Value>

type PrimitiveType is Data:
  Numeric{integerOnly: Bool}
  BooleanType{}
  StringType{}
  NullType{}
  OtherType{}

def primitiveType(+kind: String) -> PrimitiveType:
  Bool.pick(PrimitiveType, String.eq(kind, "number"), Numeric{False{}}, Bool.pick(PrimitiveType, String.eq(kind, "integer"), Numeric{True{}}, Bool.pick(PrimitiveType, String.eq(kind, "boolean"), BooleanType{}, Bool.pick(PrimitiveType, String.eq(kind, "string"), StringType{}, Bool.pick(PrimitiveType, String.eq(kind, "null"), NullType{}, OtherType{})))))

def finiteNumber(value: F.Decoded) -> Bool:
  match value:
    case F.Finite{_, _, _}: True{}
    case _: False{}

def numericText(integerOnly: Bool, +text: String) -> V.Value:
  +parsed = NumberString.toNumber(text)
  acceptable = Bool.pick(Bool, integerOnly, F.isInteger(parsed), finiteNumber(F.decode(parsed)))
  Bool.pick(V.Value, Bool.not(String.is_empty(NumberString.trim(text))) && acceptable, V.Number{parsed}, V.Text{text})

def coerceNumeric(integerOnly: Bool, value: V.Value) -> V.Value:
  match value:
    case V.Null{}: V.Number{F.fromU32(0)}
    case V.Boolean{flag}: V.Number{F.fromU32(Bool.pick(U32, flag, 1, 0))}
    case V.Text{text}: numericText(integerOnly, text)
    case other: other

def equalNumber(order: Maybe<&2, Cmp>) -> Bool:
  match order:
    case Some{EQ{}}: True{}
    case _: False{}

def coerceBoolean(value: V.Value) -> V.Value:
  match value:
    case V.Null{}: V.Boolean{False{}}
    case V.Text{+text}: Bool.pick(V.Value, String.eq(text, "true"), V.Boolean{True{}}, Bool.pick(V.Value, String.eq(text, "false"), V.Boolean{False{}}, V.Text{text}))
    case V.Number{+number}: Bool.pick(V.Value, equalNumber(F.compare(number, F.fromU32(1))), V.Boolean{True{}}, Bool.pick(V.Value, equalNumber(F.compare(number, F.fromU32(0))), V.Boolean{False{}}, V.Number{number}))
    case other: other

def formattedNumber(value: Maybe<&2, String>) -> Coercion():
  match value:
    case None{}: Fail{NumberFormattingFailure{}}
    case Some{text}: Done{V.Text{text}}

def coerceString(value: V.Value) -> Coercion():
  match value:
    case V.Null{}: Done{V.Text{""}}
    case V.Boolean{flag}: Done{V.Text{Bool.pick(String, flag, "true", "false")}}
    case V.Number{number}: formattedNumber(Decimal.toDecimal(number))
    case other: Done{other}

def coerceNull(value: V.Value) -> V.Value:
  match value:
    case V.Text{+text}: Bool.pick(V.Value, String.is_empty(text), V.Null{}, V.Text{text})
    case V.Number{+number}: Bool.pick(V.Value, equalNumber(F.compare(number, F.fromU32(0))), V.Null{}, V.Number{number})
    case V.Boolean{flag}: Bool.pick(V.Value, flag, V.Boolean{True{}}, V.Null{})
    case other: other

def coercePrimitive(kind: PrimitiveType, value: V.Value) -> Coercion():
  match kind:
    case Numeric{integerOnly}: Done{coerceNumeric(integerOnly, value)}
    case BooleanType{}: Done{coerceBoolean(value)}
    case StringType{}: coerceString(value)
    case NullType{}: Done{coerceNull(value)}
    case OtherType{}: Done{value}

def coercePrimitiveByType(value: V.Value, kind: String) -> Coercion():
  coercePrimitive(primitiveType(kind), value)

# Primitive coercion changes scalar values only; aggregates pass through.
def primitiveCandidateChanged(original: V.Value, candidate: V.Value) -> Bool:
  match original candidate:
    case V.Number{a} V.Number{b}: Bool.not(equalNumber(F.compare(a, b)))
    case V.Text{a} V.Text{b}: Bool.not(String.eq(a, b))
    case V.Boolean{+a} V.Boolean{+b}: (a && Bool.not(b)) || (Bool.not(a) && b)
    case V.Null{} V.Null{}: False{}
    case V.ArrayValue{_} V.ArrayValue{_}: False{}
    case V.ObjectValue{_} V.ObjectValue{_}: False{}
    case _ _: True{}

def matchesAnyType(types: List<&2, String>, +value: V.Value) -> Bool:
  match types:
    case Nil{}: False{}
    case head <> tail: matchesJsonType(value, head) || matchesAnyType(tail, value)

def matchesTypeUnion(types: List<&2, String>, value: V.Value) -> Bool:
  match types:
    case a <> b <> rest: matchesAnyType(a <> b <> rest, value)
    case _: False{}

type PrimitiveSelection is Data:
  TryNextType{}
  SelectedPrimitive{value: V.Value}
  PrimitiveSelectionFailed{error: CoercionError}

def primitiveSelection(original: V.Value, candidate: Coercion()) -> PrimitiveSelection:
  match candidate:
    case Fail{error}: PrimitiveSelectionFailed{error}
    case Done{+value}: Bool.pick(PrimitiveSelection, primitiveCandidateChanged(original, value), SelectedPrimitive{value}, TryNextType{})

def selectPrimitiveTypes(types: List<&2, String>, +original: V.Value, selected: PrimitiveSelection) -> Coercion():
  match types selected:
    case _ SelectedPrimitive{value}: Done{value}
    case _ PrimitiveSelectionFailed{error}: Fail{error}
    case Nil{} TryNextType{}: Done{original}
    case head <> tail TryNextType{}: selectPrimitiveTypes(tail, original, primitiveSelection(original, coercePrimitiveByType(original, head)))

def coerceUnmatchedTypes(matched: Bool, types: List<&2, String>, value: V.Value) -> Coercion():
  match matched:
    case True{}: Done{value}
    case False{}: selectPrimitiveTypes(types, value, TryNextType{})

# The scalar/type-array phase of coerceWithJsonSchema, after allOf/anyOf/oneOf
# and before object/array traversal. This is not the complete schema algorithm.
def coerceSchemaTypes(+value: V.Value, +types: List<&2, String>) -> Coercion():
  coerceUnmatchedTypes(matchesTypeUnion(types, value), types, value)

# Native normalization returns a new value; unsupported nullability decisions
# remain explicit until the full schema vocabulary is implemented.
def normalizeOptionalNulls(value: V.Value, schema: V.Value) -> Normalize.Outcome():
  Normalize.normalizeOptionalNulls(value, schema)

# Recursive coercion keeps each union candidate separate from the original.
# Continuations hold immutable values; no clone/mutate/rollback layer exists.
type CoercionTask is Data:
  Coerce{schema: V.Value}
  Union{schemas: List<&2, V.Value>}
  OriginalMembers{remaining: List<&2, V.Value>, all: List<&2, V.Value>, original: V.Value}
  OriginalChecked{matches: Result<&2, &2, CoercionError, Bool>, remaining: List<&2, V.Value>, all: List<&2, V.Value>, original: V.Value}
  Candidates{remaining: List<&2, V.Value>, original: V.Value}
  CandidateResult{schema: V.Value, remaining: List<&2, V.Value>, original: V.Value}
  CandidateChecked{matches: Result<&2, &2, CoercionError, Bool>, remaining: List<&2, V.Value>, original: V.Value}
  Scalars{types: List<&2, String>}
  Structure{schema: R.Record<V.Value>, types: List<&2, String>}
  ObjectFields{remaining: List<&2, R.Property<V.Value>>, properties: R.Record<V.Value>, additional: Maybe<&2, V.Value>, built: List<&2, R.Property<V.Value>>}
  ObjectFieldResult{key: String, remaining: List<&2, R.Property<V.Value>>, properties: R.Record<V.Value>, additional: Maybe<&2, V.Value>, built: List<&2, R.Property<V.Value>>}
  ArrayItems{remaining: List<&2, V.Value>, schemas: Normalize.Items, built: List<&2, V.Value>}
  ArrayItemResult{remaining: List<&2, V.Value>, schemas: Normalize.Items, built: List<&2, V.Value>}

def coercionTasks(schemas: List<&2, V.Value>) -> List<&2, CoercionTask>:
  match schemas:
    case Nil{}: Nil{}
    case schema <> tail: Coerce{schema} <> coercionTasks(tail)

def schemaList(value: Maybe<&2, V.Value>) -> List<&2, V.Value>:
  match value:
    case Some{V.ArrayValue{schemas}}: schemas
    case _: Nil{}

def coercionPlan(schema: V.Value, rest: List<&2, CoercionTask>) -> List<&2, CoercionTask>:
  match schema:
    case V.ObjectValue{+fields}:
      +types = getSchemaTypes(fields)
      List.append(&2, CoercionTask, coercionTasks(schemaList(R.get(V.Value, fields, "allOf"))), Union{schemaList(R.get(V.Value, fields, "anyOf"))} <> Union{schemaList(R.get(V.Value, fields, "oneOf"))} <> Scalars{types} <> Structure{fields, types} <> rest)
    case _: rest

def unionChecked(compiled: Loader.Loaded(), value: V.Value) -> Result<&2, &2, CoercionError, Bool>:
  match compiled:
    case Fail{error}: Fail{UnionSchemaFailure{error}}
    case Done{schema}: Done{Schema.check(schema, value)}

def unionMatches(schema: V.Value, value: V.Value) -> Result<&2, &2, CoercionError, Bool>:
  match schema:
    # Upstream's boolean-key cache failure affects true union arms. The native
    # behavior is part of the pending boolean-schema decision, not emulated.
    case V.Boolean{True{}}: Fail{PendingBooleanUnion{}}
    case schema: unionChecked(Loader.compile(schema), value)

def namedType(+name: String, types: List<&2, String>) -> Bool:
  match types:
    case Nil{}: False{}
    case head <> tail: String.eq(name, head) || namedType(name, tail)

def propertySchemas(value: Maybe<&2, V.Value>) -> R.Record<V.Value>:
  match value:
    case Some{V.ObjectValue{fields}}: fields
    case _: R.new(V.Value)

def additionalSchema(value: Maybe<&2, V.Value>) -> Maybe<&2, V.Value>:
  match value:
    case Some{V.ObjectValue{fields}}: Some{V.ObjectValue{fields}}
    case _: None{}

def structures(value: V.Value, +schema: R.Record<V.Value>, +types: List<&2, String>, +rest: List<&2, CoercionTask>) -> List<&2, CoercionTask>:
  match value:
    case V.ObjectValue{fields}: Bool.pick(List<&2, CoercionTask>, namedType("object", types), ObjectFields{R.entries(V.Value, fields), propertySchemas(R.get(V.Value, schema, "properties")), additionalSchema(R.get(V.Value, schema, "additionalProperties")), Nil{}} <> rest, rest)
    case V.ArrayValue{items}: Bool.pick(List<&2, CoercionTask>, namedType("array", types), ArrayItems{items, Normalize.itemSchemas(R.get(V.Value, schema, "items")), Nil{}} <> rest, rest)
    case _: rest

def fieldSchema(declared: Maybe<&2, V.Value>, additional: Maybe<&2, V.Value>) -> Maybe<&2, V.Value>:
  match declared:
    case Some{schema}: Some{schema}
    case None{}: additional

def fieldTasks(selected: Maybe<&2, V.Value>, +key: String, tail: List<&2, R.Property<V.Value>>, properties: R.Record<V.Value>, additional: Maybe<&2, V.Value>, built: List<&2, R.Property<V.Value>>, rest: List<&2, CoercionTask>) -> List<&2, CoercionTask>:
  match selected:
    case None{}: ObjectFieldResult{key, tail, properties, additional, built} <> rest
    case Some{schema}: Coerce{schema} <> ObjectFieldResult{key, tail, properties, additional, built} <> rest

def itemTasks(schemas: Normalize.Items, tail: List<&2, V.Value>, built: List<&2, V.Value>, rest: List<&2, CoercionTask>) -> List<&2, CoercionTask>:
  match schemas:
    case Normalize.NoItems{}: ArrayItemResult{tail, Normalize.NoItems{}, built} <> rest
    case Normalize.EachItem{+schema}: Coerce{schema} <> ArrayItemResult{tail, Normalize.EachItem{schema}, built} <> rest
    case Normalize.TupleItems{Nil{}}: ArrayItemResult{tail, Normalize.NoItems{}, built} <> rest
    case Normalize.TupleItems{schema <> schemas}: Coerce{schema} <> ArrayItemResult{tail, Normalize.TupleItems{schemas}, built} <> rest

# Every task consumes a schema/instance child or one finite union alternative.
@unsafe
def coerceTasks(tasks: List<&2, CoercionTask>, result: Coercion()) -> Coercion():
  match tasks result:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{value}: Done{value}
    case Coerce{schema} <> rest Done{value}: coerceTasks(coercionPlan(schema, rest), Done{value})
    case Union{+schemas} <> rest Done{+value}: coerceTasks(OriginalMembers{schemas, schemas, value} <> rest, Done{value})
    case OriginalMembers{Nil{}, all, original} <> rest _:
      coerceTasks(Candidates{all, original} <> rest, Done{V.Null{}})
    case OriginalMembers{schema <> tail, all, +original} <> rest _:
      coerceTasks(OriginalChecked{unionMatches(schema, original), tail, all, original} <> rest, Done{V.Null{}})
    case OriginalChecked{Fail{error}, _, _, _} <> _ _: Fail{error}
    case OriginalChecked{Done{True{}}, _, _, original} <> rest _: coerceTasks(rest, Done{original})
    case OriginalChecked{Done{False{}}, tail, all, original} <> rest _: coerceTasks(OriginalMembers{tail, all, original} <> rest, Done{V.Null{}})
    case Candidates{Nil{}, original} <> rest _: coerceTasks(rest, Done{original})
    case Candidates{+schema <> tail, +original} <> rest _: coerceTasks(Coerce{schema} <> CandidateResult{schema, tail, original} <> rest, Done{original})
    case CandidateResult{schema, tail, original} <> rest Done{+value}:
      coerceTasks(CandidateChecked{unionMatches(schema, value), tail, original} <> rest, Done{value})
    case CandidateChecked{Fail{error}, _, _} <> _ _: Fail{error}
    case CandidateChecked{Done{True{}}, _, _} <> rest Done{value}: coerceTasks(rest, Done{value})
    case CandidateChecked{Done{False{}}, tail, original} <> rest _: coerceTasks(Candidates{tail, original} <> rest, Done{V.Null{}})
    case Scalars{types} <> rest Done{value}: coerceTasks(rest, coerceSchemaTypes(value, types))
    case Structure{schema, types} <> rest Done{+value}: coerceTasks(structures(value, schema, types, rest), Done{value})
    case ObjectFields{Nil{}, _, _, built} <> rest _: coerceTasks(rest, Done{V.ObjectValue{R.Record{List.reverse(&2, R.Property<V.Value>, built)}}})
    case ObjectFields{R.Property{+key, value} <> tail, +properties, +additional, built} <> rest _:
      coerceTasks(fieldTasks(fieldSchema(R.get(V.Value, properties, key), additional), key, tail, properties, additional, built, rest), Done{value})
    case ObjectFieldResult{key, tail, properties, additional, built} <> rest Done{value}: coerceTasks(ObjectFields{tail, properties, additional, R.Property{key, value} <> built} <> rest, Done{V.Null{}})
    case ArrayItems{Nil{}, _, built} <> rest _: coerceTasks(rest, Done{V.ArrayValue{List.reverse(&2, V.Value, built)}})
    case ArrayItems{value <> tail, schemas, built} <> rest _: coerceTasks(itemTasks(schemas, tail, built, rest), Done{value})
    case ArrayItemResult{tail, schemas, built} <> rest Done{value}: coerceTasks(ArrayItems{tail, schemas, value <> built} <> rest, Done{V.Null{}})

def coerceWithJsonSchema(value: V.Value, schema: V.Value) -> Coercion():
  coerceTasks(Coerce{schema} <> Nil{}, Done{value})
