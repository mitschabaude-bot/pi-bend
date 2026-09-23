import Base
import ../utils.bend as U
import ../../../runtime/src/text.bend as Strings
import ../../../runtime/src/callback.bend as Callback

# Background callbacks are borrowed: the caller keeps them alive until every
# render using the state has completed. Setters never dispose caller handles.
type Cache is Data:
  Cache{width: Nat,lines: List<&2,String>}
type Text is Data:
  Text{text: String,paddingX: Nat,paddingY: Nat,customBgFn: Maybe<&2,Callback.Callback<String,String>>,cache: Maybe<&2,Cache>}

def new(text: String,paddingX: Maybe<&2,Nat>,paddingY: Maybe<&2,Nat>,background: Maybe<&2,Callback.Callback<String,String>>) -> Text:
  Text{text,Maybe.default(&2,Nat,paddingX,1n),Maybe.default(&2,Nat,paddingY,1n),background,None{}}
def invalidate(state: Text) -> Text:
  match state:
    case Text{text,x,y,background,_}: Text{text,x,y,background,None{}}
def setText(state: Text,text: String) -> Text:
  match state:
    case Text{_,x,y,background,_}: Text{text,x,y,background,None{}}
def setCustomBgFn(state: Text,background: Maybe<&2,Callback.Callback<String,String>>) -> Text:
  match state:
    case Text{text,x,y,_,_}: Text{text,x,y,background,None{}}

def background(line: String,width: Nat,callback: Maybe<&2,Callback.Callback<String,String>>) -> IO(String):
  match callback:
    case None{}:
      +line = {line: String}
      IO.pure(String,U.padResult(line,U.visibleWidth(line),width,True{}))
    case Some{callback}: U.applyBackgroundToLine(line,width,callback)

def paint(lines: List<&2,String>,+margin: String,+width: Nat,+callback: Maybe<&2,Callback.Callback<String,String>>,reversed: List<&2,String>) -> IO(List<&2,String>):
  match lines:
    case Nil{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case line <> rest:
      do IO<List<&2,String>>:
        painted : String <- background(margin ++ line ++ margin,width,callback)
        paint(rest,margin,width,callback,painted <> reversed)
def padding(count: Nat,+line: String,+width: Nat,+callback: Maybe<&2,Callback.Callback<String,String>>,reversed: List<&2,String>) -> IO(List<&2,String>):
  match count:
    case Zero{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case Succ{count}:
      do IO<List<&2,String>>:
        painted : String <- background(line,width,callback)
        padding(count,line,width,callback,painted <> reversed)

def rendered(state: Text,width: Nat,+lines: List<&2,String>) -> Text & List<&2,String>:
  match state:
    case Text{text,x,y,callback,_}: (Text{text,x,y,callback,Some{Cache{width,lines}}},lines)
def uncached(+state: Text,+width: Nat) -> IO(Text & List<&2,String>):
  match state:
    case Text{+text,x,y,+callback,_}:
      +margin = U.spaces(Nat.min(x,(width - 1n) / 2n),"")
      +contentWidth = Nat.max(1n,width - Nat.min(x,(width - 1n) / 2n) * 2n)
      Bool.pick(Unit -> IO(Text & List<&2,String>),Strings.blank(text),
        _ => IO.pure(Text & List<&2,String>,rendered(state,width,Nil{})),
        _ =>
          do IO<Text & List<&2,String>>:
            content : List<&2,String> <- paint(U.wrapTextWithAnsi(U.normalizeTerminalOutput(text),contentWidth),margin,width,callback,Nil{})
            +empty : List<&2,String> <- padding(y,U.spaces(width,""),width,callback,Nil{})
            return rendered(state,width,List.append(&2,String,empty,List.append(&2,String,content,empty))))(Unit{})

# The returned state carries the cache; using an older immutable state rerenders.
def render(+state: Text,+width: Nat) -> IO(Text & List<&2,String>):
  match state:
    case Text{_,_,_,_,Some{Cache{cachedWidth,lines}}}:
      Bool.pick(Unit -> IO(Text & List<&2,String>),Nat.is_eq(width,cachedWidth),_ => IO.pure(Text & List<&2,String>,(state,lines)),_ => uncached(state,width))(Unit{})
    case _: uncached(state,width)
