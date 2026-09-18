import Base
import ./ref.bend as R

# A duplicable callback handle. Each call obtains its own affine closure;
# captured Data (including Ref handles) retains normal shared identity.
type Factory<-A: Type> is Type:
  Factory{next: Unit -> Factory<A> & A}

type Callback<-Input: Type, -Output: Type> is Data:
  Callback{factory: R.Ref<Factory<(Input -> IO(Output))>>}

# Two factories with identical code/captures are still distinct callbacks.
def same(-Input: Type, -Output: Type, left: Callback<Input, Output>, right: Callback<Input, Output>) -> Bool:
  match left right:
    case Callback{a} Callback{b}: R.same(Factory<(Input -> IO(Output))>, a, b)

# Guarded corecursion: constructing a factory constructs one closure, without
# running it. A call constructs exactly one successor. There is no background
# task, fuel limit or eager infinite structure. Bend's structural termination
# checker cannot express this productivity argument, hence the local @unsafe.
@unsafe def factory(~Environment: Data, ~A: Type, ~make: Environment -> A, +environment: Environment) -> Factory<A>:
  Factory{unused => (factory(~Environment, ~A, ~make, environment), make(environment))}

def create(~Environment: Data, ~Input: Type, ~Output: Type, ~body: Environment -> Input -> IO(Output), environment: Environment) -> IO(Callback<Input, Output>):
  do IO<Callback<Input, Output>>:
    state : R.Ref<Factory<(Input -> IO(Output))>> <- R.new(Factory<(Input -> IO(Output))>, factory(~Environment, ~(Input -> IO(Output)), ~body, environment))
    return Callback{state}

def acquire(-A: Type, source: Factory<A>) -> Factory<A> & A:
  match source:
    case Factory{next}: next(Unit{})

def call(-Input: Type, -Output: Type, callback: Callback<Input, Output>, argument: Input) -> IO(Output):
  match callback:
    case Callback{state}:
      do IO<Output>:
        invoke : (Input -> IO(Output)) <- R.modify(Factory<(Input -> IO(Output))>, Input -> IO(Output), state, source => acquire(Input -> IO(Output), source))
        # The factory is already released. User code may await or re-enter.
        invoke(argument)

def dispose(-Input: Type, -Output: Type, callback: Callback<Input, Output>) -> IO(Unit):
  match callback:
    case Callback{state}:
      do IO<Unit>:
        source : Factory<(Input -> IO(Output))> <- R.dispose(Factory<(Input -> IO(Output))>, state)
        return Unit{}
