import Base
import ./openai-responses-prepare.bend as Preparation
import ../../../runtime/src/http-response.bend as Response

# Successful acquisition carries the preparation that produced the request.
# Processing needs its grammar mapping even if onPayload replaced the body.
type Owner<-State: Type> is Type:
  Owner{prepared: Preparation.Prepared, response: Response.Response<State>}

def acquired(-E: Data, -State: Type, prepared: Preparation.Prepared, result: Result<&2, &1, E, Response.Response<State>>) -> Result<&2, &1, E, Owner<State>>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{response}: Done{Owner{prepared, response}}

def prepared(-E: Data, -State: Type, embed: Preparation.Error -> E, acquire: Preparation.Prepared -> IO(Result<&2, &1, E, Response.Response<State>>), result: Result<&2, &2, Preparation.Error, Preparation.Prepared>) -> IO(Result<&2, &1, E, Owner<State>>):
  match result:
    case Fail{cause}: IO.pure(Result<&2, &1, E, Owner<State>>, Fail{embed(cause)})
    case Done{+value}:
      do IO<Result<&2, &1, E, Owner<State>>>:
        response : Result<&2, &1, E, Response.Response<State>> <- acquire(value)
        return acquired(E, State, value, response)

# Pass this IO program to the session producer. Preparation failures then
# settle the same event stream as transport failures, without calling fetch.
def run(-E: Data, -State: Type, prepare: IO(Result<&2, &2, Preparation.Error, Preparation.Prepared>), embed: Preparation.Error -> E, acquire: Preparation.Prepared -> IO(Result<&2, &1, E, Response.Response<State>>)) -> IO(Result<&2, &1, E, Owner<State>>):
  do IO<Result<&2, &1, E, Owner<State>>>:
    value : Result<&2, &2, Preparation.Error, Preparation.Prepared> <- prepare
    prepared(E, State, embed, acquire, value)

def release(-E: Data, -State: Type, retire: Response.Response<State> -> IO(Result<&2, &2, E, Unit>), owner: Owner<State>) -> IO(Result<&2, &2, E, Unit>):
  match owner:
    case Owner{_, response}: retire(response)
