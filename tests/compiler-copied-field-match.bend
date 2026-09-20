import Base

type Box is Data:
  Box{value: U32}

type Wrapper is Data:
  Wrapper{box: Box}

def unbox(box: Box) -> U32:
  match box:
    case Box{value}: value

def copied(value: Wrapper) -> U32:
  match value:
    case Wrapper{+box}:
      match box:
        case Box{value}: U32.add(value, unbox(box))
