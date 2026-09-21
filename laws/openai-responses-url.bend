import Base
import ../packages/ai/src/api/openai-responses-url.bend as S
import ../packages/runtime/src/url-form.bend as F
import ../packages/runtime/src/url-form-strict.bend as Strict
import ../packages/runtime/src/url-record.bend as URL
import ../packages/runtime/src/url-absolute.bend as Absolute
import ../packages/runtime/src/record.bend as R

law singleton_field_updates_dictionary:
  for name: String
  for value: String
  for fields: R.Record<String>
  {S.collect(F.Entry{name, value} <> Nil{}, fields) == R.set(String, fields, name, value) : R.Record<String>}

law fields_partition:
  for +left: List<&2, F.Entry>
  for +initial: R.Record<String>
  for +right: List<&2, F.Entry>
  {S.collect(List.append(&2, F.Entry, left, right), initial) == S.collect(right, S.collect(left, initial)) : R.Record<String>}

law later_query_replaces_earlier:
  for url: URL.URL
  for first: Maybe<&2, String>
  for second: Maybe<&2, String>
  {S.withQuery(S.withQuery(url, first), second) == S.withQuery(url, second) : URL.URL}

law malformed_query_preserves_cause:
  for url: URL.URL
  for cause: Strict.Error
  {S.normalized(url, Fail{cause}) == Fail{S.InvalidQuery{cause}} : Result<&2, &2, S.Error, URL.URL>}

law malformed_url_preserves_cause:
  for cause: Absolute.Error
  {S.parsed(Fail{cause}) == Fail{S.InvalidURL{cause}} : Result<&2, &2, S.Error, URL.URL>}

law absent_query_preserves_url:
  for url: URL.URL
  {S.queried(url, None{}) == Done{url} : Result<&2, &2, S.Error, URL.URL>}

law empty_fields_preserve_url:
  for url: URL.URL
  {S.normalized(url, Done{Nil{}}) == Done{url} : Result<&2, &2, S.Error, URL.URL>}
