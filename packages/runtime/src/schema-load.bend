import Base
import ./json-pointer.bend as Pointer
import ./schema.bend as S
import ./schema-value.bend as V
import ./record.bend as R
import ./f64.bend as F
import ./big-nat.bend as B
import ./u64.bend as W

# Paths are ordered JSON field/index segments, independent of diagnostic text.
type Issue is Data:
  UnsupportedKeyword{keyword: String}
  InvalidSchema{expected: String}
  InvalidConstruction{}
  UnsupportedReference{reference: String}
  UnsupportedReferenceCycle{reference: String}

type Error is Data:
  Error{path: List<&2, String>, issue: Issue}

def Loaded() -> Data: Result<&2, &2, Error, S.Schema>

type Constructor is Data:
  Conjunction{}
  Disjunction{}
  TypeAlternatives{}
  Exclusive{}
  Negation{}
  Conditional{}
  Properties{keys: List<&2, String>}
  Additional{properties: R.Record<S.Schema>}
  TupleItems{}
  AllItems{}
  ExtraItems{prefix: List<&2, S.Schema>}
  Containing{bounds: S.CountBounds}

type Resolved is Data:
  Resolved{value: V.Value, path: List<&2, String>, key: String}
  Unresolved{}

def Resolution() -> Data: Result<&2, &2, Error, Resolved>

type Task is Data:
  Read{value: V.Value, path: List<&2, String>}
  ResolveReference{reference: String, path: List<&2, String>}
  ReferenceResult{resolution: Resolution()}
  EndReference{}
  Keyword{key: String, value: V.Value, whole: R.Record<V.Value>, path: List<&2, String>}
  TypeName{value: V.Value, path: List<&2, String>}
  Push{schema: S.Schema}
  Build{constructor: Constructor, count: Nat}

def Scheduled() -> Data: Result<&2, &2, Error, List<&2, Task>>

def child(path: List<&2, String>, key: String) -> List<&2, String>:
  List.append(&2, String, path, key <> Nil{})

def invalid(-A: Data, path: List<&2, String>, expected: String) -> Result<&2, &2, Error, A>:
  Fail{Error{path, InvalidSchema{expected}}}

def parentReversed(path: List<&2, String>) -> List<&2, String>:
  match path:
    case Nil{}: Nil{}
    case _ <> rest: List.reverse(&2, String, rest)

def sibling(path: List<&2, String>, name: String) -> List<&2, String>:
  child(parentReversed(List.reverse(&2, String, path)), name)

def conditional(value: V.Value, +whole: R.Record<V.Value>, +path: List<&2, String>) -> Scheduled():
  consequent = Maybe.default(&2, V.Value, R.get(V.Value, whole, "then"), V.Boolean{True{}})
  alternative = Maybe.default(&2, V.Value, R.get(V.Value, whole, "else"), V.Boolean{True{}})
  Done{Read{value, path} <> Read{consequent, sibling(path, "then")} <> Read{alternative, sibling(path, "else")} <> Build{Conditional{}, 3n} <> Nil{}}

def kind(+name: String) -> Maybe<&2, S.JsonType>:
  Bool.pick(Maybe<&2, S.JsonType>, String.eq(name, "null"), Some{S.NullType{}}, Bool.pick(Maybe<&2, S.JsonType>, String.eq(name, "boolean"), Some{S.BooleanType{}}, Bool.pick(Maybe<&2, S.JsonType>, String.eq(name, "number"), Some{S.NumberType{}}, Bool.pick(Maybe<&2, S.JsonType>, String.eq(name, "integer"), Some{S.IntegerType{}}, Bool.pick(Maybe<&2, S.JsonType>, String.eq(name, "string"), Some{S.StringType{}}, Bool.pick(Maybe<&2, S.JsonType>, String.eq(name, "array"), Some{S.ArrayType{}}, Bool.pick(Maybe<&2, S.JsonType>, String.eq(name, "object"), Some{S.ObjectType{}}, None{})))))))

def typeNode(value: Maybe<&2, S.JsonType>, path: List<&2, String>) -> Loaded():
  match value:
    case Some{value}: Done{S.JsonKind{value}}
    case None{}: invalid(S.Schema, path, "a JSON type name")

def atomicType(value: V.Value, path: List<&2, String>) -> Loaded():
  match value:
    case V.Text{name}: typeNode(kind(name), path)
    case _: invalid(S.Schema, path, "a JSON type name")

def typeMembers(values: List<&2, V.Value>, +path: List<&2, String>) -> List<&2, Task>:
  match values:
    case Nil{}: Nil{}
    case value <> tail: TypeName{value, path} <> typeMembers(tail, path)

def pushed(value: Loaded()) -> Scheduled():
  match value:
    case Fail{error}: Fail{error}
    case Done{schema}: Done{Push{schema} <> Nil{}}

def typed(value: V.Value, +path: List<&2, String>) -> Scheduled():
  match value:
    case V.Text{name}: pushed(typeNode(kind(name), path))
    case V.ArrayValue{+values}: Done{List.append(&2, Task, typeMembers(values, path), Build{TypeAlternatives{}, List.length(&2, V.Value, values)} <> Nil{})}
    case _: invalid(List<&2, Task>, path, "a type name or array of type names")

def childReads(values: List<&2, V.Value>, +path: List<&2, String>, +index: Nat) -> List<&2, Task>:
  match values:
    case Nil{}: Nil{}
    case value <> tail: Read{value, child(path, Nat.show(index))} <> childReads(tail, path, index + 1n)

def group(constructor: Constructor, value: V.Value, path: List<&2, String>) -> Scheduled():
  match value:
    case V.ArrayValue{+values}: Done{List.append(&2, Task, childReads(values, path, 0n), Build{constructor, List.length(&2, V.Value, values)} <> Nil{})}
    case _: invalid(List<&2, Task>, path, "an array of schemas")

def fieldKeys(fields: List<&2, R.Property<V.Value>>) -> List<&2, String>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{key, _} <> tail: key <> fieldKeys(tail)

def fieldReads(fields: List<&2, R.Property<V.Value>>, +path: List<&2, String>) -> List<&2, Task>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{key, value} <> tail: Read{value, child(path, key)} <> fieldReads(tail, path)

def properties(value: V.Value, path: List<&2, String>) -> Scheduled():
  match value:
    case V.ObjectValue{R.Record{+fields}}: Done{List.append(&2, Task, fieldReads(fields, path), Build{Properties{fieldKeys(fields)}, List.length(&2, R.Property<V.Value>, fields)} <> Nil{})}
    case _: invalid(List<&2, Task>, path, "a dictionary of schemas")

def prependString(key: String, result: Result<&2, &2, Error, List<&2, String>>) -> Result<&2, &2, Error, List<&2, String>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{rest}: Done{key <> rest}

def strings(values: List<&2, V.Value>, +path: List<&2, String>) -> Result<&2, &2, Error, List<&2, String>>:
  match values:
    case Nil{}: Done{Nil{}}
    case V.Text{key} <> tail: prependString(key, strings(tail, path))
    case _: invalid(List<&2, String>, path, "an array of strings")

def requiredNode(result: Result<&2, &2, Error, List<&2, String>>) -> Scheduled():
  match result:
    case Fail{error}: Fail{error}
    case Done{keys}: Done{Push{S.Object{R.new(S.Schema), keys, S.Accept{}}} <> Nil{}}

def required(value: V.Value, path: List<&2, String>) -> Scheduled():
  match value:
    case V.ArrayValue{values}: requiredNode(strings(values, path))
    case _: invalid(List<&2, Task>, path, "an array of required field names")

def allowedFields(fields: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<S.Schema>>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{key, _} <> tail: R.Property{key, S.Accept{}} <> allowedFields(tail)

def declaredFields(value: Maybe<&2, V.Value>) -> R.Record<S.Schema>:
  match value:
    case Some{V.ObjectValue{R.Record{fields}}}: R.Record{allowedFields(fields)}
    case _: R.new(S.Schema)

def acceptedItems(values: List<&2, V.Value>) -> List<&2, S.Schema>:
  match values:
    case Nil{}: Nil{}
    case _ <> tail: S.Accept{} <> acceptedItems(tail)

def tuplePrefix(value: Maybe<&2, V.Value>) -> Maybe<&2, List<&2, S.Schema>>:
  match value:
    case Some{V.ArrayValue{values}}: Some{acceptedItems(values)}
    case _: None{}

def additionalItems(prefix: Maybe<&2, List<&2, S.Schema>>, value: V.Value, path: List<&2, String>) -> Scheduled():
  match prefix:
    case None{}: Done{Push{S.Accept{}} <> Nil{}}
    case Some{schemas}: Done{Read{value, path} <> Build{ExtraItems{schemas}, 1n} <> Nil{}}

def items(value: V.Value, path: List<&2, String>) -> Scheduled():
  match value:
    case V.ArrayValue{+values}: group(TupleItems{}, V.ArrayValue{values}, path)
    case other: Done{Read{other, path} <> Build{AllItems{}, 1n} <> Nil{}}

def numeric(lower: Bool, +inclusive: Bool, value: V.Value, path: List<&2, String>) -> Scheduled():
  match value:
    case V.Number{+limit}: Bool.pick(Scheduled(), S.finite(F.decode(limit)), Done{Push{Bool.pick(S.Schema, lower, S.Minimum{limit, inclusive}, S.Maximum{limit, inclusive})} <> Nil{}}, invalid(List<&2, Task>, path, "a finite numeric bound"))
    case _: invalid(List<&2, Task>, path, "a finite numeric bound")

def multiple(value: V.Value, path: List<&2, String>) -> Scheduled():
  match value:
    case V.Number{+divisor}: Bool.pick(Scheduled(), S.finite(F.decode(divisor)), Done{Push{S.MultipleOf{divisor}} <> Nil{}}, invalid(List<&2, Task>, path, "a finite numeric divisor"))
    case _: invalid(List<&2, Task>, path, "a finite numeric divisor")

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

def acceptedCount(valid: Bool, value: F.F64, path: List<&2, String>) -> Result<&2, &2, Error, B.BigNat>:
  match valid:
    case True{}: Done{decodedCount(F.decode(value))}
    case False{}: invalid(B.BigNat, path, "a nonnegative finite integer")

def readCount(value: V.Value, path: List<&2, String>) -> Result<&2, &2, Error, B.BigNat>:
  match value:
    case V.Number{+number}: acceptedCount(S.finite(F.decode(number)) && F.isInteger(number) && S.lowerBound(F.compare(number, F.fromU32(0)), True{}), number, path)
    case _: invalid(B.BigNat, path, "a nonnegative finite integer")

def boundedCount(lower: Bool, +value: B.BigNat) -> S.CountBounds:
  Bool.pick(S.CountBounds, lower, S.CountBounds{value, None{}}, S.CountBounds{B.zero(), Some{value}})

def countNode(array: Bool, lower: Bool, result: Result<&2, &2, Error, B.BigNat>) -> Scheduled():
  match result:
    case Fail{error}: Fail{error}
    case Done{value}:
      +bounds = boundedCount(lower, value)
      Done{Push{Bool.pick(S.Schema, array, S.ItemCount{bounds}, S.PropertyCount{bounds})} <> Nil{}}

def lengthNode(lower: Bool, result: Result<&2, &2, Error, B.BigNat>) -> Scheduled():
  match result:
    case Fail{error}: Fail{error}
    case Done{value}: Done{Push{S.StringLength{boundedCount(lower, value)}} <> Nil{}}

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
  Done{Read{value, path} <> Build{Containing{S.CountBounds{minimum, None{}}}, 1n} <> Nil{}}

def containsBound(lower: Bool, value: Result<&2, &2, Error, B.BigNat>, inner: Maybe<&2, V.Value>, path: List<&2, String>) -> Scheduled():
  match value inner:
    case Fail{error} _: Fail{error}
    case Done{_} None{}: Done{Push{S.Accept{}} <> Nil{}}
    case Done{limit} Some{schema}: Done{Read{schema, child(parentPath(path), "contains")} <> Build{Containing{boundedCount(lower, limit)}, 1n} <> Nil{}}

def reference(value: V.Value, path: List<&2, String>) -> Scheduled():
  match value:
    case V.Text{text}: Done{ResolveReference{text, path} <> Nil{}}
    case _: invalid(List<&2, Task>, path, "a schema reference string")

def definitions(value: V.Value, path: List<&2, String>) -> Scheduled():
  match value:
    case V.ObjectValue{_}: Done{Push{S.Accept{}} <> Nil{}}
    case _: invalid(List<&2, Task>, path, "a schema definition dictionary")

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
    case ConstKeyword{}: Done{Push{S.Constant{value}} <> Nil{}}
    case EnumKeyword{}:
      match value:
        case V.ArrayValue{values}: Done{Push{S.Enumeration{values}} <> Nil{}}
        case _: invalid(List<&2, Task>, path, "an array of enum values")
    case AllOfKeyword{}: group(Conjunction{}, value, path)
    case AnyOfKeyword{}: group(Disjunction{}, value, path)
    case OneOfKeyword{}: group(Exclusive{}, value, path)
    case IfKeyword{}: conditional(value, whole, path)
    case ThenKeyword{}: Done{Push{S.Accept{}} <> Nil{}}
    case ElseKeyword{}: Done{Push{S.Accept{}} <> Nil{}}
    case NotKeyword{}: Done{Read{value, path} <> Build{Negation{}, 1n} <> Nil{}}
    case PropertiesKeyword{}: properties(value, path)
    case RequiredKeyword{}: required(value, path)
    case AdditionalPropertiesKeyword{}: Done{Read{value, path} <> Build{Additional{declaredFields(R.get(V.Value, whole, "properties"))}, 1n} <> Nil{}}
    case ItemsKeyword{}: items(value, path)
    case AdditionalItemsKeyword{}: additionalItems(tuplePrefix(R.get(V.Value, whole, "items")), value, path)
    case MultipleOfKeyword{}: multiple(value, path)
    case MinimumKeyword{}: numeric(True{}, True{}, value, path)
    case MaximumKeyword{}: numeric(False{}, True{}, value, path)
    case ExclusiveMinimumKeyword{}: numeric(True{}, False{}, value, path)
    case ExclusiveMaximumKeyword{}: numeric(False{}, False{}, value, path)
    case UniqueItemsKeyword{}:
      match value:
        case V.Boolean{enabled}: Done{Push{Bool.pick(S.Schema, enabled, S.UniqueItems{}, S.Accept{})} <> Nil{}}
        case _: invalid(List<&2, Task>, path, "a boolean uniqueness flag")
    case MinLengthKeyword{}: lengthNode(True{}, readCount(value, path))
    case MaxLengthKeyword{}: lengthNode(False{}, readCount(value, path))
    case MinItemsKeyword{}: countNode(True{}, True{}, readCount(value, path))
    case MaxItemsKeyword{}: countNode(True{}, False{}, readCount(value, path))
    case MinPropertiesKeyword{}: countNode(False{}, True{}, readCount(value, path))
    case MaxPropertiesKeyword{}: countNode(False{}, False{}, readCount(value, path))
    case ContainsKeyword{}: contains(value, whole, path)
    case MinContainsKeyword{}: containsBound(True{}, readCount(value, path), R.get(V.Value, whole, "contains"), path)
    case MaxContainsKeyword{}: containsBound(False{}, readCount(value, path), R.get(V.Value, whole, "contains"), path)
    case AnnotationKeyword{}: Done{Push{S.Accept{}} <> Nil{}}
    case UnknownKeyword{}: Fail{Error{path, UnsupportedKeyword{key}}}

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

def keywordTasks(fields: List<&2, R.Property<V.Value>>, +whole: R.Record<V.Value>, +path: List<&2, String>) -> List<&2, Task>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{+key, value} <> tail: Keyword{key, value, whole, child(path, key)} <> keywordTasks(tail, whole, path)

def read(value: V.Value, path: List<&2, String>) -> Scheduled():
  match value:
    case V.Boolean{flag}: Done{Push{Bool.pick(S.Schema, flag, S.Accept{}, S.Reject{})} <> Nil{}}
    case V.ObjectValue{+whole}:
      +fields = R.entries(V.Value, whole)
      Done{List.append(&2, Task, keywordTasks(orderedKeywords(fields), whole, path), Build{Conjunction{}, List.length(&2, R.Property<V.Value>, fields)} <> Nil{})}
    case _: invalid(List<&2, Task>, path, "an object or boolean schema")

def pairedProperties(keys: List<&2, String>, schemas: List<&2, S.Schema>) -> List<&2, R.Property<S.Schema>>:
  match keys schemas:
    case key <> keys schema <> schemas: R.Property{key, schema} <> pairedProperties(keys, schemas)
    case _ _: Nil{}

def prependType(typeName: S.JsonType, result: Result<&2, &2, Error, List<&2, S.JsonType>>) -> Result<&2, &2, Error, List<&2, S.JsonType>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{rest}: Done{typeName <> rest}

def compiledTypes(schemas: List<&2, S.Schema>) -> Result<&2, &2, Error, List<&2, S.JsonType>>:
  match schemas:
    case Nil{}: Done{Nil{}}
    case S.JsonKind{typeName} <> rest: prependType(typeName, compiledTypes(rest))
    case _: Fail{Error{Nil{}, InvalidConstruction{}}}

def typeAlternatives(result: Result<&2, &2, Error, List<&2, S.JsonType>>) -> Loaded():
  match result:
    case Fail{error}: Fail{error}
    case Done{kinds}: Done{S.TypeUnion{kinds}}

def construct(constructor: Constructor, schemas: List<&2, S.Schema>) -> Loaded():
  match constructor schemas:
    case Conjunction{} schemas: Done{S.All{schemas}}
    case Disjunction{} schemas: Done{S.Any{schemas}}
    case TypeAlternatives{} schemas: typeAlternatives(compiledTypes(schemas))
    case Exclusive{} schemas: Done{S.One{schemas}}
    case Negation{} schema <> Nil{}: Done{S.Not{schema}}
    case Conditional{} condition <> consequent <> alternative <> Nil{}: Done{S.Conditional{condition, consequent, alternative}}
    case Properties{keys} schemas: Done{S.Object{R.Record{pairedProperties(keys, schemas)}, Nil{}, S.Accept{}}}
    case Additional{fields} schema <> Nil{}: Done{S.Object{fields, Nil{}, schema}}
    case TupleItems{} schemas: Done{S.Array{schemas, S.Accept{}}}
    case AllItems{} schema <> Nil{}: Done{S.Array{Nil{}, schema}}
    case ExtraItems{prefix} schema <> Nil{}: Done{S.AdditionalItems{List.length(&2, S.Schema, prefix), schema}}
    case Containing{bounds} schema <> Nil{}: Done{S.Contains{schema, bounds}}
    case _ _: Fail{Error{Nil{}, InvalidConstruction{}}}

type Stack is Data:
  Stack{values: List<&2, S.Schema>, rest: List<&2, S.Schema>}

def pop(count: Nat, stack: List<&2, S.Schema>, values: List<&2, S.Schema>) -> Result<&2, &2, Error, Stack>:
  match count stack:
    case Zero{} rest: Done{Stack{values, rest}}
    case Succ{count} head <> tail: pop(count, tail, head <> values)
    case _ _: Fail{Error{Nil{}, InvalidConstruction{}}}

def pushConstructed(value: Loaded(), rest: List<&2, S.Schema>) -> Result<&2, &2, Error, List<&2, S.Schema>>:
  match value:
    case Fail{error}: Fail{error}
    case Done{schema}: Done{schema <> rest}

def build(constructor: Constructor, popped: Result<&2, &2, Error, Stack>) -> Result<&2, &2, Error, List<&2, S.Schema>>:
  match popped:
    case Fail{error}: Fail{error}
    case Done{Stack{values, rest}}: pushConstructed(construct(constructor, values), rest)

def appendTasks(scheduled: Scheduled(), rest: List<&2, Task>) -> Scheduled():
  match scheduled:
    case Fail{error}: Fail{error}
    case Done{tasks}: Done{List.append(&2, Task, tasks, rest)}

def referenceActive(keys: List<&2, String>, +key: String) -> Bool:
  match keys:
    case Nil{}: False{}
    case head <> rest: String.eq(head, key) || referenceActive(rest, key)

def located(target: Maybe<&2, V.Value>, path: List<&2, String>, key: String) -> Resolution():
  match target:
    case None{}: Done{Unresolved{}}
    case Some{value}: Done{Resolved{value, path, key}}

def resolvedPointer(cyclic: Bool, root: V.Value, pointer: Pointer.Pointer, key: String, ref: String, sourcePath: List<&2, String>) -> Resolution():
  match cyclic pointer:
    case True{} _: Fail{Error{sourcePath, UnsupportedReferenceCycle{ref}}}
    case False{} Pointer.Pointer{+path}: located(Pointer.get(root, Pointer.Pointer{path}), path, key)

def parsedReference(root: V.Value, pointer: Maybe<&2, Pointer.Pointer>, ref: String, sourcePath: List<&2, String>, active: List<&2, String>) -> Resolution():
  match pointer:
    case None{}: Fail{Error{sourcePath, UnsupportedReference{ref}}}
    case Some{+pointer}:
      +key = Pointer.render(pointer)
      resolvedPointer(referenceActive(active, key), root, pointer, key, ref, sourcePath)

def resolve(root: V.Value, +ref: String, sourcePath: List<&2, String>, active: List<&2, String>) -> Resolution():
  parsedReference(root, Pointer.parseFragment(ref), ref, sourcePath, active)

# Structural reads descend through a finite schema. References may revisit
# other branches, so active canonical pointer paths reject cycles explicitly
# until the graph evaluator supports recursive schemas.
@unsafe
def run(scheduled: Scheduled(), compiled: Result<&2, &2, Error, List<&2, S.Schema>>, +root: V.Value, +active: List<&2, String>) -> Loaded():
  match scheduled compiled:
    case Fail{error} _: Fail{error}
    case _ Fail{error}: Fail{error}
    case Done{Nil{}} Done{schema <> Nil{}}: Done{schema}
    case Done{Nil{}} _: Fail{Error{Nil{}, InvalidConstruction{}}}
    case Done{ResolveReference{ref, path} <> rest} Done{stack}: run(Done{ReferenceResult{resolve(root, ref, path, active)} <> rest}, Done{stack}, root, active)
    case Done{ReferenceResult{Fail{error}} <> _} _: Fail{error}
    case Done{ReferenceResult{Done{Unresolved{}}} <> rest} Done{stack}: run(Done{Push{S.Reject{}} <> rest}, Done{stack}, root, active)
    case Done{ReferenceResult{Done{Resolved{value, path, key}}} <> rest} Done{stack}: run(Done{Read{value, path} <> EndReference{} <> rest}, Done{stack}, root, key <> active)
    case Done{EndReference{} <> rest} Done{stack}:
      match active:
        case _ <> tail: run(Done{rest}, Done{stack}, root, tail)
        case Nil{}: Fail{Error{Nil{}, InvalidConstruction{}}}
    case Done{TypeName{value, path} <> rest} Done{stack}: run(appendTasks(pushed(atomicType(value, path)), rest), Done{stack}, root, active)
    case Done{Push{schema} <> rest} Done{stack}: run(Done{rest}, Done{schema <> stack}, root, active)
    case Done{Read{value, path} <> rest} Done{stack}: run(appendTasks(read(value, path), rest), Done{stack}, root, active)
    case Done{Keyword{key, value, whole, path} <> rest} Done{stack}: run(appendTasks(keyword(key, value, whole, path), rest), Done{stack}, root, active)
    case Done{Build{constructor, count} <> rest} Done{stack}: run(Done{rest}, build(constructor, pop(count, stack, Nil{})), root, active)

def compile(+schema: V.Value) -> Loaded():
  run(Done{Read{schema, Nil{}} <> Nil{}}, Done{Nil{}}, schema, "" <> Nil{})
