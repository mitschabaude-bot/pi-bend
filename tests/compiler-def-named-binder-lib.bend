import Base

type Wrapped is Data:
  Wrapped{text: String}

def text(value: String) -> String: value

def render(value: Wrapped) -> String:
  match value:
    case Wrapped{text}: text
