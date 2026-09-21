import Base
import ./callback.bend as C
import ./http-response-stream.bend as Stream

# Borrowed, reusable transport operations. Each invocation obtains a fresh
# affine closure; the caller retains ownership of both callback factories.
def Read(-E: Data, -State: Type) -> Data:
  C.Callback<State, State & Result<&2, &2, E, Maybe<&2, Stream.Event>>>

def Close(-E: Data, -State: Type) -> Data:
  C.Callback<State, Result<&2, &2, E, Unit>>

def read(-E: Data, -State: Type, callback: Read(E, State), state: State) -> IO(State & Result<&2, &2, E, Maybe<&2, Stream.Event>>):
  C.call(State, State & Result<&2, &2, E, Maybe<&2, Stream.Event>>, callback, state)

def close(-E: Data, -State: Type, callback: Close(E, State), state: State) -> IO(Result<&2, &2, E, Unit>):
  C.call(State, Result<&2, &2, E, Unit>, callback, state)

# Static-operation convenience: factories live for this entire IO operation,
# including recursive reads, and retire before its result is returned. The
# action borrows the handles; it must not return them or spawn escaping calls.
def with(~E: Data, ~State: Type, ~Output: Type, ~read: State -> IO(State & Result<&2, &2, E, Maybe<&2, Stream.Event>>), ~close: State -> IO(Result<&2, &2, E, Unit>), action: Read(E, State) -> Close(E, State) -> IO(Output)) -> IO(Output):
  do IO<Output>:
    +reader : Read(E, State) <- C.create(~Unit, ~State, ~(State & Result<&2, &2, E, Maybe<&2, Stream.Event>>), ~(unused => state => read(state)), Unit{})
    +closer : Close(E, State) <- C.create(~Unit, ~State, ~Result<&2, &2, E, Unit>, ~(unused => state => close(state)), Unit{})
    result : Output <- action(reader, closer)
    C.dispose(State, State & Result<&2, &2, E, Maybe<&2, Stream.Event>>, reader)
    C.dispose(State, Result<&2, &2, E, Unit>, closer)
    return result
