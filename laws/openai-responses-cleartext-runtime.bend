import Base
import ../packages/ai/src/utils/provider-retry.bend as Effects
import ../packages/ai/src/api/openai-responses-fetch.bend as Input
import ../packages/ai/src/api/openai-responses-cleartext-attempt.bend as Attempt
import ../packages/ai/src/api/openai-responses-cleartext-runtime.bend as Runtime
import ../packages/ai/src/utils/provider-retry-runtime.bend as Retry
import ../packages/runtime/src/dns-resolver.bend as Resolver
import ../packages/runtime/src/http-resolved-exchange.bend as HTTP
import ../packages/runtime/src/hosts.bend as Hosts
import ../packages/runtime/src/hosts-file.bend as File
import ../packages/runtime/src/random-index.bend as Index
import ../packages/runtime/src/random-seed.bend as Seed
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/f64.bend as F

law resolver_failure_does_not_allocate_dependencies:
  for hosts: Result<&2, &2, File.Failure, List<&2, Hosts.Entry<File.Address>>>
  for options: HTTP.Options
  for date: C.Callback<String, F.F64>
  for cause: Index.Error
  {Runtime.initialized(~String, ~File.Failure, hosts, options, date, Fail{cause}) == IO.pure(Result<&2, &1, Runtime.Error, Runtime.Owner<String, File.Failure>>, Fail{Runtime.ResolverFailure{cause}}) : IO(Result<&2, &1, Runtime.Error, Runtime.Owner<String, File.Failure>>)}

law retry_failure_retires_resolver_before_returning_cause:
  for hosts: Result<&2, &2, File.Failure, List<&2, Hosts.Entry<File.Address>>>
  for options: HTTP.Options
  for resolver: Resolver.Owner
  for cause: Seed.SeedError
  {Runtime.retryInitialized(~String, ~File.Failure, hosts, options, resolver, Fail{cause}) == IO.bind(Unit, Result<&2, &1, Runtime.Error, Runtime.Owner<String, File.Failure>>, Resolver.close(resolver), ignored => IO.pure(Result<&2, &1, Runtime.Error, Runtime.Owner<String, File.Failure>>, Fail{Runtime.RetryFailure{cause}})) : IO(Result<&2, &1, Runtime.Error, Runtime.Owner<String, File.Failure>>)}

law borrowing_preserves_fetch_and_retry_handles:
  for -Reason: Data
  for -Source: Data
  for resolver: Resolver.Owner
  for fetch: Runtime.Callback(Reason, Source)
  for retry: Retry.Runtime<Reason>
  for effects: Effects.Effects<Reason>
  {Runtime.borrowed(Reason, Source, resolver, fetch, (retry, effects)) == (Runtime.Owner{resolver, fetch, retry}, Runtime.Borrowed{fetch, effects}) : Runtime.Owner<Reason, Source> & Runtime.Borrowed<Reason, Source>}

law fetch_retires_before_retry_and_resolver:
  for -Reason: Data
  for -Source: Data
  for resolver: Resolver.Owner
  for fetch: Runtime.Callback(Reason, Source)
  for retry: Retry.Runtime<Reason>
  {Runtime.dispose(Reason, Source, Runtime.Owner{resolver, fetch, retry}) == IO.bind(Unit, Unit, C.dispose(Input.Input<Reason>, Attempt.FetchResult(Reason, Source), fetch), ignored => IO.bind(Unit, Unit, Retry.dispose(Reason, retry), ignored => Resolver.close(resolver))) : IO(Unit)}
