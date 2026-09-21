import Base
import ../laws/url-form-strict.bend as Laws

def Laws.decoded_values_are_preserved(field, name, value): {==}
def Laws.invalid_name_precedes_value(field, value): {==}
def Laws.invalid_value_retains_position(field, name): {==}
def Laws.prepend_retains_entry(tuple, reversed): {==}
def Laws.prepend_preserves_failure(cause, reversed): {==}
def Laws.step_preserves_first_failure(field, text, cause):
  match text:
    case SNil{}: {==}
    case SCon{_, _}: {==}
def Laws.fields_preserve_first_failure(parts, field, cause):
  match parts:
    case Nil{}: {==}
    case _ <> _: {==}
def Laws.empty_field_preserves_accumulator(field, reversed): {==}
def Laws.finish_preserves_failure(cause): {==}
def Laws.query_marker_is_syntax(text): {==}
