import Base
import ./openai-responses-cleartext-fetch.bend as Fetch
import ./openai-responses-cleartext-attempt.bend as Attempt
import ./openai-responses-fetch.bend as Input
import ../utils/provider-retry.bend as Retry
import ../utils/provider-retry-runtime.bend as RetryRuntime
import ../../../runtime/src/dns-resolver.bend as Resolver
import ../../../runtime/src/resolver-configuration.bend as Settings
import ../../../runtime/src/socket-endpoint.bend as Endpoint
import ../../../runtime/src/http-resolved-exchange.bend as HTTP
import ../../../runtime/src/hosts.bend as Hosts
import ../../../runtime/src/hosts-file.bend as File
import ../../../runtime/src/random-index.bend as Index
import ../../../runtime/src/random-seed.bend as Seed
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/f64.bend as F

def Callback(-Reason: Data, -Source: Data) -> Data:
  C.Callback<Input.Input<Reason>, Attempt.FetchResult(Reason, Source)>

type Error is Data:
  ResolverFailure{cause: Index.Error}
  RetryFailure{cause: Seed.SeedError}

type Borrowed<-Reason: Data, -Source: Data> is Data:
  Borrowed{fetch: Callback(Reason, Source), retry: Retry.Effects<Reason>}

type Owner<-Reason: Data, -Source: Data> is Type:
  Owner{resolver: Resolver.Owner, fetch: Callback(Reason, Source), retry: RetryRuntime.Runtime<Reason>}

# Fetch must retire before its borrowed resolver; retry callbacks have the
# same request lifetime. The date parser belongs to the caller throughout.
def dispose(-Reason: Data, -Source: Data, owner: Owner<Reason, Source>) -> IO(Unit):
  match owner:
    case Owner{resolver, fetch, retry}:
      do IO<Unit>:
        C.dispose(Input.Input<Reason>, Attempt.FetchResult(Reason, Source), fetch)
        RetryRuntime.dispose(Reason, retry)
        Resolver.close(resolver)

def borrowed(-Reason: Data, -Source: Data, resolver: Resolver.Owner, +fetch: Callback(Reason, Source), pair: RetryRuntime.Runtime<Reason> & Retry.Effects<Reason>) -> Owner<Reason, Source> & Borrowed<Reason, Source>:
  match pair:
    case Tuple{retry, effects}: (Owner{resolver, fetch, retry}, Borrowed{fetch, effects})

def borrow(-Reason: Data, -Source: Data, owner: Owner<Reason, Source>) -> Owner<Reason, Source> & Borrowed<Reason, Source>:
  match owner:
    case Owner{resolver, fetch, retry}: borrowed(Reason, Source, resolver, fetch, RetryRuntime.borrow(Reason, retry))

def ready(~Reason: Data, ~Source: Data, hosts: Result<&2, &2, Source, List<&2, Hosts.Entry<File.Address>>>, options: HTTP.Options, retry: RetryRuntime.Runtime<Reason>, pair: Resolver.Owner & Resolver.Resolver) -> IO(Result<&2, &1, Error, Owner<Reason, Source>>):
  match pair:
    case Tuple{owner, resolver}:
      do IO<Result<&2, &1, Error, Owner<Reason, Source>>>:
        fetch : Callback(Reason, Source) <- Fetch.create(~Reason, ~Source, Fetch.Context{resolver, hosts, options})
        return Done{Owner{owner, fetch, retry}}

# On partial initialization failure, consume and retire the resolver before
# reporting the original seed error. No fetch callback exists on that path.
def retryInitialized(~Reason: Data, ~Source: Data, hosts: Result<&2, &2, Source, List<&2, Hosts.Entry<File.Address>>>, options: HTTP.Options, resolver: Resolver.Owner, result: Result<&2, &1, Seed.SeedError, RetryRuntime.Runtime<Reason>>) -> IO(Result<&2, &1, Error, Owner<Reason, Source>>):
  match result:
    case Fail{cause}:
      do IO<Result<&2, &1, Error, Owner<Reason, Source>>>:
        Resolver.close(resolver)
        return Fail{RetryFailure{cause}}
    case Done{retry}: ready(~Reason, ~Source, hosts, options, retry, Resolver.borrow(resolver))

def initialized(~Reason: Data, ~Source: Data, hosts: Result<&2, &2, Source, List<&2, Hosts.Entry<File.Address>>>, options: HTTP.Options, date: C.Callback<String, F.F64>, result: Result<&2, &1, Index.Error, Resolver.Owner>) -> IO(Result<&2, &1, Error, Owner<Reason, Source>>):
  match result:
    case Fail{cause}: IO.pure(Result<&2, &1, Error, Owner<Reason, Source>>, Fail{ResolverFailure{cause}})
    case Done{owner}:
      do IO<Result<&2, &1, Error, Owner<Reason, Source>>>:
        retry : Result<&2, &1, Seed.SeedError, RetryRuntime.Runtime<Reason>> <- RetryRuntime.new(~Reason, date)
        retryInitialized(~Reason, ~Source, hosts, options, owner, retry)

def create(~Reason: Data, ~Source: Data, config: Settings.Config<Endpoint.Endpoint>, hosts: Result<&2, &2, Source, List<&2, Hosts.Entry<File.Address>>>, options: HTTP.Options, date: C.Callback<String, F.F64>) -> IO(Result<&2, &1, Error, Owner<Reason, Source>>):
  do IO<Result<&2, &1, Error, Owner<Reason, Source>>>:
    resolver : Result<&2, &1, Index.Error, Resolver.Owner> <- Resolver.create(config)
    initialized(~Reason, ~Source, hosts, options, date, resolver)
