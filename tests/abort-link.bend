import Base
import ../packages/runtime/src/abort.bend as A

def show(value: Maybe<&2, A.AbortReason<U32>>) -> String:
  match value:
    case None{}: "none"
    case Some{A.Supplied{why}}: "supplied " ++ U32.show(why)
    case Some{A.DefaultAbort{}}: "default"

def main() -> IO(Unit):
  do IO<Unit>:
    +parent : A.AbortController<U32> <- A.new(U32)
    +child : A.AbortController<U32> <- A.new(U32)
    first : A.Link<U32> <- A.link(U32, A.signal(U32, parent), child)
    A.unlink(U32, first)
    won : Bool <- A.abort(U32, parent, Some{7})
    after : Maybe<&2, A.AbortReason<U32>> <- A.reason(U32, A.signal(U32, child))
    IO.print("unlinked then parent aborted: " ++ show(after))
    +other : A.AbortController<U32> <- A.new(U32)
    second : A.Link<U32> <- A.link(U32, A.signal(U32, parent), other)
    IO.sleep(5)
    forwarded : Maybe<&2, A.AbortReason<U32>> <- A.reason(U32, A.signal(U32, other))
    IO.print("linked to aborted parent: " ++ show(forwarded))
    A.unlink(U32, second)
    +third : A.AbortController<U32> <- A.new(U32)
    +fresh : A.AbortController<U32> <- A.new(U32)
    live : A.Link<U32> <- A.link(U32, A.signal(U32, third), fresh)
    won2 : Bool <- A.abort(U32, third, None{})
    IO.sleep(5)
    late : Maybe<&2, A.AbortReason<U32>> <- A.reason(U32, A.signal(U32, fresh))
    IO.print("parent aborted while linked: " ++ show(late))
    A.unlink(U32, live)
