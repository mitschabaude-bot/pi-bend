import Base
import ../../modes/interactive/components/messages.bend as Messages
import ../../modes/interactive/theme/theme.bend as Theme
import ../../../../runtime/src/schema-value.bend as Value
import ../../../../runtime/src/record.bend as Record

# Shared terminal presentation for built-in file tools. Tool arguments are
# schema values at the model boundary; result details stay typed.
def field(args: Value.Value,key: String) -> Maybe<&2,Value.Value>:
  match args:
    case Value.ObjectValue{record}: Record.get(Value.Value,record,key)
    case _: None{}
def string(value: Maybe<&2,Value.Value>) -> Maybe<&2,String>:
  match value:
    case None{}: Some{""}
    case Some{Value.Null{}}: Some{""}
    case Some{Value.Text{text}}: Some{text}
    case _: None{}
def argument(args: Value.Value,key: String) -> Maybe<&2,String>:
  string(field(args,key))
def filePath(file: Maybe<&2,Value.Value>,path: Maybe<&2,Value.Value>) -> Maybe<&2,String>:
  match file:
    case Some{Value.Text{text}}: Some{text}
    case _: string(path)
def path(+args: Value.Value) -> Maybe<&2,String>:
  filePath(field(args,"file_path"),field(args,"path"))
def shownPath(theme: Theme.Theme,value: Maybe<&2,String>) -> IO(String):
  match value:
    case None{}: Messages.foregroundText(theme,"error","[invalid arg]")
    case Some{""}: Messages.foregroundText(theme,"toolOutput","...")
    case Some{text}: Messages.foregroundText(theme,"accent",text)
def title(theme: Theme.Theme,label: String) -> IO(String):
  Messages.foregroundText(theme,"toolTitle","\u{1b}[1m" ++ label ++ "\u{1b}[22m")
def pathCall(+theme: Theme.Theme,label: String,args: Value.Value) -> IO(String):
  do IO<String>:
    name : String <- title(theme,label)
    target : String <- shownPath(theme,path(args))
    return name ++ " " ++ target
