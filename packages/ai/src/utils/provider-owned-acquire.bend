import Base

# Preparation (including payload hooks) precedes runtime initialization. A
# successful response and the runtime it borrows travel as one affine owner.
type Error<-Initialization: Data, -Request: Data> is Data:
  InitializationFailure{cause: Initialization}
  AcquisitionFailure{cause: Request}

type Owner<-Runtime: Type, -Response: Type> is Type:
  Owner{runtime: Runtime, response: Response}

def completed(-Initialization: Data, -E: Data, -Runtime: Type, -Response: Type, retire: Runtime -> IO(Unit), pair: Runtime & Result<&2, &1, E, Response>) -> IO(Result<&2, &1, Error<Initialization, E>, Owner<Runtime, Response>>):
  match pair:
    case Tuple{runtime, Fail{cause}}:
      do IO<Result<&2, &1, Error<Initialization, E>, Owner<Runtime, Response>>>:
        retire(runtime)
        return Fail{AcquisitionFailure{cause}}
    case Tuple{runtime, Done{response}}:
      IO.pure(Result<&2, &1, Error<Initialization, E>, Owner<Runtime, Response>>, Done{Owner{runtime, response}})

# The attempt lends handles from its runtime and returns that same ownership
# alongside its result. No mutable cell is needed to recover it after failure.
def initialized(-P: Data, -Initialization: Data, -E: Data, -Runtime: Type, -Response: Type, payload: P, acquire: P -> Runtime -> IO(Runtime & Result<&2, &1, E, Response>), retire: Runtime -> IO(Unit), result: Result<&2, &1, Initialization, Runtime>) -> IO(Result<&2, &1, Error<Initialization, E>, Owner<Runtime, Response>>):
  match result:
    case Fail{cause}: IO.pure(Result<&2, &1, Error<Initialization, E>, Owner<Runtime, Response>>, Fail{InitializationFailure{cause}})
    case Done{runtime}:
      do IO<Result<&2, &1, Error<Initialization, E>, Owner<Runtime, Response>>>:
        pair : Runtime & Result<&2, &1, E, Response> <- acquire(payload, runtime)
        completed(Initialization, E, Runtime, Response, retire, pair)

def prepared(-P: Data, -Initialization: Data, -E: Data, -Runtime: Type, -Response: Type, initialize: IO(Result<&2, &1, Initialization, Runtime>), acquire: P -> Runtime -> IO(Runtime & Result<&2, &1, E, Response>), retire: Runtime -> IO(Unit), result: Result<&2, &2, E, P>) -> IO(Result<&2, &1, Error<Initialization, E>, Owner<Runtime, Response>>):
  match result:
    case Fail{cause}: IO.pure(Result<&2, &1, Error<Initialization, E>, Owner<Runtime, Response>>, Fail{AcquisitionFailure{cause}})
    case Done{payload}:
      do IO<Result<&2, &1, Error<Initialization, E>, Owner<Runtime, Response>>>:
        runtime : Result<&2, &1, Initialization, Runtime> <- initialize
        initialized(P, Initialization, E, Runtime, Response, payload, acquire, retire, runtime)

def run(-P: Data, -Initialization: Data, -E: Data, -Runtime: Type, -Response: Type, prepare: IO(Result<&2, &2, E, P>), initialize: IO(Result<&2, &1, Initialization, Runtime>), acquire: P -> Runtime -> IO(Runtime & Result<&2, &1, E, Response>), retire: Runtime -> IO(Unit)) -> IO(Result<&2, &1, Error<Initialization, E>, Owner<Runtime, Response>>):
  do IO<Result<&2, &1, Error<Initialization, E>, Owner<Runtime, Response>>>:
    result : Result<&2, &2, E, P> <- prepare
    prepared(P, Initialization, E, Runtime, Response, initialize, acquire, retire, result)

# Response retirement can fail. Runtime retirement still follows it before
# returning the original close result, so no borrower outlives its dependency.
def release(-E: Data, -Runtime: Type, -Response: Type, close: Response -> IO(Result<&2, &2, E, Unit>), retire: Runtime -> IO(Unit), owner: Owner<Runtime, Response>) -> IO(Result<&2, &2, E, Unit>):
  match owner:
    case Owner{runtime, response}:
      do IO<Result<&2, &2, E, Unit>>:
        result : Result<&2, &2, E, Unit> <- close(response)
        retire(runtime)
        return result
