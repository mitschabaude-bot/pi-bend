import Base
import ../src/value.bend as V
import ../src/ref.bend as R
import ../src/record.bend as Record
import ../src/f64.bend as F
import ../src/big-nat.bend as B

def assertion(ok: Bool, message: String) -> IO(Unit):
  Bool.pick(IO(Unit), ok, IO.pure(Unit, Unit{}), IO.die(Unit, 1, message))

def equal(a: V.Value<U32>, b: V.Value<U32>) -> Bool:
  V.strictEqual(U32, a, b, x => y => U32.is_eq(x, y))

def check(a: V.Value<U32>, b: V.Value<U32>, expected: Bool, label: String) -> IO(Unit):
  assertion(V.sameBoolean(equal(a, b), expected), label)

def checkProperty(property: Maybe<&2, V.Descriptor<U32, V.Value<U32>>>, expected: V.Value<U32>) -> IO(Unit):
  match property:
    case Some{V.DataProperty{value, True{}, True{}, True{}}}: assertion(equal(value, expected), "shared graph edge lost identity")
    case _: IO.die(Unit, 1, "shared data property missing")

def checkObject(value: V.ObjectStorage(U32), self: V.Value<U32>, array: V.Value<U32>) -> IO(Unit):
  match value:
    case V.ObjectState{+properties, Nil{}, None{}, True{}}:
      do IO<Unit>:
        checkProperty(Record.get(V.Descriptor<U32, V.Value<U32>>, properties, "self"), self)
        checkProperty(Record.get(V.Descriptor<U32, V.Value<U32>>, properties, "array"), array)
    case _: IO.die(Unit, 1, "object flags changed")

def hole(value: Maybe<&2, V.Descriptor<U32, V.Value<U32>>>) -> Bool:
  match value:
    case None{}: True{}
    case _: False{}

def checkArray(value: V.ArrayStorage(U32), +object: V.Value<U32>) -> IO(Unit):
  match value:
    case V.ArrayState{V.ObjectState{+properties, Nil{}, Some{prototype}, True{}}, 3, False{}}:
      do IO<Unit>:
        assertion(equal(prototype, object), "array prototype edge lost identity")
        assertion(hole(Record.get(V.Descriptor<U32, V.Value<U32>>, properties, "0")), "array hole became present undefined")
        checkProperty(Record.get(V.Descriptor<U32, V.Value<U32>>, properties, "1"), V.Undefined{})
        checkProperty(Record.get(V.Descriptor<U32, V.Value<U32>>, properties, "2"), object)
    case _: IO.die(Unit, 1, "array length or flags changed")

def graph() -> IO(Unit):
  do IO<Unit>:
    +object : R.Ref<V.ObjectStorage(U32)> <- V.newObject(U32, None{})
    +other : R.Ref<V.ObjectStorage(U32)> <- V.newObject(U32, None{})
    +array : R.Ref<V.ArrayStorage(U32)> <- V.newArray(U32, Some{V.ObjectValue{object}})
    +otherArray : R.Ref<V.ArrayStorage(U32)> <- V.newArray(U32, None{})
    assertion(String.eq(V.typeOf(U32, V.ObjectValue{object}), "object") && String.eq(V.typeOf(U32, V.ArrayValue{array}), "object"), "aggregate typeof differs")
    check(V.ObjectValue{object}, V.ObjectValue{object}, True{}, "object alias unequal")
    check(V.ObjectValue{object}, V.ObjectValue{other}, False{}, "structurally identical objects became equal")
    check(V.ArrayValue{array}, V.ArrayValue{array}, True{}, "array alias unequal")
    check(V.ArrayValue{array}, V.ArrayValue{otherArray}, False{}, "distinct arrays became equal")
    check(V.ObjectValue{object}, V.ArrayValue{array}, False{}, "array and object became equal")
    +descriptor : V.Descriptor<U32, V.Value<U32>> = V.DataProperty{V.ObjectValue{object}, True{}, True{}, True{}}
    objectProperties : Record.Record<V.Descriptor<U32, V.Value<U32>>> = Record.set(V.Descriptor<U32, V.Value<U32>>, Record.set(V.Descriptor<U32, V.Value<U32>>, Record.new(V.Descriptor<U32, V.Value<U32>>), "self", descriptor), "array", V.DataProperty{V.ArrayValue{array}, True{}, True{}, True{}})
    R.write(V.ObjectStorage(U32), object, V.ObjectState{objectProperties, Nil{}, None{}, True{}})
    arrayProperties : Record.Record<V.Descriptor<U32, V.Value<U32>>> = Record.set(V.Descriptor<U32, V.Value<U32>>, Record.set(V.Descriptor<U32, V.Value<U32>>, Record.new(V.Descriptor<U32, V.Value<U32>>), "1", V.DataProperty{V.Undefined{}, True{}, True{}, True{}}), "2", descriptor)
    R.write(V.ArrayStorage(U32), array, V.ArrayState{V.ObjectState{arrayProperties, Nil{}, Some{V.ObjectValue{object}}, True{}}, 3, False{}})
    liveObject : V.ObjectStorage(U32) <- R.read(V.ObjectStorage(U32), object)
    checkObject(liveObject, V.ObjectValue{object}, V.ArrayValue{array})
    liveArray : V.ArrayStorage(U32) <- R.read(V.ArrayStorage(U32), array)
    checkArray(liveArray, V.ObjectValue{object})
    # Equality must remain independent of graph contents and cycles.
    check(V.ObjectValue{object}, V.ObjectValue{object}, True{}, "cyclic object alias unequal")
    # Retire the owned cycle edges before releasing either storage cell.
    R.write(V.ObjectStorage(U32), object, V.emptyObjectState(U32, V.Value<U32>, None{}))
    R.write(V.ArrayStorage(U32), array, V.ArrayState{V.emptyObjectState(U32, V.Value<U32>, None{}), 0, True{}})
    oldObject : V.ObjectStorage(U32) <- R.dispose(V.ObjectStorage(U32), object)
    oldArray : V.ArrayStorage(U32) <- R.dispose(V.ArrayStorage(U32), array)
    oldOther : V.ObjectStorage(U32) <- R.dispose(V.ObjectStorage(U32), other)
    oldOtherArray : V.ArrayStorage(U32) <- R.dispose(V.ArrayStorage(U32), otherArray)
    IO.print("PASS shared object/array identity, cycles, prototypes and sparse storage")

def checkType(value: V.Value<U32>, expected: String) -> IO(Unit):
  assertion(String.eq(V.typeOf(U32, value), expected), "runtime typeof differs")

def checkSame(a: V.Value<U32>, b: V.Value<U32>, expected: Bool, label: String) -> IO(Unit):
  actual = V.sameValue(U32, a, b, x => y => U32.is_eq(x, y))
  assertion(V.sameBoolean(actual, expected), label)
