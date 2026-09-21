import Base

def probe(mode: U32, count: U32) -> U32:
  match mode count:
    case 4 0: 0
    case 5 0: 0
    case 6 0: 0
    case +other +index: (other + other + index : U32)
