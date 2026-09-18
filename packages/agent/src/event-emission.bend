import Base

# Starting delivery and awaiting it are distinct. The emitter performs ordered
# enqueue/start effects before returning; listeners may finish concurrently.
# Pending delivery owns one receive and cannot be awaited twice.
type Emission<-Error: Data> is Type:
  Ready{outcome: Result<&2, &2, Error, Unit>}
  Pending{reply: Chan(Result<&2, &2, Error, Unit>)}

def start(-Error: Data, action: IO(Result<&2, &2, Error, Unit>)) -> IO(Emission<Error>):
  do IO<Emission<Error>>:
    reply : Chan(Result<&2, &2, Error, Unit>) <- IO.fork(Result<&2, &2, Error, Unit>, action)
    return Pending{reply}

def wait(-Error: Data, emission: Emission<Error>) -> IO(Result<&2, &2, Error, Unit>):
  match emission:
    case Ready{outcome}: IO.pure(Result<&2, &2, Error, Unit>, outcome)
    case Pending{reply}: IO.join(Result<&2, &2, Error, Unit>, reply)
