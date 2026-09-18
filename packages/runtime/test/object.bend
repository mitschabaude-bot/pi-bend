import Base
import ../src/object.bend as O
import ../src/value.bend as V
import ../src/ref.bend as R
import ../src/record.bend as Record
import ../src/utf16.bend as U
import ../src/f64.bend as F
import ./value.bend as Test

def D() -> Data: V.Descriptor<U32, V.Value<U32>>
def same(a: U32, b: U32) -> Bool: U32.is_eq(a, b)

def keyEqual(a: O.PropertyKey<U32>, b: O.PropertyKey<U32>) -> Bool:
  match a b:
    case O.StringKey{x} O.StringKey{y}: String.eq(U.normalize(x), U.normalize(y))
    case O.SymbolKey{x} O.SymbolKey{y}: U32.is_eq(x, y)
    case _ _: False{}

def keysEqual(a: List<&2, O.PropertyKey<U32>>, b: List<&2, O.PropertyKey<U32>>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case x <> xs y <> ys: keyEqual(x, y) && keysEqual(xs, ys)
    case _ _: False{}

def checkKeys(result: Result<&2, &2, O.ObjectError, List<&2, O.PropertyKey<U32>>>, expected: List<&2, O.PropertyKey<U32>>) -> IO(Unit):
  match result:
    case Done{actual}: Test.assertion(keysEqual(actual, expected), "own key order differs from Reflect.ownKeys")
    case Fail{_}: IO.die(Unit, 1, "own keys unexpectedly failed")

def sameOptional(a: Maybe<&2, U32>, b: Maybe<&2, U32>) -> Bool:
  match a b:
    case None{} None{}: True{}
    case Some{x} Some{y}: U32.is_eq(x, y)
    case _ _: False{}

def descriptorEqual(a: Maybe<&2, D()>, b: Maybe<&2, D()>) -> Bool:
  match a b:
    case None{} None{}: True{}
    case Some{V.DataProperty{x, wx, ex, cx}} Some{V.DataProperty{y, wy, ey, cy}}: V.sameValue(U32, x, y, a => b => U32.is_eq(a, b)) && V.sameBoolean(wx, wy) && V.sameBoolean(ex, ey) && V.sameBoolean(cx, cy)
    case Some{V.AccessorProperty{gx, sx, ex, cx}} Some{V.AccessorProperty{gy, sy, ey, cy}}: sameOptional(gx, gy) && sameOptional(sx, sy) && V.sameBoolean(ex, ey) && V.sameBoolean(cx, cy)
    case _ _: False{}

def checkDescriptor(result: Result<&2, &2, O.ObjectError, Maybe<&2, D()>>, expected: Maybe<&2, D()>) -> IO(Unit):
  match result:
    case Done{actual}: Test.assertion(descriptorEqual(actual, expected), "own descriptor differs from Reflect.getOwnPropertyDescriptor")
    case Fail{_}: IO.die(Unit, 1, "own descriptor unexpectedly failed")

type Query is Data:
  Query{key: O.PropertyKey<U32>, expected: Maybe<&2, D()>}

def queries(items: List<&2, Query>, +value: V.Value<U32>) -> IO(Unit):
  match items:
    case Nil{}: IO.pure(Unit, Unit{})
    case Query{key, expected} <> rest:
      do IO<Unit>:
        result : Result<&2, &2, O.ObjectError, Maybe<&2, D()>> <- O.getOwnPropertyDescriptor(~U32, ~same, value, key)
        checkDescriptor(result, expected)
        queries(rest, value)

def run(isArray: Bool, length: U32, writable: Bool, properties: Record.Record<D()>, symbols: List<&2, V.SymbolProperty<U32, V.Value<U32>>>, expectedKeys: List<&2, O.PropertyKey<U32>>, checks: List<&2, Query>) -> IO(Unit):
  do IO<Unit>:
    +prototype : R.Ref<V.ObjectStorage(U32)> <- R.new(V.ObjectStorage(U32), V.ObjectState{Record.set(D(), Record.new(D()), "inherited", V.DataProperty{V.Number{F.fromU32(42)}, True{}, True{}, True{}}), Nil{}, None{}, True{}})
    +state : V.ObjectStorage(U32) = V.ObjectState{properties, symbols, Some{V.ObjectValue{prototype}}, True{}}
    +object : R.Ref<V.ObjectStorage(U32)> <- R.new(V.ObjectStorage(U32), state)
    +array : R.Ref<V.ArrayStorage(U32)> <- R.new(V.ArrayStorage(U32), V.ArrayState{state, length, writable})
    +value : V.Value<U32> = Bool.pick(V.Value<U32>, isArray, V.ArrayValue{array}, V.ObjectValue{object})
    keys : Result<&2, &2, O.ObjectError, List<&2, O.PropertyKey<U32>>> <- O.ownKeys(U32, value)
    checkKeys(keys, expectedKeys)
    queries(checks, value)
    oldObject : V.ObjectStorage(U32) <- R.dispose(V.ObjectStorage(U32), object)
    oldArray : V.ArrayStorage(U32) <- R.dispose(V.ArrayStorage(U32), array)
    oldPrototype : V.ObjectStorage(U32) <- R.dispose(V.ObjectStorage(U32), prototype)
    return Unit{}

def live() -> IO(Unit):
  do IO<Unit>:
    +object : R.Ref<V.ObjectStorage(U32)> <- V.newObject(U32, None{})
    before : Result<&2, &2, O.ObjectError, List<&2, O.PropertyKey<U32>>> <- O.ownKeys(U32, V.ObjectValue{object})
    R.write(V.ObjectStorage(U32), object, V.ObjectState{Record.set(D(), Record.new(D()), "next", V.DataProperty{V.Undefined{}, True{}, False{}, True{}}), Nil{}, None{}, True{}})
    after : Result<&2, &2, O.ObjectError, List<&2, O.PropertyKey<U32>>> <- O.ownKeys(U32, V.ObjectValue{object})
    checkKeys(before, Nil{})
    checkKeys(after, O.StringKey{"next"} <> Nil{})
    queries(Query{O.StringKey{"next"}, Some{V.DataProperty{V.Undefined{}, True{}, False{}, True{}}}} <> Nil{}, V.ObjectValue{object})
    old : V.ObjectStorage(U32) <- R.dispose(V.ObjectStorage(U32), object)
    return Unit{}

def checkFailure(-A: Data, result: Result<&2, &2, O.ObjectError, A>, callable: Bool) -> IO(Unit):
  match result:
    case Fail{O.NotObject{}}: Test.assertion(Bool.not(callable), "callable object support gap was hidden")
    case Fail{O.UnsupportedCallableObject{}}: Test.assertion(callable, "primitive misclassified as a callable")
    case Done{_}: IO.die(Unit, 1, "unsupported target returned a descriptor or key list")

def errorCase(+value: V.Value<U32>, +callable: Bool) -> IO(Unit):
  do IO<Unit>:
    keys : Result<&2, &2, O.ObjectError, List<&2, O.PropertyKey<U32>>> <- O.ownKeys(U32, value)
    checkFailure(List<&2, O.PropertyKey<U32>>, keys, callable)
    descriptor : Result<&2, &2, O.ObjectError, Maybe<&2, D()>> <- O.getOwnPropertyDescriptor(~U32, ~same, value, O.StringKey{"x"})
    checkFailure(Maybe<&2, D()>, descriptor, callable)
    deleted : Result<&2, &2, O.ObjectError, Bool> <- O.deleteProperty(~U32, ~same, value, O.StringKey{"x"})
    checkFailure(Bool, deleted, callable)

def errors() -> IO(Unit):
  do IO<Unit>:
    errorCase(V.Null{}, False{})
    errorCase(V.Number{F.fromU32(0)}, False{})
    errorCase(V.Text{"x"}, False{})
    errorCase(V.Callable{1}, True{})
