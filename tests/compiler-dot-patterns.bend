import Base

# Reduced repeated character patterns from URL dot-segment recognition.
def dotCount(text: String, count: U32) -> Maybe<&2, U32>:
  match text count:
    case SNil{} value: Some{value}
    case _ 2: None{}
    case SCon{'.', rest} value: dotCount(rest, (value + 1 : U32))
    case SCon{'%', SCon{'2', SCon{'e', rest}}} value: dotCount(rest, (value + 1 : U32))
    case SCon{'%', SCon{'2', SCon{'E', rest}}} value: dotCount(rest, (value + 1 : U32))
    case _ _: None{}


def show(value: Maybe<&2, U32>) -> String:
  match value:
    case None{}: "ordinary"
    case Some{count}: U32.show(count)

def main() -> IO(Unit): IO.print(show(dotCount("%2E.", 0)))
