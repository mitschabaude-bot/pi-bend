import Base

def duplicate(input: String) -> String:
  match input:
    case SCon{'[', rest}: rest
    case +other: other ++ other

def main() -> IO(Unit):
  IO.print(duplicate("a"))
