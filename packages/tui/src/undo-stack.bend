import Base

# Immutable snapshots already have value semantics: pushing needs no deep
# cloning, and popping returns the snapshot together with the remaining stack.
type UndoStack<-S: Data> is Data:
  UndoStack{snapshots: List<&2,S>, count: Nat}

def create(-S: Data) -> UndoStack<S>:
  UndoStack{Nil{},Zero{}}
def length(-S: Data, stack: UndoStack<S>) -> Nat:
  match stack:
    case UndoStack{_,count}: count

def push(-S: Data, state: S, stack: UndoStack<S>) -> UndoStack<S>:
  match stack:
    case UndoStack{snapshots,count}: UndoStack{state <> snapshots,Succ{count}}

def pop(-S: Data, stack: UndoStack<S>) -> UndoStack<S> & Maybe<&2,S>:
  match stack:
    case UndoStack{Nil{},_}: (create(S),None{})
    case UndoStack{state <> rest,count}: (UndoStack{rest,Nat.sub(count,Succ{Zero{}})},Some{state})

def clear(-S: Data, stack: UndoStack<S>) -> UndoStack<S>:
  create(S)
