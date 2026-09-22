import Base
import ../laws/http-response-metadata.bend as Laws
import ../packages/runtime/src/http-message.bend as Head
import ../packages/runtime/src/http-message.bend as Headers

def Laws.fields_partition(left, initial, right):
  match left:
    case Nil{}: {==}
    case first <> rest: Laws.fields_partition(rest, Headers.appendField(initial, first), right)
def Laws.empty_fields_preserve_headers(initial): {==}
def Laws.original_head_retained(head, expose):
  match head:
    case Head.ResponseHead{_, _}: {==}
def Laws.exposure_retained(head, expose):
  match head:
    case Head.ResponseHead{_, _}: {==}
def Laws.status_retained(major, minor, code, reason, fields, expose): {==}
def Laws.success_classification(major, minor, code, reason, fields, expose): {==}
def Laws.one_field_preserved(initial, field): {==}
def Laws.received_headers_retained(line, fields, expose): {==}
