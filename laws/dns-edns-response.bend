import Base
import ../packages/runtime/src/dns-edns.bend as Option
import ../packages/runtime/src/dns-edns-response.bend as Edns
import ../packages/runtime/src/dns-message.bend as Message
import ../packages/runtime/src/dns-name.bend as Name

law scan_failure_retained:
  for packet: Name.Packet
  for records: List<&2, Message.Record>
  for +error: Edns.Error
  {Edns.scan(packet, records, Fail{error}) == Fail{error} : Result<&2, &2, Edns.Error, Maybe<&2, Edns.Response>>}

law ordinary_record_preserves_selection:
  for packet: Name.Packet
  for record: Message.Record
  for +prior: Result<&2, &2, Edns.Error, Maybe<&2, Edns.Response>>
  {Edns.selected(False{}, packet, record, prior) == prior : Result<&2, &2, Edns.Error, Maybe<&2, Edns.Response>>}

law second_opt_rejected:
  for packet: Name.Packet
  for record: Message.Record
  for prior: Edns.Response
  {Edns.selected(True{}, packet, record, Done{Some{prior}}) == Fail{Edns.Duplicate{}} : Result<&2, &2, Edns.Error, Maybe<&2, Edns.Response>>}

law misplaced_opt_rejected:
  for packet: Name.Packet
  for additional: List<&2, Message.Record>
  {Edns.placement(True{}, packet, additional) == Fail{Edns.Misplaced{}} : Result<&2, &2, Edns.Error, Maybe<&2, Edns.Response>>}

# Only the header's low code and OPT's extended code determine the result;
# version, flags, advertised size and opaque options cannot change its meaning.
law response_code_metadata_independent:
  for +header: Message.Header
  for +upper: U32
  for payload: U32
  for version: U32
  for flags: U32
  for options: List<&2, Option.Option>
  for otherPayload: U32
  for otherVersion: U32
  for otherFlags: U32
  for otherOptions: List<&2, Option.Option>
  {Edns.responseCode(header, Some{Edns.Response{payload, upper, version, flags, options}}) == Edns.responseCode(header, Some{Edns.Response{otherPayload, upper, otherVersion, otherFlags, otherOptions}}) : U32}
