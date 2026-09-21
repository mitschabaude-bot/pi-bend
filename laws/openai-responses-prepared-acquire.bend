import Base
import ../packages/ai/src/api/openai-responses-prepared-acquire.bend as Acquire
import ../packages/ai/src/api/openai-responses-prepare.bend as Preparation
import ../packages/runtime/src/http-response.bend as Response

law preparation_failure_never_acquires:
  for -E: Data
  for -State: Type
  for embed: Preparation.Error -> E
  for acquire: Preparation.Prepared -> IO(Result<&2, &1, E, Response.Response<State>>)
  for cause: Preparation.Error
  {Acquire.prepared(E, State, embed, acquire, Fail{cause}) == IO.pure(Result<&2, &1, E, Acquire.Owner<State>>, Fail{embed(cause)}) : IO(Result<&2, &1, E, Acquire.Owner<State>>)}

law successful_acquisition_retains_preparation_and_response:
  for -E: Data
  for -State: Type
  for prepared: Preparation.Prepared
  for response: Response.Response<State>
  {Acquire.acquired(E, State, prepared, Done{response}) == Done{Acquire.Owner{prepared, response}} : Result<&2, &1, E, Acquire.Owner<State>>}

law acquisition_failure_is_unchanged:
  for -E: Data
  for -State: Type
  for prepared: Preparation.Prepared
  for cause: E
  {Acquire.acquired(E, State, prepared, Fail{cause}) == Fail{cause} : Result<&2, &1, E, Acquire.Owner<State>>}

law release_transfers_the_original_response:
  for -E: Data
  for -State: Type
  for retire: Response.Response<State> -> IO(Result<&2, &2, E, Unit>)
  for prepared: Preparation.Prepared
  for response: Response.Response<State>
  {Acquire.release(E, State, retire, Acquire.Owner{prepared, response}) == retire(response) : IO(Result<&2, &2, E, Unit>)}
