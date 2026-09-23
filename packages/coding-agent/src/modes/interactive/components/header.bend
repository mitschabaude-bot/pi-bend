import Base
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/ref.bend as Ref
import ../../../../../tui/src/component.bend as Component
import ../../../../../tui/src/components/text.bend as Text
import ../../../config.bend as Config
import ../theme/theme.bend as Theme

# The built-in header belongs to the scrollable document, but survives a
# transcript replacement. Expansion and theme changes are read at render time.
type Header is Data: Header{expanded: Ref.Ref<Bool>,theme: Ref.Ref<Theme.Theme>,quiet: Bool}
type Owner is Type: Owner{expanded: Ref.Ref<Bool>,component: Component.Component,render: Callback.Callback<Nat,List<&2,String>>,invalidate: Callback.Callback<Unit,Unit>}
type Handle is Data: Handle{expanded: Ref.Ref<Bool>}

def colorResult(result: Result<&2,&2,Theme.Error,String>) -> IO(String):
  match result:
    case Done{painted}: IO.pure(String,painted)
    case Fail{_}: IO.die(String,1,"invalid header theme color")
def colored(theme: Theme.Theme,key: String,text: String) -> IO(String):
  colorResult(Theme.foreground(theme,key,text))
def logo(+theme: Theme.Theme) -> IO(String):
  do IO<String>:
    name : String <- colored(theme,"accent","pi")
    version : String <- colored(theme,"dim"," v" ++ Config.version())
    return "\u{1b}[1m" ++ name ++ "\u{1b}[22m" ++ version
def compact(+theme: Theme.Theme,brand: String) -> IO(String):
  do IO<String>:
    hints : String <- colored(theme,"muted","escape interrupt · ctrl+c/ctrl+d clear/exit · / commands · ctrl+o more")
    more : String <- colored(theme,"dim","Press ctrl+o to show full startup help.")
    onboarding : String <- colored(theme,"dim","Pi can explain its own features and look up its docs. Ask it how to use or extend Pi.")
    return brand ++ "\n" ++ hints ++ "\n" ++ more ++ "\n\n" ++ onboarding
def expanded(+theme: Theme.Theme,brand: String) -> IO(String):
  do IO<String>:
    hints : String <- colored(theme,"muted","escape  interrupt\nctrl+c  clear · twice to exit\nctrl+d  exit with an empty editor\n/       commands\nctrl+o  compact startup help")
    onboarding : String <- colored(theme,"dim","Pi can explain its own features and look up its docs. Ask it how to use or extend Pi.")
    return brand ++ "\n" ++ hints ++ "\n\n" ++ onboarding
def rendered(pair: Text.Text & List<&2,String>) -> List<&2,String>:
  match pair: case (_,lines): lines
def draw(input: Header,width: Nat) -> IO(List<&2,String>):
  match input:
    case Header{state,theme,quiet}:
      match quiet:
        case True{}: IO.pure(List<&2,String>,Nil{})
        case False{}:
          do IO<List<&2,String>>:
            isExpanded : Bool <- Ref.read(Bool,state)
            +current : Theme.Theme <- Ref.read(Theme.Theme,theme)
            +brand : String <- logo(current)
            body : String <- Bool.pick(Unit -> IO(String),isExpanded,_ => expanded(current,brand),_ => compact(current,brand))(Unit{})
            pair : Text.Text & List<&2,String> <- Text.render(Text.new(body,Some{1n},Some{0n},None{}),width)
            return "" <> List.append(&2,String,rendered(pair),"" <> Nil{})
def ignore(_: Unit,_: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def create(theme: Ref.Ref<Theme.Theme>,quiet: Bool) -> IO(Owner):
  do IO<Owner>:
    +state : Ref.Ref<Bool> <- Ref.new(Bool,False{})
    +render : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Header,~Nat,~List<&2,String>,~draw,Header{state,theme,quiet})
    +invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~ignore,Unit{})
    return Owner{state,Component.Component{Component.ComponentId{90n},render,None{},None{},invalidate,None{},False{}},render,invalidate}
def borrow(owner: Owner) -> Owner & Component.Component & Handle:
  match owner:
    case Owner{+state,+component,render,invalidate}: (Owner{state,component,render,invalidate},component,Handle{state})
def toggle(handle: Handle) -> IO(Unit):
  match handle:
    case Handle{state}: Ref.modify(Bool,Unit,state,previous => (Bool.not(previous),Unit{}))
def dispose(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{state,_,render,invalidate}:
      do IO<Unit>:
        Callback.dispose(Nat,List<&2,String>,render)
        Callback.dispose(Unit,Unit,invalidate)
        previous : Bool <- Ref.dispose(Bool,state)
        return Unit{}
