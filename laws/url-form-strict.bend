import Base
import ../packages/runtime/src/url.bend as S
import ../packages/runtime/src/url.bend as F

law decoded_values_are_preserved:
  for field: Nat
  for name: String
  for value: String
  {S.decodedFormStrict(field, Some{name}, Some{value}) == Done{F.Entry{name, value}} : Result<&2, &2, S.FormStrictError, F.Entry>}

law invalid_name_precedes_value:
  for field: Nat
  for value: Maybe<&2, String>
  {S.decodedFormStrict(field, None{}, value) == Fail{S.InvalidName{field}} : Result<&2, &2, S.FormStrictError, F.Entry>}

law invalid_value_retains_position:
  for field: Nat
  for name: String
  {S.decodedFormStrict(field, Some{name}, None{}) == Fail{S.InvalidValue{field}} : Result<&2, &2, S.FormStrictError, F.Entry>}

law prepend_retains_entry:
  for tuple: F.Entry
  for reversed: List<&2, F.Entry>
  {S.prepend(Done{tuple}, reversed) == Done{tuple <> reversed} : Result<&2, &2, S.FormStrictError, List<&2, F.Entry>>}

law prepend_preserves_failure:
  for cause: S.FormStrictError
  for reversed: List<&2, F.Entry>
  {S.prepend(Fail{cause}, reversed) == Fail{cause} : Result<&2, &2, S.FormStrictError, List<&2, F.Entry>>}

law step_preserves_first_failure:
  for field: Nat
  for text: String
  for cause: S.FormStrictError
  {S.step(field, text, Fail{cause}) == Fail{cause} : Result<&2, &2, S.FormStrictError, List<&2, F.Entry>>}

law fields_preserve_first_failure:
  for parts: List<&2, String>
  for field: Nat
  for cause: S.FormStrictError
  {S.fields(parts, field, Fail{cause}) == Fail{cause} : Result<&2, &2, S.FormStrictError, List<&2, F.Entry>>}

law empty_field_preserves_accumulator:
  for field: Nat
  for reversed: List<&2, F.Entry>
  {S.step(field, "", Done{reversed}) == Done{reversed} : Result<&2, &2, S.FormStrictError, List<&2, F.Entry>>}

law finish_preserves_failure:
  for cause: S.FormStrictError
  {S.finishFormStrict(Fail{cause}) == Fail{cause} : Result<&2, &2, S.FormStrictError, List<&2, F.Entry>>}

law query_marker_is_syntax:
  for text: String
  {S.queryFormStrict(SCon{'?', text}) == S.parseFormStrict(text) : Result<&2, &2, S.FormStrictError, List<&2, F.Entry>>}
