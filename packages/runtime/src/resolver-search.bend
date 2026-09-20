import Base
import ./resolver-options.bend as Options
import ./resolver-settings.bend as Settings
import ./resolver-domains.bend as Domains
import ./dns-search.bend as Search
import ./dns-name.bend as Name

# Search consumes ndots/no-TLD only. Keep the complete selected options for
# transport, response, retry and reload layers rather than discarding flags.
type Configuration is Data:
  Configuration{options: Options.Options, domains: Domains.Report}

def ndots(options: Options.Options) -> U32:
  match options:
    case Options.Options{value, _, _, _}: value

def policy(+options: Options.Options) -> Search.Policy:
  Search.Policy{ndots(options), True{}, True{}, Options.enabled(Options.NoTldQuery{}, options)}

# Callers supplying explicit option values have already selected their policy.
def prepare(options: Options.Options, domains: List<&2, String>) -> Configuration:
  Configuration{options, Domains.prepare(domains)}

def checked(report: Options.Report, domains: List<&2, String>) -> Result<&2, &2, List<&2, Options.Diagnostic>, Configuration>:
  match report:
    case Options.Report{options, Nil{}}: Done{prepare(options, domains)}
    case Options.Report{_, diagnostics}: Fail{diagnostics}

# Strictness is explicit in the API, not a default OS compatibility decision.
# Every option diagnostic is returned; no partial values produce a cursor.
def prepareStrict(tokens: List<&2, String>, domains: List<&2, String>) -> Result<&2, &2, List<&2, Options.Diagnostic>, Configuration>:
  checked(Options.interpretStrict(tokens, Options.defaults()), domains)

def fromSettingsStrict(settings: Settings.Settings) -> Result<&2, &2, List<&2, Options.Diagnostic>, Configuration>:
  match settings:
    case Settings.Settings{_, domains, options, _, _}: prepareStrict(options, domains)

def start(configuration: Configuration, base: Name.Name, dots: U32, absolute: Bool) -> Search.Cursor:
  match configuration:
    case Configuration{options, Domains.Report{domains, _}}: Search.startDomains(base, dots, absolute, domains, policy(options))
