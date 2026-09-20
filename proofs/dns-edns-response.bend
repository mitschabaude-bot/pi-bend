import Base
import ../packages/runtime/src/dns-message.bend as Message
import ../laws/dns-edns-response.bend as Laws

def Laws.scan_failure_retained(packet, records, error):
  match records:
    case Nil{}: {==}
    case _ <> _: {==}
def Laws.ordinary_record_preserves_selection(packet, record, prior):
  match prior:
    case Fail{_}: {==}
    case Done{_}: {==}
def Laws.second_opt_rejected(packet, record, prior): {==}
def Laws.misplaced_opt_rejected(packet, additional): {==}

def Laws.response_code_metadata_independent(header, upper, payload, version, flags, options, otherPayload, otherVersion, otherFlags, otherOptions):
  match header:
    case Message.Header{_, _, _, _, _, _}: {==}
