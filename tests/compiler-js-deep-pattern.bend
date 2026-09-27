import Base

# BEND-063: a non-tail self-call under a string pattern nested eight deep.
# The JS explicit-stack emitter delimits blocks by indentation, which stops
# growing at 32 columns, so the frame swallows the enclosing else-branches
# and the emitted JS does not parse. Native prints "xXy".
def sub(text: String, +url: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{'a', SCon{'b', SCon{'c', SCon{'d', SCon{'e', SCon{'f', SCon{'g', SCon{'h', rest}}}}}}}}: url ++ sub(rest, url)
    case SCon{c, rest}: SCon{c, sub(rest, url)}

def main() -> IO(Unit): IO.print(sub("xabcdefghy", "X"))
