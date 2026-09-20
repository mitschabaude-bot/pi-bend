import Base
import ./resolver-config.bend as Config
import ./resolver-address.bend as Address
import ./url-ipv4.bend as IPv4

# Inputs are already decoded. Supplying Some for localDomains explicitly
# overrides file search/domain directives, including an empty supplied list.
type Overrides is Data:
  Overrides{hostname: Maybe<&2, String>, localDomains: Maybe<&2, List<&2, String>>, options: List<&2, String>}

type Diagnostics is Data:
  Diagnostics{invalidServers: List<&2, String>, unknownLines: List<&2, String>}

type Settings is Data:
  Settings{servers: List<&2, Address.Address>, search: List<&2, String>, options: List<&2, String>, sortlist: List<&2, String>, diagnostics: Diagnostics}

type Collected is Data:
  Collected{servers: List<&2, Address.Address>, search: Maybe<&2, List<&2, String>>, options: List<&2, String>, sortlist: List<&2, String>, diagnostics: Diagnostics}

# All accumulated lists except the replacing search list are reversed.
def prepend(values: List<&2, String>, reversed: List<&2, String>) -> List<&2, String>:
  match values:
    case Nil{}: reversed
    case value <> rest: prepend(rest, value <> reversed)

def server(token: String, value: Result<&2, &2, Address.Error, Address.Address>, state: Collected) -> Collected:
  match value state:
    case Done{address} Collected{servers, search, options, sort, diagnostics}: Collected{address <> servers, search, options, sort, diagnostics}
    case Fail{_} Collected{servers, search, options, sort, Diagnostics{invalid, unknown}}: Collected{servers, search, options, sort, Diagnostics{token <> invalid, unknown}}

def applyEntry(entry: Config.Entry, state: Collected) -> Collected:
  match entry state:
    case Config.Nameserver{token, parsed} previous: server(token, parsed, previous)
    case Config.Domain{name} Collected{servers, _, options, sort, diagnostics}: Collected{servers, Some{name <> Nil{}}, options, sort, diagnostics}
    case Config.Search{names} Collected{servers, _, options, sort, diagnostics}: Collected{servers, Some{names}, options, sort, diagnostics}
    case Config.Options{values} Collected{servers, search, options, sort, diagnostics}: Collected{servers, search, prepend(values, options), sort, diagnostics}
    case Config.Sortlist{values} Collected{servers, search, options, sort, diagnostics}: Collected{servers, search, options, prepend(values, sort), diagnostics}
    case Config.Unknown{line} Collected{servers, search, options, sort, Diagnostics{invalid, unknown}}: Collected{servers, search, options, sort, Diagnostics{invalid, line <> unknown}}

def collect(entries: List<&2, Config.Entry>, state: Collected) -> Collected:
  match entries:
    case Nil{}: state
    case entry <> rest: collect(rest, applyEntry(entry, state))

# The default search domain is the suffix after the hostname's first dot.
# No dot means no local search suffix; an explicit final dot retains root.
def hostnameDomain(text: String) -> List<&2, String>:
  match text:
    case SNil{}: Nil{}
    case SCon{'.', rest}: rest <> Nil{}
    case SCon{_, rest}: hostnameDomain(rest)

def hostnameSearch(hostname: Maybe<&2, String>) -> List<&2, String>:
  match hostname:
    case None{}: Nil{}
    case Some{text}: hostnameDomain(text)

def searchList(hostname: Maybe<&2, String>, environment: Maybe<&2, List<&2, String>>, file: Maybe<&2, List<&2, String>>) -> List<&2, String>:
  match environment file:
    case Some{names} _: names
    case None{} Some{names}: names
    case None{} None{}: hostnameSearch(hostname)

def nameservers(reversed: List<&2, Address.Address>) -> List<&2, Address.Address>:
  match reversed:
    case Nil{}: Address.V4{IPv4.Address{2130706433}} <> Nil{}
    case entries: List.reverse(&2, Address.Address, entries)

def finalized(overrides: Overrides, state: Collected) -> Settings:
  match overrides state:
    case Overrides{hostname, local, environmentOptions} Collected{servers, search, options, sort, Diagnostics{invalid, unknown}}:
      Settings{nameservers(servers), searchList(hostname, local, search), List.reverse(&2, String, prepend(environmentOptions, options)), List.reverse(&2, String, sort), Diagnostics{List.reverse(&2, String, invalid), List.reverse(&2, String, unknown)}}

# Resolve source precedence only. Option/sort interpretation, server limits,
# IPv6 scope resolution and network scheduling are subsequent typed layers.
def configure(entries: List<&2, Config.Entry>, overrides: Overrides) -> Settings:
  finalized(overrides, collect(entries, Collected{Nil{}, None{}, Nil{}, Nil{}, Diagnostics{Nil{}, Nil{}}}))
