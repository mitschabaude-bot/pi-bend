import Base
import ../packages/ai/src/api/openai-sse-default-hooks.bend as H
import ../laws/openai-sse-default-hooks.bend as Laws

def Laws.invalid_json_reports_exact_data_and_current_block(cause, data, raw, target): {==}
def Laws.api_errors_do_not_emit_json_parse_diagnostics(error): {==}
def Laws.borrowing_preserves_owner_and_callbacks(E, hooks): {==}
def Laws.disposal_retires_both_callbacks(E, cancel, report): {==}


def Laws.raw_diagnostics_preserve_number_of_lines(lines):
  match lines:
    case Nil{}: {==}
    case first <> +rest:
      Equal.cong(Nat, Nat, size => Succ{size}, List.length(&2, String, H.quoted(rest)), List.length(&2, String, rest), Laws.raw_diagnostics_preserve_number_of_lines(rest))
