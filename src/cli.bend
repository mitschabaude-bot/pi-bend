import Base
import ./native.bend as N
import ./util.bend as U

type Config is Data:
  Config{model: String, effort: String, prompt: String, system: String, mode: String, no_tools: Bool, no_session: Bool, session: String, max_turns: Nat, action: String}

type Flag is Data:
  Model{}
  Thinking{}
  System{}
  Mode{}
  Session{}
  MaxTurns{}
  Provider{}
  Prompt{}
  NoTools{}
  NoSession{}
  Help{}
  Version{}
  Ignore{}
  Bad{}

def classify(+s: String) -> Flag:
  Bool.pick(Flag, String.eq(s, "--model"), Model{},
  Bool.pick(Flag, String.eq(s, "--thinking"), Thinking{},
  Bool.pick(Flag, String.eq(s, "--system-prompt"), System{},
  Bool.pick(Flag, String.eq(s, "--mode"), Mode{},
  Bool.pick(Flag, String.eq(s, "--session"), Session{},
  Bool.pick(Flag, String.eq(s, "--max-turns"), MaxTurns{},
  Bool.pick(Flag, String.eq(s, "--provider"), Provider{},
  Bool.pick(Flag, String.eq(s, "--no-tools") || String.eq(s, "-nt"), NoTools{},
  Bool.pick(Flag, String.eq(s, "--no-session"), NoSession{},
  Bool.pick(Flag, String.eq(s, "--help") || String.eq(s, "-h"), Help{},
  Bool.pick(Flag, String.eq(s, "--version") || String.eq(s, "-v"), Version{},
  Bool.pick(Flag, String.eq(s, "-p") || String.eq(s, "--print") || String.eq(s, "--offline") || String.eq(s, "--no-extensions") || String.eq(s, "--no-skills") || String.eq(s, "--no-context-files") || String.eq(s, "--no-prompt-templates"), Ignore{},
  Bool.pick(Flag, String.starts_with(s, "-"), Bad{}, Prompt{})))))))))))))

type ParseState is Data:
  Ready{config: Config}
  Waiting{flag: Flag, config: Config}
  Error{message: String}

def set_value(flag: Flag, value: String, config: Config) -> ParseState:
  match flag config:
    case Model{} Config{_, e, p, s, m, nt, ns, file, turns, a}: Ready{Config{value, e, p, s, m, nt, ns, file, turns, a}}
    case Thinking{} Config{model, _, p, s, m, nt, ns, file, turns, a}: Ready{Config{model, value, p, s, m, nt, ns, file, turns, a}}
    case System{} Config{model, e, p, _, m, nt, ns, file, turns, a}: Ready{Config{model, e, p, value, m, nt, ns, file, turns, a}}
    case Mode{} Config{model, e, p, s, _, nt, ns, file, turns, a}: Ready{Config{model, e, p, s, value, nt, ns, file, turns, a}}
    case Session{} Config{model, e, p, s, m, nt, ns, _, turns, a}: Ready{Config{model, e, p, s, m, nt, ns, value, turns, a}}
    case MaxTurns{} Config{model, e, p, s, m, nt, ns, file, _, a}: Ready{Config{model, e, p, s, m, nt, ns, file, U.natural(value, 128n), a}}
    case Provider{} config: Bool.pick(ParseState, String.eq(value, "openai-codex"), Ready{config}, Error{"Only openai-codex is implemented at this milestone"})
    case _ _: Error{"Unexpected option value"}

def set_flag(flag: Flag, value: String, +config: Config) -> ParseState:
  match flag config:
    case Prompt{} Config{model, e, +p, s, m, nt, ns, file, turns, a}: Ready{Config{model, e, p ++ Bool.pick(String, String.is_empty(p), "", "\n") ++ value, s, m, nt, ns, file, turns, a}}
    case NoTools{} Config{model, e, p, s, m, _, ns, file, turns, a}: Ready{Config{model, e, p, s, m, True{}, ns, file, turns, a}}
    case NoSession{} Config{model, e, p, s, m, nt, _, file, turns, a}: Ready{Config{model, e, p, s, m, nt, True{}, file, turns, a}}
    case Help{} Config{model, e, p, s, m, nt, ns, file, turns, _}: Ready{Config{model, e, p, s, m, nt, ns, file, turns, "help"}}
    case Version{} Config{model, e, p, s, m, nt, ns, file, turns, _}: Ready{Config{model, e, p, s, m, nt, ns, file, turns, "version"}}
    case Ignore{} _: Ready{config}
    case Bad{} _: Error{"Unsupported option: " ++ value}
    case flag _: Waiting{flag, config}

def parse_arg(state: ParseState, +arg: String) -> ParseState:
  match state:
    case Ready{config}: set_flag(classify(arg), arg, config)
    case Waiting{flag, config}: set_value(flag, arg, config)
    case Error{e}: Error{e}

def read_args(fuel: Nat, +index: Nat, state: ParseState) -> IO(ParseState):
  match fuel:
    case 0n: IO.pure(ParseState, state)
    case 1n+n:
      do IO<ParseState>:
        arg : String <- N.arg(index)
        read_args(n, 1n+index, parse_arg(state, arg))

def defaults() -> Config:
  Config{"gpt-5.6-sol", "low", "", "", "text", False{}, False{}, "", 128n, "run"}

def parse() -> IO(ParseState):
  do IO<ParseState>:
    count : String <- N.argc()
    read_args(Nat.sub(U.natural(count, 1n), 1n), 1n, Ready{defaults()})

def help() -> String:
  "pi-bend - native Bend coding agent (port in progress)\n\nUsage: pi-bend [options] [prompt]\n\n  -p, --print             Process prompt and exit\n  --model <id>            OpenAI Codex model\n  --thinking <level>      Reasoning effort\n  --system-prompt <text>  Replace default instructions\n  --no-tools             Disable tool execution\n  --no-session           Do not persist the session\n  --session <path>       Session file\n  --max-turns <n>        Maximum agent turns\n  -h, --help             Show help\n  -v, --version          Show version\n"
