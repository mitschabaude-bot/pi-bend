import Base
import ../packages/runtime/src/http-response-metadata.bend as Metadata
import ../packages/runtime/src/http-head.bend as Head
import ../packages/runtime/src/http-status.bend as Status
import ../packages/runtime/src/http-header.bend as Header
import ../packages/runtime/src/headers.bend as Headers

law fields_partition:
  for +left: List<&2, Header.Header>
  for +initial: Headers.Headers
  for +right: List<&2, Header.Header>
  {Metadata.appendFields(List.append(&2, Header.Header, left, right), initial) == Metadata.appendFields(right, Metadata.appendFields(left, initial)) : Headers.Headers}

law empty_fields_preserve_headers:
  for +initial: Headers.Headers
  {Metadata.appendFields(Nil{}, initial) == initial : Headers.Headers}

law original_head_retained:
  for +head: Head.ResponseHead
  for expose: Bool
  {Metadata.original(Metadata.fromHead(head, expose)) == head : Head.ResponseHead}

law exposure_retained:
  for head: Head.ResponseHead
  for +expose: Bool
  {Metadata.bodyPresent(Metadata.fromHead(head, expose)) == expose : Bool}

law status_retained:
  for major: U32
  for minor: U32
  for +code: U32
  for reason: List<&2, U32>
  for fields: List<&2, Header.Header>
  for expose: Bool
  {Metadata.status(Metadata.fromHead(Head.ResponseHead{Status.StatusLine{major, minor, code, reason}, fields}, expose)) == code : U32}

law success_classification:
  for major: U32
  for minor: U32
  for +code: U32
  for reason: List<&2, U32>
  for fields: List<&2, Header.Header>
  for expose: Bool
  {Metadata.ok(Metadata.fromHead(Head.ResponseHead{Status.StatusLine{major, minor, code, reason}, fields}, expose)) == (U32.is_ge(code, 200) && U32.is_lt(code, 300)) : Bool}

law one_field_preserved:
  for +initial: Headers.Headers
  for +field: Header.Header
  {Metadata.appendFields(field <> Nil{}, initial) == Headers.appendField(initial, field) : Headers.Headers}

law received_headers_retained:
  for line: Status.StatusLine
  for +fields: List<&2, Header.Header>
  for expose: Bool
  {Metadata.headers(Metadata.fromHead(Head.ResponseHead{line, fields}, expose)) == Metadata.appendFields(fields, Headers.new()) : Headers.Headers}
