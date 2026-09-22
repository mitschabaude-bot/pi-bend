import Base
import ../packages/runtime/src/json-string.bend as Quote
import ../packages/runtime/src/file-fold.bend as Fold
import ../packages/runtime/src/dns-resolver.bend as D
import ../packages/runtime/src/resolver-config.bend as Options
import ../packages/runtime/src/dns-resolver.bend as System
import ../packages/runtime/src/dns-resolver.bend as Servers
import ../packages/runtime/src/resolver-config.bend as Load
import ../packages/runtime/src/resolver-config.bend as Plan
import ../packages/runtime/src/utf8-strict.bend as UTF8

law every_invalid_option_has_a_diagnostic:
  for errors: List<&2, Options.Diagnostic>
  {List.length(&2, String, D.options(errors)) == List.length(&2, Options.Diagnostic, errors) : Nat}

law option_batches_preserve_order_and_composition:
  for left: List<&2, Options.Diagnostic>
  for right: List<&2, Options.Diagnostic>
  {D.options(List.append(&2, Options.Diagnostic, left, right)) == List.append(&2, String, D.options(left), D.options(right)) : List<&2, String>}

law source_report_does_not_replace_transport_cause:
  for report: Servers.SystemServersReport
  for cause: Plan.Error
  {D.messages(System.InvalidTransport{report, cause}) == D.transport(cause) <> Nil{} : List<&2, String>}

law loading_preserves_diagnostic:
  for cause: Load.LoadError<UTF8.Error>
  {D.messages(System.Loading{cause}) == D.loading(cause) <> Nil{} : List<&2, String>}

law source_report_does_not_replace_option_causes:
  for report: Servers.SystemServersReport
  for errors: List<&2, Options.Diagnostic>
  {D.messages(System.InvalidOptions{report, errors}) == D.options(errors) : List<&2, String>}

law malformed_option_retains_token:
  for token: String
  {D.option(Options.Malformed{token}) == "Malformed resolver option " ++ Quote.quote(token) : String}

law unknown_option_retains_token:
  for token: String
  {D.option(Options.OptionsUnknown{token}) == "Unknown resolver option " ++ Quote.quote(token) : String}

law open_failure_retains_code_and_message:
  for code: U32
  for message: String
  {D.file(Fold.Open{code, message}) == "Could not open resolver configuration (code " ++ Nat.show(U32.to_nat(code)) ++ "): " ++ message : String}

law read_failure_retains_code_and_message:
  for code: U32
  for message: String
  {D.file(Fold.Read{code, message}) == "Could not read resolver configuration (code " ++ Nat.show(U32.to_nat(code)) ++ "): " ++ message : String}
