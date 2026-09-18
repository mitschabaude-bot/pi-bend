import Base
import ../src/object.bend as O
import ../src/value.bend as V
import ../src/ref.bend as R
import ../src/record.bend as Record
import ../src/f64.bend as F
import ./object.bend as Inspect
import ./value.bend as Test

type Deletion is Data:
  Deletion{key: O.PropertyKey<U32>, success: Bool, keys: List<&2, O.PropertyKey<U32>>, descriptor: Maybe<&2, Inspect.D()>}

def checkSuccess(result: Result<&2, &2, O.ObjectError, Bool>, expected: Bool) -> IO(Unit):
  match result:
    case Done{actual}: Test.assertion(V.sameBoolean(actual, expected), "delete success differs")
    case Fail{_}: IO.die(Unit, 1, "ordinary deletion failed")

def steps(items: List<&2, Deletion>, +value: V.Value<U32>, +expectedLength: Maybe<&2, Inspect.D()>) -> IO(Unit):
  match items:
    case Nil{}: IO.pure(Unit, Unit{})
    case Deletion{+key, success, keys, descriptor} <> rest:
      do IO<Unit>:
        result : Result<&2, &2, O.ObjectError, Bool> <- O.deleteProperty(~U32, ~Inspect.same, value, key)
        checkSuccess(result, success)
        actualKeys : Result<&2, &2, O.ObjectError, List<&2, O.PropertyKey<U32>>> <- O.ownKeys(U32, value)
        Inspect.checkKeys(actualKeys, keys)
        Inspect.queries(Inspect.Query{key, descriptor} <> Inspect.Query{O.StringKey{"length"}, expectedLength} <> Nil{}, value)
        steps(rest, value, expectedLength)

def checkMetadata(state: V.ObjectStorage(U32), prototype: R.Ref<V.ObjectStorage(U32)>, expectedExtensible: Bool) -> IO(Unit):
  match state:
    case V.ObjectState{_, _, Some{V.ObjectValue{actual}}, extensible}: Test.assertion(R.same(V.ObjectStorage(U32), actual, prototype) && V.sameBoolean(extensible, expectedExtensible), "deletion changed prototype or extensibility")
    case _: IO.die(Unit, 1, "prototype lost after deletion")

def arrayObject(state: V.ArrayStorage(U32)) -> V.ObjectStorage(U32):
  match state:
    case V.ArrayState{object, _, _}: object

def run(+isArray: Bool, +length: U32, +writable: Bool, +extensible: Bool, properties: Record.Record<Inspect.D()>, symbols: List<&2, V.SymbolProperty<U32, V.Value<U32>>>, deletions: List<&2, Deletion>) -> IO(Unit):
  do IO<Unit>:
    +prototype : R.Ref<V.ObjectStorage(U32)> <- R.new(V.ObjectStorage(U32), V.ObjectState{Record.set(Inspect.D(), Record.new(Inspect.D()), "inherited", V.DataProperty{V.Number{F.fromU32(42)}, True{}, True{}, True{}}), Nil{}, None{}, True{}})
    +state : V.ObjectStorage(U32) = V.ObjectState{properties, symbols, Some{V.ObjectValue{prototype}}, extensible}
    +object : R.Ref<V.ObjectStorage(U32)> <- R.new(V.ObjectStorage(U32), state)
    +array : R.Ref<V.ArrayStorage(U32)> <- R.new(V.ArrayStorage(U32), V.ArrayState{state, length, writable})
    +value : V.Value<U32> = Bool.pick(V.Value<U32>, isArray, V.ArrayValue{array}, V.ObjectValue{object})
    steps(deletions, value, Bool.pick(Maybe<&2, Inspect.D()>, isArray, Some{V.DataProperty{V.Number{F.fromU32(length)}, writable, False{}, False{}}}, None{}))
    objectState : V.ObjectStorage(U32) <- R.read(V.ObjectStorage(U32), object)
    arrayState : V.ArrayStorage(U32) <- R.read(V.ArrayStorage(U32), array)
    checkMetadata(objectState, prototype, extensible)
    checkMetadata(arrayObject(arrayState), prototype, extensible)
    # Deletion must leave the inherited property itself intact.
    Inspect.queries(Inspect.Query{O.StringKey{"inherited"}, Some{V.DataProperty{V.Number{F.fromU32(42)}, True{}, True{}, True{}}}} <> Nil{}, V.ObjectValue{prototype})
    oldObject : V.ObjectStorage(U32) <- R.dispose(V.ObjectStorage(U32), object)
    oldArray : V.ArrayStorage(U32) <- R.dispose(V.ArrayStorage(U32), array)
    oldPrototype : V.ObjectStorage(U32) <- R.dispose(V.ObjectStorage(U32), prototype)
    return Unit{}
