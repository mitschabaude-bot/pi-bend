import Base
import ./listing.bend as Listing
import ../../../modes/interactive/components/messages.bend as Messages
import ../../../modes/interactive/theme/theme.bend as Theme
import ../../../../../runtime/src/schema-value.bend as Value

def globValue(theme: Theme.Theme,glob: Maybe<&2,String>) -> IO(String):
  match glob:
    case Some{+value}: Bool.pick(Unit -> IO(String),String.is_empty(value),_ => IO.pure(String,""),_ => Messages.foregroundText(theme,"toolOutput"," (" ++ value ++ ")"))(Unit{})
    case None{}: IO.pure(String,"")
def renderCall(+args: Value.Value,+theme: Theme.Theme) -> IO(String):
  do IO<String>:
    name : String <- Listing.title(theme,"grep")
    pattern : String <- Listing.pattern(theme,args,True{})
    joiner : String <- Messages.foregroundText(theme,"toolOutput"," in ")
    path : String <- Listing.path(theme,args,False{})
    glob : String <- globValue(theme,Listing.textField(args,"glob"))
    limit : String <- Listing.limit(theme,args,False{})
    return name ++ " " ++ pattern ++ joiner ++ path ++ glob ++ limit
def matchWarning(limit: Maybe<&2,Nat>) -> List<&2,String>:
  match limit:
    case Some{Succ{rest}}: (Nat.show(Succ{rest}) ++ " matches limit") <> Nil{}
    case _: Nil{}
def lineWarning(details: Maybe<&2,Value.Value>) -> List<&2,String>:
  Bool.pick(List<&2,String>,Listing.detailBool(details,"linesTruncated"),"some lines truncated" <> Nil{},Nil{})
def renderResult(output: String,+details: Maybe<&2,Value.Value>,expanded: Bool,theme: Theme.Theme) -> IO(String):
  +warnings = List.append(&2,String,matchWarning(Listing.detailNumber(details,"matchLimitReached")),List.append(&2,String,Listing.byteWarning(details),lineWarning(details)))
  Listing.withWarning(output,expanded,theme,15n,warnings)
