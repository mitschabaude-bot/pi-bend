import Base
import ../laws/dns-resolver.bend as Laws
import ../packages/runtime/src/dns-resolver.bend as D
import ../packages/runtime/src/resolver-config.bend as Options

def Laws.every_invalid_option_has_a_diagnostic(errors):
  match errors:
    case Nil{}: {==}
    case first <> +rest:
      Equal.cong(Nat, Nat, size => Succ{size}, List.length(&2, String, D.options(rest)), List.length(&2, Options.Diagnostic, rest), Laws.every_invalid_option_has_a_diagnostic(rest))

def Laws.option_batches_preserve_order_and_composition(left, right):
  match left right:
    case Nil{} _: {==}
    case +first <> +rest +right:
      Equal.cong(List<&2, String>, List<&2, String>, tail => D.option(first) <> tail, D.options(List.append(&2, Options.Diagnostic, rest, right)), List.append(&2, String, D.options(rest), D.options(right)), Laws.option_batches_preserve_order_and_composition(rest, right))

def Laws.source_report_does_not_replace_transport_cause(report, cause): {==}
def Laws.loading_preserves_diagnostic(cause): {==}
def Laws.source_report_does_not_replace_option_causes(report, errors): {==}

def Laws.malformed_option_retains_token(token): {==}
def Laws.unknown_option_retains_token(token): {==}
def Laws.open_failure_retains_code_and_message(code, message): {==}
def Laws.read_failure_retains_code_and_message(code, message): {==}
