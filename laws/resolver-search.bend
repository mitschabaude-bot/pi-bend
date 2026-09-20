import Base
import ../packages/runtime/src/resolver-options.bend as Options
import ../packages/runtime/src/resolver-search.bend as Configuration
import ../packages/runtime/src/dns-query.bend as Query
import ../packages/runtime/src/dns-search.bend as Search
import ../packages/runtime/src/dns-name.bend as Name

def request(plan: Configuration.Plan) -> Query.Options:
  match plan:
    case Configuration.Plan{options, _}: options

def cursor(plan: Configuration.Plan) -> Search.Cursor:
  match plan:
    case Configuration.Plan{_, value}: value

law preserves_request_policy:
  for +configuration: Configuration.Configuration
  for name: Name.Name
  for dots: U32
  for absolute: Bool
  {request(Configuration.plan(configuration, name, dots, absolute)) == Configuration.requestOptions(configuration) : Query.Options}

law preserves_search_policy:
  for +configuration: Configuration.Configuration
  for +name: Name.Name
  for +dots: U32
  for +absolute: Bool
  {cursor(Configuration.plan(configuration, name, dots, absolute)) == Configuration.start(configuration, name, dots, absolute) : Search.Cursor}

law rejects_diagnostics:
  for options: Options.Options
  for +first: Options.Diagnostic
  for +rest: List<&2, Options.Diagnostic>
  for domains: List<&2, String>
  {Configuration.checked(Options.Report{options, first <> rest}, domains) == Fail{first <> rest} : Result<&2, &2, List<&2, Options.Diagnostic>, Configuration.Configuration>}
