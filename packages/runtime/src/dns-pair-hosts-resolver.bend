import Base
import ./hosts.bend as Hosts
import ./hosts-file.bend as File
import ./hosts-family.bend as Family
import ./hosts-resolve.bend as HostsResolve
import ./dns-search-text.bend as Text
import ./dns-presentation.bend as Presentation
import ./dns-resolver.bend as Resolver
import ./dns-pair-resolver.bend as Paired
import ./dns-pair-search.bend as Network
import ./dns-pair-result.bend as Pair
import ./dns-id.bend as Id
import ./abort.bend as Abort

type DNS<-Reason: Data> is Data:
  InvalidName{error: Presentation.Error}
  Completed{report: Network.Report<Reason>}

def network(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, environment: Environment, resolver: Resolver.Resolver, parent: Abort.AbortSignal<Reason>, priority: Pair.Priority, input: Result<&2, &2, Presentation.Error, Text.Input>) -> IO(DNS<Reason>):
  match input:
    case Fail{error}: IO.pure(DNS<Reason>, InvalidName{error})
    case Done{Text.Input{name, dots, absolute}}:
      do IO<DNS<Reason>>:
        report : Network.Report<Reason> <- Paired.lookupWith(~Environment, ~draw, ~Reason, environment, resolver, parent, priority, name, dots, absolute)
        return Completed{report}

type Context<-Environment: Data, -Reason: Data> is Data:
  Context{environment: Environment, resolver: Resolver.Resolver, parent: Abort.AbortSignal<Reason>, priority: Pair.Priority}

def requested(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, context: Context<Environment, Reason>, family: Family.Family, text: String) -> IO(DNS<Reason>):
  match context:
    case Context{environment, resolver, parent, priority}: network(~Environment, ~draw, ~Reason, environment, resolver, parent, priority, Text.prepare(text))

# Any local family satisfies files-first lookup. Preserve source order and
# duplicates; do not query DNS to fill in an absent family. Only a complete
# local miss starts paired DNS. Source failures and local hits bypass DNS text
# parsing, identifier draws, server rotation and deadline allocation.
def lookupWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, ~Error: Data, environment: Environment, resolver: Resolver.Resolver, parent: Abort.AbortSignal<Reason>, priority: Pair.Priority, name: String, source: Result<&2, &2, Error, List<&2, Hosts.Entry<File.Address>>>) -> IO(HostsResolve.Report<Error, DNS<Reason>>):
  HostsResolve.resolveWith(~Context<Environment, Reason>, ~Error, ~DNS<Reason>, ~requested(~Environment, ~draw, ~Reason), Context{environment, resolver, parent, priority}, Family.Any{}, name, source)

def lookup(~Reason: Data, ~Error: Data, resolver: Resolver.Resolver, parent: Abort.AbortSignal<Reason>, priority: Pair.Priority, name: String, source: Result<&2, &2, Error, List<&2, Hosts.Entry<File.Address>>>) -> IO(HostsResolve.Report<Error, DNS<Reason>>):
  lookupWith(~Unit, ~Id.random, ~Reason, ~Error, Unit{}, resolver, parent, priority, name, source)
