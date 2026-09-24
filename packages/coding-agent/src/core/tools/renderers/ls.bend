import Base
import ./listing.bend as Listing
import ../../../modes/interactive/theme/theme.bend as Theme
import ../../../../../runtime/src/schema-value.bend as Value

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
def renderResult(output: String,+details: Maybe<&2,Value.Value>,expanded: Bool,theme: Theme.Theme) -> IO(String):
  +warnings = List.append(&2,String,entryWarning(Listing.detailNumber(details,"entryLimitReached")),Listing.byteWarning(details))
  Listing.withWarning(output,expanded,theme,20n,warnings)
