import Base
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema.bend as S
import ../../../runtime/src/schema.bend as L

# Normalization is a persistent transformation. An unsupported schema needed
# for a nullability decision is an explicit error, not guessed acceptance.
type Error is Data:
  Error{instancePath: List<&2, String>, schemaError: L.LoadError}
  PendingBooleanNull{instancePath: List<&2, String>}

def Outcome() -> Data: Result<&2, &2, Error, V.Value>

type FieldAction is Data:
  Preserve{}
  Omit{}
  Descend{schema: V.Value}

type Items is Data:
  NoItems{}
  EachItem{schema: V.Value}
  TupleItems{schemas: List<&2, V.Value>}

type Task is Data:
  Visit{value: V.Value, schema: V.Value, path: List<&2, String>}
  Fields{remaining: List<&2, R.Property<V.Value>>, properties: R.Record<V.Value>, required: List<&2, V.Value>, path: List<&2, String>, built: List<&2, R.Property<V.Value>>}
  FieldResult{key: String, remaining: List<&2, R.Property<V.Value>>, properties: R.Record<V.Value>, required: List<&2, V.Value>, path: List<&2, String>, built: List<&2, R.Property<V.Value>>}
  Elements{remaining: List<&2, V.Value>, schemas: Items, path: List<&2, String>, index: Nat, built: List<&2, V.Value>}
  ElementResult{remaining: List<&2, V.Value>, schemas: Items, path: List<&2, String>, index: Nat, built: List<&2, V.Value>}

def Scheduled() -> Data: Result<&2, &2, Error, List<&2, Task>>

def property(schema: V.Value, key: String) -> Maybe<&2, V.Value>:
  match schema:
    case V.ObjectValue{fields}: R.get(V.Value, fields, key)
    case _: None{}

def values(value: Maybe<&2, V.Value>) -> List<&2, V.Value>:
  match value:
    case Some{V.ArrayValue{entries}}: entries
    case _: Nil{}

def requiredKey(+key: String, required: List<&2, V.Value>) -> Bool:
  match required:
    case Nil{}: False{}
    case V.Text{name} <> tail: String.eq(key, name) || requiredKey(key, tail)
    case _ <> tail: requiredKey(key, tail)

def reference(value: Maybe<&2, V.Value>) -> Bool:
  match value:
    case Some{V.Text{_}}: True{}
    case _: False{}

def nullable(result: L.Loaded(), path: List<&2, String>) -> Result<&2, &2, Error, FieldAction>:
  match result:
    case Fail{error}: Fail{Error{path, error}}
    case Done{schema}: Done{Bool.pick(FieldAction, S.check(schema, V.Null{}), Preserve{}, Omit{})}

def optionalNull(keep: Bool, schema: V.Value, path: List<&2, String>) -> Result<&2, &2, Error, FieldAction>:
  match keep schema:
    case True{} _: Done{Preserve{}}
    # The user is deciding whether to replace upstream's boolean-key cache
    # failure with native schema behavior. Do not choose either outcome here.
    case False{} V.Boolean{False{}}: Fail{PendingBooleanNull{path}}
    case False{} schema: nullable(L.compile(schema), path)

def fieldAction(value: V.Value, schema: Maybe<&2, V.Value>, required: Bool, path: List<&2, String>) -> Result<&2, &2, Error, FieldAction>:
  match value schema:
    case _ None{}: Done{Preserve{}}
    case V.Null{} Some{+schema}: optionalNull(required || reference(property(schema, "$ref")), schema, path)
    case _ Some{schema}: Done{Descend{schema}}

def itemSchemas(value: Maybe<&2, V.Value>) -> Items:
  match value:
    case Some{V.ArrayValue{schemas}}: TupleItems{schemas}
    case Some{V.ObjectValue{schema}}: EachItem{V.ObjectValue{schema}}
    case _: NoItems{}

def visitObject(value: R.Record<V.Value>, properties: Maybe<&2, V.Value>, required: List<&2, V.Value>, path: List<&2, String>, rest: List<&2, Task>) -> List<&2, Task>:
  match properties:
    case Some{V.ObjectValue{schemas}}: Fields{R.entries(V.Value, value), schemas, required, path, Nil{}} <> rest
    case _: Visit{V.ObjectValue{value}, V.Null{}, path} <> rest

# Unmapped values bypass recursion. Boolean item schemas have no nested fields.
def schedule(value: V.Value, schema: V.Value, path: List<&2, String>, rest: List<&2, Task>) -> List<&2, Task>:
  match value schema:
    case V.ObjectValue{value} V.ObjectValue{+schema}: visitObject(value, R.get(V.Value, schema, "properties"), values(R.get(V.Value, schema, "required")), path, rest)
    case V.ArrayValue{entries} V.ObjectValue{schema}: Elements{entries, itemSchemas(R.get(V.Value, schema, "items")), path, 0n, Nil{}} <> rest
    case value _: Visit{value, V.Null{}, path} <> rest

def scheduleField(action: Result<&2, &2, Error, FieldAction>, +key: String, value: V.Value, tail: List<&2, R.Property<V.Value>>, schemas: R.Record<V.Value>, required: List<&2, V.Value>, +path: List<&2, String>, built: List<&2, R.Property<V.Value>>, rest: List<&2, Task>) -> Scheduled():
  match action:
    case Fail{error}: Fail{error}
    case Done{Preserve{}}: Done{Fields{tail, schemas, required, path, R.Property{key, value} <> built} <> rest}
    case Done{Omit{}}: Done{Fields{tail, schemas, required, path, built} <> rest}
    case Done{Descend{schema}}: Done{Visit{value, schema, L.child(path, key)} <> FieldResult{key, tail, schemas, required, path, built} <> rest}

def scheduleElement(value: V.Value, tail: List<&2, V.Value>, schemas: Items, +path: List<&2, String>, +index: Nat, built: List<&2, V.Value>, rest: List<&2, Task>) -> List<&2, Task>:
  match schemas:
    case NoItems{}: Elements{tail, NoItems{}, path, index + 1n, value <> built} <> rest
    case EachItem{+schema}: Visit{value, schema, L.child(path, Nat.show(index))} <> ElementResult{tail, EachItem{schema}, path, index + 1n, built} <> rest
    case TupleItems{Nil{}}: Elements{tail, NoItems{}, path, index + 1n, value <> built} <> rest
    case TupleItems{schema <> schemas}: Visit{value, schema, L.child(path, Nat.show(index))} <> ElementResult{tail, TupleItems{schemas}, path, index + 1n, built} <> rest

# Every continuation consumes an instance field/item or descends into a finite
# instance subtree. Old values remain valid and no caller-owned state changes.
@unsafe
def run(scheduled: Scheduled(), completed: V.Value) -> Outcome():
  match scheduled:
    case Fail{error}: Fail{error}
    case Done{Nil{}}: Done{completed}
    case Done{Visit{value, V.Null{}, _} <> rest}: run(Done{rest}, value)
    case Done{Visit{value, schema, path} <> rest}: run(Done{schedule(value, schema, path, rest)}, completed)
    case Done{Fields{Nil{}, _, _, _, built} <> rest}: run(Done{rest}, V.ObjectValue{R.Record{List.reverse(&2, R.Property<V.Value>, built)}})
    case Done{Fields{R.Property{+key, +value} <> tail, +schemas, +required, +path, built} <> rest}:
      run(scheduleField(fieldAction(value, R.get(V.Value, schemas, key), requiredKey(key, required), L.child(path, key)), key, value, tail, schemas, required, path, built, rest), completed)
    case Done{FieldResult{key, tail, schemas, required, path, built} <> rest}: run(Done{Fields{tail, schemas, required, path, R.Property{key, completed} <> built} <> rest}, V.Null{})
    case Done{Elements{Nil{}, _, _, _, built} <> rest}: run(Done{rest}, V.ArrayValue{List.reverse(&2, V.Value, built)})
    case Done{Elements{value <> tail, schemas, path, index, built} <> rest}: run(Done{scheduleElement(value, tail, schemas, path, index, built, rest)}, completed)
    case Done{ElementResult{tail, schemas, path, index, built} <> rest}: run(Done{Elements{tail, schemas, path, index, completed <> built} <> rest}, V.Null{})

def normalizeOptionalNulls(value: V.Value, schema: V.Value) -> Outcome():
  run(Done{Visit{value, schema, Nil{}} <> Nil{}}, V.Null{})
