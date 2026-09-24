import Base
import ./listing.bend as Listing
import ../../../modes/interactive/theme/theme.bend as Theme
import ../../../../../runtime/src/schema-value.bend as Value
import ../index.bend as Tools
import ../ls.bend as Ls

def renderCall(+args: Value.Value,+theme: Theme.Theme) -> IO(String):
  do IO<String>:
    name : String <- Listing.title(theme,"ls")
    path : String <- Listing.path(theme,args,True{})
    limit : String <- Listing.limit(theme,args,True{})
    return name ++ " " ++ path ++ limit
def entryWarning(limit: Maybe<&2,Nat>) -> List<&2,String>:
  match limit:
    case Some{Succ{rest}}: (Nat.show(Succ{rest}) ++ " entries limit") <> Nil{}
    case _: Nil{}
def warnings(details: Maybe<&2,Tools.ToolDetails>) -> List<&2,String>:
  match details:
    case Some{Tools.LsDetails{Ls.LsToolDetails{cut,reached}}}: List.append(&2,String,entryWarning(reached),Listing.byteWarning(cut))
    case _: Nil{}
def renderResult(output: String,details: Maybe<&2,Tools.ToolDetails>,expanded: Bool,theme: Theme.Theme) -> IO(String):
  Listing.withWarning(output,expanded,theme,20n,warnings(details))
