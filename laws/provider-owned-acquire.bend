import Base
import ../packages/ai/src/utils/provider-owned-acquire.bend as A

law preparation_failure_skips_initialization:
  for -P: Data
  for -Initialization: Data
  for -E: Data
  for -Runtime: Type
  for -Response: Type
  for initialize: IO(Result<&2, &1, Initialization, Runtime>)
  for acquire: P -> Runtime -> IO(Runtime & Result<&2, &1, E, Response>)
  for retire: Runtime -> IO(Unit)
  for cause: E
  {A.prepared(P, Initialization, E, Runtime, Response, initialize, acquire, retire, Fail{cause}) == IO.pure(Result<&2, &1, A.Error<Initialization, E>, A.Owner<Runtime, Response>>, Fail{A.AcquisitionFailure{cause}}) : IO(Result<&2, &1, A.Error<Initialization, E>, A.Owner<Runtime, Response>>)}

law initialization_failure_skips_acquisition:
  for -P: Data
  for -Initialization: Data
  for -E: Data
  for -Runtime: Type
  for -Response: Type
  for payload: P
  for acquire: P -> Runtime -> IO(Runtime & Result<&2, &1, E, Response>)
  for retire: Runtime -> IO(Unit)
  for cause: Initialization
  {A.initialized(P, Initialization, E, Runtime, Response, payload, acquire, retire, Fail{cause}) == IO.pure(Result<&2, &1, A.Error<Initialization, E>, A.Owner<Runtime, Response>>, Fail{A.InitializationFailure{cause}}) : IO(Result<&2, &1, A.Error<Initialization, E>, A.Owner<Runtime, Response>>)}

law acquisition_failure_retires_runtime_before_return:
  for -Initialization: Data
  for -E: Data
  for -Runtime: Type
  for -Response: Type
  for retire: Runtime -> IO(Unit)
  for runtime: Runtime
  for cause: E
  {A.completed(Initialization, E, Runtime, Response, retire, (runtime, Fail{cause})) == IO.bind(Unit, Result<&2, &1, A.Error<Initialization, E>, A.Owner<Runtime, Response>>, retire(runtime), ignored => IO.pure(Result<&2, &1, A.Error<Initialization, E>, A.Owner<Runtime, Response>>, Fail{A.AcquisitionFailure{cause}})) : IO(Result<&2, &1, A.Error<Initialization, E>, A.Owner<Runtime, Response>>)}

law success_transfers_runtime_and_response:
  for -Initialization: Data
  for -E: Data
  for -Runtime: Type
  for -Response: Type
  for retire: Runtime -> IO(Unit)
  for runtime: Runtime
  for response: Response
  {A.completed(Initialization, E, Runtime, Response, retire, (runtime, Done{response})) == IO.pure(Result<&2, &1, A.Error<Initialization, E>, A.Owner<Runtime, Response>>, Done{A.Owner{runtime, response}}) : IO(Result<&2, &1, A.Error<Initialization, E>, A.Owner<Runtime, Response>>)}

law response_close_precedes_runtime_retirement:
  for -E: Data
  for -Runtime: Type
  for -Response: Type
  for close: Response -> IO(Result<&2, &2, E, Unit>)
  for retire: Runtime -> IO(Unit)
  for runtime: Runtime
  for response: Response
  {A.release(E, Runtime, Response, close, retire, A.Owner{runtime, response}) == IO.bind(Result<&2, &2, E, Unit>, Result<&2, &2, E, Unit>, close(response), result => IO.bind(Unit, Result<&2, &2, E, Unit>, retire(runtime), ignored => IO.pure(Result<&2, &2, E, Unit>, result))) : IO(Result<&2, &2, E, Unit>)}
