import Base

# Newest entry first. Rotation persists: a later push starts above the
# currently selected entry, just as a kill after yank-pop does upstream.
type KillRing is Data:
  KillRing{entries: List<&2,String>, count: Nat}
type PushOptions is Data:
  PushOptions{prepend: Bool, accumulate: Bool}

def create() -> KillRing:
  KillRing{Nil{},Zero{}}
def length(ring: KillRing) -> Nat:
  match ring:
    case KillRing{_,count}: count

def peek(ring: KillRing) -> Maybe<&2,String>:
  match ring:
    case KillRing{Nil{},_}: None{}
    case KillRing{entry <> _,_}: Some{entry}

def pushed(+text: String, options: PushOptions, ring: KillRing) -> KillRing:
  match options ring:
    case PushOptions{prepend,True{}} KillRing{+latest <> rest,count}:
      KillRing{Bool.pick(Unit -> String,prepend,_ => text ++ latest,_ => latest ++ text)(Unit{}) <> rest,count}
    case _ KillRing{entries,count}: KillRing{text <> entries,Succ{count}}

def push(text: String, options: PushOptions, ring: KillRing) -> KillRing:
  match text:
    case SNil{}: ring
    case text: pushed(text,options,ring)

def rotate(ring: KillRing) -> KillRing:
  match ring:
    case KillRing{Nil{},count}: KillRing{Nil{},count}
    case KillRing{latest <> rest,count}:
      KillRing{List.append(&2,String,rest,latest <> Nil{}),count}
