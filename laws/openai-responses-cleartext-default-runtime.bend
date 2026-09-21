import Base
import ../packages/ai/src/api/openai-responses-cleartext-default-runtime.bend as Default
import ../packages/ai/src/api/openai-responses-cleartext-runtime.bend as Runtime
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/f64.bend as F

law initialization_failure_retires_date_before_returning_cause:
  for -Reason: Data
  for -Source: Data
  for date: C.Callback<String, F.F64>
  for cause: Runtime.Error
  {Default.initialized(Reason, Source, date, Fail{cause}) == IO.bind(Unit, Result<&2, &1, Runtime.Error, Default.Owner<Reason, Source>>, C.dispose(String, F.F64, date), ignored => IO.pure(Result<&2, &1, Runtime.Error, Default.Owner<Reason, Source>>, Fail{cause})) : IO(Result<&2, &1, Runtime.Error, Default.Owner<Reason, Source>>)}

law initialization_success_transfers_both_owners:
  for -Reason: Data
  for -Source: Data
  for date: C.Callback<String, F.F64>
  for runtime: Runtime.Owner<Reason, Source>
  {Default.initialized(Reason, Source, date, Done{runtime}) == IO.pure(Result<&2, &1, Runtime.Error, Default.Owner<Reason, Source>>, Done{Default.Owner{date, runtime}}) : IO(Result<&2, &1, Runtime.Error, Default.Owner<Reason, Source>>)}

law borrow_preserves_owners_and_dependencies:
  for -Reason: Data
  for -Source: Data
  for date: C.Callback<String, F.F64>
  for runtime: Runtime.Owner<Reason, Source>
  for dependencies: Runtime.Borrowed<Reason, Source>
  {Default.borrowed(Reason, Source, date, (runtime, dependencies)) == (Default.Owner{date, runtime}, dependencies) : Default.Owner<Reason, Source> & Runtime.Borrowed<Reason, Source>}

law retry_runtime_retires_before_date_callback:
  for -Reason: Data
  for -Source: Data
  for date: C.Callback<String, F.F64>
  for runtime: Runtime.Owner<Reason, Source>
  {Default.dispose(Reason, Source, Default.Owner{date, runtime}) == IO.bind(Unit, Unit, Runtime.dispose(Reason, Source, runtime), ignored => C.dispose(String, F.F64, date)) : IO(Unit)}
