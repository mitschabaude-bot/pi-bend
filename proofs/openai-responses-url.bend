import Base
import ../laws/openai-responses-url.bend as Laws
import ../packages/ai/src/api/openai-responses-url.bend as S
import ../packages/runtime/src/url-form.bend as F
import ../packages/runtime/src/url-record.bend as URL
import ../packages/runtime/src/record.bend as R

def Laws.singleton_field_updates_dictionary(name, value, fields): {==}
def Laws.fields_partition(left, initial, right):
  match left:
    case Nil{}: {==}
    case F.Entry{name, value} <> rest: Laws.fields_partition(rest, R.set(String, initial, name, value), right)
def Laws.later_query_replaces_earlier(url, first, second):
  match url:
    case URL.URL{_, _, _, _, _, _, _, _}: {==}
def Laws.malformed_query_preserves_cause(url, cause): {==}
def Laws.malformed_url_preserves_cause(cause): {==}
def Laws.absent_query_preserves_url(url): {==}
def Laws.empty_fields_preserve_url(url): {==}
