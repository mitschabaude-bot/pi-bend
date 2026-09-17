import Base
import ./json.bend as J
import ./provider.bend as P
import ./auth.bend as A
import ./tools.bend as T
import ./util.bend as U
import ./native.bend as N
import ./cli.bend as C

type Context is Data:
  Context{session: String, model: String, effort: String, instructions: String, cwd: String, tools: J.Json}

type Phase is Data:
  Request{history: J.Json}
  Response{history: J.Json, response: J.Json}
  Continue{history: J.Json, results: J.Json}

def tool_output(call_id: String, output: String) -> J.Json:
  J.Object{J.str_field("type", "function_call_output", J.str_field("call_id", call_id, J.str_field("output", output, J.End{})))}

def execute_parsed(parsed: Result<&2, &2, String, J.Json>, name: String, cwd: String) -> IO(T.ToolResult):
  match parsed:
    case Fail{message}: IO.pure(T.ToolResult, T.ToolResult{"Invalid tool arguments: " ++ message, True{}})
    case Done{args}: T.execute(name, args, cwd)

def perform_one(is_call: Bool, +event: J.Json, cwd: String) -> IO(J.Json):
  match is_call:
    case False{}: IO.pure(J.Json, J.End{})
    case True{}:
      do IO<J.Json>:
        IO.print_err("[" ++ U.field(event, "name") ++ "] " ++ U.field(event, "arguments"))
        result : T.ToolResult <- execute_parsed(J.parse(U.field(event, "arguments")), U.field(event, "name"), cwd)
        return J.Item{tool_output(U.field(event, "call_id"), T.result_text(result)), J.End{}}

def perform(items: J.Json, +cwd: String) -> IO(J.Json):
  match items:
    case J.Item{+event, rest}:
      do IO<J.Json>:
        own : J.Json <- perform_one(String.eq(U.field(event, "type"), "function_call"), event, cwd)
        next : J.Json <- perform(rest, cwd)
        return J.append(own, next)
    case _: IO.pure(J.Json, J.End{})

def loop(fuel: Nat, phase: Phase, +context: Context) -> IO(J.Json):
  match fuel phase context:
    case 0n _ _: IO.die(J.Json, 1, "Agent turn limit reached")
    case 1n+n Request{+history} Context{session, model, effort, instructions, cwd, tools}:
      do IO<J.Json>:
        auth : A.Credential <- A.load()
        response : J.Json <- P.call(auth, session, model, instructions, history, tools, effort)
        loop(n, Response{history, response}, context)
    case 1n+n Response{history, +response} Context{_, _, _, _, cwd, _}:
      do IO<J.Json>:
        IO.print("")
        results : J.Json <- perform(J.array(J.get(response, "output")), cwd)
        loop(n, Continue{J.append(history, J.array(J.get(response, "output"))), results}, context)
    case 1n+n Continue{history, J.End{}} _: IO.pure(J.Json, history)
    case 1n+n Continue{history, results} _:
      loop(n, Request{J.append(history, results)}, context)

def default_system(cwd: String) -> String:
  "You are an expert coding assistant operating inside pi-bend, a coding agent harness written in Bend. You help users by reading files, executing commands, editing code, and writing new files.\n\n<tools>\n- read: Read file contents\n- bash: Execute bash commands\n- edit: Make precise edits\n- write: Create or overwrite files\n</tools>\n\n<rules>\n- Use read to examine files.\n- Use bash for file operations like ls, rg, find.\n- Use edit for precise targeted edits, and write for new files or complete rewrites.\n- Read AGENTS.md in the working directory and relevant parent directories before making changes.\n- Run appropriate tests after changing code.\n- Be concise in your responses.\n- Show file paths clearly when working with files.\n</rules>\n\n<cwd>\n" ++ cwd ++ "\n</cwd>"

def context(config: C.Config, session: String, +cwd: String) -> Context:
  match config:
    case C.Config{model, effort, _, +system, _, no_tools, _, _, _, _}: Context{session, model, effort, Bool.pick(String, String.is_empty(system), default_system(cwd), system), cwd, Bool.pick(J.Json, no_tools, J.End{}, T.schema())}

def start(config: C.Config, ctx: Context) -> IO(J.Json):
  match config:
    case C.Config{_, _, prompt, _, _, _, _, _, turns, _}: loop(Nat.mul(turns, 3n), Request{J.Item{P.user_message(prompt), J.End{}}}, ctx)
