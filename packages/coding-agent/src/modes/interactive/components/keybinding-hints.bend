import Base
import ../../../../../tui/src/keybindings.bend as Bindings
import ../../../../../tui/src/keys.bend as Keys
import ../theme/theme.bend as Theme

def capitalized(part: String) -> String:
  match part:
    case SNil{}: ""
    case SCon{first,rest}: String.to_upper(SCon{first,SNil{}}) ++ rest
def shown(part: String,capitalize: Bool) -> String:
  match capitalize:
    case True{}: capitalized(part)
    case False{}: part
def parts(values: List<&2,String>,+capitalize: Bool) -> List<&2,String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: shown(value,capitalize) <> parts(rest,capitalize)
def alternatives(values: List<&2,String>,+capitalize: Bool) -> List<&2,String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: String.join(parts(String.split(value,'+'),capitalize),"+") <> alternatives(rest,capitalize)
def formatKeyText(key: String,capitalize: Bool) -> String:
  String.join(alternatives(String.split(key,'/'),capitalize),"/")
def formatted(keys: List<&2,Keys.KeyId>,+capitalize: Bool) -> List<&2,String>:
  match keys:
    case Nil{}: Nil{}
    case key <> rest: formatKeyText(Keys.formatKeyId(key),capitalize) <> formatted(rest,capitalize)
def keyText(bindings: Bindings.KeybindingsManager,action: String) -> String:
  String.join(formatted(Bindings.getKeys(bindings,action),False{}),"/")
def keyDisplayText(bindings: Bindings.KeybindingsManager,action: String) -> String:
  String.join(formatted(Bindings.getKeys(bindings,action),True{}),"/")
def color(theme: Theme.Theme,key: String,+value: String) -> String:
  Result.default(&2,&2,Theme.Error,String,Theme.foreground(theme,key,value),value)
def rawKeyHint(+theme: Theme.Theme,key: String,description: String) -> String:
  color(theme,"dim",formatKeyText(key,False{})) ++ color(theme,"muted"," " ++ description)
def keyHint(+theme: Theme.Theme,bindings: Bindings.KeybindingsManager,action: String,description: String) -> String:
  rawKeyHint(theme,keyText(bindings,action),description)
