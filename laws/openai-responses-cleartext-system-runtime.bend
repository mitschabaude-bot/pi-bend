import Base
import ../packages/ai/src/api/openai-responses-cleartext-system-runtime.bend as System
import ../packages/ai/src/api/openai-responses-cleartext-default-runtime.bend as Default
import ../packages/ai/src/api/openai-responses-cleartext-runtime.bend as Runtime
import ../packages/runtime/src/resolver-system-config.bend as Configuration
import ../packages/runtime/src/utf8-strict.bend as UTF8
import ../packages/runtime/src/http-resolved-exchange.bend as HTTP

law resolver_failure_skips_hosts_loading:
  for files: System.Files
  for cause: Configuration.Error<UTF8.Error>
  {System.loaded(files, Fail{cause}) == IO.pure(Result<&2, &2, System.Error, System.Snapshot>, Fail{System.ConfigurationFailure{cause}}) : IO(Result<&2, &2, System.Error, System.Snapshot>)}

law configuration_failure_allocates_no_runtime:
  for options: HTTP.Options
  for cause: System.Error
  {System.configured(~String, options, Fail{cause}) == IO.pure(Result<&2, &1, System.Error, System.Owner<String>>, Fail{cause}) : IO(Result<&2, &1, System.Error, System.Owner<String>>)}

law initialization_failure_retains_cause:
  for -Reason: Data
  for snapshot: System.Snapshot
  for cause: Runtime.Error
  {System.initialized(Reason, snapshot, Fail{cause}) == Fail{System.InitializationFailure{cause}} : Result<&2, &1, System.Error, System.Owner<Reason>>}

law initialized_owner_retains_full_snapshot:
  for -Reason: Data
  for snapshot: System.Snapshot
  for runtime: Default.Owner<Reason, System.SourceError()>
  {System.initialized(Reason, snapshot, Done{runtime}) == Done{System.Owner{snapshot, runtime}} : Result<&2, &1, System.Error, System.Owner<Reason>>}

law borrowing_retains_snapshot_and_dependencies:
  for -Reason: Data
  for snapshot: System.Snapshot
  for runtime: Default.Owner<Reason, System.SourceError()>
  for dependencies: Runtime.Borrowed<Reason, System.SourceError()>
  {System.borrowed(Reason, snapshot, (runtime, dependencies)) == (System.Owner{snapshot, runtime}, dependencies) : System.Owner<Reason> & Runtime.Borrowed<Reason, System.SourceError()>}
