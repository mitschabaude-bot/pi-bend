import Base
import ./cli.bend as C
import ./agent.bend as Agent
import ./native.bend as N
import ./json.bend as J

def run_mode(supported: Bool, +config: C.Config) -> IO(Unit):
  match supported:
    case False{}: IO.die(Unit, 1, "This milestone supports text print mode; JSON/RPC and terminal UI are still being ported")
    case True{}:
      do IO<Unit>:
        cwd : String <- N.cwd()
        session : String <- N.uuid()
        history : J.Json <- Agent.start(config, Agent.context(config, session, cwd))
        IO.pure(Unit, Unit{})

def run_action(help: Bool, version: Bool, empty: Bool, supported: Bool, config: C.Config) -> IO(Unit):
  match help version empty:
    case True{} _ _: IO.print(C.help())
    case False{} True{} _: IO.print("pi-bend 0.1.0-dev (upstream pi 0.85.1)")
    case False{} False{} True{}: IO.print(C.help())
    case False{} False{} False{}: run_mode(supported, config)

def run_config(+config: C.Config) -> IO(Unit):
  match config:
    case C.Config{_, _, prompt, _, mode, _, _, _, _, action}:
      run_action(String.eq(action, "help"), String.eq(action, "version"), String.is_empty(prompt), String.eq(mode, "text"), config)

def entry(result: C.ParseState) -> IO(Unit):
  match result:
    case C.Error{e}: IO.die(Unit, 2, e)
    case C.Waiting{_, _}: IO.die(Unit, 2, "Missing option value")
    case C.Ready{config}: run_config(config)

def main() -> IO(Unit):
  do IO<Unit>:
    config : C.ParseState <- C.parse()
    entry(config)
