import Base
import ../packages/runtime/src/resolver-config.bend as Options
import ../packages/runtime/src/resolver-config.bend as Configuration
import ../packages/runtime/src/dns-message.bend as Query
import ../packages/runtime/src/dns-message.bend as Search
import ../packages/runtime/src/dns-message.bend as Name

def request(plan: Configuration.Plan) -> Query.QueryOptions:
  match plan:
    case Configuration.Plan{options, _}: options

def cursor(plan: Configuration.Plan) -> Search.SearchCursor:
  match plan:
    case Configuration.Plan{_, value}: value

law preserves_request_policy:
  for +configuration: Configuration.Configuration
  for name: Name.Name
  for dots: U32
  for absolute: Bool
  {request(Configuration.plan(configuration, name, dots, absolute)) == Configuration.requestOptions(configuration) : Query.QueryOptions}

law preserves_search_policy:
  for +configuration: Configuration.Configuration
  for +name: Name.Name
  for +dots: U32
  for +absolute: Bool
  {cursor(Configuration.plan(configuration, name, dots, absolute)) == Configuration.startSearch(configuration, name, dots, absolute) : Search.SearchCursor}

law rejects_diagnostics:
  for options: Options.ResolverOptions
  for +first: Options.Diagnostic
  for +rest: List<&2, Options.Diagnostic>
  for domains: List<&2, String>
  {Configuration.checkedSearch(Options.OptionsReport{options, first <> rest}, domains) == Fail{first <> rest} : Result<&2, &2, List<&2, Options.Diagnostic>, Configuration.Configuration>}
