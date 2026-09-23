import Base
import ../packages/runtime/src/random.bend as Random
import ../packages/tui/src/terminal-image.bend as I
import ../packages/runtime/src/record.bend as R

def state(value: Result<&2,&2,I.Error,I.State>) -> I.State:
  match value:
    case Done{value}: value
    case Fail{_}: I.create()
def environment() -> I.Environment: I.Environment{R.set(String,R.new(String),"TMUX","x"),"linux","/test"}
def caps(pair: I.State & I.TerminalCapabilities) -> I.TerminalCapabilities:
  match pair:
    case (_,value): value
def cached(pair: I.State & I.TerminalCapabilities) -> I.State:
  match pair:
    case (value,_): value
def links(value: I.TerminalCapabilities) -> Bool:
  match value:
    case I.TerminalCapabilities{_,_,value}: value
def generation(value: Maybe<&2,I.KittyImagePlacement>) -> Nat:
  match value:
    case None{}: 0n
    case Some{I.KittyImagePlacement{_,value,_,_,_,_}}: value
def add(remaining: Nat,+id: U32,current: I.State) -> I.State:
  match remaining:
    case 0n: current
    case 1n+rest: add(rest,(id+1:U32),state(I.registerKittyImageMetadata(current,I.KittyImageMetadata{id,1n,1n,1,1})))
def check(name: String,value: Bool) -> IO(Unit):
  match value:
    case True{}: IO.print("ok " ++ name)
    case False{}: IO.die(Unit,1,"failed " ++ name)
def validId(value: Result<&2,&2,Random.Error,U32>) -> Bool:
  match value:
    case Fail{_}: False{}
    case Done{+id}: U32.is_gt(id,0) && U32.is_lt(id,4294967295)
def allocate(remaining: Nat) -> IO(Bool):
  match remaining:
    case 0n: IO.pure(Bool,True{})
    case 1n+rest:
      do IO<Bool>:
        value : Result<&2,&2,Random.Error,U32> <- I.allocateImageId()
        Bool.pick(Unit -> IO(Bool),validId(value),_ => allocate(rest),_ => IO.pure(Bool,False{}))(Unit{})
def checks() -> IO(Unit):
  do IO<Unit>:
    +initial : I.State = I.create()
    check("tmux needs probe",I.needsTmuxProbe(initial,environment()))
    +detected : I.State = cached(I.getCapabilities(initial,environment(),True{}))
    check("cache bypasses probe",Bool.not(I.needsTmuxProbe(detected,environment())))
    check("cache survives changed probe",links(caps(I.getCapabilities(detected,environment(),False{}))))
    +same : I.State = I.setCapabilityOverrides(detected,I.noOverrides())
    check("equal overrides keep cache",Bool.not(I.needsTmuxProbe(same,environment())))
    +overridden : I.State = I.setCapabilityOverrides(same,I.CapabilityOverrides{None{},None{},Some{False{}}})
    check("explicit override bypasses probe",Bool.not(I.needsTmuxProbe(overridden,environment())))
    check("explicit false wins",Bool.not(links(caps(I.getCapabilities(overridden,environment(),True{})))))
    +cleared : I.State = I.setCapabilityOverrides(overridden,I.noOverrides())
    check("cleared override reopens probe",I.needsTmuxProbe(cleared,environment()))
    check("reset reopens probe",I.needsTmuxProbe(I.resetCapabilitiesCache(detected),environment()))
    +populated : I.State = add(1000n,1,I.create())
    +renewed : I.State = state(I.registerKittyImageMetadata(populated,I.KittyImageMetadata{1,2n,3n,4,5}))
    +evicted : I.State = add(1n,1001,renewed)
    check("registry evicts oldest",Maybe.is_none(&2,I.KittyImageMetadata,I.getKittyImageMetadata(evicted,"\u{1b}_Gi=2;AAAA\u{1b}\\")))
    check("re-registration retains id",Bool.not(Maybe.is_none(&2,I.KittyImageMetadata,I.getKittyImageMetadata(evicted,"\u{1b}_Gi=1;AAAA\u{1b}\\"))))
    check("generation changes on replacement",Nat.is_eq(generation(I.getKittyImagePlacement(evicted,"\u{1b}_Gi=1;AAAA\u{1b}\\")),1001n))
    check("generation on new id",Nat.is_eq(generation(I.getKittyImagePlacement(evicted,"\u{1b}_Gi=1001;AAAA\u{1b}\\")),1002n))
    check("no placement before complete transmission",Maybe.is_none(&2,I.KittyImagePlacement,I.getKittyImagePlacement(evicted,"\u{1b}_Gi=1,m=1;AAAA\u{1b}\\")))
    check("retained old state immutable",Bool.not(Maybe.is_none(&2,I.KittyImageMetadata,I.getKittyImageMetadata(populated,"\u{1b}_Gi=2;AAAA\u{1b}\\"))))
    ids : Bool <- allocate(32n)
    check("allocated ids stay in source range",ids)
def run(args: List<String>) -> IO(Unit):
  match args:
    case "probe" <> cwd <> Nil{}:
      do IO<Unit>:
        env : List<String> <- IO.environment()
        result : Bool <- I.probeTmuxHyperlinks(cwd,env)
        IO.print(Bool.pick(String,result,"true","false"))
    case _: checks()
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
