import Base
import ../packages/runtime/src/resolver-request.bend as Request
import ../packages/runtime/src/resolver-options.bend as Resolver

def settings(prepared: Request.Prepared) -> Resolver.Options:
  match prepared:
    case Request.Prepared{options, _}: options

law preserves_settings:
  for +options: Resolver.Options
  {settings(Request.prepare(options)) == options : Resolver.Options}

law rejects_diagnostics:
  for options: Resolver.Options
  for +first: Resolver.Diagnostic
  for +rest: List<&2, Resolver.Diagnostic>
  {Request.checked(Resolver.Report{options, first <> rest}) == Fail{first <> rest} : Result<&2, &2, List<&2, Resolver.Diagnostic>, Request.Prepared>}
