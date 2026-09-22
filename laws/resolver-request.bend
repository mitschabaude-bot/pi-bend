import Base
import ../packages/runtime/src/resolver-config.bend as Request
import ../packages/runtime/src/resolver-config.bend as Resolver

def settings(prepared: Request.Prepared) -> Resolver.ResolverOptions:
  match prepared:
    case Request.Prepared{options, _}: options

law preserves_settings:
  for +options: Resolver.ResolverOptions
  {settings(Request.prepareRequest(options)) == options : Resolver.ResolverOptions}

law rejects_diagnostics:
  for options: Resolver.ResolverOptions
  for +first: Resolver.Diagnostic
  for +rest: List<&2, Resolver.Diagnostic>
  {Request.checkedRequest(Resolver.OptionsReport{options, first <> rest}) == Fail{first <> rest} : Result<&2, &2, List<&2, Resolver.Diagnostic>, Request.Prepared>}
