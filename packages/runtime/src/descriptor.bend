import Base
import ./value.bend as V

# Presence is independent of value. Some{None{}} explicitly clears an
# accessor; Some{Undefined{}} explicitly defines a data value.
type Definition<-M: Data> is Data:
  Definition{value: Maybe<&2, V.Value<M>>, writable: Maybe<&2, Bool>, get: Maybe<&2, Maybe<&2, M>>, set: Maybe<&2, Maybe<&2, M>>, enumerable: Maybe<&2, Bool>, configurable: Maybe<&2, Bool>}

type DescriptorKind is Data:
  Generic{}
  DataKind{}
  AccessorKind{}
  InvalidKind{}

type Decision<-M: Data> is Data:
  Define{descriptor: V.Descriptor<M, V.Value<M>>}
  Reject{}
  Invalid{}

def present(-A: Data, value: Maybe<&2, A>) -> Bool:
  match value:
    case None{}: False{}
    case Some{_}: True{}

def selected(-A: Data, value: Maybe<&2, A>, fallback: A) -> A:
  match value:
    case None{}: fallback
    case Some{x}: x

def kindFlags(data: Bool, accessor: Bool) -> DescriptorKind:
  match data accessor:
    case True{} True{}: InvalidKind{}
    case True{} False{}: DataKind{}
    case False{} True{}: AccessorKind{}
    case False{} False{}: Generic{}

def definitionKind(-M: Data, definition: Definition<M>) -> DescriptorKind:
  match definition:
    case Definition{value, writable, get, set, _, _}: kindFlags(present(V.Value<M>, value) || present(Bool, writable), present(Maybe<&2, M>, get) || present(Maybe<&2, M>, set))

def descriptorConfigurable(-M: Data, descriptor: V.Descriptor<M, V.Value<M>>) -> Bool:
  match descriptor:
    case V.DataProperty{_, _, _, value}: value
    case V.AccessorProperty{_, _, _, value}: value

def descriptorEnumerable(-M: Data, descriptor: V.Descriptor<M, V.Value<M>>) -> Bool:
  match descriptor:
    case V.DataProperty{_, _, value, _}: value
    case V.AccessorProperty{_, _, value, _}: value

def sameKind(-M: Data, kind: DescriptorKind, descriptor: V.Descriptor<M, V.Value<M>>) -> Bool:
  match kind descriptor:
    case Generic{} _: True{}
    case DataKind{} V.DataProperty{_, _, _, _}: True{}
    case AccessorKind{} V.AccessorProperty{_, _, _, _}: True{}
    case _ _: False{}

def unchangedFlag(value: Maybe<&2, Bool>, expected: Bool) -> Bool:
  match value:
    case None{}: True{}
    case Some{x}: V.sameBoolean(x, expected)

def unchangedValue(~M: Data, ~same: M -> M -> Bool, value: Maybe<&2, V.Value<M>>, expected: V.Value<M>) -> Bool:
  match value:
    case None{}: True{}
    case Some{x}: V.sameValue(M, x, expected, same)

def sameOptional(~M: Data, ~same: M -> M -> Bool, a: Maybe<&2, M>, b: Maybe<&2, M>) -> Bool:
  match a b:
    case None{} None{}: True{}
    case Some{x} Some{y}: same(x, y)
    case _ _: False{}

def unchangedAccessor(~M: Data, ~same: M -> M -> Bool, value: Maybe<&2, Maybe<&2, M>>, expected: Maybe<&2, M>) -> Bool:
  match value:
    case None{}: True{}
    case Some{x}: sameOptional(~M, ~same, x, expected)

# Called for a non-configurable property after checking descriptor kind.
def fixedFieldsAllowed(~M: Data, ~same: M -> M -> Bool, current: V.Descriptor<M, V.Value<M>>, definition: Definition<M>) -> Bool:
  match current definition:
    case V.DataProperty{old, False{}, _, _} Definition{value, writable, _, _, _, _}: unchangedFlag(writable, False{}) && unchangedValue(~M, ~same, value, old)
    case V.DataProperty{_, True{}, _, _} _: True{}
    case V.AccessorProperty{oldGet, oldSet, _, _} Definition{_, _, get, set, _, _}: unchangedAccessor(~M, ~same, get, oldGet) && unchangedAccessor(~M, ~same, set, oldSet)

def fixedFlagsAllowed(-M: Data, currentEnumerable: Bool, definition: Definition<M>) -> Bool:
  match definition:
    case Definition{_, _, _, _, enumerable, configurable}: unchangedFlag(configurable, False{}) && unchangedFlag(enumerable, currentEnumerable)

def canRedefine(~M: Data, ~same: M -> M -> Bool, +current: V.Descriptor<M, V.Value<M>>, +definition: Definition<M>, kind: DescriptorKind) -> Bool:
  descriptorConfigurable(M, current) || (sameKind(M, kind, current) && fixedFlagsAllowed(M, descriptorEnumerable(M, current), definition) && fixedFieldsAllowed(~M, ~same, current, definition))

def convertKind(-M: Data, kind: DescriptorKind, current: V.Descriptor<M, V.Value<M>>) -> V.Descriptor<M, V.Value<M>>:
  match kind current:
    case AccessorKind{} V.DataProperty{_, _, enumerable, configurable}: V.AccessorProperty{None{}, None{}, enumerable, configurable}
    case DataKind{} V.AccessorProperty{_, _, enumerable, configurable}: V.DataProperty{V.Undefined{}, False{}, enumerable, configurable}
    case _ current: current

def apply(-M: Data, current: V.Descriptor<M, V.Value<M>>, definition: Definition<M>) -> V.Descriptor<M, V.Value<M>>:
  match current definition:
    case V.DataProperty{old, oldWritable, oldEnumerable, oldConfigurable} Definition{value, writable, _, _, enumerable, configurable}: V.DataProperty{selected(V.Value<M>, value, old), selected(Bool, writable, oldWritable), selected(Bool, enumerable, oldEnumerable), selected(Bool, configurable, oldConfigurable)}
    case V.AccessorProperty{oldGet, oldSet, oldEnumerable, oldConfigurable} Definition{_, _, get, set, enumerable, configurable}: V.AccessorProperty{selected(Maybe<&2, M>, get, oldGet), selected(Maybe<&2, M>, set, oldSet), selected(Bool, enumerable, oldEnumerable), selected(Bool, configurable, oldConfigurable)}

def redefine(-M: Data, allowed: Bool, kind: DescriptorKind, current: V.Descriptor<M, V.Value<M>>, definition: Definition<M>) -> Decision<M>:
  match allowed:
    case False{}: Reject{}
    case True{}: Define{apply(M, convertKind(M, kind, current), definition)}

def planKind(~M: Data, ~same: M -> M -> Bool, kind: DescriptorKind, extensible: Bool, current: Maybe<&2, V.Descriptor<M, V.Value<M>>>, +definition: Definition<M>) -> Decision<M>:
  match kind current:
    case InvalidKind{} _: Invalid{}
    case kind None{}: redefine(M, extensible, kind, V.DataProperty{V.Undefined{}, False{}, False{}, False{}}, definition)
    case +kind Some{+old}: redefine(M, canRedefine(~M, ~same, old, definition, kind), kind, old, definition)

def validate(~M: Data, ~same: M -> M -> Bool, extensible: Bool, current: Maybe<&2, V.Descriptor<M, V.Value<M>>>, +definition: Definition<M>) -> Decision<M>:
  planKind(~M, ~same, definitionKind(M, definition), extensible, current, definition)
