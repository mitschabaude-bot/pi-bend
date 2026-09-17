import Base
import ./json.bend as J
import ./util.bend as U
import ./native.bend as N

type ToolResult is Data:
  ToolResult{text: String, error: Bool}

def result_text(result: ToolResult) -> String:
  match result:
    case ToolResult{text, error}: text

def schema() -> J.Json:
  J.array(J.or_null(J.parse("[{\"type\":\"function\",\"name\":\"read\",\"description\":\"Read the contents of a text file. Output is truncated to 2000 lines or 50KB. Use offset/limit for large files.\",\"parameters\":{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"offset\":{\"type\":\"integer\",\"minimum\":1},\"limit\":{\"type\":\"integer\",\"minimum\":1}},\"required\":[\"path\"]},\"strict\":false},{\"type\":\"function\",\"name\":\"bash\",\"description\":\"Execute a bash command in the current working directory. Returns stdout and stderr. Optionally specify a timeout in seconds.\",\"parameters\":{\"type\":\"object\",\"properties\":{\"command\":{\"type\":\"string\"},\"timeout\":{\"type\":\"integer\",\"minimum\":1}},\"required\":[\"command\"]},\"strict\":false},{\"type\":\"function\",\"name\":\"edit\",\"description\":\"Edit a file by replacing exact text. The oldText must match exactly and uniquely. Use this for precise targeted edits.\",\"parameters\":{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"oldText\":{\"type\":\"string\"},\"newText\":{\"type\":\"string\"}},\"required\":[\"path\",\"oldText\",\"newText\"]},\"strict\":false},{\"type\":\"function\",\"name\":\"write\",\"description\":\"Write content to a file. Creates the file if it does not exist, overwrites if it does. Automatically creates parent directories.\",\"parameters\":{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"}},\"required\":[\"path\",\"content\"]},\"strict\":false}]")))

def is_text(j: J.Json) -> Bool:
  match j:
    case J.Text{s}: True{}
    case _: False{}

def io_result(r: Result<&1, &1, U32 & String, String>, success: String) -> ToolResult:
  match r:
    case Done{_}: ToolResult{success, False{}}
    case Fail{(code, message)}: ToolResult{message, True{}}

def truncate_bytes(s: String, +bytes: Nat, stopped: Bool) -> String:
  match s stopped:
    case SNil{} _: ""
    case _ True{}: ""
    case SCon{+c, t} False{}:
      +width = U.byte_width(c)
      +fits = Nat.is_le(width, bytes)
      Bool.pick(String, fits, SCon{c, SNil{}}, "") ++ truncate_bytes(t, Nat.sub(bytes, width), Bool.not(fits))

def read_content(+content: String, +offset: Nat, +limit: Nat) -> ToolResult:
  +lines = String.split(content, '\n')
  +total = List.length(&2, String, lines)
  +start = Nat.sub(offset, 1n)
  +selected = String.join(U.take_lines(U.drop_lines(lines, start), limit), "\n")
  +cut = Nat.is_gt(U.byte_length(selected), U32.to_nat(51200))
  shown = truncate_bytes(selected, U32.to_nat(51200), False{})
  +next = Nat.add(start, limit)
  notice = Bool.pick(String, cut, "\n\n[50KB limit reached. Use offset/limit to continue.]", Bool.pick(String, Nat.is_lt(next, total), "\n\n[" ++ Nat.show(Nat.sub(total, next)) ++ " more lines in file. Use offset=" ++ Nat.show(1n+next) ++ " to continue.]", ""))
  Bool.pick(ToolResult, Nat.is_ge(start, total), ToolResult{"Offset " ++ Nat.show(offset) ++ " is beyond end of file (" ++ Nat.show(total) ++ " lines total)", True{}}, ToolResult{shown ++ notice, False{}})

def read_result(result: Result<&1, &1, U32 & String, String>, args: J.Json) -> ToolResult:
  match result:
    case Fail{(code, message)}: ToolResult{message, True{}}
    case Done{content}:
      +a = args
      read_content(content, J.number(J.get(a, "offset"), 1n), Nat.min(J.number(J.get(a, "limit"), U32.to_nat(2000)), U32.to_nat(2000)))

def read(+args: J.Json) -> IO(ToolResult):
  do IO<ToolResult>:
    r : Result<&1, &1, U32 & String, String> <- N.read(U.field(args, "path"))
    return read_result(r, args)

def write(+args: J.Json) -> IO(ToolResult):
  do IO<ToolResult>:
    r : Result<&1, &1, U32 & String, String> <- N.write(U.field(args, "path"), U.field(args, "content"))
    return io_result(r, "Successfully wrote to " ++ U.field(args, "path"))

def find_matches(+s: String, +needle: String, +index: Nat) -> List<&2, Nat>:
  match s:
    case SNil{}: Nil{}
    case SCon{c, t}:
      +rest = find_matches(t, needle, 1n+index)
      Bool.pick(List<&2, Nat>, String.starts_with(s, needle), index <> rest, rest)

def edit_match(matches: List<&2, Nat>, +content: String, old: String, replacement: String) -> Result<&2, &2, String, String>:
  match matches:
    case Nil{}: Fail{"Could not find the exact text. The old text must match exactly including all whitespace and newlines."}
    case +index <> Nil{}: Done{String.take(content, index) ++ replacement ++ String.drop(content, Nat.add(index, String.length(old)))}
    case _ <> _ : Fail{"The text must be unique. Please provide more context to make it unique."}

def edit_persist(result: Result<&2, &2, String, String>, +path: String) -> IO(ToolResult):
  match result:
    case Fail{e}: IO.pure(ToolResult, ToolResult{e, True{}})
    case Done{updated}:
      do IO<ToolResult>:
        r : Result<&1, &1, U32 & String, String> <- N.write(path, updated)
        return io_result(r, "Successfully replaced text in " ++ path ++ ".")

def edit_result(result: Result<&1, &1, U32 & String, String>, +args: J.Json) -> IO(ToolResult):
  match result:
    case Fail{(code, message)}: IO.pure(ToolResult, ToolResult{message, True{}})
    case Done{+content}:
      +old = U.field(args, "oldText")
      edit_persist(edit_match(find_matches(content, old, 0n), content, old, U.field(args, "newText")), U.field(args, "path"))

def edit(+args: J.Json) -> IO(ToolResult):
  do IO<ToolResult>:
    r : Result<&1, &1, U32 & String, String> <- N.read(U.field(args, "path"))
    edit_result(r, args)

def bash_output(result: Result<&1, &1, U32 & String, String>, +status: String) -> ToolResult:
  match result:
    case Fail{(code, message)}: ToolResult{message, True{}}
    case Done{+text}:
      +tail = String.reverse(truncate_bytes(String.reverse(String.join(List.reverse(&2, String, U.take_lines(List.reverse(&2, String, String.split(text, '\n')), U32.to_nat(2000))), "\n")), U32.to_nat(51200), False{}))
      suffix = Bool.pick(String, String.eq(status, "0"), "", "\n\nCommand exited with code " ++ status)
      ToolResult{tail ++ suffix, Bool.not(String.eq(status, "0"))}

def bash_collect(+handle: String) -> IO(ToolResult):
  do IO<ToolResult>:
    result : Result<&1, &1, U32 & String, String> <- U.collect(handle)
    status : String <- N.status(handle)
    closed : String <- N.close(handle)
    return bash_output(result, status)

def bash_started(result: Result<&1, &1, U32 & String, String>) -> IO(ToolResult):
  match result:
    case Fail{(code, message)}: IO.pure(ToolResult, ToolResult{message, True{}})
    case Done{handle}: bash_collect(handle)

def bash(+args: J.Json, cwd: String) -> IO(ToolResult):
  do IO<ToolResult>:
    r : Result<&1, &1, U32 & String, String> <- N.spawn(U.field(args, "command"), cwd, Nat.mul(J.number(J.get(args, "timeout"), 0n), U32.to_nat(1000)))
    bash_started(r)

type ToolKind is Data:
  Read{}
  Write{}
  Edit{}
  Bash{}
  Unknown{}

def kind(+name: String) -> ToolKind:
  Bool.pick(ToolKind, String.eq(name, "read"), Read{}, Bool.pick(ToolKind, String.eq(name, "write"), Write{}, Bool.pick(ToolKind, String.eq(name, "edit"), Edit{}, Bool.pick(ToolKind, String.eq(name, "bash"), Bash{}, Unknown{}))))

def valid(kind: ToolKind, +args: J.Json) -> Bool:
  match kind:
    case Read{}: is_text(J.get(args, "path"))
    case Write{}: is_text(J.get(args, "path")) && is_text(J.get(args, "content"))
    case Edit{}: is_text(J.get(args, "path")) && is_text(J.get(args, "oldText")) && is_text(J.get(args, "newText")) && Bool.not(String.is_empty(U.field(args, "oldText")))
    case Bash{}: is_text(J.get(args, "command"))
    case Unknown{}: False{}

def dispatch(ok: Bool, kind: ToolKind, args: J.Json, cwd: String) -> IO(ToolResult):
  match ok kind:
    case False{} _: IO.pure(ToolResult, ToolResult{"Invalid tool name or arguments", True{}})
    case True{} Read{}: read(args)
    case True{} Write{}: write(args)
    case True{} Edit{}: edit(args)
    case True{} Bash{}: bash(args, cwd)
    case True{} Unknown{}: IO.pure(ToolResult, ToolResult{"Unknown tool", True{}})

def execute(+name: String, +args: J.Json, cwd: String) -> IO(ToolResult):
  dispatch(valid(kind(name), args), kind(name), args, cwd)
