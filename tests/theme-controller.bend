import Base
import ../packages/coding-agent/src/modes/interactive/theme/theme-controller.bend as Controller
import ../packages/coding-agent/src/modes/interactive/theme/detection.bend as Detection
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme

def route(value: Controller.Route) -> String:
  match value:
    case Controller.Explicit{name}: "explicit:" ++ name
    case Controller.Automatic{_}: "auto"
    case Controller.Detect{}: "detect"
def setting(value: Maybe<&2,String>) -> String:
  match value:
    case None{}: "undefined"
    case Some{name}: name
def decision(+value: Maybe<&2,String>) -> IO(Unit):
  IO.print(setting(value) ++ "|" ++ route(Controller.route(value)) ++ "|" ++ Controller.selectedName(value,Detection.Dark{}) ++ "|" ++ Controller.selectedName(value,Detection.Light{}))
def loaded(result: Result<&2,&2,Theme.LoadError,Controller.Loaded>) -> String:
  match result:
    case Fail{_}: "fatal"
    case Done{Controller.Loaded{name,Theme.Theme{loadedName,_,_,_,_,_},error}}:
      name ++ ":" ++ loadedName ++ ":" ++ Bool.show(Bool.not(Maybe.is_none(&2,Theme.LoadError,error)))
def main() -> IO(Unit):
  do IO<Unit>:
    decision(None{})
    decision(Some{"light"})
    decision(Some{"light/dark"})
    decision(Some{"light/dark/extra"})
    decision(Some{"missing"})
    found : Result<&2,&2,Theme.LoadError,Controller.Loaded> <- Controller.load("light","packages/coding-agent/src/modes/interactive/theme","tests",Color.TrueColor{})
    IO.print("load-light:" ++ loaded(found))
    missing : Result<&2,&2,Theme.LoadError,Controller.Loaded> <- Controller.load("missing","packages/coding-agent/src/modes/interactive/theme","tests",Color.TrueColor{})
    IO.print("load-missing:" ++ loaded(missing))
