import Base
import ./listing.bend as Listing
import ../../../modes/interactive/components/messages.bend as Messages
import ../../../modes/interactive/theme/theme.bend as Theme
import ../../../../../runtime/src/schema-value.bend as Value
import ../index.bend as Tools
import ../find.bend as Find

def renderCall(+args: Value.Value,+theme: Theme.Theme) -> IO(String):
  do IO<String>:
    name : String <- Listing.title(theme,"find")
    pattern : String <- Listing.pattern(theme,args,False{})
    joiner : String <- Messages.foregroundText(theme,"toolOutput"," in ")
    path : String <- Listing.path(theme,args,False{})
    limit : String <- Listing.limit(theme,args,True{})
    return name ++ " " ++ pattern ++ joiner ++ path ++ limit
def resultWarning(limit: Maybe<&2,Nat>) -> List<&2,String>:
  match limit:
    case Some{Succ{rest}}: (Nat.show(Succ{rest}) ++ " results limit") <> Nil{}
    case _: Nil{}
def warnings(details: Maybe<&2,Tools.ToolDetails>) -> List<&2,String>:
  match details:
    case Some{Tools.FindDetails{Find.FindToolDetails{cut,limit}}}: List.append(&2,String,resultWarning(limit),Listing.byteWarning(cut))
    case _: Nil{}
def renderResult(output: String,details: Maybe<&2,Tools.ToolDetails>,expanded: Bool,theme: Theme.Theme) -> IO(String):
  Listing.withWarning(output,expanded,theme,20n,warnings(details))
