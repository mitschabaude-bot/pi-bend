import Base
import ../packages/ai/src/utils/validation.bend as Validation
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R

# Primitive coercion only ever rewrites scalars: arrays and objects pass every
# primitive kind and every declared type list unchanged.

law arrays_pass_primitive_coercion:
  for kind: Validation.PrimitiveType
  for +items: List<&2, V.Value>
  {Validation.coercePrimitive(kind, V.ArrayValue{items}) == Done{V.ArrayValue{items}} : Validation.Coercion()}

law objects_pass_primitive_coercion:
  for kind: Validation.PrimitiveType
  for +fields: R.Record<V.Value>
  {Validation.coercePrimitive(kind, V.ObjectValue{fields}) == Done{V.ObjectValue{fields}} : Validation.Coercion()}

law type_lists_never_alter_arrays:
  for types: List<&2, String>
  for +items: List<&2, V.Value>
  {Validation.selectPrimitiveTypes(types, V.ArrayValue{items}, Validation.TryNextType{}) == Done{V.ArrayValue{items}} : Validation.Coercion()}

law type_lists_never_alter_objects:
  for types: List<&2, String>
  for +fields: R.Record<V.Value>
  {Validation.selectPrimitiveTypes(types, V.ObjectValue{fields}, Validation.TryNextType{}) == Done{V.ObjectValue{fields}} : Validation.Coercion()}

# The recursive coercion driver: a failure is final, and schemas without
# keywords accept every value unchanged.

law coercion_failures_are_final:
  for tasks: List<&2, Validation.CoercionTask>
  for error: Validation.CoercionError
  {Validation.coerceTasks(tasks, Fail{error}) == Fail{error} : Validation.Coercion()}

law boolean_schemas_coerce_nothing:
  for accept: Bool
  for value: V.Value
  {Validation.coerceWithJsonSchema(value, V.Boolean{accept}) == Done{value} : Validation.Coercion()}

law empty_schemas_coerce_nothing:
  for value: V.Value
  {Validation.coerceWithJsonSchema(value, V.ObjectValue{R.Record{Nil{}}}) == Done{value} : Validation.Coercion()}
