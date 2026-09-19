import Base
import ../../../runtime/src/random.bend as Random
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/callback.bend as C

# The callback borrows the generator. Dispose the callback before retiring its
# generator; it can be shared with other request loops using the same source.
def draw(generator: Random.Generator, unused: Unit) -> IO(F.F64):
  Random.random(generator)

def create(generator: Random.Generator) -> IO(C.Callback<Unit, F.F64>):
  C.create(~Random.Generator, ~Unit, ~F.F64, ~draw, generator)
