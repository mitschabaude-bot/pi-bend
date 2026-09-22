import Base
import ../laws/validation.bend as Laws
import ../packages/ai/src/utils/validation.bend as Validation
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R

def Laws.arrays_pass_primitive_coercion(kind, items):
  match kind:
    case Validation.Numeric{integerOnly}: {==}
    case Validation.BooleanType{}: {==}
    case Validation.StringType{}: {==}
    case Validation.NullType{}: {==}
    case Validation.OtherType{}: {==}

def Laws.objects_pass_primitive_coercion(kind, fields):
  match kind:
    case Validation.Numeric{integerOnly}: {==}
    case Validation.BooleanType{}: {==}
    case Validation.StringType{}: {==}
    case Validation.NullType{}: {==}
    case Validation.OtherType{}: {==}

def Laws.type_lists_never_alter_arrays(types, items):
  match types:
    case Nil{}: {==}
    case head <> tail:
      %Equal.sym(Validation.Coercion(), Validation.coercePrimitive(Validation.primitiveType(head), V.ArrayValue{items}), Done{V.ArrayValue{items}}, Laws.arrays_pass_primitive_coercion(Validation.primitiveType(head), items)) : {Validation.selectPrimitiveTypes(tail, V.ArrayValue{items}, Validation.primitiveSelection(V.ArrayValue{items}, _)) == Done{V.ArrayValue{items}} : Validation.Coercion()}
      Laws.type_lists_never_alter_arrays(tail, items)

def Laws.type_lists_never_alter_objects(types, fields):
  match types:
    case Nil{}: {==}
    case head <> tail:
      %Equal.sym(Validation.Coercion(), Validation.coercePrimitive(Validation.primitiveType(head), V.ObjectValue{fields}), Done{V.ObjectValue{fields}}, Laws.objects_pass_primitive_coercion(Validation.primitiveType(head), fields)) : {Validation.selectPrimitiveTypes(tail, V.ObjectValue{fields}, Validation.primitiveSelection(V.ObjectValue{fields}, _)) == Done{V.ObjectValue{fields}} : Validation.Coercion()}
      Laws.type_lists_never_alter_objects(tail, fields)

def Laws.coercion_failures_are_final(tasks, error):
  match tasks:
    case Nil{}: {==}
    case Validation.Coerce{schema} <> rest: {==}
    case Validation.Union{schemas} <> rest: {==}
    case Validation.OriginalMembers{Nil{}, all, original} <> rest: {==}
    case Validation.OriginalMembers{schema <> remaining, all, original} <> rest: {==}
    case Validation.OriginalChecked{Fail{failure}, remaining, all, original} <> rest: {==}
    case Validation.OriginalChecked{Done{True{}}, remaining, all, original} <> rest: {==}
    case Validation.OriginalChecked{Done{False{}}, remaining, all, original} <> rest: {==}
    case Validation.Candidates{Nil{}, original} <> rest: {==}
    case Validation.Candidates{schema <> remaining, original} <> rest: {==}
    case Validation.CandidateResult{schema, remaining, original} <> rest: {==}
    case Validation.CandidateChecked{Fail{failure}, remaining, original} <> rest: {==}
    case Validation.CandidateChecked{Done{True{}}, remaining, original} <> rest: {==}
    case Validation.CandidateChecked{Done{False{}}, remaining, original} <> rest: {==}
    case Validation.Scalars{types} <> rest: {==}
    case Validation.Structure{schema, types} <> rest: {==}
    case Validation.ObjectFields{Nil{}, properties, additional, built} <> rest: {==}
    case Validation.ObjectFields{R.Property{key, value} <> remaining, properties, additional, built} <> rest: {==}
    case Validation.ObjectFieldResult{key, remaining, properties, additional, built} <> rest: {==}
    case Validation.ArrayItems{Nil{}, schemas, built} <> rest: {==}
    case Validation.ArrayItems{value <> remaining, schemas, built} <> rest: {==}
    case Validation.ArrayItemResult{remaining, schemas, built} <> rest: {==}

def Laws.boolean_schemas_coerce_nothing(accept, value): {==}

def Laws.empty_schemas_coerce_nothing(value):
  match value:
    case V.Null{}: {==}
    case V.Boolean{flag}: {==}
    case V.Number{number}: {==}
    case V.Text{text}: {==}
    case V.ArrayValue{items}: {==}
    case V.ObjectValue{fields}: {==}
