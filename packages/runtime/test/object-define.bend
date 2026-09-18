import Base
import ../src/object.bend as O
import ../src/descriptor.bend as D
import ../src/value.bend as V
import ../src/ref.bend as R
import ../src/record.bend as Record
import ./object.bend as I
import ./value.bend as Test

def status(result: Result<&2, &2, O.DefinitionError, Bool>) -> String:
  match result:
    case Done{True{}}: "true"
    case Done{False{}}: "false"
    case Fail{O.InvalidPropertyDescriptor{}}: "invalid"
    case Fail{_}: "unsupported"

def initial(current: Maybe<&2, I.D()>, key: O.PropertyKey<U32>, state: V.ObjectStorage(U32)) -> V.ObjectStorage(U32):
  match current:
    case None{}: state
    case Some{descriptor}: O.putOwn(~U32, ~I.same, state, key, descriptor)

def run(+key: O.PropertyKey<U32>, extensible: Bool, current: Maybe<&2, I.D()>, definition: D.Definition<U32>, expectedStatus: String, expected: Maybe<&2, I.D()>, keys: List<&2, O.PropertyKey<U32>>) -> IO(Unit):
  do IO<Unit>:
    properties : Record.Record<I.D()> = Record.set(I.D(), Record.set(I.D(), Record.new(I.D()), "before", V.DataProperty{V.Undefined{}, True{}, True{}, True{}}), "2", V.DataProperty{V.Undefined{}, True{}, True{}, True{}})
    state : V.ObjectStorage(U32) = V.ObjectState{properties, V.SymbolProperty{9, V.DataProperty{V.Undefined{}, True{}, True{}, True{}}} <> Nil{}, None{}, extensible}
    withCurrent : V.ObjectStorage(U32) = initial(current, key, state)
    withString : V.ObjectStorage(U32) = O.putOwn(~U32, ~I.same, withCurrent, O.StringKey{"after"}, V.DataProperty{V.Undefined{}, True{}, True{}, True{}})
    withSymbol : V.ObjectStorage(U32) = O.putOwn(~U32, ~I.same, withString, O.SymbolKey{10}, V.DataProperty{V.Undefined{}, True{}, True{}, True{}})
    +object : R.Ref<V.ObjectStorage(U32)> <- R.new(V.ObjectStorage(U32), withSymbol)
    result : Result<&2, &2, O.DefinitionError, Bool> <- O.defineOwnProperty(~U32, ~I.same, V.ObjectValue{object}, key, definition)
    Test.assertion(String.eq(status(result), expectedStatus), "property definition result differs")
    descriptor : Result<&2, &2, O.ObjectError, Maybe<&2, I.D()>> <- O.getOwnPropertyDescriptor(~U32, ~I.same, V.ObjectValue{object}, key)
    I.checkDescriptor(descriptor, expected)
    ownKeys : Result<&2, &2, O.ObjectError, List<&2, O.PropertyKey<U32>>> <- O.ownKeys(U32, V.ObjectValue{object})
    I.checkKeys(ownKeys, keys)
    old : V.ObjectStorage(U32) <- R.dispose(V.ObjectStorage(U32), object)
    return Unit{}

def aliasDefinition(child: V.Value<U32>) -> D.Definition<U32>:
  D.Definition{Some{child}, None{}, None{}, None{}, None{}, None{}}

def aliases() -> IO(Unit):
  do IO<Unit>:
    +child : R.Ref<V.ObjectStorage(U32)> <- V.newObject(U32, None{})
    +other : R.Ref<V.ObjectStorage(U32)> <- V.newObject(U32, None{})
    +object : R.Ref<V.ObjectStorage(U32)> <- V.newObject(U32, None{})
    first : Result<&2, &2, O.DefinitionError, Bool> <- O.defineOwnProperty(~U32, ~I.same, V.ObjectValue{object}, O.StringKey{"child"}, aliasDefinition(V.ObjectValue{child}))
    Test.assertion(String.eq(status(first), "true"), "initial child property failed")
    repeated : Result<&2, &2, O.DefinitionError, Bool> <- O.defineOwnProperty(~U32, ~I.same, V.ObjectValue{object}, O.StringKey{"child"}, aliasDefinition(V.ObjectValue{child}))
    Test.assertion(String.eq(status(repeated), "true"), "identical child alias rejected")
    distinct : Result<&2, &2, O.DefinitionError, Bool> <- O.defineOwnProperty(~U32, ~I.same, V.ObjectValue{object}, O.StringKey{"child"}, aliasDefinition(V.ObjectValue{other}))
    Test.assertion(String.eq(status(distinct), "false"), "equal-content object replaced fixed child")
    I.queries(I.Query{O.StringKey{"child"}, Some{V.DataProperty{V.ObjectValue{child}, False{}, False{}, False{}}}} <> Nil{}, V.ObjectValue{object})
    oldObject : V.ObjectStorage(U32) <- R.dispose(V.ObjectStorage(U32), object)
    oldChild : V.ObjectStorage(U32) <- R.dispose(V.ObjectStorage(U32), child)
    oldOther : V.ObjectStorage(U32) <- R.dispose(V.ObjectStorage(U32), other)
    return Unit{}
